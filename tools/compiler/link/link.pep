## Module linking: binds each file's imports and re-exports, then rewrites
## every imported spelling (`m.sqrt`, an alias `power`, a qualified type
## `m.Point`) to the name of the declaration it denotes. After linking, the
## program has a single namespace: each file's private declarations, and
## the references to them, take names no other file can spell
## (`helper@io/file`).
##
## A file's exports are its `export` declarations plus its `export x as y`
## re-exports; a module's are those of its `module.pep`. What a file can
## name from elsewhere:
##
## - the exports of prelude files (the runtime, forced imports),
##   unqualified, with no import;
## - `import m` / `import m as q` / `import "f" as q`: the target's exports
##   as `m.x` / `q.x`;
## - `import "f"`: the file's exports, unqualified;
## - `import [x, y as z] from m`: those exports, as `x` and `z`.
##
## Locally bound names (parameters, locals, generic parameters, struct
## members) hide imports; a name the file declares itself may not also be
## imported.

import compiler.ast;
import [Attribute, Declaration, Expression, FunctionDecl, Module, Pattern, Span, TypeName] from compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import io;
import [Path] from io;
import "names" as names;
import [Target] from "platform";
import [Scope, ScopeKind, ScopeWalk, Scopes] from "walk";

# The home (`_Linker.home`) of the runtime's top-level files, and of the
# built-in types.
const _PRELUDE_HOME = "<prelude>";

## One parsed file of a program, with its imports resolved to other files.
export struct ProgramFile {
    ## The name diagnostics use: the path as the program reached it.
    var name: String = "";
    ## Its identity, `files.path_key` of its path.
    var key: String = "";
    ## The namespace its private names are mangled with, unique in the
    ## program.
    var namespace: String = "";
    ## The folder of the module the file belongs to, if any.
    var module_root: Path?;
    ## The file's text.
    var source: String = "";
    ## Its syntax tree, linked in place.
    var module: Module;
    ## A runtime or forced-import file: its exports are visible to every
    ## file without an import.
    var prelude: bool;
    ## A file a prelude file reaches through local imports (another file of
    ## a forced module): its exports may repeat the runtime's, but are
    ## visible only through the module's own exports.
    var prelude_part: bool;
    ## For each of `module.imports`, the index of the file it names, or
    ## none when it did not resolve.
    var imports: Array<ulong?> = Array<ulong?>();
    ## For each of `module.imports`: a local import that resolved to a
    ## module folder (`import "vec"` for `vec/module.pep`).
    var folder_imports: bool[] = Array<bool>();

    ## Creates a file.
    ##
    ## @param name its name
    ## @param source its text
    ## @param module its syntax tree
    construct(name: String, source: String, module: Module) {
        this.name = name;
        this.source = source;
        this.module = module;
    }
}

## A module-linking error, anchored in one file.
export struct ModuleError {
    ## The file, as an index into the program's files.
    var file: ulong;
    ## Where in it.
    var span: Span;
    ## What is wrong.
    var message: String = "";
    ## An import that names no module or file on the search paths.
    var unresolved: bool;
    ## A second place in the same file that explains the error.
    var note_span: Span?;
    ## What the note says.
    var note: String = "";

    ## Creates an error.
    ##
    ## @param file the file
    ## @param span where
    ## @param message what is wrong
    ## @param unresolved whether an import names nothing on the search paths
    construct(file: ulong, span: Span, message: String, unresolved: bool = false) {
        this.file = file;
        this.span = span;
        this.message = message;
        this.unresolved = unresolved;
    }

    ## Returns the error as a diagnostic, with its note.
    ##
    ## @returns the diagnostic
    to_diagnostic(): Diagnostic {
        var out = Diagnostic.error(message).at(Location(file, span));
        if (note_span.is_value()) {
            out = out.with_note(note, Optional<Location>.Value(Location(file, note_span.value())));
        }
        return out;
    }

    ## Returns whether `other` says the same thing at the same place.
    ##
    ## @param other another error
    ## @returns true when equal
    same(other: ModuleError): bool {
        bool notes = note_span.is_value() == other.note_span.is_value()
            and (!note_span.is_value()
                or (note_span.value().start == other.note_span.value().start
                    and note_span.value().end == other.note_span.value().end));
        return file == other.file
            and span.start == other.span.start
            and span.end == other.span.end
            and message == other.message
            and unresolved == other.unresolved
            and notes
            and note == other.note;
    }
}

## What linking learned about one file, for the checks that follow.
export struct FileScope {
    ## The references linking rewrote, as span start -> declaration name:
    ## each was reached through an import.
    var imported: HashMap<ulong, String> = HashMap<ulong, String>();
    ## The names the file's import lists and re-exports bind, as span
    ## start -> declaration name.
    var named: HashMap<ulong, String> = HashMap<ulong, String>();
    ## The other files whose exported extensions this file may use.
    var extensions: HashSet<ulong> = HashSet<ulong>();
    ## The other files that extend a type this file declares: code
    ## anywhere that uses the type sees what they add to it (a
    ## specialization of `Array<T>.find` the `==` an extension gives `T`).
    var extended_by: HashSet<ulong> = HashSet<ulong>();
    ## The declarations the file's imports bind, by their linked names.
    var bound: HashSet<String> = HashSet<String>();

    ## Creates an empty scope.
    construct() {}
}

## What `link` returns.
export struct Linked {
    ## Each file's scope.
    var scopes: FileScope[] = Array<FileScope>();
    ## Every linking error, by file and position.
    var errors: ModuleError[] = Array<ModuleError>();
    ## The overload sets that span files: each union's name -> the names of
    ## the functions or single-file sets it joins, grouped by module.
    var overload_unions: Map<String, String[][]> = Map<String, String[][]>();

    ## Creates an empty result.
    construct() {}
}

## Binds every file's imports and re-exports and rewrites imported
## spellings in place.
##
## @param files the program's files, the root first
## @param target the target platform selection evaluates against
## @returns each file's scope and every linking error
export link(files: ProgramFile[], target: Target): Linked {
    var linker = _Linker(files, target);
    return linker.run();
}

## A program whose names are bound and whose bodies are not yet rewritten:
## `link` in two steps, so a build can leave alone the bodies of the files
## whose compilation units its cache holds checked.
export struct PendingLink {
    # The linker, prepared.
    var _linker: _Linker;

    ## Binds `files`' names and imports.
    ##
    ## @param files the program's files, rewritten in place by `finish`
    ## @param target the target platform
    construct(files: ProgramFile[], target: Target) {
        _linker = _Linker(files, target);
        _linker.prepare();
    }

    ## Each file's scope as far as binding goes: the files whose
    ## extensions it sees, and the overload unions. The imported
    ## spellings come with `finish`.
    ##
    ## @returns what `link` would return, without `imported` and errors
    bound(): Linked {
        var out = Linked();
        var extended_by = _linker.extended_by();
        ulong i = 0;
        for (var extensions in _linker.prepared_extensions) {
            var scope = FileScope();
            scope.extensions = extensions;
            scope.extended_by = extended_by[i];
            out.scopes.append(scope);
            i += 1;
        }
        out.overload_unions = _linker.unions.by_module();
        return out;
    }

    ## Rewrites the files, the bodies of those `bodies` marks only.
    ##
    ## @param bodies per file, whether to rewrite its bodies
    ## @returns what `link` returns
    finish(bodies: bool[]): Linked {
        return _linker.finish(bodies);
    }

    ## After `finish`, rewrites file `file`'s bodies too, its module read
    ## again whole.
    ##
    ## @param file the file
    ## @returns its scope, and the errors in it
    finish_bodies(file: ulong): (FileScope, ModuleError[]) {
        var before = _linker.errors.count;
        var scope = _linker.finish_file(file, true);
        var errors = Array<ModuleError>();
        for (var i in before.._linker.errors.count) {
            errors.append(_linker.errors[i]);
        }
        return (scope, errors);
    }
}

# Names a file declares, exports, or can see, each with the parameter
# counts of the generics it names (empty for a type).
type _Names = HashMap<String, HashSet<ulong>>;

_copy_names(names: _Names): _Names {
    var out = _Names();
    for (var (name, counts) in names) {
        out[name] = counts.copy();
    }
    return out;
}

# Adds `name` with `counts` to `to`; whether that changed it.
_add_names(to: _Names, name: String, counts: HashSet<ulong>): bool {
    var entry = to.try_get(name);
    if (!entry.is_value()) {
        to[name] = counts.copy();
        return true;
    }
    bool changed = false;
    for (var count in counts) {
        if (entry.value().insert(count)) {
            changed = true;
        }
    }
    return changed;
}

_same_names(a: _Names, b: _Names): bool {
    if (a.count != b.count) {
        return false;
    }
    for (var (name, counts) in a) {
        var other = b.try_get(name);
        if (!other.is_value() or other.value().count != counts.count) {
            return false;
        }
        for (var count in counts) {
            if (!other.value().contains(count)) {
                return false;
            }
        }
    }
    return true;
}

_copy_set(set: HashSet<String>): HashSet<String> {
    return set.copy();
}

# One file's import bindings.
struct _Bindings {
    # A name imported unqualified -> the declaration it denotes, or none
    # when two imports bind it to different declarations.
    var unqualified: HashMap<String, String?> = HashMap<String, String?>();
    # qualifier -> the file whose exports it names.
    var qualified: HashMap<String, ulong> = HashMap<String, ulong>();
    # Qualifiers and listed names of imports that did not resolve.
    var unresolved: HashSet<String> = HashSet<String>();
    # A whole-file import did not resolve.
    var unresolved_whole_file: bool;
    # The declarations of the other files of the file's module, which it
    # sees after its imports: each name -> the declaration it denotes, or
    # the union of the module's functions of that name. A name the file
    # declares itself is here only as such a union.
    var module: HashMap<String, String> = HashMap<String, String>();

    construct() {}
}

# A declaration of a module file, as `compute_module_names` groups them.
struct _ModuleDeclaration {
    # The name it takes in the merged program.
    var name: String;
    # A free function (not an extern).
    var function: bool;
    # The declaring file.
    var file: ulong;
    # Declared `private` to its file.
    var file_private: bool;

    construct(name: String, function: bool, file: ulong, file_private: bool) {
        this.name = name;
        this.function = function;
        this.file = file;
        this.file_private = file_private;
    }
}

# What an unqualified name that is not the file's own denotes.
enum _Resolution {
    # A declaration, by name: bound by an import, declared by another file
    # of the module, or a prelude export. `from_import` is false for a
    # prelude export.
    Declared(name: String, from_import: bool),
    # Two whole-file imports bind it to different declarations.
    Ambiguous,
    Unknown,
}

# Resolves an unqualified name through the file's imports, then the
# other files of its module, then the prelude.
_resolve_imported(name: String, bindings: _Bindings, prelude: HashMap<String, String>): _Resolution {
    var bound = bindings.unqualified.try_get(name);
    if (bound.is_value()) {
        if (bound.value().is_value()) {
            return _Resolution.Declared(bound.value().value(), true);
        }
        return _Resolution.Ambiguous;
    }
    var mate = bindings.module.try_get(name);
    if (mate.is_value()) {
        return _Resolution.Declared(mate.value(), true);
    }
    var exported = prelude.try_get(name);
    if (exported.is_value()) {
        return _Resolution.Declared(exported.value(), false);
    }
    return _Resolution.Unknown;
}

_ambiguous(name: String): String {
    return $"'{name}' is ambiguous: more than one import provides it";
}

# Overload sets that span files and modules: where one binding would take
# a name from two files and both denote free functions declared under that
# name, it takes a union instead, a name of its own (`f@geo/a#set1`) that
# sema resolves as one overload set of every member.
struct _Unions {
    # Each free function a non-prelude file declares, by its linked name ->
    # the module it belongs to.
    var functions: HashMap<String, String> = HashMap<String, String>();
    # Each union's parts, sorted and joined by newlines -> its name.
    var by_parts: HashMap<String, String> = HashMap<String, String>();
    # Each union's name -> its parts.
    var parts: Map<String, String[]> = Map<String, String[]>();

    construct() {}

    _expand(name: String): String[] {
        var parts_of = parts.try_get(name);
        if (parts_of.is_value()) {
            return parts_of.value().copy();
        }
        return [name];
    }

    # The one name a binding takes for both `a` and `b`: their union, when
    # every part is a free function of a non-prelude file declared under
    # the same name.
    merge(a: String, b: String): String? {
        var all = _expand(a);
        all.append_all(_expand(b));
        all.sort((x, y) => x.compare(y));
        var unique = Array<String>();
        for (var part in all) {
            if (unique.count == 0 or unique[unique.count - 1] != part) {
                unique.append(part);
            }
        }
        var name = names.demangle_name(unique[0]);
        for (var part in unique) {
            if (!functions.contains(part) or names.demangle_name(part) != name) {
                return Optional<String>.Empty;
            }
        }
        if (unique.count == 1) {
            return Optional<String>.Value(unique[0]);
        }
        var key = "\n".join(unique);
        var known = by_parts.try_get(key);
        if (known.is_value()) {
            return known;
        }
        var number = parts.count + 1;
        var union = unique[0].contains(names.NAMESPACE_SEPARATOR) ?
            $"{unique[0]}#set{number}" :
            names.mangle(unique[0], $"#set{number}");
        by_parts[key] = union;
        parts.insert(union, unique);
        return Optional<String>.Value(union);
    }

    # Each union's parts grouped by module, the modules in path order.
    by_module(): Map<String, String[][]> {
        var out = Map<String, String[][]>();
        for (var (union, members) in parts) {
            var modules = Array<String>();
            var groups = HashMap<String, String[]>();
            for (var part in members) {
                var module = functions[part];
                if (!groups.contains(module)) {
                    groups[module] = Array<String>();
                    modules.append(module);
                }
                groups[module].append(part);
            }
            modules.sort((a, b) => _compare_paths(a, b));
            var grouped = Array<String[]>();
            for (var module in modules) {
                grouped.append(groups[module]);
            }
            out.insert(union, grouped);
        }
        return out;
    }
}

# Orders two paths component by component.
_compare_paths(a: String, b: String): int {
    var left = Path(a).components();
    var right = Path(b).components();
    ulong i = 0;
    while (i < left.count and i < right.count) {
        int rank = _component_rank(left[i], i) - _component_rank(right[i], i);
        if (rank != 0) {
            return rank;
        }
        if (i == 0 and _is_prefix(left[i])) {
            var (left_kind, left_key) = _prefix_order(left[i]);
            var (right_kind, right_key) = _prefix_order(right[i]);
            if (left_kind != right_kind) {
                return left_kind - right_kind;
            }
            int order = left_key.compare(right_key);
            if (order != 0) {
                return order;
            }
            i += 1;
            continue;
        }
        int c = left[i].compare(right[i]);
        if (c != 0) {
            return c;
        }
        i += 1;
    }
    return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1);
}

# Where a component sorts among a path's kinds of component: a Windows
# prefix (`C:`, `\\server\share`), a
# root, `.`, `..`, then a name. Only the first component can be a prefix.
_component_rank(component: String, index: ulong): int {
    if (index == 0 and _is_prefix(component)) {
        return 0;
    }
    if (component == "/" or component == "\\") {
        return 1;
    }
    if (component == ".") {
        return 2;
    }
    if (component == "..") {
        return 3;
    }
    return 4;
}

# POSIX paths have no prefix.
[Target(!OS(Windows))]
_is_prefix(component: String): bool {
    return false;
}

# A drive (`C:`) or a UNC share: what `Path.components` puts first.
[Target(OS(Windows))]
_is_prefix(component: String): bool {
    return component.ends_with(":") or component.starts_with("\\\\") or component.starts_with("//");
}

# How a Windows prefix sorts: by kind (`\\?\x`, `\\?\UNC\x`,
# `\\?\C:`, `\\.\x`, `\\server\share`, then `C:`), then by what it names,
# a drive by its upper-case letter.
_prefix_order(component: String): (int, String) {
    var text = component.replace("/", "\\");
    if (text.starts_with("\\\\?\\")) {
        var rest = text.substr_bytes(4, text.size - 4);
        if (rest.starts_with("UNC\\") or rest == "UNC") {
            return (1, rest);
        }
        if (rest.size == 2 and rest.ends_with(":")) {
            return (2, rest.upper());
        }
        return (0, rest);
    }
    if (text.starts_with("\\\\.\\")) {
        return (3, text.substr_bytes(4, text.size - 4));
    }
    if (text.starts_with("\\\\")) {
        return (4, text.substr_bytes(2, text.size - 2));
    }
    return (5, text.upper());
}

# A struct's members from an extension: its name, file and whether the
# extension is exported.
struct _ExtensionMember {
    var name: String = "";
    var file: ulong;
    var exported: bool;
    # Declared in a `private` extension: visible only in its own file.
    var file_private: bool;

    construct(name: String, file: ulong, exported: bool, file_private: bool) {
        this.name = name;
        this.file = file;
        this.exported = exported;
        this.file_private = file_private;
    }
}

# Struct member names, for hiding inside method bodies.
struct _Members {
    # struct -> names declared in its body.
    var of_body: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    # struct -> members from extensions.
    var of_extensions: HashMap<String, _ExtensionMember[]> = HashMap<String, _ExtensionMember[]>();
    # trait -> the structs extensions make conform to it.
    var adopters: HashMap<String, String[]> = HashMap<String, String[]>();
    # type alias -> the type it names.
    var aliases: HashMap<String, String> = HashMap<String, String>();
    # struct, enum or trait -> the file that declares it.
    var declared_in: HashMap<String, ulong> = HashMap<String, ulong>();
    # Each extension's type and the file of the extension.
    var extended_in: Array<(String, ulong)> = Array<(String, ulong)>();

    construct() {}

    # The type `name` denotes, through any aliases.
    resolve(name: String): String {
        var out = name;
        ulong i = 0;
        while (i <= aliases.count as ulong) {
            var target = aliases.try_get(out);
            if (!target.is_value()) {
                break;
            }
            out = target.value();
            i += 1;
        }
        return out;
    }
}

# A function's parameter types as written, with its generic parameters
# named by position: `describe<T>(T)` and `describe<Point>(Point)` have one
# shape.
_parameter_shape(function: FunctionDecl): String {
    var generics = Array<String>();
    for (var param in function.generic_params) {
        generics.append(param.name);
    }
    var out = Array<String>();
    for (var parameter in function.parameters) {
        out.append(_spell(parameter.type_name, generics));
    }
    return ";".join(out);
}

_spell(type_name: TypeName, generics: String[]): String {
    var name = type_name.name;
    ulong i = 0;
    while (i < generics.count) {
        if (generics[i] == type_name.name) {
            name = $"${i}";
            break;
        }
        i += 1;
    }
    if (type_name.generic_types.count == 0) {
        return name;
    }
    var arguments = Array<String>();
    for (var argument in type_name.generic_types) {
        arguments.append(_spell(argument, generics));
    }
    return $"{name}<{",".join(arguments)}>";
}

# How diagnostics name the file whose exports are meant: `module
# 'geometry'` for a module's `module.pep`, else `"shapes.pep"`.
_describe_file(file: ProgramFile): String {
    var path = Path(file.name);
    var name = path.file_name();
    var file_name = name.is_value() ? name.value() : "";
    if (file.module_root.is_value() and file_name == "module.pep") {
        var root = file.module_root.value().file_name();
        return $"module '{root.is_value() ? root.value() : ""}'";
    }
    return $"\"{file_name}\"";
}

# The whole link, over one program's files.
struct _Linker {
    var files: ProgramFile[];
    var target: Target;
    var errors: ModuleError[] = Array<ModuleError>();
    # What `prepare` bound for `finish`: each file's imports and the files
    # whose extensions it sees.
    var prepared_bindings: Array<_Bindings> = Array<_Bindings>();
    var prepared_extensions: Array<HashSet<ulong>> = Array<HashSet<ulong>>();
    # `extended_by()`, as `finish` found it.
    var _extended_by: HashSet<ulong>[] = Array<HashSet<ulong>>();
    # Per file, the names that denote a type there (struct, alias, trait).
    var types_of: HashSet<String>[] = Array<HashSet<String>>();
    # Per file, the names that denote a struct or type alias there.
    var value_types_of: HashSet<String>[] = Array<HashSet<String>>();
    # Per file, the generic bases its imports and the prelude give it.
    var imported_bases: _Names[] = Array<_Names>();
    # Per file, the generic bases it can call, by every name it has for
    # them.
    var bases: _Names[] = Array<_Names>();
    # Per file, its own names -> the names their declarations take.
    var own: HashMap<String, String>[] = Array<HashMap<String, String>>();
    # Per file, the other files of the program in its module that it
    # imports: the only ones it sees.
    var mates: Array<ulong[]> = Array<ulong[]>();
    # Per file, every other file of the program in its module.
    var all_mates: Array<ulong[]> = Array<ulong[]>();
    # Per file, the names its module's other files declare (`_Bindings.module`).
    var module_names: HashMap<String, String>[] = Array<HashMap<String, String>>();
    # Per file, the other files of its module that declare each of those
    # names, found on the file's first unknown name (`_module_from`).
    var module_from: HashMap<ulong, HashMap<String, ulong[]>> = HashMap<ulong, HashMap<String, ulong[]>>();
    var unions: _Unions = _Unions();
    # Every type name declared at top level, in any file.
    var types: HashSet<String> = HashSet<String>();
    # Per file, its exports -> the declarations they denote.
    var exports: HashMap<String, String>[] = Array<HashMap<String, String>>();
    # The prelude's exports.
    var prelude: HashMap<String, String> = HashMap<String, String>();
    var members: _Members = _Members();
    # Every struct and module-scope variable, by linked name.
    var structs: HashSet<String> = HashSet<String>();
    var constants: HashSet<String> = HashSet<String>();
    # Every file's name, for diagnostics.
    var file_names: String[] = Array<String>();
    # Every top-level declaration's linked name -> the files that declare
    # it.
    var declared_in: HashMap<String, ulong[]> = HashMap<String, ulong[]>();

    construct(files: ProgramFile[], target: Target) {
        this.files = files;
        this.target = target;
    }

    # Whether file `file` imports file `other`.
    imports_file(file: ulong, other: ulong): bool {
        for (var target in files[file].imports) {
            if (target.is_value() and target.value() == other) {
                return true;
            }
        }
        return false;
    }

    # Reports a use in `file` of `name`, which it does not bind, when other
    # files of its module declare it: the file does not import them.
    #
    # @returns whether it reported one
    report_unimported_mate(file: ulong, name: String, span: Span): bool {
        var from = _module_from(file).try_get(name);
        if (!from.is_value() or from.value().is_empty) {
            return false;
        }
        _error(
            file,
            span,
            $"'{name}' is declared in {file_names[from.value()[0]]}, another file of this module, which this file does not import; add an import for it"
        );
        return true;
    }

    # The other files of `file`'s module that declare each name it does not.
    _module_from(file: ulong): HashMap<String, ulong[]> {
        var found = module_from.try_get(file);
        if (found.is_value()) {
            return found.value();
        }
        var out = HashMap<String, ulong[]>();
        for (var m in all_mates[file]) {
            for (var d in named_decls(files[m].module)) {
                if (d.is_private() or own[file].contains(d.declared_name())) {
                    continue;
                }
                var name = d.declared_name();
                if (!out.contains(name)) {
                    out[name] = Array<ulong>();
                }
                if (!out[name].contains(m)) {
                    out[name].append(m);
                }
            }
        }
        module_from[file] = out;
        return out;
    }

    # Where an override may go: a module's files share their module, the
    # runtime's top-level files share the prelude, and any other file is
    # its own.
    home(file: ulong): String {
        var f = files[file];
        if (f.module_root.is_value()) {
            return f.module_root.value().to_string();
        }
        if (f.prelude) {
            return _PRELUDE_HOME;
        }
        return $"<file {file}>";
    }

    # Whether a file with this home declares the linked name `name`.
    declared_at(name: String, home: String): bool {
        var found = declared_in.try_get(name);
        if (!found.is_value()) {
            return false;
        }
        for (var file in found.value()) {
            if (this.home(file) == home) {
                return true;
            }
        }
        return false;
    }

    _error(file: ulong, span: Span, message: String) {
        errors.append(ModuleError(file, span, message));
    }

    # The named top-level declarations that survive platform selection.
    named_decls(module: Module): Declaration[] {
        var out = Array<Declaration>();
        for (var d in module.declarations) {
            match (d) {
                Extend(_) => {}
                else => {
                    if (target.keeps(d.attributes())) {
                        out.append(d);
                    }
                }
            }
        }
        return out;
    }

    # A function named `name` (possibly mangled) with these generic
    # parameters, declared in `file`, is a concrete override.
    is_named_override(name: String, params: String[], file: ulong): bool {
        if (names.is_override(params)) {
            return true;
        }
        if (params.count == 0) {
            return false;
        }
        for (var p in params) {
            if (!_names_type(types_of[file], p)) {
                return false;
            }
        }
        bool all_values = true;
        for (var p in params) {
            if (!_names_type(value_types_of[file], p)) {
                all_values = false;
            }
        }
        var found = (all_values ? bases[file] : imported_bases[file]).try_get(names.demangle_name(name));
        return found.is_value() and found.value().contains(params.count);
    }

    # `f`, declared in `file`, is a concrete override. A constrained name
    # (`describe<T: Shape>`) is always a parameter.
    is_override(f: FunctionDecl, file: ulong): bool {
        var params = Array<String>();
        for (var g in f.generic_params) {
            if (g.bounds.count > 0) {
                return false;
            }
            params.append(g.name);
        }
        return is_named_override(f.name, params, file);
    }

    _names_type(types: HashSet<String>, param: String): bool {
        return names.is_concrete_override([param]) or types.contains(param);
    }

    # Per file, the names it can see: its `own`, the prelude's exports, and
    # what its imports bind. Iterated until re-exports settle.
    visible_names(own_names: _Names[], exported: _Names[], shadow: HashSet<String>[]): _Names[] {
        ulong n = files.count;
        var exports_of = Array<_Names>();
        var visible = Array<_Names>();
        for (var e in exported) {
            exports_of.append(_copy_names(e));
        }
        for (var o in own_names) {
            visible.append(_copy_names(o));
        }
        var prelude_files = Array<ulong>();
        ulong j = 0;
        while (j < n) {
            if (files[j].prelude) {
                prelude_files.append(j);
            }
            j += 1;
        }
        # A file is looked at again only once the exports of a file it reads
        # (a prelude file or an import) have changed since it last was.
        var reads = Array<Array<ulong>>();
        ulong r = 0;
        while (r < n) {
            var from = Array<ulong>();
            for (var p in prelude_files) {
                if (p != r) {
                    from.append(p);
                }
            }
            for (var t_index in files[r].imports) {
                if (t_index.is_value()) {
                    from.append(t_index.value());
                }
            }
            reads.append(from);
            r += 1;
        }
        ulong clock = 1;
        var exports_changed = Array<ulong>();
        var looked = Array<ulong>();
        r = 0;
        while (r < n) {
            exports_changed.append(0);
            looked.append(0);
            r += 1;
        }
        while (true) {
            bool changed = false;
            ulong i = 0;
            while (i < n) {
                if (looked[i] > 0) {
                    bool stale = false;
                    for (var t in reads[i]) {
                        stale = stale or exports_changed[t] > looked[i];
                    }
                    if (!stale) {
                        i += 1;
                        continue;
                    }
                }
                clock += 1;
                looked[i] = clock;
                var seen = _copy_names(own_names[i]);
                for (var p in prelude_files) {
                    if (p == i) {
                        continue;
                    }
                    for (var (k, v) in exports_of[p]) {
                        if (!shadow[i].contains(k)) {
                            _add_names(seen, k, v);
                        }
                    }
                }
                var qualified = HashMap<String, ulong>();
                var module = files[i].module;
                ulong m = 0;
                while (m < module.imports.count) {
                    var imp = module.imports[m];
                    var t_index = files[i].imports[m];
                    m += 1;
                    if (!target.keeps(imp.attributes) or !t_index.is_value()) {
                        continue;
                    }
                    var t = t_index.value();
                    # `export ... from` publishes names and binds none here.
                    if (imp.reexport) {
                        var published = Array<(String, HashSet<ulong>)>();
                        if (imp.symbols.is_value()) {
                            for (var s in imp.symbols.value()) {
                                var v = exports_of[t].try_get(s.name);
                                if (v.is_value()) {
                                    published.append((s.local_name(), v.value().copy()));
                                }
                            }
                        } else {
                            for (var (k, v) in exports_of[t]) {
                                published.append((k, v.copy()));
                            }
                        }
                        for (var (k, v) in published) {
                            if (_add_names(exports_of[i], k, v)) {
                                changed = true;
                                exports_changed[i] = clock;
                            }
                        }
                        continue;
                    }
                    var q = imp.qualifier();
                    if (!imp.symbols.is_value() and q.is_value()) {
                        qualified[q.value()] = t;
                    }
                    if (imp.symbols.is_value()) {
                        for (var s in imp.symbols.value()) {
                            var v = exports_of[t].try_get(s.name);
                            if (v.is_value() and !shadow[i].contains(s.local_name())) {
                                _add_names(seen, s.local_name(), v.value().copy());
                            }
                        }
                    } else if (!q.is_value()) {
                        var listed = Array<(String, HashSet<ulong>)>();
                        for (var (k, v) in exports_of[t]) {
                            listed.append((k, v.copy()));
                        }
                        for (var (k, v) in listed) {
                            if (!shadow[i].contains(k)) {
                                _add_names(seen, k, v);
                            }
                        }
                    }
                }
                for (var ea in module.exports) {
                    if (!target.keeps(ea.attributes)) {
                        continue;
                    }
                    # `export q.x` names the export `x` of the file `q`
                    # names.
                    HashSet<ulong>? found = Optional<HashSet<ulong>>.Empty;
                    var split = ea.symbol.split_once(".");
                    if (split.is_value()) {
                        var (qualifier, x) = split.value();
                        var t = qualified.try_get(qualifier);
                        if (t.is_value()) {
                            var v = exports_of[t.value()].try_get(x);
                            if (v.is_value()) {
                                found = Optional<HashSet<ulong>>.Value(v.value().copy());
                            }
                        }
                    } else {
                        var v = seen.try_get(ea.symbol);
                        if (v.is_value()) {
                            found = Optional<HashSet<ulong>>.Value(v.value().copy());
                        }
                    }
                    if (found.is_value() and _add_names(exports_of[i], ea.exported_name(), found.value())) {
                        changed = true;
                        exports_changed[i] = clock;
                    }
                }
                if (!_same_names(seen, visible[i])) {
                    visible[i] = seen;
                    changed = true;
                }
                i += 1;
            }
            if (!changed) {
                return visible;
            }
        }
        return visible;
    }

    # Per file, the visible names of the declarations `kind` accepts: 0 for
    # structs, aliases and traits, 1 for structs and aliases.
    _visible_types(value_only: bool): HashSet<String>[] {
        var own_names = Array<_Names>();
        var shared_names = Array<_Names>();
        var exported = Array<_Names>();
        var shadow = Array<HashSet<String>>();
        for (var f in files) {
            var all = _Names();
            var shared = _Names();
            var out = _Names();
            var keys = HashSet<String>();
            for (var d in named_decls(f.module)) {
                bool accepted = false;
                match (d) {
                    Struct(_) => {
                        accepted = true;
                    }
                    TypeAlias(_) => {
                        accepted = true;
                    }
                    Trait(_) => {
                        accepted = !value_only;
                    }
                    else => {}
                }
                if (!accepted) {
                    continue;
                }
                all[d.declared_name()] = HashSet<ulong>();
                if (!d.is_private()) {
                    shared[d.declared_name()] = HashSet<ulong>();
                }
                keys.insert(d.declared_name());
                if (d.is_exported()) {
                    out[d.declared_name()] = HashSet<ulong>();
                }
            }
            own_names.append(all);
            shared_names.append(shared);
            exported.append(out);
            shadow.append(keys);
        }
        # Imports come before the module's other files.
        var out = Array<HashSet<String>>();
        for (var v in visible_names(_with_mates(own_names, shared_names), exported, shadow)) {
            var keys = HashSet<String>();
            for (var (k, _) in v) {
                keys.insert(k);
            }
            out.append(keys);
        }
        return out;
    }

    _bases_of(i: ulong, exported_only: bool, shared_only: bool): _Names {
        var out = _Names();
        for (var d in named_decls(files[i].module)) {
            match (d) {
                Function(f) => {
                    if ((exported_only and !f.is_exported) or (shared_only and f.is_private)) {
                        continue;
                    }
                    bool base = false;
                    for (var p in f.generic_params) {
                        if (p.bounds.count > 0 or !_names_type(value_types_of[i], p.name)) {
                            base = true;
                        }
                    }
                    if (base) {
                        if (!out.contains(f.name)) {
                            out[f.name] = HashSet<ulong>();
                        }
                        out[f.name].insert(f.generic_params.count);
                    }
                }
                else => {}
            }
        }
        return out;
    }

    # Per file, the other files of the program in its module: those with the
    # same module folder. A file outside any module has none.
    compute_mates() {
        var by_root = HashMap<String, ulong[]>();
        ulong i = 0;
        while (i < files.count) {
            var root = files[i].module_root;
            if (root.is_value()) {
                var key = root.value().to_string();
                if (!by_root.contains(key)) {
                    by_root[key] = Array<ulong>();
                }
                by_root[key].append(i);
            }
            i += 1;
        }
        i = 0;
        while (i < files.count) {
            var out = Array<ulong>();
            var root = files[i].module_root;
            if (root.is_value()) {
                for (var j in by_root[root.value().to_string()]) {
                    if (j != i) {
                        out.append(j);
                    }
                }
            }
            all_mates.append(out);
            # A file sees another file of its module only through an import
            # of it.
            var imported = Array<ulong>();
            for (var j in out) {
                if (imports_file(i, j)) {
                    imported.append(j);
                }
            }
            mates.append(imported);
            i += 1;
        }
    }

    # Per file, `own` with the names of its module's other files added: a
    # file sees them as its own, except their `private` ones (`shared`, per
    # file).
    _with_mates(own_names: _Names[], shared: _Names[]): _Names[] {
        var out = Array<_Names>();
        ulong i = 0;
        while (i < files.count) {
            var names_here = _copy_names(own_names[i]);
            for (var j in mates[i]) {
                for (var (k, v) in shared[j]) {
                    _add_names(names_here, k, v);
                }
            }
            out.append(names_here);
            i += 1;
        }
        return out;
    }

    # Per file, the names the files of its module that it imports declare
    # (`mates`). The functions it and those files declare under one name form
    # one overload set, a union. Externs keep their names. Any other name
    # declared by two files of one module is the first one's; the visibility
    # check reports the second. A `private` declaration is bound for no other
    # file.
    compute_module_names() {
        ulong i = 0;
        while (i < files.count) {
            module_names.append(HashMap<String, String>());
            i += 1;
        }
        i = 0;
        while (i < files.count) {
            if (mates[i].count == 0) {
                i += 1;
                continue;
            }
            var group = Array<ulong>();
            group.append(i);
            group.append_all(mates[i]);
            # In path order: the first declaration of a name is the one kept.
            group.sort((a, b) => files[a].name.compare(files[b].name));
            # name -> (declaring file, the name it takes, a function).
            var by_name = Map<String, _ModuleDeclaration[]>();
            for (var j in group) {
                var seen = HashSet<String>();
                for (var d in named_decls(files[j].module)) {
                    # A `private` declaration is its file's alone.
                    if (d.is_private() and j != i) {
                        continue;
                    }
                    var name = d.declared_name();
                    var c = own[j].try_get(name);
                    if (!c.is_value() or !seen.insert(name)) {
                        continue;
                    }
                    bool function = false;
                    match (d) {
                        Function(f) => {
                            function = !f.external;
                        }
                        else => {}
                    }
                    if (!by_name.contains(name)) {
                        by_name[name] = Array<_ModuleDeclaration>();
                    }
                    by_name[name].append(_ModuleDeclaration(c.value(), function, j, d.is_private()));
                }
            }
            for (var (name, all_declared) in by_name) {
                # A name the file declares only privately is its own alone,
                # and joins no union.
                bool only_private = false;
                var declared = Array<_ModuleDeclaration>();
                for (var d in all_declared) {
                    if (d.file == i and d.file_private) {
                        only_private = true;
                    } else {
                        declared.append(d);
                    }
                }
                if (only_private or declared.is_empty) {
                    continue;
                }
                bool all_functions = true;
                for (var d in declared) {
                    if (!d.function) {
                        all_functions = false;
                    }
                }
                bool union = declared.count > 1 and all_functions;
                var canonical = declared[0].name;
                if (union) {
                    String? merged = Optional<String>.Value(declared[0].name);
                    ulong k = 1;
                    while (k < declared.count and merged.is_value()) {
                        merged = unions.merge(merged.value(), declared[k].name);
                        k += 1;
                    }
                    if (!merged.is_value()) {
                        continue;
                    }
                    canonical = merged.value();
                }
                if (union or !own[i].contains(name)) {
                    module_names[i][name] = canonical;
                }
            }
            i += 1;
        }
    }

    # The override rule over the files of the program, before linking.
    compute_overrides() {
        # An override's type argument may name any type, and is an error
        # unless it names a struct; a generic base is a function with a
        # parameter that names no struct or alias its file can see.
        types_of = _visible_types(false);
        value_types_of = _visible_types(true);
        var own_bases = Array<_Names>();
        var shared_bases = Array<_Names>();
        var exported_bases = Array<_Names>();
        ulong i = 0;
        while (i < files.count) {
            own_bases.append(_bases_of(i, false, false));
            shared_bases.append(_bases_of(i, false, true));
            exported_bases.append(_bases_of(i, true, false));
            i += 1;
        }
        # A file's own declaration of a name hides what its imports bind
        # under that name: a plain function, or a generic base.
        var plain = Array<HashSet<String>>();
        var shadow = Array<HashSet<String>>();
        i = 0;
        while (i < files.count) {
            var names_here = HashSet<String>();
            for (var d in named_decls(files[i].module)) {
                bool generic = false;
                match (d) {
                    Function(f) => {
                        generic = f.generic_params.count > 0;
                    }
                    else => {}
                }
                if (!generic) {
                    names_here.insert(d.declared_name());
                }
            }
            var hidden = names_here.copy();
            for (var (k, _) in own_bases[i]) {
                hidden.insert(k);
            }
            plain.append(names_here);
            shadow.append(hidden);
            i += 1;
        }
        bases = visible_names(_with_mates(own_bases, shared_bases), exported_bases, shadow);
        var none = Array<_Names>();
        i = 0;
        while (i < files.count) {
            none.append(_Names());
            i += 1;
        }
        imported_bases = visible_names(none, exported_bases, plain);
    }

    # Whether file `i`'s exports keep their names in the merged program:
    # the root file's, and the prelude's.
    exports_keep_names(i: ulong): bool {
        return i == 0 or files[i].prelude or files[i].prelude_part;
    }

    # Whether `d` keeps its name in the merged program: an export of a file
    # whose exports keep their names, an extern, or a concrete override.
    keeps_name(d: Declaration, file: ulong, bare_exports: bool): bool {
        if (d.is_exported() and bare_exports) {
            return true;
        }
        match (d) {
            Function(f) => {
                return f.external or is_override(f, file);
            }
            else => {}
        }
        return false;
    }

    # Every file's own names. The root file's private names are mangled only
    # where another file keeps the same name; every other file's are.
    compute_own_names() {
        var kept = HashSet<String>();
        ulong i = 1;
        while (i < files.count) {
            for (var d in named_decls(files[i].module)) {
                if (keeps_name(d, i, exports_keep_names(i))) {
                    kept.insert(d.declared_name());
                }
            }
            i += 1;
        }
        i = 0;
        while (i < files.count) {
            var f = files[i];
            bool bare_exports = exports_keep_names(i);
            var kept_here = HashSet<String>();
            var decls = named_decls(f.module);
            for (var d in decls) {
                bool keep_it = d.is_exported() and bare_exports;
                match (d) {
                    Function(func) => {
                        if (func.external) {
                            keep_it = true;
                        }
                    }
                    else => {}
                }
                if (keep_it) {
                    kept_here.insert(d.declared_name());
                }
            }
            var names_here = HashMap<String, String>();
            for (var d in decls) {
                bool skip = false;
                match (d) {
                    Function(func) => {
                        skip = is_override(func, i);
                    }
                    else => {}
                }
                if (skip) {
                    continue;
                }
                var name = d.declared_name();
                bool mangled = !kept_here.contains(name) and (i > 0 or kept.contains(name));
                names_here[name] = mangled ? names.mangle(name, f.namespace) : name;
                var linked = names_here[name];
                if (!declared_in.contains(linked)) {
                    declared_in[linked] = Array<ulong>();
                }
                declared_in[linked].append(i);
            }
            own.append(names_here);
            i += 1;
        }
    }

    compute_unions() {
        ulong i = 0;
        while (i < files.count) {
            var f = files[i];
            if (!f.prelude and !f.prelude_part) {
                var module = f.module_root.is_value() ? f.module_root.value().to_string() : f.name;
                for (var d in named_decls(f.module)) {
                    match (d) {
                        Function(func) => {
                            if (!func.external and !is_override(func, i)) {
                                var name = own[i].try_get(func.name);
                                if (name.is_value()) {
                                    unions.functions[name.value()] = module;
                                }
                            }
                        }
                        else => {}
                    }
                }
            }
            i += 1;
        }
    }

    # The names of a file's exported concrete overrides.
    exported_overrides(i: ulong): String[] {
        var out = Array<String>();
        for (var d in named_decls(files[i].module)) {
            match (d) {
                Function(f) => {
                    if (f.is_exported and is_override(f, i)) {
                        out.append(f.name);
                    }
                }
                else => {}
            }
        }
        return out;
    }

    # The name a concrete override named `name` takes, when it overrides a
    # generic reached under another name.
    override_rename(name: String, own_names: HashMap<String, String>, bindings: _Bindings): String? {
        if (own_names.contains(name)) {
            return Optional<String>.Empty;
        }
        match (_resolve_imported(name, bindings, prelude)) {
            Declared(c, _) => {
                if (c != name) {
                    return Optional<String>.Value(c);
                }
            }
            else => {}
        }
        return Optional<String>.Empty;
    }

    # Every prelude file's exports: name -> the declaration it denotes. The
    # first definition of a name wins.
    prelude_exports(): HashMap<String, String> {
        var out = HashMap<String, String>();
        ulong i = 0;
        while (i < files.count) {
            if (files[i].prelude) {
                for (var (k, v) in exports[i]) {
                    if (!out.contains(k)) {
                        out[k] = v;
                    }
                }
            }
            i += 1;
        }
        return out;
    }

    # Resolves a re-export's symbol (`x` or `q.x`) in file scope.
    resolve_top_level(symbol: String, own_names: HashMap<String, String>, bindings: _Bindings): Result<String, String> {
        var split = symbol.split_once(".");
        if (split.is_value()) {
            var (q, name) = split.value();
            var target_file = bindings.qualified.try_get(q);
            if (!target_file.is_value()) {
                return Result<String, String>.err($"'{q}' is not an imported module");
            }
            var c = exports[target_file.value()].try_get(name);
            if (!c.is_value()) {
                return Result<String, String>.err($"'{name}' is not exported by '{q}'");
            }
            return Result<String, String>.ok(c.value());
        }
        var mine = own_names.try_get(symbol);
        if (mine.is_value()) {
            return Result<String, String>.ok(mine.value());
        }
        match (_resolve_imported(symbol, bindings, prelude)) {
            Declared(c, _) => {
                return Result<String, String>.ok(c);
            }
            Ambiguous => {
                return Result<String, String>.err(_ambiguous(symbol));
            }
            Unknown => {
                return Result<String, String>.err(
                    $"cannot export '{symbol}': no such symbol in this file or its imports"
                );
            }
        }
        return Result<String, String>.err("");
    }

    # Binds file `i`'s imports against the current export tables, reporting
    # to `out`. Whole-file imports bind first, so a symbol named in an
    # import list always wins over a whole-file import of the same name.
    bind_imports(i: ulong, out: ModuleError[]): _Bindings {
        var b = _Bindings();
        b.module = module_names[i];
        var module = files[i].module;
        var own_names = own[i];
        # Whether each import resolved to a module folder, by span start.
        var folder = HashMap<ulong, bool>();
        ulong m = 0;
        while (m < module.imports.count) {
            folder[module.imports[m].span.start] = files[i].folder_imports[m];
            m += 1;
        }
        # An import platform selection drops binds nothing, and is no
        # error.
        var kept = Array<ulong>();
        m = 0;
        while (m < module.imports.count) {
            var imp = module.imports[m];
            if (!imp.reexport and target.keeps(imp.attributes)) {
                kept.append(m);
            }
            m += 1;
        }
        for (var k in kept) {
            if (files[i].imports[k].is_value()) {
                continue;
            }
            var imp = module.imports[k];
            var q = imp.qualifier();
            if (q.is_value()) {
                b.unresolved.insert(q.value());
            }
            if (imp.symbols.is_value()) {
                for (var s in imp.symbols.value()) {
                    b.unresolved.insert(s.local_name());
                }
            } else if (!q.is_value()) {
                b.unresolved_whole_file = true;
            }
        }
        # Qualifiers and whole-file imports. Two whole-file imports that
        # bind a name to different declarations make it ambiguous.
        for (var k in kept) {
            var t_index = files[i].imports[k];
            var imp = module.imports[k];
            if (!t_index.is_value() or imp.symbols.is_value()) {
                continue;
            }
            var t = t_index.value();
            var q = imp.qualifier();
            if (q.is_value()) {
                var existing = b.qualified.try_get(q.value());
                if (own_names.contains(q.value())) {
                    out.append(ModuleError(i, imp.span, $"'{q.value()}' is imported but also declared in this file"));
                } else if (existing.is_value() and existing.value() != t) {
                    out.append(ModuleError(i, imp.span, $"'{q.value()}' is already imported"));
                } else {
                    b.qualified[q.value()] = t;
                }
                continue;
            }
            for (var (name, c) in exports[t]) {
                # The file's own functions of the name (with its module's)
                # join an imported set of it; anything else of the file's own
                # hides the import.
                var mine = own_names.try_get(name);
                if (mine.is_value()) {
                    var seed = module_names[i].try_get(name).value_or(mine.value());
                    var bound = b.unqualified.try_get(name);
                    if (bound.is_value() and bound.value().is_value()) {
                        seed = bound.value().value();
                    }
                    var union = unions.merge(seed, c);
                    if (union.is_value()) {
                        b.unqualified[name] = union;
                    }
                    continue;
                }
                var bound = b.unqualified.try_get(name);
                if (!bound.is_value()) {
                    b.unqualified[name] = Optional<String>.Value(c);
                } else if (bound.value().is_value() and bound.value().value() != c) {
                    b.unqualified[name] = unions.merge(bound.value().value(), c);
                }
            }
        }
        # Named symbols replace whatever a whole-file import bound.
        var explicit = HashMap<String, String>();
        for (var k in kept) {
            var t_index = files[i].imports[k];
            var imp = module.imports[k];
            if (!t_index.is_value() or !imp.symbols.is_value()) {
                continue;
            }
            var t = t_index.value();
            for (var s in imp.symbols.value()) {
                var found = exports[t].try_get(s.name);
                if (!found.is_value()) {
                    var described = imp.describe_as(folder.try_get(imp.span.start).value_or(false));
                    out.append(ModuleError(i, s.name_span, $"'{s.name}' is not exported by {described}"));
                    continue;
                }
                var c = found.value();
                var local = s.local_name();
                # Only functions join the file's own of the name.
                var existing = explicit.try_get(local);
                if (!existing.is_value() and own_names.contains(local)) {
                    existing = module_names[i].try_get(local);
                }
                if (!existing.is_value()) {
                    existing = own_names.try_get(local);
                }
                if (own_names.contains(local) and !unions.merge(existing.value(), c).is_value()) {
                    out.append(ModuleError(i, s.span, $"'{local}' is imported but also declared in this file"));
                    continue;
                }
                String? merged = Optional<String>.Value(c);
                if (existing.is_value() and existing.value() != c) {
                    merged = unions.merge(existing.value(), c);
                }
                if (!merged.is_value()) {
                    out.append(ModuleError(i, s.span, $"'{local}' is already imported as a different symbol"));
                } else {
                    explicit[local] = merged.value();
                    b.unqualified[local] = merged;
                }
            }
        }
        # `import m;` with `import [m] from n;` would make `m.x` and a bare
        # `m` name different things.
        for (var k in kept) {
            var imp = module.imports[k];
            var q = imp.qualifier();
            if (q.is_value() and b.unqualified.contains(q.value())) {
                out.append(ModuleError(i, imp.span, $"'{q.value()}' is imported both as a module and as a symbol"));
            }
        }
        return b;
    }

    # File `i`'s exports: its `export` declarations (`direct`) plus its
    # re-exports, resolved against `bindings`, reporting to `out`.
    resolve_reexports(
        i: ulong, direct: HashMap<String, String>, bindings: _Bindings, out: ModuleError[]
    ): HashMap<String, String> {
        var table = direct.copy();
        var own_names = own[i];
        var module = files[i].module;
        # An exported override is exported under its generic's name, as
        # linking renames it.
        for (var name in exported_overrides(i)) {
            var c = override_rename(name, own_names, bindings);
            if (c.is_value()) {
                table.remove(name);
                table[names.demangle_name(c.value())] = c.value();
            }
        }
        # Where each name `table` publishes came from, for "also exported
        # here".
        var origins = HashMap<String, Span>();
        for (var d in named_decls(module)) {
            if (d.is_exported()) {
                origins[d.declared_name()] = d.name_span();
            }
        }
        # `export * from source` and `export [...] from source`, in order.
        ulong m = 0;
        while (m < module.imports.count) {
            var imp = module.imports[m];
            var t_index = files[i].imports[m];
            bool folder = files[i].folder_imports[m];
            m += 1;
            if (!imp.reexport) {
                continue;
            }
            var kept = target.keep(imp.attributes);
            if (kept.is_err() or !kept.value() or !t_index.is_value()) {
                continue;
            }
            var t = t_index.value();
            if (!imp.symbols.is_value()) {
                var listed = Array<String>();
                for (var (name, _) in exports[t]) {
                    listed.append(name);
                }
                listed.sort((a, b) => a.compare(b));
                for (var name in listed) {
                    _publish(i, table, origins, name, exports[t][name], imp.span, out);
                }
                continue;
            }
            for (var s in imp.symbols.value()) {
                var c = exports[t].try_get(s.name);
                if (c.is_value()) {
                    _publish(i, table, origins, s.local_name(), c.value(), s.span, out);
                } else {
                    out.append(ModuleError(i, s.name_span, $"'{s.name}' is not exported by {imp.describe_as(folder)}"));
                }
            }
        }
        for (var ea in module.exports) {
            var kept = target.keep(ea.attributes);
            if (kept.is_err()) {
                out.append(ModuleError(i, ea.span, kept.error()));
                continue;
            }
            if (!kept.value()) {
                continue;
            }
            var first = ea.symbol.split(".")[0];
            if (bindings.unresolved.contains(first) and !own_names.contains(first)) {
                continue;
            }
            var resolved = resolve_top_level(ea.symbol, own_names, bindings);
            if (resolved.is_ok()) {
                var canonical = resolved.value();
                var name = ea.exported_name();
                var existing = table.try_get(name);
                if (existing.is_value() and existing.value() != canonical) {
                    var union = unions.merge(existing.value(), canonical);
                    if (union.is_value()) {
                        table[name] = union.value();
                    } else {
                        out.append(
                            ModuleError(
                                i, ea.span, $"'{name}' is exported twice, as '{existing.value()}' and '{canonical}'"
                            )
                        );
                    }
                } else {
                    table[name] = canonical;
                }
            } else if (!(bindings.unresolved_whole_file and !ea.symbol.contains("."))) {
                out.append(ModuleError(i, ea.symbol_span, resolved.error()));
            }
        }
        return table;
    }

    _publish(
        i: ulong,
        table: HashMap<String, String>,
        origins: HashMap<String, Span>,
        name: String,
        canonical: String,
        span: Span,
        out: ModuleError[]
    ) {
        var existing = table.try_get(name);
        if (!existing.is_value()) {
            table[name] = canonical;
            origins[name] = span;
            return;
        }
        if (existing.value() == canonical) {
            return;
        }
        var union = unions.merge(existing.value(), canonical);
        if (union.is_value()) {
            table[name] = union.value();
            return;
        }
        var error = ModuleError(i, span, $"'{name}' is exported twice by {_describe_file(files[i])}");
        var origin = origins.try_get(name);
        if (origin.is_value()) {
            error.note_span = origin;
            error.note = "also exported here";
        }
        out.append(error);
    }

    # File `i`'s import-list entries and re-exports that denote a
    # declaration.
    named_bindings(i: ulong, bindings: _Bindings): HashMap<ulong, String> {
        var named = HashMap<ulong, String>();
        var module = files[i].module;
        ulong m = 0;
        while (m < module.imports.count) {
            var imp = module.imports[m];
            var t = files[i].imports[m];
            m += 1;
            if (!imp.symbols.is_value() or !t.is_value()) {
                continue;
            }
            for (var s in imp.symbols.value()) {
                var c = exports[t.value()].try_get(s.name);
                if (c.is_value()) {
                    named[s.span.start] = c.value();
                }
            }
        }
        for (var ea in module.exports) {
            var c = resolve_top_level(ea.symbol, own[i], bindings);
            if (c.is_ok()) {
                named[ea.symbol_span.start] = c.value();
            }
        }
        return named;
    }

    # Per file, the other files that extend a type it declares.
    extended_by(): HashSet<ulong>[] {
        var out = Array<HashSet<ulong>>();
        for (var _ in 0..files.count) {
            out.append(HashSet<ulong>());
        }
        for (var (extended, file) in members.extended_in) {
            var declared = members.declared_in.try_get(extended);
            if (declared.is_value() and declared.value() != file) {
                out[declared.value()].insert(file);
            }
        }
        return out;
    }

    # Per file, the other files whose exported extensions it may use: the
    # prelude, the files it imports, and every file of a module it imports.
    visible_extensions(): HashSet<ulong>[] {
        var everywhere = HashSet<ulong>();
        ulong j = 0;
        while (j < files.count) {
            if (files[j].prelude or files[j].prelude_part) {
                everywhere.insert(j);
            }
            j += 1;
        }
        var out = Array<HashSet<ulong>>();
        ulong i = 0;
        for (var f in files) {
            var visible = everywhere.copy();
            # The other files of its own module: their extensions are
            # visible exported or not.
            for (var mate in mates[i]) {
                visible.insert(mate);
            }
            i += 1;
            ulong m = 0;
            while (m < f.module.imports.count) {
                var imp = f.module.imports[m];
                var t = f.imports[m];
                bool folder = f.folder_imports[m];
                m += 1;
                if (imp.reexport or !target.keeps(imp.attributes) or !t.is_value()) {
                    continue;
                }
                visible.insert(t.value());
                var root = files[t.value()].module_root;
                if ((!imp.is_local or folder) and root.is_value()) {
                    j = 0;
                    while (j < files.count) {
                        var other = files[j].module_root;
                        if (other.is_value() and other.value().to_string() == root.value().to_string()) {
                            visible.insert(j);
                        }
                        j += 1;
                    }
                }
            }
            out.append(visible);
        }
        return out;
    }

    _resolve_or_name(i: ulong, bindings: _Bindings, name: String): String {
        var resolved = resolve_top_level(name, own[i], bindings);
        return resolved.is_ok() ? resolved.value() : name;
    }

    # Struct member names by struct, for hiding inside method bodies.
    compute_members(bindings: _Bindings[]) {
        ulong i = 0;
        while (i < files.count) {
            for (var d in files[i].module.declarations) {
                if (!target.keeps(d.attributes())) {
                    continue;
                }
                match (d) {
                    TypeAlias(t) => {
                        members.aliases[_resolve_or_name(
                            i, bindings[i], t.name
                        )] = _resolve_or_name(i, bindings[i], t.target.name);
                    }
                    else => {}
                }
            }
            i += 1;
        }
        i = 0;
        while (i < files.count) {
            for (var d in files[i].module.declarations) {
                if (!target.keeps(d.attributes())) {
                    continue;
                }
                match (d) {
                    Trait(t) => {
                        members.declared_in[own[i].try_get(t.name).value_or(t.name)] = i;
                    }
                    Struct(s) => {
                        var key = own[i].try_get(s.name).value_or(s.name);
                        members.declared_in[key] = i;
                        if (!members.of_body.contains(key)) {
                            members.of_body[key] = HashSet<String>();
                        }
                        var names_of = members.of_body[key];
                        for (var field in s.fields) {
                            names_of.insert(field.name);
                        }
                        for (var property in s.properties) {
                            names_of.insert(property.name);
                        }
                        for (var method in s.methods) {
                            if (target.keeps(method.attributes)) {
                                names_of.insert(method.name);
                            }
                        }
                    }
                    Extend(e) => {
                        var extended = members.resolve(_resolve_or_name(i, bindings[i], e.target.name));
                        members.extended_in.append((extended, i));
                        for (var t in e.traits) {
                            var trait_name = members.resolve(_resolve_or_name(i, bindings[i], t.name));
                            if (!members.adopters.contains(trait_name)) {
                                members.adopters[trait_name] = Array<String>();
                            }
                            members.adopters[trait_name].append(extended);
                        }
                        if (!members.of_extensions.contains(extended)) {
                            members.of_extensions[extended] = Array<_ExtensionMember>();
                        }
                        var list = members.of_extensions[extended];
                        for (var method in e.methods) {
                            if (target.keeps(method.attributes)) {
                                list.append(_ExtensionMember(method.name, i, e.is_exported, e.is_private));
                            }
                        }
                        for (var property in e.properties) {
                            list.append(_ExtensionMember(property.name, i, e.is_exported, e.is_private));
                        }
                    }
                    else => {}
                }
            }
            i += 1;
        }
    }

    run(): Linked {
        prepare();
        var all = Array<bool>();
        for (var _ in files) {
            all.append(true);
        }
        return finish(all);
    }

    # Binds every file's names and imports; `finish` rewrites the files.
    prepare() {
        ulong n = files.count;
        for (var f in files) {
            file_names.append(f.name);
        }
        compute_mates();
        compute_overrides();
        compute_own_names();
        compute_unions();
        compute_module_names();
        for (var f in files) {
            for (var d in named_decls(f.module)) {
                match (d) {
                    Struct(_) => {
                        types.insert(d.declared_name());
                    }
                    TypeAlias(_) => {
                        types.insert(d.declared_name());
                    }
                    Trait(_) => {
                        types.insert(d.declared_name());
                    }
                    else => {}
                }
            }
        }
        # Exports: direct `export` declarations first, then re-exports
        # resolved to a fixpoint, since a re-export may name another file's
        # re-export.
        var direct = Array<HashMap<String, String>>();
        ulong i = 0;
        while (i < n) {
            var table = HashMap<String, String>();
            for (var d in named_decls(files[i].module)) {
                if (d.is_exported()) {
                    table[d.declared_name()] = own[i].try_get(d.declared_name()).value_or(d.declared_name());
                }
            }
            direct.append(table);
            i += 1;
        }
        var override_counts = Array<ulong>();
        var reexport_counts = Array<ulong>();
        var is_reexporting = Array<bool>();
        var reexporting = Array<ulong>();
        bool any_reexport_lines = false;
        i = 0;
        while (i < n) {
            override_counts.append(exported_overrides(i).count);
            ulong lines = 0;
            for (var imp in files[i].module.imports) {
                if (imp.reexport) {
                    lines += imp.symbols.is_value() ? imp.symbols.value().count : 1;
                }
            }
            reexport_counts.append(lines);
            if (lines > 0) {
                any_reexport_lines = true;
            }
            bool reexports = files[i].module.exports.count > 0 or override_counts[i] > 0 or lines > 0;
            is_reexporting.append(reexports);
            if (reexports) {
                reexporting.append(i);
            }
            i += 1;
        }
        for (var table in direct) {
            exports.append(table.copy());
        }
        bool prelude_reexports = false;
        for (var r in reexporting) {
            if (files[r].prelude) {
                prelude_reexports = true;
            }
        }
        prelude = prelude_exports();
        # Per re-exporting file, from the round that last computed them:
        # its bindings with the errors binding reported, and the errors
        # resolving its re-exports reported.
        var bound = Array<_Bindings?>();
        var bound_errors = Array<ModuleError[]>();
        var resolve_errors = Array<ModuleError[]?>();
        i = 0;
        while (i < n) {
            bound.append(Optional<_Bindings>.Empty);
            bound_errors.append(Array<ModuleError>());
            resolve_errors.append(Optional<ModuleError[]>.Empty);
            i += 1;
        }
        # Files whose exports changed in the last round; none before the
        # first.
        HashSet<ulong>? changed = Optional<HashSet<ulong>>.Empty;
        bool prelude_changed = false;
        ulong rounds = 0;
        ulong settling = 0;
        for (var r in reexporting) {
            settling += files[r].module.exports.count + override_counts[r] + reexport_counts[r];
        }
        ulong direct_total = 0;
        for (var table in direct) {
            direct_total += table.count as ulong;
        }
        ulong max_rounds = settling * (any_reexport_lines ? direct_total.max(1) : 1) + 1;
        # Two functions of one name in one file overload each other, unless
        # a generic and another function have the same parameters.
        i = 0;
        while (i < n) {
            var functions = Array<FunctionDecl>();
            for (var d in named_decls(files[i].module)) {
                match (d) {
                    Function(func) => {
                        if (!is_override(func, i)) {
                            functions.append(func);
                        }
                    }
                    else => {}
                }
            }
            ulong k = 0;
            while (k < functions.count) {
                var func = functions[k];
                var shape = _parameter_shape(func);
                bool earlier = false;
                bool earlier_generic = false;
                ulong e = 0;
                while (e < k) {
                    var g = functions[e];
                    if (g.name == func.name and _parameter_shape(g) == shape) {
                        earlier = true;
                        if (g.generic_params.count > 0) {
                            earlier_generic = true;
                        }
                    }
                    e += 1;
                }
                bool names_types = func.generic_params.count > 0;
                for (var p in func.generic_params) {
                    if (!value_types_of[i].contains(p.name)) {
                        names_types = false;
                    }
                }
                bool clashes = earlier and (func.generic_params.count > 0 or earlier_generic);
                bool another = false;
                if (names_types) {
                    e = 0;
                    while (e < functions.count) {
                        if (e != k and functions[e].name == func.name) {
                            another = true;
                        }
                        e += 1;
                    }
                }
                if (clashes or another) {
                    _error(
                        i,
                        func.name_span,
                        $"redefinition of generic '{func.name}'; to override it for a type, each type argument must name a struct this file can see"
                    );
                }
                k += 1;
            }
            i += 1;
        }
        while (reexporting.count > 0) {
            var next_files = Array<ulong>();
            var next_tables = Array<HashMap<String, String>>();
            for (var r in reexporting) {
                bool inputs_changed = !changed.is_value();
                if (changed.is_value()) {
                    for (var t in files[r].imports) {
                        if (t.is_value() and changed.value().contains(t.value())) {
                            inputs_changed = true;
                        }
                    }
                }
                if (!inputs_changed and !prelude_changed) {
                    continue;
                }
                if (inputs_changed) {
                    var errs = Array<ModuleError>();
                    bound[r] = Optional<_Bindings>.Value(bind_imports(r, errs));
                    bound_errors[r] = errs;
                }
                var errs = Array<ModuleError>();
                var table = resolve_reexports(r, direct[r], bound[r].value(), errs);
                resolve_errors[r] = Optional<ModuleError[]>.Value(errs);
                if (!_same_table(table, exports[r])) {
                    next_files.append(r);
                    next_tables.append(table);
                }
            }
            rounds += 1;
            if (next_files.count == 0) {
                break;
            }
            if (rounds > max_rounds) {
                # Two files re-exporting through each other can flip
                # forever: report the re-exports still changing, and link
                # against the latest round.
                ulong x = 0;
                while (x < next_files.count) {
                    var r = next_files[x];
                    for (var ea in files[r].module.exports) {
                        var name = ea.exported_name();
                        var now = next_tables[x].try_get(name);
                        var before = exports[r].try_get(name);
                        bool same = now.is_value() == before.is_value()
                            and (!now.is_value() or now.value() == before.value());
                        if (!same) {
                            _error(
                                r,
                                ea.span,
                                $"cannot re-export '{name}': it depends on itself through an import that is ambiguous"
                            );
                        }
                    }
                    x += 1;
                }
                x = 0;
                while (x < next_files.count) {
                    exports[next_files[x]] = next_tables[x];
                    x += 1;
                }
                # Bindings from before this last change are stale.
                i = 0;
                while (i < n) {
                    bound[i] = Optional<_Bindings>.Empty;
                    resolve_errors[i] = Optional<ModuleError[]>.Empty;
                    i += 1;
                }
                prelude = prelude_exports();
                break;
            }
            prelude_changed = false;
            if (prelude_reexports) {
                for (var r in next_files) {
                    if (files[r].prelude) {
                        prelude_changed = true;
                    }
                }
            }
            var now_changed = HashSet<ulong>();
            ulong x = 0;
            while (x < next_files.count) {
                now_changed.insert(next_files[x]);
                exports[next_files[x]] = next_tables[x];
                x += 1;
            }
            changed = Optional<HashSet<ulong>>.Value(now_changed);
            if (prelude_changed) {
                prelude = prelude_exports();
            }
        }
        # A prelude re-export may not take the name of another prelude
        # file's export.
        i = 0;
        while (i < n) {
            if (files[i].prelude) {
                for (var ea in files[i].module.exports) {
                    if (!target.keeps(ea.attributes)) {
                        continue;
                    }
                    var name = ea.exported_name();
                    var c = exports[i].try_get(name);
                    bool renamed = c.is_value() and c.value() != name;
                    bool taken = false;
                    ulong j = 0;
                    while (j < n) {
                        if (j != i and files[j].prelude and direct[j].contains(name)) {
                            taken = true;
                        }
                        j += 1;
                    }
                    if (renamed and taken) {
                        _error(
                            i,
                            ea.span,
                            $"a forced import cannot replace '{name}' with an alias, since the runtime's own files would still call theirs; declare 'export {name}(...)' under that name instead"
                        );
                    }
                }
            }
            i += 1;
        }
        # Every file bound against the settled exports.
        var bindings = Array<_Bindings>();
        i = 0;
        while (i < n) {
            if (bound[i].is_value()) {
                errors.append_all(bound_errors[i]);
                if (resolve_errors[i].is_value()) {
                    errors.append_all(resolve_errors[i].value());
                }
                bindings.append(bound[i].value());
                i += 1;
                continue;
            }
            var b = bind_imports(i, errors);
            if (is_reexporting[i]) {
                resolve_reexports(i, direct[i], b, errors);
            }
            bindings.append(b);
            i += 1;
        }
        compute_members(bindings);
        var extensions = visible_extensions();
        i = 0;
        while (i < n) {
            for (var d in named_decls(files[i].module)) {
                match (d) {
                    Struct(s) => {
                        structs.insert(own[i].try_get(s.name).value_or(s.name));
                    }
                    Variable(v) => {
                        constants.insert(own[i].try_get(v.name).value_or(v.name));
                    }
                    else => {}
                }
            }
            i += 1;
        }
        prepared_bindings = bindings;
        prepared_extensions = extensions;
    }

    # Rewrites each file's spellings, the bodies only of the files
    # `bodies` marks, and returns the scopes and every error.
    finish(bodies: bool[]): Linked {
        ulong n = files.count;
        _extended_by = extended_by();
        var linked = Linked();
        ulong i = 0;
        while (i < n) {
            linked.scopes.append(finish_file(i, bodies[i]));
            i += 1;
        }
        sort_errors(errors);
        for (var error in errors) {
            if (linked.errors.count == 0 or !linked.errors[linked.errors.count - 1].same(error)) {
                linked.errors.append(error);
            }
        }
        linked.overload_unions = unions.by_module();
        return linked;
    }

    # Rewrites file `i`'s spellings, its bodies too when `bodies` says, and
    # returns its scope; its errors go to `errors`. After `finish`.
    finish_file(i: ulong, bodies: bool): FileScope {
        var bindings = prepared_bindings[i];
        var named = named_bindings(i, bindings);
        var rewriter = _Rewriter(this, i, bindings, prepared_extensions[i]);
        rewriter.bodies = bodies;
        rewriter.module(files[i].module);
        var scope = FileScope();
        scope.imported = rewriter.imported;
        scope.named = named;
        scope.extensions = prepared_extensions[i];
        scope.extended_by = _extended_by[i];
        for (var (_, c) in bindings.unqualified) {
            if (c.is_value()) {
                scope.bound.insert(c.value());
            }
        }
        for (var (_, t) in bindings.qualified) {
            for (var (_, c) in exports[t]) {
                scope.bound.insert(c);
            }
        }
        for (var (_, c) in bindings.module) {
            scope.bound.insert(c);
        }
        return scope;
    }
}

_same_table(a: HashMap<String, String>, b: HashMap<String, String>): bool {
    if (a.count != b.count) {
        return false;
    }
    for (var (k, v) in a) {
        var other = b.try_get(k);
        if (!other.is_value() or other.value() != v) {
            return false;
        }
    }
    return true;
}

## Sorts errors by file, then by where they start; errors at one place
## keep their order.
##
## @param errors the errors
export sort_errors(errors: ModuleError[]) {
    errors.sort((a, b) => {
        if (a.file != b.file) {
            return a.file < b.file ? -1 : 1;
        }
        if (a.span.start != b.span.start) {
            return a.span.start < b.span.start ? -1 : 1;
        }
        return 0;
    });
}

# A generic method's member name (`run<S>`) as a type, every part at
# `span`, or none when it does not spell back the same way.
_member_type(name: String, span: Span): TypeName? {
    var parsed = names.parse_type_string(name, span);
    if (parsed.to_string() != name) {
        return Optional<TypeName>.Empty;
    }
    return Optional<TypeName>.Value(parsed);
}

# Rewrites one file's imported spellings.
struct _Rewriter {
    var linker: _Linker;
    var file: ulong;
    var own_names: HashMap<String, String>;
    var bindings: _Bindings;
    # Other files whose exported extensions this file may use.
    var extensions: HashSet<ulong>;
    var walk_scopes: Scopes = Scopes();
    # The name span starts of this file's top-level concrete overrides,
    # decided before `module` renames them.
    var override_decls: HashSet<ulong> = HashSet<ulong>();
    var imported: HashMap<ulong, String> = HashMap<ulong, String>();
    # Whether to rewrite the bodies too.
    var bodies: bool = true;

    construct(linker: _Linker, file: ulong, bindings: _Bindings, extensions: HashSet<ulong>) {
        this.linker = linker;
        this.file = file;
        this.own_names = linker.own[file];
        this.bindings = bindings;
        this.extensions = extensions;
    }

    _error(span: Span, message: String) {
        linker.errors.append(ModuleError(file, span, message));
    }

    walks_bodies(): bool {
        return bodies;
    }

    module(module: Module) {
        for (var decl in module.declarations) {
            # A declaration this platform drops is never compiled, so what
            # it names from other modules need not exist here.
            if (!linker.target.keeps(decl.attributes())) {
                continue;
            }
            bool handled = false;
            match (decl) {
                Function(f) => {
                    if (linker.is_override(f, file)) {
                        handled = true;
                        # A concrete override of an imported generic takes
                        # the generic's name, as its call sites do.
                        override_decls.insert(f.name_span.start);
                        var c = linker.override_rename(f.name, own_names, bindings);
                        if (c.is_value()) {
                            f.name = c.value();
                        } else {
                            var mine = own_names.try_get(f.name);
                            if (mine.is_value()) {
                                f.name = mine.value();
                            }
                        }
                    }
                }
                else => {}
            }
            if (!handled) {
                var mine = own_names.try_get(decl.declared_name());
                if (mine.is_value()) {
                    decl.rename(mine.value());
                }
            }
            walk_declaration(decl);
        }
    }

    # Hidden where it is used: as a value, or as a type.
    _is_hidden(name: String, value: bool): bool {
        return value ? is_local(name) : walk_scopes.is_type_local(name);
    }

    # The qualifier `q` names an imported module here (not hidden).
    _qualifier(q: String): ulong? {
        if (own_names.contains(q) or is_local(q)) {
            return Optional<ulong>.Empty;
        }
        return bindings.qualified.try_get(q);
    }

    # `q.name` for an imported qualifier `q`: the declaration it denotes.
    _qualified(target_file: ulong, q: String, name: String, span: Span, value: bool): String? {
        var c = linker.exports[target_file].try_get(name);
        if (!c.is_value()) {
            _error(span, $"'{name}' is not exported by '{q}' ({linker.file_names[target_file]})");
            return Optional<String>.Empty;
        }
        return _denote($"{q}.{name}", c.value(), span, value, true);
    }

    # An unqualified name: rewritten when an import (or a prelude export)
    # binds it.
    _unqualified(name: String, span: Span, value: bool): String? {
        if (_is_hidden(name, value)) {
            return Optional<String>.Empty;
        }
        # The file's own declaration: renamed when it is private, or the
        # union its functions of the name form with an imported set.
        var mine = own_names.try_get(name);
        if (mine.is_value()) {
            var bound = bindings.unqualified.try_get(name);
            if (bound.is_value() and bound.value().is_value()) {
                return _denote(name, bound.value().value(), span, value, true);
            }
            var union = bindings.module.try_get(name);
            if (union.is_value()) {
                return _denote(name, union.value(), span, value, true);
            }
            return mine.value() != name ? mine : Optional<String>.Empty;
        }
        match (_resolve_imported(name, bindings, linker.prelude)) {
            Declared(c, from_import) => {
                return _denote(name, c, span, value, from_import);
            }
            Ambiguous => {
                _error(span, _ambiguous(name));
            }
            Unknown => {
                linker.report_unimported_mate(file, name, span);
            }
        }
        return Optional<String>.Empty;
    }

    # `spelled` denotes the declaration `c`: record the import, unless a
    # local of that name would capture the rewritten reference.
    _denote(spelled: String, c: String, span: Span, value: bool, from_import: bool): String? {
        if (value and from_import and !is_local(c) and _is_any_extension_method(c)) {
            _error(
                span,
                $"'{spelled}' refers to the imported '{c}', but an extension in another file gives this struct a method '{c}' that would be called instead; rename one"
            );
            return Optional<String>.Empty;
        }
        if (spelled != c and _is_hidden(c, value)) {
            _error(
                span,
                $"'{spelled}' refers to '{c}', which a local, parameter, or member named '{c}' hides here; rename it"
            );
            return Optional<String>.Empty;
        }
        imported[span.start] = c;
        return Optional<String>.Value(c);
    }

    # `name` is a method some extension adds to the struct whose methods
    # are being walked (in a trait's default methods, to any struct an
    # extension makes conform to the trait).
    _is_any_extension_method(name: String): bool {
        var candidates = Array<String>();
        var current = walk_scopes.current_struct();
        if (current.is_value()) {
            candidates.append(linker.members.resolve(current.value()));
        } else {
            var current_trait = walk_scopes.current_trait();
            if (current_trait.is_value()) {
                var adopters = linker.members.adopters.try_get(linker.members.resolve(current_trait.value()));
                if (adopters.is_value()) {
                    candidates = adopters.value();
                }
            }
        }
        for (var candidate in candidates) {
            var extension = linker.members.of_extensions.try_get(candidate);
            if (extension.is_value()) {
                for (var member in extension.value()) {
                    if (member.name == name) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
}

extend _Rewriter with ScopeWalk {
    scopes(): Scopes {
        return walk_scopes;
    }

    keeps(attributes: Attribute[]): bool {
        return linker.target.keeps(attributes);
    }

    is_member(struct_name: String, name: String): bool {
        var resolved = linker.members.resolve(struct_name);
        var body = linker.members.of_body.try_get(resolved);
        if (body.is_value() and body.value().contains(name)) {
            return true;
        }
        var extension = linker.members.of_extensions.try_get(resolved);
        if (extension.is_value()) {
            for (var member in extension.value()) {
                if (member.name == name
                    and (member.file == file
                        or (!member.file_private and linker.mates[file].contains(member.file))
                        or (member.exported and extensions.contains(member.file)))) {
                    return true;
                }
            }
        }
        return false;
    }

    # `extend Box<T>` introduces T; `extend Array<Pt>`, with `Pt` imported
    # or declared by any file, specializes and is rewritten like any
    # reference.
    extend_params(target_type: TypeName): HashSet<String> {
        var out = HashSet<String>();
        for (var t in target_type.generic_types) {
            if (t.generic_types.count > 0 or own_names.contains(t.name) or linker.types.contains(t.name)) {
                continue;
            }
            if (bindings.qualified.contains(t.name.split(".")[0])) {
                continue;
            }
            match (_resolve_imported(t.name, bindings, linker.prelude)) {
                Unknown => {
                    out.insert(t.name);
                }
                else => {}
            }
        }
        return out;
    }

    # An override's parameters are types, so each takes the name of the
    # struct it denotes, mangled or imported.
    visit_function_generics(function: FunctionDecl): bool {
        if (!override_decls.contains(function.name_span.start)) {
            return false;
        }
        for (var p in function.generic_params) {
            p.is_argument = true;
            if (names.is_concrete_override([p.name])) {
                continue;
            }
            # A struct this file declares, or one an import or the prelude
            # reaches; not another file's private struct.
            var c = own_names.try_get(p.name);
            if (!c.is_value()) {
                c = _unqualified(p.name, p.name_span, false);
            }
            if (c.is_value() and linker.structs.contains(c.value())) {
                p.name = c.value();
                continue;
            }
            if (c.is_value()) {
                _error(p.name_span, $"'{p.name}' is not a struct; an override's type argument must name a struct");
            } else {
                _error(p.name_span, $"unknown type name '{p.name}'");
            }
        }
        _check_orphan(function);
        return true;
    }

    # The orphan rule: an override goes where its generic or one of its
    # type arguments is declared, so every file that reaches both sees it.
    _check_orphan(function: FunctionDecl) {
        var home = linker.home(file);
        if (linker.declared_at(function.name, home)) {
            return;
        }
        var arguments = Array<String>();
        for (var p in function.generic_params) {
            bool built_in = names.is_concrete_override([p.name]);
            if (built_in and home == _PRELUDE_HOME) {
                return;
            }
            if (!built_in and linker.declared_at(p.name, home)) {
                return;
            }
            arguments.append($"'{names.demangle_name(p.name)}'");
        }
        var generic = names.demangle_name(function.name);
        _error(
            function.name_span,
            $"cannot override '{generic}' for {", ".join(arguments)} here: an override must be in the file or module that declares '{generic}' or one of its type arguments"
        );
    }

    visit_expression(e: Expression): Expression {
        match (e) {
            MemberAccess(lhs, name, _, span) => {
                match (lhs) {
                    SymbolRef(id, _) => {
                        var target_file = _qualifier(id);
                        if (target_file.is_value()) {
                            # The rewritten reference keeps the whole
                            # `q.name` span, which the visibility check
                            # looks the import up by.
                            var c = _qualified(target_file.value(), id, name, span, true);
                            if (c.is_value()) {
                                return Expression.SymbolRef(c.value(), span);
                            }
                            return e;
                        }
                    }
                    else => {}
                }
            }
            else => {}
        }
        var walked = walk_expression(e);
        # `x.run<S>(...)`: the parser keeps a generic method's type
        # arguments in the member name, so they are resolved here like any
        # other type.
        match (walked) {
            MemberAccess(lhs, name, name_span, span) => {
                if (name.contains("<")) {
                    var parsed = _member_type(name, name_span);
                    if (parsed.is_value()) {
                        var ty = parsed.value();
                        for (var g in ty.generic_types) {
                            visit_type_name(g);
                        }
                        return Expression.MemberAccess(lhs, ty.to_string(), name_span, span);
                    }
                }
            }
            else => {}
        }
        return walked;
    }

    visit_pattern_name(pattern: Pattern) {
        var span = pattern.case_span;
        var linked = "";
        if (!pattern.qualifier.is_value()) {
            var mine = own_names.try_get(pattern.case_name);
            if (mine.is_value()) {
                linked = mine.value();
            } else {
                match (_resolve_imported(pattern.case_name, bindings, linker.prelude)) {
                    Declared(c, _) => {
                        linked = c;
                    }
                    else => {
                        return;
                    }
                }
            }
        } else {
            var target_file = _qualifier(pattern.qualifier.value().name);
            if (!target_file.is_value()) {
                return;
            }
            var c = linker.exports[target_file.value()].try_get(pattern.case_name);
            if (!c.is_value()) {
                return;
            }
            linked = c.value();
        }
        if (!linker.constants.contains(linked)) {
            return;
        }
        # Record the reference as any other use of the constant.
        String? renamed = Optional<String>.Empty;
        if (!pattern.qualifier.is_value()) {
            renamed = _unqualified(pattern.case_name, span, true);
        } else {
            var q = pattern.qualifier.value().name;
            renamed = _qualified(_qualifier(q).value(), q, pattern.case_name, span, true);
        }
        pattern.constant = Optional<String>.Value(renamed.value_or(linked));
    }

    visit_case_type(pattern: Pattern) {
        if (!pattern.type_name.is_value()) {
            return;
        }
        var ty = pattern.type_name.value();
        # `Color.Red` names an enum's case, not a type in a module.
        var split = ty.name.split_once(".");
        if (split.is_value()) {
            var (q, _) = split.value();
            if (!bindings.qualified.contains(q)) {
                return;
            }
        }
        visit_type_name(ty);
    }

    visit_symbol(id: String, span: Span): String {
        var c = _unqualified(id, span, true);
        return c.value_or(id);
    }

    visit_type_name(type_name: TypeName) {
        var name = type_name.name;
        var base = names.base_type_name(name);
        var suffix = name.substr_bytes(base.size, name.size - base.size);
        String? resolved = Optional<String>.Empty;
        var split = base.split_once(".");
        if (split.is_value()) {
            var (q, member) = split.value();
            # Only a module can qualify a type, so a value named `q` does
            # not hide the import here.
            var target_file = bindings.qualified.try_get(q);
            if (target_file.is_value()) {
                resolved = _qualified(target_file.value(), q, member, type_name.span, false);
            } else if (bindings.unresolved.contains(q)) {
                # Reported at the import.
            } else if (walk_scopes.in_static_block() and walk_scopes.is_value_bound(q)) {
                # `field.Type` in a `static` block: the type of a member
                # the block reflects, known when it is expanded.
            } else {
                _error(type_name.span, $"'{q}' is not an imported module");
            }
        } else {
            resolved = _unqualified(base, type_name.span, false);
        }
        if (resolved.is_value()) {
            type_name.name = resolved.value() + suffix;
        }
        walk_type_name(type_name);
    }
}

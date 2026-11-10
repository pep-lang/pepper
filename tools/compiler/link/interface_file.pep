## A Pepper library's interface file (`--lib pepper`'s `.pepi`, #220), as
## program loading reads it: an `import` of the library finds it in the
## library folders, and its files join the program.
##
## The file is a text header, then the checked record of the library's
## files (`incremental.library_interface` writes it). The header's first
## line is `INTERFACE_MAGIC` and `RECORD_VERSION`; then, for each of the
## library's files:
##
## - `file <namespace>`, with ` root` after it for the library's root;
## - `import <module>` for each module the file imports that is not one of
##   the library's files (a runtime module), which the program loads;
## - `export <name> <declaration>` for each name an importer of the file
##   sees, and the linked name of the declaration it denotes;
## - its link table (`link_table`): a `declare` line per top-level
##   declaration, with what linking reads of it, and the `[Deprecated]`
##   and `[Link]` attributes it carries.
##
## Then `record`, a line break, and the record. The file holds no source
## text: the program links the library's files from their link tables, as
## declarations without bodies named as the library build named them, and
## checks against the record.

import [
    Attribute,
    Declaration,
    EnumBody,
    EnumCase,
    Expression,
    ExtendDecl,
    FunctionDecl,
    GenericParam,
    Import,
    ImportedSymbol,
    Literal,
    Module,
    PropertyDecl,
    Span,
    StructDecl,
    TraitDecl,
    TypeAliasDecl,
    TypeName,
    VariableDecl
] from compiler.ast;
import digest;
import [File, Path] from io;
import os;
import [Utf8] from text;
import "names" as names;
import [Target] from "platform";
import [RECORD_VERSION] from "stamp";

## The first line of a library interface, before its record version.
export const INTERFACE_MAGIC = "pepper-library-interface ";

## The extension of a library interface file.
export const INTERFACE_EXTENSION = "pepi";

## A file of a library, as its interface names it.
export struct InterfaceFile {
    ## Its namespace, which the library's mangled names carry.
    var namespace: String;
    ## Whether it is the library's root, which an import of the library
    ## names.
    var root: bool = false;
    ## Each name an importer of the file sees -> the linked name of the
    ## declaration it denotes.
    var exports: HashMap<String, String> = HashMap<String, String>();
    ## The modules it imports that are not files of the library.
    var imports: String[] = Array<String>();
    # Its link table's `declare` lines, each with the attribute lines
    # after it.
    var _declared: Array<String[]> = Array<String[]>();

    ## @param namespace the file's namespace
    construct(namespace: String) {
        this.namespace = namespace;
    }

    ## Returns the file's declarations as linking reads them, built anew
    ## from its link table: no bodies, parameters or types, each named as
    ## the library declared it (`names.demangle_name` of its linked name),
    ## with the names it refers to (an extension's target, a type alias's,
    ## an override's type arguments) linked already.
    ##
    ## Its imports are those of `imports`, each binding no name: the
    ## program loads those modules, which the library's record reads.
    ##
    ## @returns the declarations, and the linked name of each (empty for
    ##   an extension)
    declarations(): (Module, String[]) {
        var module = Module();
        for (var name in imports) {
            var imp = Import();
            imp.name = name;
            imp.symbols = Optional<ImportedSymbol[]>.Value(Array<ImportedSymbol>());
            module.imports.append(imp);
        }
        var linked = Array<String>();
        for (var lines in _declared) {
            var (declaration, name) = _declaration(lines);
            module.declarations.append(declaration);
            linked.append(name);
        }
        return (module, linked);
    }
}

## A library interface a program loaded.
export struct LibraryInterface {
    ## The library's name: what `import` names.
    var name: String;
    ## The interface file.
    var path: Path;
    ## The library's archive, beside it.
    var archive: Path;
    ## The hash of the interface file's bytes (`interface_hash`), which
    ## the archive's stamp must name.
    var hash: String = "";
    ## The library's files.
    var files: InterfaceFile[] = Array<InterfaceFile>();
    ## The record of the library's files.
    var record: u8[] = Array<u8>();

    ## @param name the library's name
    ## @param path the interface file
    ## @param archive the library's archive
    construct(name: String, path: Path, archive: Path) {
        this.name = name;
        this.path = path;
        this.archive = archive;
    }
}

## Returns the name of the interface file of the library `name` for
## `target`, beside its archive: `libgeo.pepi`, `geo.pepi` on Windows.
##
## @param name the library's name
## @param target the compile target
## @returns the file name
export interface_file_name(name: String, target: Target): String {
    return target.os == "windows" ? $"{name}.{INTERFACE_EXTENSION}" : $"lib{name}.{INTERFACE_EXTENSION}";
}

## Returns the folders of `$PEPPER_LIBRARY_PATH`, separated as in `PATH`.
##
## @returns the folders
export library_path_dirs(): Path[] {
    var dirs = Array<Path>();
    var library_path = os.environment("PEPPER_LIBRARY_PATH");
    if (library_path.is_value()) {
        var separator = os.system_os() == os.OperatingSystem.Windows ? ";" : ":";
        for (var dir in library_path.value().split(separator)) {
            if (!dir.is_empty) {
                dirs.append(Path(dir));
            }
        }
    }
    return dirs;
}

## Returns the hash of a library interface's bytes, which its library's
## stamp names (`Stamp.interface`).
##
## @param bytes the interface
## @returns the hash, in hexadecimal
export interface_hash(bytes: u8[]): String {
    var hasher = digest.Blake3();
    hasher.update(bytes);
    return hasher.finish_hex().substr_bytes(0, 16);
}

## Returns the interface of the library `name` in the first of `dirs` that
## holds one (`interface_file_name`), with its archive beside it; none when
## no folder does.
##
## @param name the library's name
## @param dirs the library folders, in search order
## @param target the compile target
## @returns the interface, why it cannot be read, or none
export find_library_interface(name: String, dirs: Path[], target: Target): Result<LibraryInterface, String>? {
    for (var dir in dirs) {
        var path = dir.join(Path(interface_file_name(name, target)));
        if (!path.is_file()) {
            continue;
        }
        var archive = path.with_extension(target.os == "windows" ? "lib" : "a");
        if (!archive.is_file()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err(
                    $"the Pepper library interface {path} has no archive {archive} beside it"
                )
            );
        }
        var bytes = File.read_bytes(path);
        if (bytes.is_err()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err($"cannot read {path}: {bytes.error().message}")
            );
        }
        var out = LibraryInterface(name, path, archive);
        var read = read_interface_bytes(out, bytes.value());
        if (read.is_value()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err($"{path}: {read.value()}")
            );
        }
        return Optional<Result<LibraryInterface, String>>.Value(Result<LibraryInterface, String>.ok(out));
    }
    return Optional<Result<LibraryInterface, String>>.Empty;
}

## Reads the interface file `bytes` into `out`: its files, its record and
## its hash.
##
## @param out the interface
## @param bytes the interface file's bytes
## @returns why it cannot be read, if it cannot
export read_interface_bytes(out: LibraryInterface, bytes: u8[]): String? {
    out.hash = interface_hash(bytes);
    ulong at = 0;
    var first = _line(bytes, at);
    if (!first.is_value() or first.value().0 != $"{INTERFACE_MAGIC}{RECORD_VERSION}") {
        var line = first.is_value() ? first.value().0 : "";
        if (line.starts_with(INTERFACE_MAGIC)) {
            return Optional<String>.Value(
                $"the interface is record version {line.substr_bytes(INTERFACE_MAGIC.size, line.size - INTERFACE_MAGIC.size)}, and this compiler reads version {RECORD_VERSION}; rebuild the library '{out.name}' with this compiler"
            );
        }
        return Optional<String>.Value($"not a Pepper library interface of record version {RECORD_VERSION}");
    }
    at = first.value().1;
    while (true) {
        var next = _line(bytes, at);
        if (!next.is_value()) {
            return Optional<String>.Value("the library interface ends before its record");
        }
        var (line, after) = next.value();
        at = after;
        if (line == "record") {
            out.record = bytes.slice(at, bytes.count).to_array();
            return Optional<String>.Empty;
        }
        var parts = line.split(" ");
        if (parts[0] == "file" and (parts.count == 2 or (parts.count == 3 and parts[2] == "root"))) {
            var file = InterfaceFile(parts[1]);
            file.root = parts.count == 3;
            out.files.append(file);
            continue;
        }
        if (out.files.is_empty) {
            return Optional<String>.Value($"a malformed library interface line: '{line}'");
        }
        var file = out.files[out.files.count - 1];
        if (parts[0] == "export" and parts.count == 3) {
            file.exports[parts[1]] = parts[2];
        } else if (parts[0] == "import" and parts.count == 2) {
            file.imports.append(parts[1]);
        } else if (parts[0] == "declare" and parts.count >= 3 and _is_kind(parts[1])) {
            file._declared.append([line]);
        } else if ((parts[0] == "attribute" or parts[0] == "constructor-attribute")
            and parts.count >= 2
            and !file._declared.is_empty) {
            file._declared[file._declared.count - 1].append(line);
        } else {
            return Optional<String>.Value($"a malformed library interface line: '{line}'");
        }
    }
    return Optional<String>.Empty;
}

# Whether `kind` is a kind of declaration a `declare` line names.
_is_kind(kind: String): bool {
    match (kind) {
        "function", "struct", "trait", "alias", "var", "extend" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns the link table of a library file, its declarations as linking
## left them (`module`, linked): a `declare` line for each that `target`
## keeps, with its kind, its linked name (an extension's target's), and
## `key` or `key=value` words for what linking and the checks that follow
## it read: `export`, `private`, `extern`, `override`, `generic=` (`bounded=`
## for a constrained one), `field=` (`generic-field=` for one whose type
## names a generic parameter), `property=`, `method=`, `constructors=`,
## `enum`, `case=`, `target=` and `trait=`. Each `[Deprecated]` or `[Link]`
## attribute follows on an `attribute` line (`constructor-attribute` for a
## struct's lone constructor's), with its string arguments, each
## `name=value` (`=value` for a positional one), the value escaped
## (`Uri.encode`). No bodies, parameters or types.
##
## @param module the file's declarations, linked
## @param target the target, whose platform selection the table follows
## @returns the lines, each ending in a line break
export link_table(module: Module, target: Target): String {
    var out = StringBuilder();
    for (var d in module.declarations) {
        if (!target.keeps(d.attributes())) {
            continue;
        }
        var words = Array<String>();
        var extra = Array<String>();
        match (d) {
            Function(f) => {
                words.append_all(["function", f.name]);
                if (f.external) {
                    words.append("extern");
                }
                bool is_override = names.is_function_override(f);
                if (is_override) {
                    words.append("override");
                }
                _generics(words, f.generic_params, !is_override);
            }
            Struct(s) => {
                words.append_all(["struct", s.name]);
                _generics(words, s.generic_params, true);
                var params = HashSet<String>();
                for (var p in s.generic_params) {
                    params.insert(p.name);
                }
                for (var field in s.fields) {
                    words.append(
                        names.mentions(field.type_name, params) ? $"generic-field={field.name}" : $"field={field.name}"
                    );
                }
                _members(words, s.properties, s.methods, target);
                words.append($"constructors={s.constructors.count}");
                if (s.constructors.count == 1) {
                    _attributes(extra, "constructor-attribute", s.constructors[0].attributes);
                }
                if (s.enumeration.is_value()) {
                    words.append("enum");
                    for (var c in s.enumeration.value().cases) {
                        words.append($"case={c.name}");
                    }
                }
            }
            Trait(t) => {
                words.append_all(["trait", t.name]);
                _generics(words, t.generic_params, true);
                _members(words, t.properties, t.methods, target);
            }
            TypeAlias(t) => {
                words.append_all(["alias", t.name]);
                _generics(words, t.generic_params, true);
                words.append($"target={t.target.name}");
            }
            Variable(v) => {
                words.append_all(["var", v.name]);
            }
            Extend(e) => {
                words.append_all(["extend", e.target.name]);
                for (var t in e.traits) {
                    words.append($"trait={t.name}");
                }
                _members(words, e.properties, e.methods, target);
            }
            Static(_) => {
                continue;
            }
        }
        if (d.is_exported()) {
            words.append("export");
        }
        if (d.is_private()) {
            words.append("private");
        }
        out.append($"declare {" ".join(words)}\n");
        _attributes(extra, "attribute", d.attributes());
        for (var line in extra) {
            out.append($"{line}\n");
        }
    }
    return out.to_string();
}

# Adds the words of `params` to `words`: each `generic=`, or `bounded=`
# for a constrained one when `bounds` says to tell them apart.
_generics(words: String[], params: GenericParam[], bounds: bool) {
    for (var p in params) {
        words.append(bounds and p.bounds.count > 0 ? $"bounded={p.name}" : $"generic={p.name}");
    }
}

# Adds the words of a body's properties and of the methods `target` keeps.
_members(words: String[], properties: PropertyDecl[], methods: FunctionDecl[], target: Target) {
    for (var p in properties) {
        words.append($"property={p.name}");
    }
    for (var m in methods) {
        if (target.keeps(m.attributes)) {
            words.append($"method={m.name}");
        }
    }
}

# Adds an `attribute`-like line per kept attribute of `attributes` to
# `lines`: its name, then its string arguments.
_attributes(lines: String[], what: String, attributes: Attribute[]) {
    for (var a in attributes) {
        # What linking and the checks after it read of a declaration the
        # program does not check.
        if (a.name() != "Deprecated" and a.name() != "Link") {
            continue;
        }
        var words = [what, a.name()];
        if (a.body is FunctionCall(_, arguments, _)) {
            for (var argument in arguments) {
                var key = "";
                var value = argument;
                if (argument is NamedArgument(name, _, named, _)) {
                    key = name;
                    value = named;
                }
                if (value is Literal(literal, _)) {
                    if (literal is String(text)) {
                        words.append($"{key}={Uri.encode(text)}");
                    }
                }
            }
        }
        lines.append(" ".join(words));
    }
}

# The declaration a `declare` line and its attribute lines stand for, and
# its linked name.
_declaration(lines: String[]): (Declaration, String) {
    var words = lines[0].split(" ");
    var kind = words[1];
    var linked = words[2];
    var name = names.demangle_name(linked);
    var flags = HashSet<String>();
    var values = Array<(String, String)>();
    for (var i in 3..words.count) {
        var split = words[i].split_once("=");
        if (split.is_value()) {
            values.append(split.value());
        } else {
            flags.insert(words[i]);
        }
    }
    var attributes = Array<Attribute>();
    var constructor_attributes = Array<Attribute>();
    for (var i in 1..lines.count) {
        var parts = lines[i].split(" ");
        var arguments = Array<Expression>();
        for (var j in 2..parts.count) {
            var (key, escaped) = parts[j].split_once("=").value_or(("", ""));
            var text = Expression.Literal(Literal.String(_decoded(escaped)), Span());
            arguments.append(key.is_empty ? text : Expression.NamedArgument(key, Span(), text, Span()));
        }
        var body = Expression.FunctionCall(Expression.SymbolRef(parts[1], Span()), arguments, Span());
        if (parts[0] == "attribute") {
            attributes.append(Attribute(body, Span()));
        } else {
            constructor_attributes.append(Attribute(body, Span()));
        }
    }
    var generics = Array<GenericParam>();
    var methods = Array<FunctionDecl>();
    var properties = Array<PropertyDecl>();
    for (var (key, value) in values) {
        if (key == "generic" or key == "bounded") {
            var param = GenericParam(value, Span());
            if (key == "bounded") {
                param.bounds.append(TypeName(value));
            }
            # An override's type arguments, linked.
            param.is_argument = flags.contains("override");
            generics.append(param);
        } else if (key == "method") {
            methods.append(FunctionDecl(value));
        } else if (key == "property") {
            var property = PropertyDecl();
            property.name = value;
            properties.append(property);
        }
    }
    bool exported = flags.contains("export");
    bool file_private = flags.contains("private");
    if (kind == "function") {
        var f = FunctionDecl(name);
        f.generic_params = generics;
        f.external = flags.contains("extern");
        f.attributes = attributes;
        f.is_exported = exported;
        f.is_private = file_private;
        return (Declaration.Function(f), linked);
    }
    if (kind == "struct") {
        var s = StructDecl();
        s.name = name;
        s.generic_params = generics;
        s.methods = methods;
        s.properties = properties;
        s.attributes = attributes;
        s.is_exported = exported;
        s.is_private = file_private;
        for (var (key, value) in values) {
            if (key == "field" or key == "generic-field") {
                var field = VariableDecl(value);
                # Only whether its type names a generic parameter is kept.
                field.type_name = TypeName(key == "field" or generics.is_empty ? "int" : generics[0].name);
                s.fields.append(field);
            } else if (key == "constructors") {
                for (var _ in 0..ulong.parse(value).value_or(0)) {
                    var constructor = FunctionDecl("construct");
                    constructor.attributes = constructor_attributes;
                    s.constructors.append(constructor);
                }
            } else if (key == "case") {
                var c = EnumCase();
                c.name = value;
                if (!s.enumeration.is_value()) {
                    s.enumeration = Optional<EnumBody>.Value(EnumBody());
                }
                s.enumeration.value().cases.append(c);
            }
        }
        if (flags.contains("enum") and !s.enumeration.is_value()) {
            s.enumeration = Optional<EnumBody>.Value(EnumBody());
        }
        return (Declaration.Struct(s), linked);
    }
    if (kind == "trait") {
        var t = TraitDecl();
        t.name = name;
        t.generic_params = generics;
        t.methods = methods;
        t.properties = properties;
        t.attributes = attributes;
        t.is_exported = exported;
        t.is_private = file_private;
        return (Declaration.Trait(t), linked);
    }
    if (kind == "alias") {
        var t = TypeAliasDecl();
        t.name = name;
        t.generic_params = generics;
        t.attributes = attributes;
        t.is_exported = exported;
        t.is_private = file_private;
        for (var (key, value) in values) {
            if (key == "target") {
                t.target = TypeName(value);
            }
        }
        return (Declaration.TypeAlias(t), linked);
    }
    if (kind == "var") {
        var v = VariableDecl(name);
        v.attributes = attributes;
        v.is_exported = exported;
        v.is_private = file_private;
        return (Declaration.Variable(v), linked);
    }
    var e = ExtendDecl();
    e.target = TypeName(linked);
    e.methods = methods;
    e.properties = properties;
    e.attributes = attributes;
    e.is_exported = exported;
    e.is_private = file_private;
    for (var (key, value) in values) {
        if (key == "trait") {
            e.traits.append(TypeName(value));
        }
    }
    return (Declaration.Extend(e), "");
}

# The line of `bytes` at `at`, and where the next starts; none at the end.
_line(bytes: u8[], at: ulong): (String, ulong)? {
    if (at >= bytes.count) {
        return Optional<(String, ulong)>.Empty;
    }
    var end = at;
    while (end < bytes.count and bytes[end] != '\n') {
        end += 1;
    }
    var line = Utf8.decode_lossy(bytes.slice(at, end).to_array());
    return Optional<(String, ulong)>.Value((line, end < bytes.count ? end + 1 : end));
}

# `escaped` with its percent-escapes decoded (`Uri.decode`); as it is when
# one is malformed.
_decoded(escaped: String): String {
    var decoded = Uri.decode(escaped);
    return decoded.is_ok() ? decoded.value() : escaped;
}

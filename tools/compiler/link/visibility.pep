## Module visibility: every top-level declaration (functions and externs,
## structs, type aliases, traits, extensions, and module variables) is
## private to the file that declares it unless marked `export`. Checked on
## the linked files, as the Rust compiler checks them, before they are
## merged into one program.
##
## A name is resolved by spelling, program-wide, with two refinements: a
## name the referencing file declares itself (or binds locally: parameters,
## locals, generic parameters, and the members of the struct being defined
## or extended) is always visible, and a name declared only in other files
## is visible only if one of those declarations is exported. Names with no
## top-level declaration (built-ins, primitive types) are not this check's
## concern.
##
## Linking has already given private declarations names no other file can
## spell (`helper@io/file`), so two files may each declare a private
## `helper`. A reference that names another file's private declaration is
## left unrenamed by linking; it is matched here by its demangled name. What
## keeps its name in the merged program must still be unique: an exported
## declaration of a file outside the prelude, and a concrete override
## (`hash<String>`), which takes its generic's name. Externs are exempt,
## since every `extern` of a name is the same C symbol. Anything else with
## generic parameters is a generic base, compared by parameter count, not
## spelling: `pick<T>` and `pick<U>` collide.
##
## An extension's methods share the extension's visibility. A member (`x.m`,
## or a bare `m` in a method body) that some extension declares is accepted
## only if a struct body visible to the referencing file declares it, or an
## extension visible to it does: its own, or an exported one in a prelude
## file or a file it imports.

import compiler.ast;
import [Attribute, Declaration, Expression, FunctionDecl, Module, Span, StructDecl, TypeName] from compiler.ast;
import [Diagnostic, Location, SourceText] from compiler.diagnostic;
import [FileScope, ProgramFile] from "link";
import "names" as names;
import [Target] from "platform";
import [Scopes, ScopeWalk] from "walk";

## What a `VisibilityError` is about.
export enum VisibilityErrorKind {
    ## A reference to a private top-level declaration of another file.
    Private,
    ## A reference to a `private` declaration of another file of its
    ## module.
    FilePrivate,
    ## A reference to a method of another file's private extension.
    PrivateExtension,
    ## A reference to a method of an exported extension in a file this file
    ## does not import.
    ExtensionNotImported,
    ## A private concrete override (`hash<int>`) another file also declares.
    DuplicateOverride,
    ## A reference to another file's export that this file did not import.
    NotImported,
    ## An exported declaration of a file outside the prelude whose name
    ## another file also declares.
    DuplicateExport,
    ## A type or variable a file declares twice.
    Redefinition,
    ## A type or variable that two prelude files both export. Reported in
    ## the file loaded first.
    PreludeRedefinition,
    ## A top-level declaration named like a built-in type (`double`): names
    ## resolve program-wide by spelling, so it would capture the type in
    ## every other file, the runtime's included.
    BuiltInType,
}

## A visibility violation.
export struct VisibilityError {
    ## The offending file.
    var file: ulong;
    ## The reference, or the declared name, in that file.
    var span: Span;
    ## The referenced or declared name.
    var name: String = "";
    ## The other file involved: the one that declares the name privately,
    ## or that also declares it.
    var declared_in: ulong;
    ## The declaration in `declared_in`, when it is known here rather than
    ## looked up by name.
    var declared_at: Span?;
    ## What it is about.
    var kind: VisibilityErrorKind;

    ## Creates an error.
    ##
    ## @param file the offending file
    ## @param span where in it
    ## @param name the name
    ## @param declared_in the other file
    ## @param declared_at the declaration there, if known
    ## @param kind what it is about
    construct(
        file: ulong, span: Span, name: String, declared_in: ulong, declared_at: Span?, kind: VisibilityErrorKind
    ) {
        this.file = file;
        this.span = span;
        this.name = name;
        this.declared_in = declared_in;
        this.declared_at = declared_at;
        this.kind = kind;
    }

    ## Returns what the error says, without a position.
    ##
    ## @param files the program's files
    ## @returns the message
    message(files: ProgramFile[]): String {
        var other = files[declared_in].name;
        match (kind) {
            Private => {
                var module = _module_name(files[declared_in]);
                if (module.is_value()) {
                    return $"'{name}' is internal to module '{module.value()}'; export it from the module to use it here";
                }
                return $"'{name}' is private to {other}; declare it with 'export' to use it from another file";
            }
            FilePrivate => {
                return $"'{name}' is private to {other}; remove 'private' to use it from the other files of its module";
            }
            PrivateExtension => {
                # Within one module only a `private` extension is out of
                # reach.
                var root = files[declared_in].module_root;
                var own = files[file].module_root;
                if (root.is_value() and own.is_value() and root.value().to_string() == own.value().to_string()) {
                    return $"'{name}' is declared in a private extension in {other}; remove 'private' to use it from the other files of its module";
                }
                var module = _module_name(files[declared_in]);
                if (module.is_value()) {
                    return $"'{name}' is declared in an extension internal to module '{module.value()}'; export the extension to use it here";
                }
                return $"'{name}' is declared in a private extension in {other}; declare the extension with 'export' to use it from another file";
            }
            ExtensionNotImported => {
                # A file of another module is reached through its module.
                var root = files[declared_in].module_root;
                var own = files[file].module_root;
                var fix = "add an import for it";
                if (root.is_value()) {
                    var module = root.value().file_name();
                    if (module.is_value()
                        and (!own.is_value() or own.value().to_string() != root.value().to_string())) {
                        fix = $"import its module '{module.value()}'";
                    }
                }
                return $"'{name}' is declared in an extension in {other}, which this file does not import; {fix}";
            }
            NotImported => {
                return $"'{name}' is exported by {other}, which this file does not import; add an import for it";
            }
            DuplicateExport => {
                return $"exported '{name}' is also declared in {other}; top-level names must be unique across files, even in different modules";
            }
            DuplicateOverride => {
                return $"override '{name}' is also declared in {other}; a generic may be overridden for the same types in only one file";
            }
            BuiltInType => {
                return $"'{name}' is the name of a built-in type; choose another name";
            }
            else => {
                return $"redefinition of '{name}'";
            }
        }
    }

    ## Returns the error as a diagnostic, with a note at the declaration in
    ## the other file.
    ##
    ## @param files the program's files
    ## @returns the diagnostic
    to_diagnostic(files: ProgramFile[]): Diagnostic {
        if (kind == VisibilityErrorKind.BuiltInType) {
            return Diagnostic.error(message(files)).at(Location(file, span));
        }
        var note = "declared here";
        match (kind) {
            DuplicateOverride => {
                note = "also declared here";
            }
            Redefinition => {
                note = "previous definition is here";
            }
            PreludeRedefinition => {
                note = "also exported here";
            }
            else => {}
        }
        var at = declared_at;
        if (!at.is_value()) {
            at = _declaration_span(files[declared_in].module, name, kind);
        }
        var note_at = Optional<Location>.Empty;
        if (at.is_value()) {
            note_at = Optional<Location>.Value(Location(declared_in, at.value()));
        }
        return Diagnostic.error(message(files)).at(Location(file, span)).with_note(note, note_at);
    }
}

# The span of the name `name` declares in `module`: a top-level
# declaration, or for an extension error, the extension's method.
_declaration_span(module: Module, name: String, kind: VisibilityErrorKind): Span? {
    bool extension = kind == VisibilityErrorKind.PrivateExtension or kind == VisibilityErrorKind.ExtensionNotImported;
    for (var d in module.declarations) {
        match (d) {
            Extend(e) => {
                if (!extension) {
                    continue;
                }
                for (var m in e.methods) {
                    if (m.name == name) {
                        return Optional<Span>.Value(m.name_span);
                    }
                }
                for (var p in e.properties) {
                    if (p.name == name) {
                        return Optional<Span>.Value(p.name_span);
                    }
                }
            }
            else => {
                if (names.demangle_name(d.declared_name()) == name) {
                    return Optional<Span>.Value(d.name_span());
                }
            }
        }
    }
    return Optional<Span>.Empty;
}

# One named top-level declaration.
struct _Decl {
    var file: ulong;
    var exported: bool;
    # Declared `private`: visible only in its own file.
    var file_private: bool;
    # An `extern` function: every declaration of it names one C symbol.
    var external: bool;
    # The declared name.
    var span: Span;
    # A function's generic parameters as spelled.
    var generics: String[] = Array<String>();
    # A concrete override (see `_is_function_override`).
    var is_override: bool;
    # A function, which may share its name with another file's.
    var is_function: bool;

    construct(file: ulong, exported: bool, file_private: bool, span: Span) {
        this.file = file;
        this.exported = exported;
        this.file_private = file_private;
        this.span = span;
    }

    # A generic function a concrete override would specialize: it has
    # generic parameters, and it is not an override itself.
    is_generic_base(): bool {
        return generics.count > 0 and !is_override;
    }

    # How a concrete override is identified (by its arguments), or a
    # generic base (by how many parameters it has).
    shape(): String {
        if (is_override) {
            return ",".join(generics);
        }
        return $"#{generics.count}";
    }
}

# A concrete override: one for primitives or `String` (`hash<int>`), or one
# linking marked (`hash<Point>`).
_is_function_override(f: FunctionDecl): bool {
    var params = Array<String>();
    bool any_argument = false;
    for (var g in f.generic_params) {
        if (g.bounds.count > 0) {
            return false;
        }
        params.append(g.name);
        if (g.is_argument) {
            any_argument = true;
        }
    }
    return names.is_override(params) or any_argument;
}

# Where a member name is declared, and whether that is exported or
# `private`.
struct _Owner {
    var file: ulong;
    var exported: bool;
    var file_private: bool;

    construct(file: ulong, exported: bool, file_private: bool) {
        this.file = file;
        this.exported = exported;
        this.file_private = file_private;
    }
}

# `_ExtensionMember` (a method or property an extension declares) is
# link.pep's: the files of a module share their declarations.

# A method a trait declares.
struct _TraitMethod {
    var file: ulong;
    var exported: bool;
    var file_private: bool;
    var trait_name: String;

    construct(file: ulong, exported: bool, file_private: bool, trait_name: String) {
        this.file = file;
        this.exported = exported;
        this.file_private = file_private;
        this.trait_name = trait_name;
    }
}

# Member names across the program, for bare member references in method
# bodies and for `x.m` accesses.
struct _VisibilityMembers {
    # Struct -> its generic parameters' names.
    var struct_params: HashMap<String, String[]> = HashMap<String, String[]>();
    # Struct -> the names its body declares (fields, properties, methods).
    var of_struct: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    # Member -> the structs whose bodies declare it.
    var in_struct_bodies: HashMap<String, _Owner[]> = HashMap<String, _Owner[]>();
    # Struct -> the members its extensions declare.
    var of_extensions: HashMap<String, _ExtensionMember[]> = HashMap<String, _ExtensionMember[]>();
    # Member -> the extensions that declare it.
    var in_extensions: HashMap<String, _Owner[]> = HashMap<String, _Owner[]>();
    # Trait -> the structs extensions make conform to it.
    var adopters: HashMap<String, String[]> = HashMap<String, String[]>();
    # Struct -> its fields typed by one of its type parameters.
    var generic_fields: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    # Method -> the traits declaring it.
    var in_traits: HashMap<String, _TraitMethod[]> = HashMap<String, _TraitMethod[]>();
    # Type alias -> the type it names (its base name, for a generic one).
    var aliases: HashMap<String, String> = HashMap<String, String>();

    construct() {}

    # The type `name` denotes, through any alias.
    resolve(name: String): String {
        var out = name;
        # An alias cycle is reported elsewhere; stop rather than loop.
        ulong i = 0;
        while (i <= aliases.count) {
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

_add_owner(map: HashMap<String, _Owner[]>, name: String, owner: _Owner) {
    if (!map.contains(name)) {
        map[name] = Array<_Owner>();
    }
    map[name].append(owner);
}

_add_extension_member(map: HashMap<String, _ExtensionMember[]>, target: String, member: _ExtensionMember) {
    if (!map.contains(target)) {
        map[target] = Array<_ExtensionMember>();
    }
    map[target].append(member);
}

_add_decl(map: HashMap<String, _Decl[]>, name: String, decl: _Decl) {
    if (!map.contains(name)) {
        map[name] = Array<_Decl>();
    }
    map[name].append(decl);
}

_struct_member_names(s: StructDecl): String[] {
    var out = Array<String>();
    for (var f in s.fields) {
        out.append(f.name);
    }
    for (var p in s.properties) {
        out.append(p.name);
    }
    for (var m in s.methods) {
        out.append(m.name);
    }
    return out;
}

# `type_name` names, or has among its type arguments, a name in `params`
# (`X`, `X[]`, `Array<X>`).
_mentions(type_name: TypeName, params: HashSet<String>): bool {
    if (params.contains(names.base_type_name(type_name.name))) {
        return true;
    }
    for (var g in type_name.generic_types) {
        if (_mentions(g, params)) {
            return true;
        }
    }
    return false;
}

# The name a chain of accesses and calls starts from (`x` in `x.f().g`).
_receiver_root(e: Expression): String? {
    match (e) {
        SymbolRef(id, _) => {
            return Optional<String>.Value(id);
        }
        MemberAccess(lhs, _, _, _) => {
            return _receiver_root(lhs);
        }
        Index(lhs, _, _) => {
            return _receiver_root(lhs);
        }
        FunctionCall(function, _, _) => {
            return _receiver_root(function);
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

# The member a chain starting from `this` reaches first (`v` in
# `this.v.f()`).
_receiver_field(e: Expression): String? {
    match (e) {
        MemberAccess(lhs, name, _, _) => {
            match (lhs) {
                SymbolRef(id, _) => {
                    if (id == "this") {
                        return Optional<String>.Value(name);
                    }
                }
                else => {}
            }
            return _receiver_field(lhs);
        }
        Index(lhs, _, _) => {
            return _receiver_field(lhs);
        }
        FunctionCall(function, _, _) => {
            return _receiver_field(function);
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

## Checks every file's references against the other files' exports.
##
## @param files the linked program's files
## @param scopes what linking learned about each file
## @param target the target platform selection evaluates against
## @returns the errors: duplicate declarations in source order, then each
##   file's references in walk order
## Whether `name` is a built-in type's, which no declaration may take.
_is_built_in_type(name: String): bool {
    match (name) {
        "void", "bool", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "f64", "double", "f32", "float" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

# The top-level declarations named like a built-in type, as errors.
_built_in_type_names(files: ProgramFile[], target: Target): VisibilityError[] {
    var errors = Array<VisibilityError>();
    for (var i in 0..files.count) {
        for (var d in files[i].module.declarations) {
            if (!target.keeps(d.attributes())) {
                continue;
            }
            var name = "";
            match (d) {
                Function(f) => {
                    name = f.name;
                }
                Struct(s) => {
                    name = s.name;
                }
                Trait(t) => {
                    name = t.name;
                }
                TypeAlias(t) => {
                    name = t.name;
                }
                Variable(v) => {
                    name = v.name;
                }
                else => {}
            }
            var written = names.demangle_name(name);
            if (_is_built_in_type(written)) {
                errors.append(
                    VisibilityError(i, d.name_span(), written, i, Optional<Span>.Empty, VisibilityErrorKind.BuiltInType)
                );
            }
        }
    }
    return errors;
}

export check_visibility(files: ProgramFile[], scopes: FileScope[], target: Target): VisibilityError[] {
    var decls = HashMap<String, _Decl[]>();
    # Load order of the names in `decls`, so errors come out the same way
    # whatever the map's order.
    var decl_names = Array<String>();
    var types = HashSet<String>();
    var members = _VisibilityMembers();
    var traits = Map<String, _TraitMethod>();
    var trait_methods = HashMap<String, String[]>();
    # An extension may name its target or its traits through an alias.
    for (var file in files) {
        for (var d in file.module.declarations) {
            if (!target.keeps(d.attributes())) {
                continue;
            }
            match (d) {
                TypeAlias(t) => {
                    members.aliases[t.name] = t.target.name;
                }
                else => {}
            }
        }
    }
    ulong i = 0;
    while (i < files.count) {
        for (var d in files[i].module.declarations) {
            # A malformed attribute is reported by platform filtering
            # itself.
            if (!target.keeps(d.attributes())) {
                continue;
            }
            match (d) {
                Function(f) => {
                    var decl = _Decl(i, f.is_exported, f.is_private, f.name_span);
                    decl.external = f.external;
                    for (var g in f.generic_params) {
                        decl.generics.append(g.name);
                    }
                    decl.is_override = _is_function_override(f);
                    decl.is_function = true;
                    _add_name(decls, decl_names, f.name, decl);
                }
                Struct(s) => {
                    var params = HashSet<String>();
                    var param_list = Array<String>();
                    for (var p in s.generic_params) {
                        params.insert(p.name);
                        param_list.append(p.name);
                    }
                    var fields = HashSet<String>();
                    for (var field in s.fields) {
                        if (_mentions(field.type_name, params)) {
                            fields.insert(field.name);
                        }
                    }
                    members.generic_fields[s.name] = fields;
                    types.insert(s.name);
                    types.insert(names.demangle_name(s.name));
                    _add_name(decls, decl_names, s.name, _Decl(i, s.is_exported, s.is_private, s.name_span));
                    if (!members.of_struct.contains(s.name)) {
                        members.of_struct[s.name] = HashSet<String>();
                    }
                    var body = members.of_struct[s.name];
                    for (var m in _struct_member_names(s)) {
                        body.insert(m);
                        _add_owner(members.in_struct_bodies, m, _Owner(i, s.is_exported, s.is_private));
                    }
                    members.struct_params[s.name] = param_list;
                }
                TypeAlias(t) => {
                    types.insert(t.name);
                    types.insert(names.demangle_name(t.name));
                    _add_name(decls, decl_names, t.name, _Decl(i, t.is_exported, t.is_private, t.name_span));
                }
                Trait(t) => {
                    var methods = Array<String>();
                    for (var m in t.methods) {
                        if (target.keeps(m.attributes)) {
                            methods.append(m.name);
                        }
                    }
                    for (var p in t.properties) {
                        methods.append(p.name);
                    }
                    traits[t.name] = _TraitMethod(i, t.is_exported, t.is_private, t.name);
                    trait_methods[t.name] = methods;
                    types.insert(t.name);
                    types.insert(names.demangle_name(t.name));
                    _add_name(decls, decl_names, t.name, _Decl(i, t.is_exported, t.is_private, t.name_span));
                }
                Variable(v) => {
                    _add_name(decls, decl_names, v.name, _Decl(i, v.is_exported, v.is_private, v.name_span));
                }
                Extend(e) => {
                    var extended = members.resolve(e.target.name);
                    for (var t in e.traits) {
                        var adopted = members.resolve(t.name);
                        if (!members.adopters.contains(adopted)) {
                            members.adopters[adopted] = Array<String>();
                        }
                        members.adopters[adopted].append(extended);
                    }
                    # A method platform selection drops is never compiled.
                    for (var m in e.methods) {
                        if (target.keeps(m.attributes)) {
                            _add_extension_member(
                                members.of_extensions,
                                extended,
                                _ExtensionMember(m.name, i, e.is_exported, e.is_private)
                            );
                            _add_owner(members.in_extensions, m.name, _Owner(i, e.is_exported, e.is_private));
                        }
                    }
                    for (var p in e.properties) {
                        _add_extension_member(
                            members.of_extensions, extended, _ExtensionMember(p.name, i, e.is_exported, e.is_private)
                        );
                        _add_owner(members.in_extensions, p.name, _Owner(i, e.is_exported, e.is_private));
                    }
                }
                # Its constants are declared beside it, as variables.
                Static(_) => {}
            }
        }
        i += 1;
    }
    # Every trait's methods, by the trait declaring them: a call through a
    # trait value needs no conformance to be visible.
    for (var (trait_name, owner) in traits) {
        for (var m in trait_methods[trait_name]) {
            if (!members.in_traits.contains(m)) {
                members.in_traits[m] = Array<_TraitMethod>();
            }
            members.in_traits[m].append(owner);
        }
    }
    # Mangled private declarations, by the name the user wrote.
    var mangled_private = HashMap<String, _Decl[]>();
    for (var name in decl_names) {
        if (name.contains(names.NAMESPACE_SEPARATOR)) {
            var written = names.demangle_name(name);
            if (!mangled_private.contains(written)) {
                mangled_private[written] = Array<_Decl>();
            }
            mangled_private[written].append_all(decls[name]);
        }
    }

    # Every reference to a declaration named like a built-in type would be
    # reported too: only the declarations are.
    var built_in = _built_in_type_names(files, target);
    if (!built_in.is_empty) {
        return built_in;
    }
    var errors = Array<VisibilityError>();
    for (var name in decl_names) {
        var entries = decls[name];
        # Exports of prelude files may repeat each other, by design; every
        # other file's names must be unique. Private declarations are
        # mangled apart, except overrides.
        for (var d in entries) {
            if (d.external or (d.exported and _exempt(files[d.file])) or !(d.exported or d.is_override)) {
                continue;
            }
            for (var other in entries) {
                if (other.file != d.file and other.shape() == d.shape()) {
                    var shown = d.exported ? name : $"{name}<{", ".join(d.generics)}>";
                    var kind = d.exported ? VisibilityErrorKind.DuplicateExport : VisibilityErrorKind.DuplicateOverride;
                    errors.append(
                        VisibilityError(d.file, d.span, shown, other.file, Optional<Span>.Value(other.span), kind)
                    );
                    break;
                }
            }
        }
        # Only functions may repeat: a type or variable declared twice in
        # one file, or exported by two prelude files, would leave the merged
        # program with one of them. Entries are in load order.
        ulong j = 0;
        while (j < entries.count) {
            var d = entries[j];
            if (d.is_function) {
                j += 1;
                continue;
            }
            bool reported = false;
            ulong k = 0;
            while (k < j) {
                var o = entries[k];
                if (!o.is_function and o.file == d.file) {
                    errors.append(
                        VisibilityError(
                            d.file, d.span, name, o.file, Optional<Span>.Value(o.span), VisibilityErrorKind.Redefinition
                        )
                    );
                    reported = true;
                    break;
                }
                k += 1;
            }
            if (!reported and d.exported and _exempt(files[d.file])) {
                k = 0;
                while (k < j) {
                    var first = entries[k];
                    if (!first.is_function and first.exported and _exempt(files[first.file])) {
                        errors.append(
                            VisibilityError(
                                first.file,
                                first.span,
                                name,
                                d.file,
                                Optional<Span>.Value(d.span),
                                VisibilityErrorKind.PreludeRedefinition
                            )
                        );
                        break;
                    }
                    k += 1;
                }
            }
            j += 1;
        }
    }
    # Files of one module see each other's declarations: two of them may
    # declare a function of one name (an overload set) or an extern, but
    # nothing else, unless one is `private` to its file. Mangling keeps their names apart, so they are compared
    # by the names the user wrote, in path order (the first is the one
    # kept).
    var in_module = HashMap<String, _ModuleFirst>();
    var by_path = Array<ulong>();
    i = 0;
    while (i < files.count) {
        if (files[i].module_root.is_value()) {
            by_path.append(i);
        }
        i += 1;
    }
    by_path.sort((a, b) => files[a].name.compare(files[b].name));
    for (var f in by_path) {
        var root = files[f].module_root.value().to_string();
        for (var d in files[f].module.declarations) {
            if (d.is_private() or !target.keeps(d.attributes())) {
                continue;
            }
            bool skip = false;
            bool function = false;
            bool external = false;
            match (d) {
                Extend(_) => {
                    skip = true;
                }
                Static(_) => {
                    skip = true;
                }
                Function(func) => {
                    skip = _is_function_override(func);
                    function = true;
                    external = func.external;
                }
                else => {}
            }
            if (skip) {
                continue;
            }
            var name = names.demangle_name(d.declared_name());
            var key = $"{root}\n{name}";
            var first = in_module.try_get(key);
            if (!first.is_value()) {
                in_module[key] = _ModuleFirst(f, d.name_span(), function and !external);
            } else if (first.value().file != f and !(function and first.value().function) and !external) {
                errors.append(
                    VisibilityError(
                        f,
                        d.name_span(),
                        name,
                        first.value().file,
                        Optional<Span>.Value(first.value().span),
                        VisibilityErrorKind.Redefinition
                    )
                );
            }
        }
    }
    # A concrete override (`conv<int>`) of a generic base only another file
    # declares, privately, would replace that file's own instantiation of
    # it: the base is out of reach.
    for (var name in decl_names) {
        var entries = decls[name];
        for (var d in entries) {
            if (d.external or !d.is_override) {
                continue;
            }
            # An exported base the override's file can reach (its imports
            # bind it, or the prelude's) binds it; a private base elsewhere
            # is mangled apart and unaffected.
            bool bound = false;
            for (var e in entries) {
                bool reachable = e.exported and (_exempt(files[e.file]) or scopes[d.file].bound.contains(name));
                if ((e.file == d.file or reachable) and e.is_generic_base() and e.generics.count == d.generics.count) {
                    bound = true;
                    break;
                }
            }
            if (bound) {
                continue;
            }
            # The base may be private under its own name (in the root file)
            # or mangled. Another module's export is mangled too, but it is
            # not private.
            var bases = Array<_Decl>();
            for (var e in entries) {
                if (!e.exported) {
                    bases.append(e);
                }
            }
            var mangled = mangled_private.try_get(name);
            if (mangled.is_value()) {
                for (var e in mangled.value()) {
                    if (!e.exported) {
                        bases.append(e);
                    }
                }
            }
            for (var base in bases) {
                if (base.file != d.file and base.is_generic_base() and base.generics.count == d.generics.count) {
                    errors.append(
                        VisibilityError(
                            d.file,
                            d.span,
                            name,
                            base.file,
                            Optional<Span>.Value(base.span),
                            VisibilityErrorKind.Private
                        )
                    );
                    break;
                }
            }
        }
    }
    errors.sort((a, b) => _compare_errors(a, b));

    var prelude = Array<bool>();
    var roots = Array<String?>();
    for (var f in files) {
        prelude.append(f.prelude);
        roots.append(
            f.module_root.is_value() ?
                Optional<String>.Value(f.module_root.value().to_string()) :
                Optional<String>.Empty
        );
    }
    i = 0;
    while (i < files.count) {
        # An extension declares no name of its own, nor does a concrete
        # override: after linking it may carry an imported generic's name,
        # which it must not make visible. Nor does what platform selection
        # drops.
        var own = HashSet<String>();
        for (var d in files[i].module.declarations) {
            bool declares = true;
            match (d) {
                Extend(_) => {
                    declares = false;
                }
                Function(f) => {
                    declares = !_is_function_override(f);
                }
                else => {}
            }
            if (declares and target.keeps(d.attributes())) {
                own.insert(d.declared_name());
            }
        }
        var checker = _Checker(i, own, scopes[i], types, prelude, decls, mangled_private, members, target, errors);
        checker.roots = roots;
        for (var d in files[i].module.declarations) {
            if (target.keeps(d.attributes())) {
                checker.walk_declaration(d);
            }
        }
        i += 1;
    }
    return errors;
}

_add_name(decls: HashMap<String, _Decl[]>, order: String[], name: String, decl: _Decl) {
    if (!decls.contains(name)) {
        order.append(name);
    }
    _add_decl(decls, name, decl);
}

# Its exports may repeat other exempt files' exports: prelude files, and
# the other files of a forced module.
_exempt(file: ProgramFile): bool {
    return file.prelude or file.prelude_part;
}

_compare_errors(a: VisibilityError, b: VisibilityError): int {
    if (a.file != b.file) {
        return a.file < b.file ? -1 : 1;
    }
    if (a.span.start != b.span.start) {
        return a.span.start < b.span.start ? -1 : 1;
    }
    return 0;
}

# The walk of one file for `check_visibility`.
# The first declaration of a name in a module (see `check_visibility`).
struct _ModuleFirst {
    var file: ulong;
    var span: Span;
    # A free function (not an extern), which another may join.
    var function: bool;

    construct(file: ulong, span: Span, function: bool) {
        this.file = file;
        this.span = span;
        this.function = function;
    }
}

struct _Checker {
    var file: ulong;
    var own: HashSet<String>;
    var scope: FileScope;
    # Every type name declared at top level.
    var types: HashSet<String>;
    # Per file: its exports are visible without an import.
    var prelude: bool[];
    # Per file, its module's folder, if any.
    var roots: Array<String?> = Array<String?>();
    var decls: HashMap<String, _Decl[]>;
    # Other files' private declarations, by the name the user wrote.
    var mangled_private: HashMap<String, _Decl[]>;
    var members: _VisibilityMembers;
    var target: Target;
    var errors: VisibilityError[];
    var walk_scopes: Scopes = Scopes();
    # The span start of the last callee reported as captured.
    var captured: long = -1;
    # The member name span starts of each `x.m` whose receiver's type is
    # not known here.
    var unknown_receivers: HashSet<ulong> = HashSet<ulong>();

    construct(
        file: ulong,
        own: HashSet<String>,
        scope: FileScope,
        types: HashSet<String>,
        prelude: bool[],
        decls: HashMap<String, _Decl[]>,
        mangled_private: HashMap<String, _Decl[]>,
        members: _VisibilityMembers,
        target: Target,
        errors: VisibilityError[]
    ) {
        this.file = file;
        this.own = own;
        this.scope = scope;
        this.types = types;
        this.prelude = prelude;
        this.decls = decls;
        this.mangled_private = mangled_private;
        this.members = members;
        this.target = target;
        this.errors = errors;
    }

    _report(span: Span, name: String, declared_in: ulong, kind: VisibilityErrorKind) {
        errors.append(VisibilityError(file, span, name, declared_in, Optional<Span>.Empty, kind));
    }

    # Whether `name` is a field of the struct being walked that its type
    # parameter types.
    _is_generic_field(name: String): bool {
        var current = walk_scopes.current_struct();
        if (!current.is_value()) {
            return false;
        }
        var fields = members.generic_fields.try_get(members.resolve(current.value()));
        return fields.is_value() and fields.value().contains(name);
    }

    # `e` (a chain of accesses and calls) starts from a value whose type is
    # not known here: `this` in a trait's default method, a binding of
    # generic type, or a field typed by the struct's type parameter.
    _is_unknown_type(e: Expression): bool {
        var root = _receiver_root(e);
        if (!root.is_value()) {
            return false;
        }
        var name = root.value();
        if (name == "this") {
            if (!walk_scopes.current_struct().is_value() and walk_scopes.current_trait().is_value()) {
                return true;
            }
            var field = _receiver_field(e);
            return field.is_value() and _is_generic_field(field.value());
        }
        if (walk_scopes.is_value_bound(name)) {
            return walk_scopes.is_marked_value(name);
        }
        return _is_generic_field(name);
    }

    # `other` is this file, or another file of its module.
    _same_module(other: ulong): bool {
        if (other == file) {
            return true;
        }
        var root = roots[other];
        return root.is_value() and roots[file].is_value() and root.value() == roots[file].value();
    }

    # An extension in `in_file` is visible here: it is this file's own or
    # its module's (unless `private`), or exported by a prelude file or a
    # file this one imports.
    _sees_extension(in_file: ulong, exported: bool, file_private: bool): bool {
        return in_file == file
            or (!file_private and _same_module(in_file))
            or (exported and (prelude[in_file] or scope.extensions.contains(in_file)));
    }

    # What a reference to another file's unexported `d` is: a `private`
    # declaration of another file of this module, or one internal to its
    # file or module.
    _private_kind(d: _Decl): VisibilityErrorKind {
        if (d.file_private and roots[d.file].is_value() and _same_module(d.file)) {
            return VisibilityErrorKind.FilePrivate;
        }
        return VisibilityErrorKind.Private;
    }

    # Checks a reference not bound locally: used as a value, or as a type.
    _check_reference(name: String, span: Span, value: bool) {
        if (own.contains(name)) {
            return;
        }
        var found = decls.try_get(name);
        if (!found.is_value()) {
            # Linking leaves a reference to another file's mangled
            # declaration unrenamed: a private one, or an export of a file
            # this one does not import.
            var candidates = mangled_private.try_get(name);
            if (candidates.is_value()) {
                _Decl? pick;
                for (var d in candidates.value()) {
                    if (d.file != file and d.exported) {
                        pick = Optional<_Decl>.Value(d);
                        break;
                    }
                }
                if (!pick.is_value()) {
                    for (var d in candidates.value()) {
                        if (d.file != file) {
                            pick = Optional<_Decl>.Value(d);
                            break;
                        }
                    }
                }
                if (pick.is_value()) {
                    var d = pick.value();
                    _report(span, name, d.file, d.exported ? VisibilityErrorKind.NotImported : _private_kind(d));
                    return;
                }
            }
            # Not a top-level name: possibly a bare extension method in a
            # method body. A type (`double`) is never a method.
            if (value) {
                visit_member(name, span);
            }
            return;
        }
        var entries = found.value();
        var imported = scope.imported.try_get(span.start);
        if (imported.is_value() and imported.value() == name) {
            return;
        }
        # This file's own declaration counts, unless it is only a concrete
        # override of a generic another file exports: that would unlock the
        # other file's name.
        bool other_base = false;
        for (var e in entries) {
            if (e.file != file and e.exported and e.is_generic_base()) {
                other_base = true;
            }
        }
        for (var d in entries) {
            if ((d.file == file and (!d.is_override or !other_base)) or (d.exported and prelude[d.file])) {
                return;
            }
        }
        # Name the other file: the one whose declaration is out of reach.
        var elsewhere = entries[0];
        for (var d in entries) {
            if (d.file != file) {
                elsewhere = d;
                break;
            }
        }
        for (var d in entries) {
            if (d.exported and d.file != file) {
                _report(span, name, d.file, VisibilityErrorKind.NotImported);
                return;
            }
        }
        _report(span, name, elsewhere.file, _private_kind(elsewhere));
    }
}

extend _Checker with ScopeWalk {
    scopes(): Scopes {
        return walk_scopes;
    }

    keeps(attributes: Attribute[]): bool {
        return target.keeps(attributes);
    }

    # The members of `struct_name` visible in this file: its body's, plus
    # those of this file's extensions and of the exported extensions it can
    # see.
    is_member(struct_name: String, name: String): bool {
        var resolved = members.resolve(struct_name);
        var body = members.of_struct.try_get(resolved);
        if (body.is_value() and body.value().contains(name)) {
            return true;
        }
        var extension = members.of_extensions.try_get(resolved);
        if (extension.is_value()) {
            for (var m in extension.value()) {
                if (m.name == name and _sees_extension(m.file, m.exported, m.file_private)) {
                    return true;
                }
            }
        }
        return false;
    }

    # `extend Foo<T>` introduces T as a generic parameter. A name the
    # program declares as a type specializes instead, unless it is the
    # struct's own parameter at that position (`extend Box<T>` of
    # `struct Box<T>`).
    extend_params(target_type: TypeName): HashSet<String> {
        var own_params = members.struct_params.try_get(target_type.name);
        var out = HashSet<String>();
        ulong i = 0;
        while (i < target_type.generic_types.count) {
            var t = target_type.generic_types[i];
            if (t.generic_types.count == 0) {
                bool own_param = own_params.is_value()
                    and i < own_params.value().count
                    and own_params.value()[i] == t.name;
                if (!types.contains(t.name) or own_param) {
                    out.insert(t.name);
                }
            }
            i += 1;
        }
        return out;
    }

    # Sema binds a bare call in a method to a method of the struct, from
    # every extension in the program: one this file cannot see would
    # silently replace the function the call names. In a trait's default
    # methods, that is any struct an extension makes conform to the trait.
    visit_callee(function: Expression) {
        match (function) {
            SymbolRef(id, span) => {
                if (is_local(id)) {
                    return;
                }
                var structs = Array<String>();
                var current = walk_scopes.current_struct();
                var current_trait = walk_scopes.current_trait();
                if (current.is_value()) {
                    structs.append(members.resolve(current.value()));
                } else if (current_trait.is_value()) {
                    var adopters = members.adopters.try_get(current_trait.value());
                    if (adopters.is_value()) {
                        structs = adopters.value();
                    }
                } else {
                    return;
                }
                for (var st in structs) {
                    var extension = members.of_extensions.try_get(st);
                    if (!extension.is_value()) {
                        continue;
                    }
                    bool seen = false;
                    _ExtensionMember? first;
                    _ExtensionMember? first_exported;
                    for (var m in extension.value()) {
                        if (m.name != id) {
                            continue;
                        }
                        if (_sees_extension(m.file, m.exported, m.file_private)) {
                            seen = true;
                        }
                        if (!first.is_value()) {
                            first = Optional<_ExtensionMember>.Value(m);
                        }
                        if (m.exported and !first_exported.is_value()) {
                            first_exported = Optional<_ExtensionMember>.Value(m);
                        }
                    }
                    if (seen or !first.is_value()) {
                        continue;
                    }
                    # An exported extension this file does not import, else
                    # a private one.
                    var m = first_exported.is_value() ? first_exported.value() : first.value();
                    var kind = m.exported ?
                        VisibilityErrorKind.ExtensionNotImported :
                        VisibilityErrorKind.PrivateExtension;
                    _report(span, id, m.file, kind);
                    captured = span.start as long;
                    return;
                }
            }
            else => {}
        }
    }

    # An override's type arguments (`describe<S>`, marked by linking) are
    # types, not parameters: they bind no names.
    visit_function_generics(function: FunctionDecl): bool {
        for (var p in function.generic_params) {
            if (p.is_argument) {
                return true;
            }
        }
        return false;
    }

    # A value typed by a generic parameter in scope, or initialized from
    # such a value, is marked: its type is unknown here.
    visit_binding(type_name: TypeName, initializer: Expression?): bool {
        var generics = HashSet<String>();
        _type_locals(type_name, generics);
        if (generics.count > 0) {
            return true;
        }
        return initializer.is_value() and _is_unknown_type(initializer.value());
    }

    # `x.m` resolves where its receiver's type is known: for `this` in a
    # trait's default method, or a parameter typed by a generic parameter,
    # that is where the generic is instantiated, whose imports apply.
    visit_expression(e: Expression): Expression {
        match (e) {
            MemberAccess(lhs, _, name_span, _) => {
                if (_is_unknown_type(lhs)) {
                    unknown_receivers.insert(name_span.start);
                }
            }
            # A bare call with type arguments in a method (`make<String>(n)`)
            # names the struct's method, as `this.make<String>(n)` does: only
            # its type arguments are references.
            FunctionCall(function, arguments, span) => {
                if (function is TypeLiteral(type_name)) {
                    if (is_local(type_name.name)) {
                        walk_type_name(type_name);
                        return Expression.FunctionCall(function, _visit_all(arguments), span);
                    }
                }
            }
            else => {}
        }
        return walk_expression(e);
    }

    visit_symbol(id: String, span: Span): String {
        # A captured callee is reported once, as captured.
        if (!is_local(id) and captured != span.start as long) {
            _check_reference(id, span, true);
        }
        return id;
    }

    visit_type_name(type_name: TypeName) {
        # Only a generic parameter hides a type: a local or member named
        # `Point` is a value, as linking also treats it.
        var base = names.base_type_name(type_name.name);
        if (!walk_scopes.is_type_local(base)) {
            _check_reference(base, type_name.span, false);
        }
        walk_type_name(type_name);
    }

    # A member name (`x.name`, or bare `name` in a method body) that some
    # extension declares: rejected unless a struct body or an extension
    # visible to this file declares it too.
    visit_member(name: String, name_span: Span) {
        var entries = members.in_extensions.try_get(name);
        if (!entries.is_value() or unknown_receivers.contains(name_span.start)) {
            return;
        }
        for (var e in entries.value()) {
            if (_sees_extension(e.file, e.exported, e.file_private)) {
                return;
            }
        }
        var bodies = members.in_struct_bodies.try_get(name);
        if (bodies.is_value()) {
            for (var b in bodies.value()) {
                if (b.exported or b.file == file or (!b.file_private and _same_module(b.file))) {
                    return;
                }
            }
        }
        # A trait this file can see may declare it: the call may go
        # through a value of that trait, which needs no conformance in
        # view.
        var in_traits = members.in_traits.try_get(name);
        if (in_traits.is_value()) {
            for (var t in in_traits.value()) {
                if (_sees_extension(t.file, t.exported, t.file_private)
                    or (t.exported and scope.bound.contains(t.trait_name))) {
                    return;
                }
            }
        }
        # An exported extension this file does not import, else a private
        # one.
        for (var e in entries.value()) {
            if (e.exported) {
                _report(name_span, name, e.file, VisibilityErrorKind.ExtensionNotImported);
                return;
            }
        }
        _report(name_span, name, entries.value()[0].file, VisibilityErrorKind.PrivateExtension);
    }

    # The names `type_name` mentions that a generic parameter in scope
    # binds.
    _type_locals(type_name: TypeName, out: HashSet<String>) {
        var base = names.base_type_name(type_name.name);
        if (walk_scopes.is_type_local(base)) {
            out.insert(base);
        }
        for (var g in type_name.generic_types) {
            _type_locals(g, out);
        }
    }
}

# The name of the module `file` belongs to, if any.
_module_name(file: ProgramFile): Optional<String> {
    var root = file.module_root;
    if (!root.is_value()) {
        return Optional<String>.Empty;
    }
    var name = root.value().file_name();
    if (!name.is_value()) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(name.value());
}

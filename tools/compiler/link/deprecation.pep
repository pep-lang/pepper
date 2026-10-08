## `[Deprecated("message")]` and `[Deprecated("message", "replacement")]`:
## every use of a declaration marked deprecated is reported as a warning at
## the used name, with a note at the declaration. When the attribute names a
## replacement, the warning carries a fix that renames the use to it.
##
## `check_uses` walks each file's linked syntax tree for the top-level
## names: free functions and externs, structs and their constructors,
## traits, type aliases, and module variables, as values, as types, and in
## `import [...]` lists. Uses of members are found later, once types are
## known. Neither reports a use inside a declaration that is itself
## deprecated, nor the declaration itself. The attribute's form is checked
## later too, so a malformed one is skipped here.

import compiler.ast;
import [Attribute, Declaration, Expression, Span, TypeName] from compiler.ast;
import [Diagnostic, Fix, Location] from compiler.diagnostic;
import [FileScope, ProgramFile] from "link";
import "names" as names;
import [Target] from "platform";
import [Scopes, ScopeWalk] from "walk";

## The attribute's name.
export const DEPRECATED_ATTRIBUTE = "Deprecated";

## What a `[Deprecated(...)]` attribute says.
export struct Deprecation {
    ## Why, or what to do instead.
    var message: String = "";
    ## The name uses should be renamed to, if the attribute names one.
    var replacement: String?;

    ## Creates a deprecation.
    ##
    ## @param message why
    ## @param replacement the new name, if any
    construct(message: String, replacement: String?) {
        this.message = message;
        this.replacement = replacement;
    }
}

## A malformed `[Deprecated]` attribute: what is wrong, and where.
export struct DeprecationError {
    ## Where: the attribute, or the argument that is wrong.
    var span: Span;
    ## What is wrong.
    var message: String = "";

    ## Creates an error.
    ##
    ## @param span where
    ## @param message what is wrong
    construct(span: Span, message: String) {
        this.span = span;
        this.message = message;
    }
}

## Returns whether `attribute` is a `[Deprecated]` attribute, well-formed or
## not.
##
## @param attribute the attribute
## @returns true for `Deprecated`
export is_deprecation(attribute: Attribute): bool {
    var callee = attribute.body;
    match (attribute.body) {
        FunctionCall(function, _, _) => {
            callee = function;
        }
        else => {}
    }
    match (callee) {
        SymbolRef(id, _) => {
            return id == DEPRECATED_ATTRIBUTE;
        }
        else => {
            return false;
        }
    }
}

## Returns the `[Deprecated(...)]` among `attributes`, if any, or what is
## wrong with it.
##
## @param attributes the attributes
## @returns the deprecation, none, or the error
export deprecation_of(attributes: Attribute[]): Result<Deprecation?, DeprecationError> {
    Deprecation? found;
    for (var attribute in attributes) {
        if (!is_deprecation(attribute)) {
            continue;
        }
        if (found.is_value()) {
            return Result<Deprecation?, DeprecationError>.err(
                DeprecationError(attribute.span, "duplicate 'Deprecated' attribute")
            );
        }
        var expects_message = "'Deprecated' expects a message string: [Deprecated(\"message\")]";
        var arguments = Array<Expression>();
        match (attribute.body) {
            FunctionCall(_, list, _) => {
                arguments = list;
            }
            else => {
                return Result<Deprecation?, DeprecationError>.err(DeprecationError(attribute.span, expects_message));
            }
        }
        if (arguments.count == 0) {
            return Result<Deprecation?, DeprecationError>.err(DeprecationError(attribute.span, expects_message));
        }
        var message = _string(arguments[0]);
        if (!message.is_value()) {
            return Result<Deprecation?, DeprecationError>.err(DeprecationError(arguments[0].span(), expects_message));
        }
        String? replacement;
        if (arguments.count > 1) {
            var second = arguments[1];
            var name = _string(second);
            if (!name.is_value()) {
                return Result<Deprecation?, DeprecationError>.err(
                    DeprecationError(
                        second.span(),
                        "'Deprecated' expects the replacement as a string: [Deprecated(\"message\", \"replacement\")]"
                    )
                );
            }
            if (!_is_name(name.value())) {
                return Result<Deprecation?, DeprecationError>.err(
                    DeprecationError(second.span(), $"the replacement '{name.value()}' is not a name")
                );
            }
            replacement = name;
        }
        if (arguments.count > 2) {
            return Result<Deprecation?, DeprecationError>.err(
                DeprecationError(
                    arguments[2].span(),
                    $"too many arguments to 'Deprecated': expected at most 2, have {arguments.count}"
                )
            );
        }
        found = Optional<Deprecation>.Value(Deprecation(message.value(), replacement));
    }
    return Result<Deprecation?, DeprecationError>.ok(found);
}

## Returns the deprecation `attributes` declare, ignoring a malformed one.
##
## @param attributes the attributes
## @returns the deprecation, or none
export declared_deprecation(attributes: Attribute[]): Deprecation? {
    var found = deprecation_of(attributes);
    if (found.is_err()) {
        return Optional<Deprecation>.Empty;
    }
    return found.value();
}

_string(e: Expression): String? {
    match (e) {
        Literal(value, _) => {
            match (value) {
                String(text) => {
                    return Optional<String>.Value(text);
                }
                else => {}
            }
        }
        else => {}
    }
    return Optional<String>.Empty;
}

# A letter or `_`, then letters, digits and `_`. Any byte of a character
# outside ASCII counts as a letter.
_is_name(text: String): bool {
    if (text.is_empty or _is_digit(text.byte_at(0))) {
        return false;
    }
    ulong i = 0;
    while (i < text.size) {
        if (!_is_name_byte(text.byte_at(i))) {
            return false;
        }
        i += 1;
    }
    return true;
}

_is_digit(b: byte): bool {
    return b >= '0' and b <= '9';
}

_is_name_byte(b: byte): bool {
    return _is_digit(b) or (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_' or b as u8 >= 0x80;
}

## Returns the warning for a use of `name` at `used` (whose source text is
## `spelled`), declared at `declared` with `deprecation`. The fix renames
## the use only when it is spelled as the declaration (not through an
## import alias), since the replacement is the declaration's new name.
##
## @param name the declaration's name
## @param deprecation what its attribute says
## @param used where it is used
## @param spelled how the use is spelled
## @param declared where it is declared
## @returns the warning
export deprecation_warning(
    name: String, deprecation: Deprecation, used: Location, spelled: String, declared: Location
): Diagnostic {
    var out = Diagnostic.deprecated_declaration(
        name, deprecation.message, used
    ).with_note($"'{name}' declared here", Optional<Location>.Value(declared));
    if (deprecation.replacement.is_value() and spelled == names.demangle_name(name)) {
        var replacement = deprecation.replacement.value();
        out = out.with_fix(Fix($"Replace '{name}' with '{replacement}'", used, replacement));
    }
    return out;
}

# A deprecated top-level declaration or constructor.
struct _Entry {
    var deprecation: Deprecation;
    # The declared name.
    var at: Location;

    construct(deprecation: Deprecation, at: Location) {
        this.deprecation = deprecation;
        this.at = at;
    }
}

## Returns the uses of deprecated top-level declarations in every file of a
## linked program, as warnings in the files that use them.
##
## @param files the program's files
## @param scopes what linking learned about each file
## @param target the target platform selection evaluates against
## @returns the warnings, file by file
export check_uses(
    files: ProgramFile[], scopes: FileScope[], target: Target, bodies: bool[] = Array<bool>()
): Diagnostic[] {
    var deprecated = HashMap<String, _Entry>();
    var constructors = HashMap<String, _Entry>();
    var members = HashMap<String, HashSet<String>>();
    var types = HashSet<String>();
    ulong i = 0;
    while (i < files.count) {
        for (var d in files[i].module.declarations) {
            if (!target.keeps(d.attributes())) {
                continue;
            }
            bool extension = false;
            match (d) {
                Struct(s) => {
                    types.insert(s.name);
                    var names_in = _members_of(members, s.name);
                    for (var f in s.fields) {
                        names_in.insert(f.name);
                    }
                    for (var p in s.properties) {
                        names_in.insert(p.name);
                    }
                    for (var m in s.methods) {
                        names_in.insert(m.name);
                    }
                    # Overloaded constructors are checked per call, once
                    # resolved.
                    if (s.constructors.count == 1 and !constructors.contains(s.name)) {
                        var c = s.constructors[0];
                        var deprecation = declared_deprecation(c.attributes);
                        if (deprecation.is_value()) {
                            constructors[s.name] = _Entry(deprecation.value(), Location(i, c.name_span));
                        }
                    }
                }
                Trait(t) => {
                    types.insert(t.name);
                }
                TypeAlias(t) => {
                    types.insert(t.name);
                }
                Extend(e) => {
                    extension = true;
                    var names_in = _members_of(members, e.target.name);
                    for (var m in e.methods) {
                        names_in.insert(m.name);
                    }
                    for (var p in e.properties) {
                        names_in.insert(p.name);
                    }
                }
                else => {}
            }
            if (extension) {
                continue;
            }
            var deprecation = declared_deprecation(d.attributes());
            if (deprecation.is_value() and !deprecated.contains(d.declared_name())) {
                deprecated[d.declared_name()] = _Entry(deprecation.value(), Location(i, d.name_span()));
            }
        }
        i += 1;
    }
    var warnings = Array<Diagnostic>();
    if (deprecated.count == 0 and constructors.count == 0) {
        return warnings;
    }
    i = 0;
    while (i < files.count) {
        # A file whose bodies were not linked is as it was when it last
        # checked without a warning (`Program.link_bodies`).
        if (i < bodies.count and !bodies[i]) {
            i += 1;
            continue;
        }
        var walker = _Uses(i, files[i].source, deprecated, constructors, members, types, target, warnings);
        for (var d in files[i].module.declarations) {
            if (target.keeps(d.attributes())) {
                walker.walk_declaration(d);
            }
        }
        # `import [name] from m` names the declaration too; `export [name]
        # from m` only passes it on.
        if (i < scopes.count) {
            var named = scopes[i].named;
            for (var imp in files[i].module.imports) {
                if (imp.reexport or !target.keeps(imp.attributes) or !imp.symbols.is_value()) {
                    continue;
                }
                for (var symbol in imp.symbols.value()) {
                    var name = named.try_get(symbol.span.start);
                    if (name.is_value()) {
                        walker._report(name.value(), symbol.name_span);
                    }
                }
            }
        }
        i += 1;
    }
    return warnings;
}

_members_of(members: HashMap<String, HashSet<String>>, name: String): HashSet<String> {
    if (!members.contains(name)) {
        members[name] = HashSet<String>();
    }
    return members[name];
}

# The name token of a use at `span`: the last segment of a qualified name
# (`sqrt` in `m.sqrt`), without generic arguments or array brackets.
_name_token(text: String, span: Span): Span {
    var limit = span.end < text.size ? span.end : text.size;
    var start = span.start < limit ? span.start : limit;
    var end = start;
    while (end < limit and (_is_name_byte(text.byte_at(end)) or text.byte_at(end) == '.')) {
        end += 1;
    }
    var first = end;
    while (first > start and text.byte_at(first - 1) != '.') {
        first -= 1;
    }
    return Span(first, end);
}

# The walk of one file for `check_uses`.
struct _Uses {
    var file: ulong;
    var text: String;
    var deprecated: HashMap<String, _Entry>;
    var constructors: HashMap<String, _Entry>;
    # Struct -> the member names its body and extensions declare, which
    # hide top-level names inside its methods.
    var members: HashMap<String, HashSet<String>>;
    # Every type name declared at top level.
    var types: HashSet<String>;
    var target: Target;
    var warnings: Diagnostic[];
    var walk_scopes: Scopes = Scopes();
    # For each declaration being walked, whether it is deprecated.
    var context: bool[] = Array<bool>();

    construct(
        file: ulong,
        text: String,
        deprecated: HashMap<String, _Entry>,
        constructors: HashMap<String, _Entry>,
        members: HashMap<String, HashSet<String>>,
        types: HashSet<String>,
        target: Target,
        warnings: Diagnostic[]
    ) {
        this.file = file;
        this.text = text;
        this.deprecated = deprecated;
        this.constructors = constructors;
        this.members = members;
        this.types = types;
        this.target = target;
        this.warnings = warnings;
    }

    # A use of top-level `name` at `span` (a reference, possibly qualified,
    # or a type name with its arguments).
    _report(name: String, span: Span) {
        var entry = deprecated.try_get(name);
        if (entry.is_value()) {
            _report_entry(name, entry.value(), span);
        }
    }

    _report_entry(name: String, entry: _Entry, span: Span) {
        for (var inside in context) {
            if (inside) {
                return;
            }
        }
        var token = _name_token(text, span);
        var used = Location(file, token);
        if (used.same(entry.at)) {
            return;
        }
        var spelled = text.substr_bytes(token.start, token.end - token.start);
        warnings.append(deprecation_warning(name, entry.deprecation, used, spelled, entry.at));
    }
}

extend _Uses with ScopeWalk {
    scopes(): Scopes {
        return walk_scopes;
    }

    keeps(attributes: Attribute[]): bool {
        return target.keeps(attributes);
    }

    is_member(struct_name: String, name: String): bool {
        var found = members.try_get(struct_name);
        return found.is_value() and found.value().contains(name);
    }

    extend_params(target_type: TypeName): HashSet<String> {
        var out = HashSet<String>();
        for (var t in target_type.generic_types) {
            if (t.generic_types.count == 0 and !types.contains(t.name)) {
                out.insert(t.name);
            }
        }
        return out;
    }

    enter_declaration(attributes: Attribute[]) {
        context.append(declared_deprecation(attributes).is_value());
    }

    exit_declaration() {
        context.pop();
    }

    visit_symbol(id: String, span: Span): String {
        if (!is_local(id)) {
            _report(id, span);
        }
        return id;
    }

    visit_type_name(type_name: TypeName) {
        var base = names.base_type_name(type_name.name);
        if (!walk_scopes.is_type_local(base)) {
            _report(base, type_name.span);
        }
        walk_type_name(type_name);
    }

    # A construction `S(...)` also uses the constructor, which may be
    # deprecated on its own; a deprecated struct is reported once, as the
    # struct.
    visit_expression(e: Expression): Expression {
        match (e) {
            FunctionCall(function, _, _) => {
                String? name;
                var at = Span();
                match (function) {
                    SymbolRef(id, span) => {
                        if (!is_local(id)) {
                            name = Optional<String>.Value(id);
                            at = span;
                        }
                    }
                    TypeLiteral(t) => {
                        if (!walk_scopes.is_type_local(t.name)) {
                            name = Optional<String>.Value(t.name);
                            at = t.span;
                        }
                    }
                    else => {}
                }
                if (name.is_value() and !deprecated.contains(name.value())) {
                    var entry = constructors.try_get(name.value());
                    if (entry.is_value()) {
                        _report_entry(name.value(), entry.value(), at);
                    }
                }
            }
            else => {}
        }
        return walk_expression(e);
    }
}

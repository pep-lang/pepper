## Named arguments' attributes: `[Alias("alias", "parameter")]` gives a
## parameter a second name and `[Rename("old", "new")]` keeps a former name
## working. The checks of;
## binding calls comes later.

import compiler.ast;
import [Diagnostic, Fix, Location] from compiler.diagnostic;
import [attribute_arguments, attribute_name] from "attributes";
import [enum_method_name] from "builder";
import [is_checked_function, unit_decls] from "checked";
import "common";
import [Loc] from "loc";
import [
    Block,
    Declaration,
    DefaultArgumentExpression,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    MethodCallExpression,
    Module,
    Statement,
    StructDef,
    SubjectExpression,
    TypeName,
    WithSubject
] from "model";
import [set_name] from "names";
import [PassMemo, PassState] from "state";
import [instance, trait_def, trait_types_of] from "traits";
import "type_name";
import [method_is_static, value_type_key] from "value_types";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## The attribute that gives a parameter a second permanent name.
export const ALIAS_ATTRIBUTE = "Alias";
## The attribute that keeps a parameter's former name working, deprecated.
export const RENAME_ATTRIBUTE = "Rename";

## Another name for a parameter.
export struct OtherName {
    ## The name.
    var name: String;
    ## The parameter's index.
    var parameter: ulong;
    ## A former name (`[Rename]`): using it warns.
    var deprecated: bool;

    construct(name: String, parameter: ulong, deprecated: bool) {
        this.name = name;
        this.parameter = parameter;
        this.deprecated = deprecated;
    }
}

## Returns the names of `function`'s parameters as calls name them: a
## constructor's `this.x` (`__init_x` once named) is `x`.
##
## @param function the function
## @returns the names
export parameter_names(function: FunctionDef): String[] {
    var out = Array<String>();
    for (var p in function.parameters) {
        var name = p.name;
        if (name.starts_with("this.")) {
            name = name.substr_bytes(5, name.size - 5);
        } else if (name.starts_with("__init_")) {
            name = name.substr_bytes(7, name.size - 7);
        }
        out.append(name);
    }
    return out;
}

## Returns the names `[Alias]` and `[Rename]` give `params`, or the error
## for each attribute that is wrong, in order.
##
## @param attributes the function's attributes
## @param params the parameters' names
## @param file the file the attributes are in
## @returns one result per `[Alias]` or `[Rename]`
export other_names(attributes: ast.Attribute[], params: String[], file: uint): Array<Result<OtherName, Diagnostic>> {
    var seen = params.copy();
    var found = Array<Result<OtherName, Diagnostic>>();
    for (var attribute in attributes) {
        var call = _attribute_call(attribute);
        if (!call.is_value()) {
            continue;
        }
        var (kind, arguments) = call.value();
        if (kind != RENAME_ATTRIBUTE and kind != ALIAS_ATTRIBUTE) {
            continue;
        }
        var named = _other_name(kind, arguments, attribute, params, seen, file);
        if (named.is_err()) {
            found.append(Result<OtherName, Diagnostic>.Err(named.error()));
        } else {
            var (name, parameter) = named.value();
            found.append(Result<OtherName, Diagnostic>.Ok(OtherName(name, parameter, kind == RENAME_ATTRIBUTE)));
        }
    }
    return found;
}

## An attribute's name and arguments, when it is a name or a call of one.
_attribute_call(attribute: ast.Attribute): (String, ast.Expression[])? {
    match (attribute.body) {
        FunctionCall(function, arguments, _) => {
            if (function is SymbolRef(id, _)) {
                return Optional<(String, ast.Expression[])>.Value((id, arguments));
            }
        }
        SymbolRef(id, _) => {
            return Optional<(String, ast.Expression[])>.Value((id, Array<ast.Expression>()));
        }
        else => {}
    }
    return Optional<(String, ast.Expression[])>.Empty;
}

_other_name(
    kind: String, arguments: ast.Expression[], attribute: ast.Attribute, params: String[], seen: String[], file: uint
): Result<(String, ulong), Diagnostic> {
    var usage = kind == RENAME_ATTRIBUTE ? "[Rename(\"old\", \"new\")]" : "[Alias(\"alias\", \"parameter\")]";
    var strings = Array<(String, ast.Span)>();
    for (var argument in arguments) {
        if (argument is Literal(literal, span)) {
            if (literal is String(text)) {
                strings.append((text, span));
            }
        }
    }
    if (strings.count != 2) {
        return Result<(String, ulong), Diagnostic>.Err(
            error_at($"'{kind}' takes two strings: {usage}", Loc.at(file, attribute.span))
        );
    }
    var (name, name_span) = strings[0];
    var (parameter, parameter_span) = strings[1];
    var index = Optional<ulong>.Empty;
    ulong i = 0;
    while (i < params.count) {
        if (params[i] == parameter) {
            index = Optional<ulong>.Value(i);
            break;
        }
        i += 1;
    }
    if (!index.is_value()) {
        return Result<(String, ulong), Diagnostic>.Err(
            error_at($"no parameter named '{parameter}'", Loc.at(file, parameter_span))
        );
    }
    if (seen.contains(name)) {
        var what = params.contains(name) ? "a parameter" : "already another name of a parameter";
        return Result<(String, ulong), Diagnostic>.Err(error_at($"'{name}' is {what}", Loc.at(file, name_span)));
    }
    seen.append(name);
    return Result<(String, ulong), Diagnostic>.Ok((name, index.value()));
}

## Reports a wrong `[Alias]` or `[Rename]` on any function.
##
## @param module the model
## @param state the passes' state, which keeps the first error
export check_named_attributes(module: Module, state: PassState) {
    for (var function in module.functions) {
        _check_names(function, state);
    }
    for (var st in module.structs) {
        for (var f in st.constructors) {
            _check_names(f, state);
        }
        for (var f in st.method_members) {
            _check_names(f, state);
        }
        for (var f in st.generic_methods) {
            _check_names(f, state);
        }
    }
    for (var ext in module.extensions) {
        for (var f in ext.methods) {
            _check_names(f, state);
        }
    }
}

_check_names(function: FunctionDef, state: PassState) {
    bool any = false;
    for (var a in function.attributes) {
        var call = _attribute_call(a);
        if (call.is_value()) {
            var (kind, _) = call.value();
            if (kind == RENAME_ATTRIBUTE or kind == ALIAS_ATTRIBUTE) {
                any = true;
            }
        }
    }
    if (!any) {
        return;
    }
    for (var result in other_names(function.attributes, parameter_names(function), function.loc.file)) {
        if (result.is_err()) {
            state.report(result.error());
        }
    }
}

## Reports the first extern whose `[Link]` attributes are wrong.
##
## @param module the model
## @param state the passes' state, which keeps the first error
export check_link_attributes(module: Module, state: PassState) {
    for (var ext in module.externs) {
        var error = _link_error(ext.name, ext.attributes, ext.loc.file);
        if (error.is_value()) {
            state.report(error.value());
            return;
        }
    }
}

## The error in an extern's `[Link]` attributes: the removed `[LinkName]`,
## or a malformed `[Link]`.
_link_error(name: String, attributes: ast.Attribute[], file: uint): Diagnostic? {
    var name_at = Optional<Loc>.Empty;
    for (var attribute in attributes) {
        var attribute_name = attribute.name();
        if (attribute_name == "LinkName") {
            var arguments = attribute_arguments(attribute);
            var replacement = "[Link(name = \"sym\")]";
            if (arguments.count == 1 and !arguments[0].name.is_value()) {
                replacement = $"[Link(name = {arguments[0].value.to_string()})]";
            }
            var at = Loc.at(file, attribute.span);
            return Optional<Diagnostic>.Value(
                error_at(
                    $"'LinkName' was removed; use '{replacement}'", at
                ).with_fix(Fix($"replace with '{replacement}'", location_of(at), replacement))
            );
        }
        if (attribute_name != "Link") {
            continue;
        }
        var arguments = attribute_arguments(attribute);
        if (arguments.count == 0) {
            return Optional<Diagnostic>.Value(
                error_at(
                    "'Link' needs a library or a symbol: [Link(\"lib\")], [Link(name = \"sym\")]",
                    Loc.at(file, attribute.span)
                )
            );
        }
        bool library_given = false;
        bool path_given = false;
        ulong index = 0;
        while (index < arguments.count) {
            var argument = arguments[index];
            var key = "";
            var key_at = Loc.none();
            if (argument.name.is_value()) {
                var (k, span) = argument.name.value();
                key = k;
                key_at = Loc.at(file, span);
            } else if (index == 0) {
                key = "lib";
                key_at = Loc.at(file, argument.value.span());
            } else {
                return Optional<Diagnostic>.Value(
                    error_at(
                        "'Link' takes one positional argument, the library; name the others",
                        Loc.at(file, argument.value.span())
                    )
                );
            }
            var value = Optional<(String, ast.Span)>.Empty;
            if (argument.value is Literal(literal, span)) {
                if (literal is String(text)) {
                    value = Optional<(String, ast.Span)>.Value((text, span));
                }
            }
            if (!value.is_value()) {
                return Optional<Diagnostic>.Value(
                    error_at($"'Link' argument '{key}' must be a string", Loc.at(file, argument.value.span()))
                );
            }
            var (text, span) = value.value();
            if (text.is_empty) {
                return Optional<Diagnostic>.Value(
                    error_at($"'Link' argument '{key}' must not be empty", Loc.at(file, span))
                );
            }
            match (key) {
                "lib" => {
                    if (library_given) {
                        return Optional<Diagnostic>.Value(error_at("library given twice in one 'Link'", key_at));
                    }
                    library_given = true;
                }
                "path" => {
                    if (path_given) {
                        return Optional<Diagnostic>.Value(error_at("path given twice in one 'Link'", key_at));
                    }
                    path_given = true;
                }
                "name" => {
                    if (name_at.is_value()) {
                        return Optional<Diagnostic>.Value(
                            error_at(
                                $"extern '{name}' has more than one symbol name", key_at
                            ).with_note("first named here", Optional<Location>.Value(location_of(name_at.value())))
                        );
                    }
                    name_at = Optional<Loc>.Value(key_at);
                }
                else => {
                    return Optional<Diagnostic>.Value(
                        error_at($"'Link' has no argument named '{key}'; use 'lib', 'path' or 'name'", key_at)
                    );
                }
            }
            index += 1;
        }
    }
    return Optional<Diagnostic>.Empty;
}

# ── Binding calls ───────────────────────────────────────────────────────────

## One parameter, as binding needs it.
export struct Parameter {
    ## The name calls use.
    var name: String;
    ## Whether it has a default.
    var has_default: bool;
    ## Its type, or `auto` where it names a generic parameter.
    var ty: TypeName;

    construct(name: String, has_default: bool, ty: TypeName) {
        this.name = name;
        this.has_default = has_default;
        this.ty = ty;
    }
}

## A function a call may bind to.
export struct Callee {
    ## The name errors show.
    var display: String;
    ## The parameters.
    var params: Parameter[];
    ## The parameters' other names.
    var renames: OtherName[];
    ## Where it is declared.
    var loc: Loc;

    construct(display: String, params: Parameter[], renames: OtherName[], loc: Loc) {
        this.display = display;
        this.params = params;
        this.renames = renames;
        this.loc = loc;
    }

    ## Returns `function` as a callee: its parameters after the first
    ## `skip`, with `generic` (and its own type parameters) erased to `auto`.
    ##
    ## @param function the function
    ## @param display the name errors show
    ## @param skip how many leading parameters calls do not pass
    ## @param generic the type parameters in scope of its declaration
    ## @returns the callee
    static of(function: FunctionDef, display: String, skip: ulong, generic: String[]): Callee {
        var names = generic.copy();
        for (var p in function.generic_params) {
            names.append(p.name);
        }
        var all = parameter_names(function);
        var params = Array<Parameter>();
        ulong i = skip;
        while (i < function.parameters.count) {
            var p = function.parameters[i];
            bool erased = p.ty.contains_auto();
            for (var g in names) {
                if (p.ty.mentions(g)) {
                    erased = true;
                }
            }
            params.append(Parameter(all[i], p.default.is_value(), erased ? TypeName.auto() : p.ty.copy()));
            i += 1;
        }
        var param_names = Array<String>();
        for (var p in params) {
            param_names.append(p.name);
        }
        var others = Array<OtherName>();
        for (var result in other_names(function.attributes, param_names, function.loc.file)) {
            if (result.is_ok()) {
                others.append(result.value());
            }
        }
        return Callee(display, params, others, function.loc);
    }

    ## The parameter a call names `name`, and whether that is a former name.
    index_of(name: String): (ulong, bool)? {
        ulong i = 0;
        while (i < params.count) {
            if (params[i].name == name) {
                return Optional<(ulong, bool)>.Value((i, false));
            }
            i += 1;
        }
        for (var o in renames) {
            if (o.name == name) {
                return Optional<(ulong, bool)>.Value((o.parameter, o.deprecated));
            }
        }
        return Optional<(ulong, bool)>.Empty;
    }
}

## The location of argument `index` of `args` (its name, if named).
_argument_loc(args: Expression[], index: ulong, call: Loc, literals: Array<(Loc, ulong, Loc)>): Loc {
    if (args[index] is NamedArgument(named)) {
        return named.loc;
    }
    var loc = _expression_loc(args[index]);
    if (!loc.is_none()) {
        return loc;
    }
    for (var (c, i, at) in literals) {
        if (c.same(call) and i == index) {
            return at;
        }
    }
    return call;
}

## Where each parameter's argument comes from (the index written, or none
## for a skipped parameter that takes its default), and the former names
## used.
struct _Plan {
    var slots: Array<ulong?>;
    var deprecated: Array<(Loc, String, String)>;

    construct(slots: Array<ulong?>, deprecated: Array<(Loc, String, String)>) {
        this.slots = slots;
        this.deprecated = deprecated;
    }

    same_slots(other: _Plan): bool {
        if (slots.count != other.slots.count) {
            return false;
        }
        ulong i = 0;
        while (i < slots.count) {
            var a = slots[i];
            var b = other.slots[i];
            if (a.is_value() != b.is_value() or (a.is_value() and a.value() != b.value())) {
                return false;
            }
            i += 1;
        }
        return true;
    }
}

## Binds `args` to `callee`'s parameters.
_plan(callee: Callee, args: Expression[], call: Loc, literals: Array<(Loc, ulong, Loc)>): Result<_Plan, Diagnostic> {
    var slots = Array<ulong?>();
    for (var _ in callee.params) {
        slots.append(Optional<ulong>.Empty);
    }
    var deprecated = Array<(Loc, String, String)>();
    var declared = Optional<Location>.Value(location_of(callee.loc));
    ulong written = 0;
    while (written < args.count) {
        ulong index = written;
        if (args[written] is NamedArgument(named)) {
            var found = callee.index_of(named.name);
            if (!found.is_value()) {
                var message = $"no parameter named '{named.name}' in '{callee.display}'";
                var candidates = Array<String>();
                for (var p in callee.params) {
                    candidates.append(p.name);
                }
                for (var o in callee.renames) {
                    if (!o.deprecated) {
                        candidates.append(o.name);
                    }
                }
                var close = _closest(named.name, candidates);
                if (close.is_value()) {
                    message = message + $"; did you mean '{close.value()}'?";
                }
                return Result<_Plan, Diagnostic>.Err(error_at(message, named.loc).with_note("declared here", declared));
            }
            var (i, renamed) = found.value();
            if (renamed) {
                deprecated.append((named.loc, named.name, callee.params[i].name));
            }
            index = i;
        } else if (written >= callee.params.count) {
            return Result<_Plan, Diagnostic>.Err(
                error_at(
                    $"too many arguments to '{callee.display}': expected at most {callee.params.count}, have {args.count}",
                    _argument_loc(args, written, call, literals)
                ).with_note("declared here", declared)
            );
        }
        if (slots[index].is_value()) {
            var first = slots[index].value();
            return Result<_Plan, Diagnostic>.Err(
                error_at(
                    $"argument for '{callee.params[index].name}' given twice",
                    _argument_loc(args, written, call, literals)
                ).with_note(
                    "first given here",
                    Optional<Location>.Value(location_of(_argument_loc(args, first, call, literals)))
                )
            );
        }
        slots[index] = Optional<ulong>.Value(written);
        written += 1;
    }
    ulong p = 0;
    while (p < slots.count) {
        if (!slots[p].is_value() and !callee.params[p].has_default) {
            return Result<_Plan, Diagnostic>.Err(
                error_at(
                    $"missing argument for parameter '{callee.params[p].name}' in call to '{callee.display}'", call
                ).with_note("declared here", declared)
            );
        }
        p += 1;
    }
    # Trailing parameters left out keep their defaults as usual.
    ulong used = slots.count;
    while (used > 0 and !slots[used - 1].is_value()) {
        used -= 1;
    }
    var kept = Array<ulong?>();
    ulong k = 0;
    while (k < used) {
        kept.append(slots[k]);
        k += 1;
    }
    return Result<_Plan, Diagnostic>.Ok(_Plan(kept, deprecated));
}

## The candidate closest to `name` by edit distance, if close enough to be
## a likely typo.
_closest(name: String, candidates: String[]): String? {
    var a = _chars(name);
    var best = Optional<String>.Empty;
    ulong best_distance = 0;
    for (var c in candidates) {
        var b = _chars(c);
        var row = Array<ulong>();
        ulong j = 0;
        while (j <= b.count) {
            row.append(j);
            j += 1;
        }
        ulong i = 0;
        while (i < a.count) {
            var previous = row[0];
            row[0] = i + 1;
            j = 0;
            while (j < b.count) {
                var current = row[j + 1];
                var substitution = previous + (a[i] == b[j] ? 0 : 1);
                var value = substitution;
                if (row[j] + 1 < value) {
                    value = row[j] + 1;
                }
                if (current + 1 < value) {
                    value = current + 1;
                }
                row[j + 1] = value;
                previous = current;
                j += 1;
            }
            i += 1;
        }
        var distance = row[b.count];
        var longest = name.size > c.size ? name.size : c.size;
        if (distance <= (longest + 2) / 3 and (!best.is_value() or distance < best_distance)) {
            best = Optional<String>.Value(c);
            best_distance = distance;
        }
    }
    return best;
}

## The characters of `text`, each as its bytes.
_chars(text: String): String[] {
    var out = Array<String>();
    ulong i = 0;
    while (i < text.size) {
        ulong end = i + 1;
        while (end < text.size and (text.byte_at(end) & 0xC0) == 0x80) {
            end += 1;
        }
        out.append(text.substr_bytes(i, end - i));
        i = end;
    }
    return out;
}

## Whether `args` names any argument.
_has_named(args: Expression[]): bool {
    for (var a in args) {
        if (a is NamedArgument(_)) {
            return true;
        }
    }
    return false;
}

## The location of the first named argument's name.
_first_named(args: Expression[]): Loc {
    for (var a in args) {
        if (a is NamedArgument(named)) {
            return named.loc;
        }
    }
    return Loc.none();
}

## Whether `e` stays in place when binding reorders arguments: a literal or
## a closure.
_is_constant(e: Expression): bool {
    if (_is_string_literal(e)) {
        return true;
    }
    match (e) {
        MakeClosure(_), BoolLiteral(_), IntLiteral(_), FloatLiteral(_), StringLiteral(_), PointerLiteral, ClosureLiteral(_), FunctionRef(_) => {
            return true;
        }
        Unary(node) => {
            match (node.op) {
                Neg, Pos, BitNot, LogicalNot => {
                    return _is_constant(node.operand);
                }
                else => {
                    return false;
                }
            }
        }
        Cast(node) => {
            return _is_constant(node.expr);
        }
        else => {
            return false;
        }
    }
}

## A string literal `convert_string_literals` made a `String`.
_is_string_literal(e: Expression): bool {
    if (e is FunctionCall(call)) {
        if (call.function == "String" and call.args.count > 0) {
            if (call.args[0] is StringLiteral(literal)) {
                return literal.is_raw and literal.loc.same(call.loc);
            }
        }
    }
    return false;
}

## Binds the call `call` (a `FunctionCall` or `MethodCall` with named
## arguments) to the one of `callees` its names fit, reporting an error
## when none does.
##
## @param call the call
## @param callees the functions it may call
## @param literals `Module.literal_args`
## @param state the passes' state
## @returns the bound call, wrapped in what it evaluates first
export bind_call(
    call: Expression, callees: Callee[], literals: Array<(Loc, ulong, Loc)>, state: PassState
): Expression {
    var args = Array<Expression>();
    var at = Loc.none();
    match (call) {
        FunctionCall(node) => {
            args = node.args;
            at = node.loc;
        }
        MethodCall(node) => {
            args = node.args;
            at = node.loc;
        }
        else => {
            return call;
        }
    }
    if (!_has_named(args) or callees.count == 0) {
        return call;
    }
    var results = Array<Result<_Plan, Diagnostic>>();
    for (var c in callees) {
        results.append(_plan(c, args, at, literals));
    }
    var viable = Array<ulong>();
    ulong r = 0;
    while (r < results.count) {
        if (results[r].is_ok()) {
            viable.append(r);
        }
        r += 1;
    }
    if (viable.count == 0) {
        if (results.count == 1) {
            state.report(results[0].error());
            return call;
        }
        var error = error_at($"no matching function for call to '{callees[0].display}'", _first_named(args));
        ulong i = 0;
        while (i < callees.count) {
            if (results[i].is_err()) {
                error = error.with_note(
                    $"candidate function not viable: {results[i].error().message}",
                    Optional<Location>.Value(location_of(callees[i].loc))
                );
            }
            i += 1;
        }
        state.report(error);
        return call;
    }
    var first = viable[0];
    var chosen = results[first].value();
    for (var v in viable) {
        if (results[v].value().same_slots(chosen)) {
            continue;
        }
        var error = error_at(
            $"named arguments bind differently in the overloads of '{callees[first].display}'", _first_named(args)
        );
        for (var w in viable) {
            error = error.with_note("candidate function", Optional<Location>.Value(location_of(callees[w].loc)));
        }
        state.report(error);
        return call;
    }
    for (var (loc, old, current) in chosen.deprecated) {
        var fix = Fix($"rename '{old}' to '{current}'", location_of(loc), current);
        state.notes.append(
            Diagnostic.deprecated($"parameter name '{old}'", $"use '{current}' instead", location_of(loc), fix)
        );
    }
    ulong positional = 0;
    while (positional < args.count and !(args[positional] is NamedArgument(_))) {
        positional += 1;
    }
    # The parameter each named argument fills, in written order.
    var filled = Array<ulong>();
    ulong w = positional;
    while (w < args.count) {
        ulong slot = 0;
        ulong s = 0;
        while (s < chosen.slots.count) {
            if (chosen.slots[s].is_value() and chosen.slots[s].value() == w) {
                slot = s;
                break;
            }
            s += 1;
        }
        filled.append(slot);
        w += 1;
    }
    bool reordered = false;
    ulong f = 1;
    while (f < filled.count) {
        if (filled[f - 1] > filled[f]) {
            reordered = true;
        }
        f += 1;
    }
    var written = Array<Expression>();
    for (var a in args) {
        if (a is NamedArgument(named)) {
            written.append(named.value);
        } else {
            written.append(a);
        }
    }
    # Reordered arguments: evaluate the receiver when it is a call, then
    # every argument, first, in the order written.
    var hoisted = Array<(ulong, Expression, Loc)>();
    if (reordered) {
        if (call is MethodCall(node)) {
            match (node.this_value) {
                FunctionCall(_), MethodCall(_), Invoke(_) => {
                    node.this_value = _hoist(node.this_value, at, hoisted, state);
                }
                else => {}
            }
        }
        ulong i = 0;
        while (i < written.count) {
            if (!_is_constant(written[i])) {
                written[i] = _hoist(written[i], at, hoisted, state);
            }
            i += 1;
        }
    }
    var bound = Array<Expression>();
    ulong index = 0;
    while (index < chosen.slots.count) {
        var slot = chosen.slots[index];
        if (slot.is_value()) {
            bound.append(written[slot.value()]);
        } else {
            # A skipped parameter's type: its members' if they agree.
            var ty = callees[viable[0]].params[index].ty;
            for (var v in viable) {
                if (!(callees[v].params[index].ty == ty)) {
                    ty = TypeName.auto();
                    break;
                }
            }
            bound.append(Expression.DefaultArgument(DefaultArgumentExpression(ty.copy())));
        }
        index += 1;
    }
    match (call) {
        FunctionCall(node) => {
            node.args = bound;
        }
        MethodCall(node) => {
            node.args = bound;
        }
        else => {}
    }
    var out = call;
    ulong h = hoisted.count;
    while (h > 0) {
        h -= 1;
        var (id, subject, loc) = hoisted[h];
        out = Expression.WithSubject(WithSubject(subject, out, id, Optional<String>.Empty, loc));
    }
    return out;
}

_hoist(value: Expression, at: Loc, hoisted: Array<(ulong, Expression, Loc)>, state: PassState): Expression {
    var id = state.next_subject;
    state.next_subject += 1;
    var loc = _expression_loc(value);
    if (loc.is_none()) {
        loc = at;
    }
    hoisted.append((id, value, loc));
    return Expression.Subject(SubjectExpression(id, TypeName.auto(), loc));
}

## The callees of `module`'s checked declarations, built once per unit
## and kept in `state.checked_callees`.
_checked_callees(module: Module, state: PassState): Callees {
    if (state.checked_callees.is_value()) {
        var kept = state.checked_callees.value() as? Callees;
        if (kept.is_value()) {
            return kept.value();
        }
    }
    var built = Callees(module);
    state.checked_callees = Optional<PassMemo>.Value(built);
    return built;
}

## The callees of a module, by how calls name them, over a module with no
## checked runtime. Trait types' methods are not gathered: only
## `bind_method_call` reads them.
export struct Callees {
    ## Free functions (and value-type methods, `E::m`) by overload set.
    var functions: HashMap<String, Callee[]> = HashMap<String, Callee[]>();
    ## The externs' names.
    var externs: HashSet<String> = HashSet<String>();
    ## Constructors by struct name (`Point`, `Box<int>`, a generic base's
    ## `Box`).
    var constructors: HashMap<String, Callee[]> = HashMap<String, Callee[]>();
    ## Methods by receiver type, then by overload set.
    var methods: HashMap<String, HashMap<String, Callee[]>> = HashMap<String, HashMap<String, Callee[]>>();
    ## `Module.literal_args`.
    var literals: Array<(Loc, ulong, Loc)>;

    ## The callees of the checked declarations, when nothing in the unit
    ## changed them: built once per unit (`PassState.checked_callees`), and
    ## read under what the rest of the module adds.
    var base: Callees? = Optional<Callees>.Empty;
    # A unit's checked callees: how many methods and constructors each
    # checked struct had (`covers`).
    var members: HashMap<String, ulong> = HashMap<String, ulong>();
    # A unit's checked callees, indexed to be made as lookups reach them.
    var _checked_functions: HashMap<String, FunctionDef[]> = HashMap<String, FunctionDef[]>();
    var _by_name: HashMap<String, Array<(ulong, StructDef)>> = HashMap<String, Array<(ulong, StructDef)>>();
    var _by_spelling: HashMap<String, Array<(ulong, StructDef)>> = HashMap<String, Array<(ulong, StructDef)>>();
    var _made_receivers: HashSet<String> = HashSet<String>();
    var _made_constructors: HashSet<String> = HashSet<String>();

    ## The callees of `module`.
    ##
    ## @param module the model
    ## @param state the passes' state, which keeps the checked declarations'
    ##     callees
    ## @param trait_types the module's trait types, when already found
    construct(module: Module, state: PassState, trait_types: TypeName[]? = Optional<TypeName[]>.Empty) {
        literals = module.literal_args;
        bool checked = module.checked.structs.count > 0 or module.checked.functions.count > 0;
        if (checked) {
            base = Optional<Callees>.Value(_checked_callees(module, state));
        }
        # The base holds the rest: a checked struct it does not cover is one
        # the unit extended or specialized a method for, one of its own.
        var own = unit_decls(module);
        for (var function in own.functions) {
            _add_function(function);
        }
        for (var st in own.structs) {
            if (checked and base.value().covers(st)) {
                continue;
            }
            _add_struct(st);
        }
        for (var e in module.externs) {
            externs.insert(e.name);
        }
        _add_trait_types(module, trait_types_of(module, trait_types, state.trait_types_memo()));
    }

    # The callees of `module`'s checked declarations alone, made as lookups
    # reach them: their structs by name and by spelling and their functions
    # by overload set, each in the module's order.
    construct(module: Module) {
        literals = Array<(Loc, ulong, Loc)>();
        for (var function in module.functions) {
            if (is_checked_function(module, function)) {
                var set = set_name(_before_type_arguments(function.name));
                if (!_checked_functions.contains(set)) {
                    _checked_functions[set] = Array<FunctionDef>();
                }
                _checked_functions[set].append(function);
            }
        }
        ulong at = 0;
        for (var st in module.structs) {
            if (!module.checked.structs.contains(st.name)) {
                continue;
            }
            members[st.name] = _members(st);
            _index(_by_name, st.name, at, st);
            var spelled = st.ty.to_string();
            if (spelled != st.name) {
                _index(_by_spelling, spelled, at, st);
            }
            at += 1;
        }
    }

    _index(map: HashMap<String, Array<(ulong, StructDef)>>, key: String, at: ulong, st: StructDef) {
        if (!map.contains(key)) {
            map[key] = Array<(ulong, StructDef)>();
        }
        map[key].append((at, st));
    }

    # A base's free functions of overload set `set`.
    _checked_set(set: String): Callee[]? {
        var made = functions.try_get(set);
        if (made.is_value()) {
            return made;
        }
        var found = _checked_functions.try_get(set);
        if (!found.is_value()) {
            return Optional<Callee[]>.Empty;
        }
        for (var function in found.value()) {
            _add_function(function);
        }
        return functions.try_get(set);
    }

    # A base's checked structs a lookup of `key` reaches: those named, then
    # spelled, `key`, in the module's order.
    _checked_structs(key: String): Array<StructDef> {
        var all = Array<(ulong, StructDef)>();
        var named = _by_name.try_get(key);
        if (named.is_value()) {
            all.append_all(named.value());
        }
        var spelled = _by_spelling.try_get(key);
        if (spelled.is_value()) {
            all.append_all(spelled.value());
        }
        all.sort((a, b) => {
            var (x, _) = a;
            var (y, _) = b;
            return x < y ? -1 : (x > y ? 1 : 0);
        });
        var out = Array<StructDef>();
        for (var (_, st) in all) {
            out.append(st);
        }
        return out;
    }

    # A base's method sets of receiver `key`: those of the checked structs
    # spelled `key`, in the module's order.
    _checked_receiver(key: String): HashMap<String, Callee[]>? {
        if (!_made_receivers.insert(key)) {
            return methods.try_get(key);
        }
        var sets = HashMap<String, Callee[]>();
        for (var st in _checked_structs(key)) {
            if (st.ty.to_string() == key) {
                _add_methods(st, sets);
            }
        }
        if (sets.count == 0 and !_spelled_by(key)) {
            return Optional<HashMap<String, Callee[]>>.Empty;
        }
        methods[key] = sets;
        return Optional<HashMap<String, Callee[]>>.Value(sets);
    }

    # Whether a checked struct is spelled `key`.
    _spelled_by(key: String): bool {
        for (var st in _checked_structs(key)) {
            if (st.ty.to_string() == key) {
                return true;
            }
        }
        return false;
    }

    # A base's constructors called `key`: those of the checked structs
    # named or spelled `key`, in the module's order.
    _checked_constructors(key: String): Callee[]? {
        if (!_made_constructors.insert(key)) {
            return constructors.try_get(key);
        }
        for (var st in _checked_structs(key)) {
            for (var c in st.constructors) {
                _push(constructors, key, Callee.of(c, st.name, 0, _generic_names(st)));
            }
        }
        return constructors.try_get(key);
    }

    ## Whether these (a unit's checked callees) cover `st`: it is checked,
    ## and nothing added to its methods or constructors since.
    covers(st: StructDef): bool {
        var counted = members.try_get(st.name);
        return counted.is_value() and counted.value() == _members(st);
    }

    _add_function(function: FunctionDef) {
        var display = _before_type_arguments(function.name);
        _push(functions, set_name(display), Callee.of(function, display, 0, Array<String>()));
    }

    _add_struct(st: StructDef) {
        var generic = _generic_names(st);
        var made = Array<Callee>();
        for (var c in st.constructors) {
            made.append(Callee.of(c, st.name, 0, generic));
        }
        for (var c in made) {
            _push(constructors, st.name, c);
        }
        var spelled = st.ty.to_string();
        if (spelled != st.name) {
            for (var c in made) {
                _push(constructors, spelled, c);
            }
        }
        if (!methods.contains(spelled)) {
            methods[spelled] = HashMap<String, Callee[]>();
        }
        _add_methods(st, methods[spelled]);
    }

    _generic_names(st: StructDef): Array<String> {
        var generic = Array<String>();
        if (!st.name.contains("<")) {
            for (var p in st.generic_params) {
                generic.append(p.name);
            }
        }
        return generic;
    }

    # `st`'s methods, filed under their overload sets in `own`.
    _add_methods(st: StructDef, own: HashMap<String, Callee[]>) {
        var generic = _generic_names(st);
        var all = Array<FunctionDef>();
        all.append_all(st.method_members);
        all.append_all(st.generic_methods);
        for (var method in all) {
            var bare = _before_type_arguments(method.name);
            var set = set_name(bare);
            if (!own.contains(set)) {
                own[set] = Array<Callee>();
            }
            # A specialized generic method (`map<long>`) repeats its base.
            bool repeats = false;
            if (method.name.contains("<")) {
                for (var g in st.generic_methods) {
                    if (g.name == bare) {
                        repeats = true;
                    }
                }
            }
            if (!repeats) {
                own[set].append(Callee.of(method, $"{st.name}.{set}", 0, generic));
            }
        }
    }

    # A value of trait type calls the trait's methods, by name.
    _add_trait_types(module: Module, trait_types: TypeName[]) {
        for (var ty in trait_types) {
            var def = trait_def(module.traits, ty);
            if (!def.is_value()) {
                continue;
            }
            var key = ty.to_string();
            if (!methods.contains(key)) {
                methods[key] = HashMap<String, Callee[]>();
            }
            var own = methods[key];
            for (var method in instance(def.value(), ty).methods) {
                _push(own, method.name, Callee.of(method, $"{ty.display()}.{method.name}", 0, Array<String>()));
            }
        }
    }

    ## The methods of set `method` on a receiver of type `receiver`.
    methods_of(receiver: String, method: String): Callee[]? {
        var own = methods.try_get(receiver);
        if (!own.is_value() and base.is_value()) {
            own = base.value()._checked_receiver(receiver);
        }
        if (!own.is_value()) {
            return Optional<Callee[]>.Empty;
        }
        return own.value().try_get(set_name(_before_type_arguments(method)));
    }

    ## The methods a receiver of type `receiver` has, by overload set.
    receiver(receiver: String): HashMap<String, Callee[]>? {
        var own = methods.try_get(receiver);
        if (own.is_value() or !base.is_value()) {
            return own;
        }
        return base.value()._checked_receiver(receiver);
    }

    ## The free functions named `name` (type arguments ignored).
    functions_named(name: String): Callee[]? {
        return function_set(set_name(_before_type_arguments(name)));
    }

    ## The free functions of overload set `set`: the checked ones first, as
    ## the module declares them.
    function_set(set: String): Callee[]? {
        return _merged(
            base.is_value() ? base.value()._checked_set(set) : Optional<Callee[]>.Empty, functions.try_get(set)
        );
    }

    ## The constructors of the struct called `name`: one struct's, so all
    ## here or all in `base`.
    constructors_of(name: String): Callee[]? {
        var own = constructors.try_get(name);
        if (own.is_value() or !base.is_value()) {
            return own;
        }
        return base.value()._checked_constructors(name);
    }
}

extend Callees with PassMemo;

## `first`'s callees, then `then`'s.
_merged(first: Callee[]?, then: Callee[]?): Callee[]? {
    if (!first.is_value()) {
        return then;
    }
    if (!then.is_value()) {
        return first;
    }
    var out = Array<Callee>();
    out.append_all(first.value());
    out.append_all(then.value());
    return Optional<Callee[]>.Value(out);
}

## How many methods and constructors `st` has.
_members(st: StructDef): ulong {
    return st.method_members.count + st.generic_methods.count + st.constructors.count;
}

_push(map: HashMap<String, Callee[]>, key: String, callee: Callee) {
    if (!map.contains(key)) {
        map[key] = Array<Callee>();
    }
    map[key].append(callee);
}

_before_type_arguments(name: String): String {
    var at = name.find("<");
    return at < 0 ? name : name.substr_bytes(0, at as ulong);
}

## Every name declared in `function`: its parameters and locals.
_declared_names(function: FunctionDef): HashSet<String> {
    var names = HashSet<String>();
    for (var p in function.parameters) {
        names.insert(p.name);
    }
    if (function.body.is_value()) {
        _declared_in(function.body.value(), names);
    }
    return names;
}

## Adds each local `block` declares, in nested blocks too, to `names`.
export _declared_in(block: Block, names: HashSet<String>) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    names.insert(variable.name);
                }
            }
            Block(inner) => {
                _declared_in(inner, names);
            }
            Branch(branch) => {
                _declared_in(branch.if_block, names);
                if (branch.else_block.is_value()) {
                    _declared_in(branch.else_block.value(), names);
                }
            }
            While(loop) => {
                _declared_in(loop.block, names);
            }
            else => {}
        }
    }
}

## Binds the calls whose callee a name decides (free functions,
## constructors, and a method called bare inside its struct).
##
## @param module the model, changed in place
## @param state the passes' state
export bind_calls(module: Module, state: PassState) {
    var callees = Callees(module, state);
    var globals = HashSet<String>();
    for (var g in module.globals) {
        globals.insert(g.name);
    }
    var none = Optional<HashMap<String, Callee[]>>.Empty;
    # A checked declaration's calls were bound with its compilation unit:
    # binding the closure's defaults again cost each unit's check more than
    # its own code (#167).
    var own = unit_decls(module);
    for (var function in own.functions) {
        # Only bodies and defaults are bound (a checked runtime's bodies
        # are stashed).
        if (function.body.is_value() or _has_default(function)) {
            _bind_in(function, none, callees, globals, state);
        }
    }
    for (var st in own.structs) {
        var members = Array<FunctionDef>();
        members.append_all(st.constructors);
        members.append_all(st.method_members);
        members.append_all(st.generic_methods);
        members.append(st.destructor);
        # Only bodies are bound (a checked runtime's are stashed).
        bool any = false;
        for (var m in members) {
            if (m.body.is_value()) {
                any = true;
            }
            for (var p in m.parameters) {
                if (p.default.is_value()) {
                    any = true;
                }
            }
        }
        if (!any) {
            continue;
        }
        var own = callees.receiver(st.ty.to_string());
        for (var m in members) {
            _bind_in(m, own, callees, globals, state);
        }
    }
    for (var e in module.checked.extensions..module.extensions.count) {
        for (var m in module.extensions[e].methods) {
            _bind_in(m, none, callees, globals, state);
        }
    }
    for (var t in module.traits) {
        for (var m in t.methods) {
            _bind_in(m, none, callees, globals, state);
        }
    }
    var binder = _GlobalBinder(callees, state);
    for (var g in module.globals) {
        if (g.default.is_value() and !module.checked.globals.contains(g.name)) {
            g.default = Optional<Expression>.Value(rewrite_expression(g.default.value(), binder));
        }
    }
}

_has_default(function: FunctionDef): bool {
    for (var p in function.parameters) {
        if (p.default.is_value()) {
            return true;
        }
    }
    return false;
}

_bind_in(
    function: FunctionDef, own: HashMap<String, Callee[]>?, callees: Callees, globals: HashSet<String>, state: PassState
) {
    var binder = _Binder(callees, own, _declared_names(function), globals, state);
    for (var p in function.parameters) {
        if (p.default.is_value()) {
            p.default = Optional<Expression>.Value(rewrite_expression(p.default.value(), binder));
        }
    }
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), binder);
    }
}

_report_extern(state: PassState, name: String, args: Expression[]) {
    state.report(error_at($"cannot name arguments in a call to extern function '{name}'", _first_named(args)));
}

## What `bind_calls` does at each expression of a function.
struct _Binder {
    var callees: Callees;
    var own: HashMap<String, Callee[]>?;
    var locals: HashSet<String>;
    var globals: HashSet<String>;
    var state: PassState;

    construct(
        callees: Callees,
        own: HashMap<String, Callee[]>?,
        locals: HashSet<String>,
        globals: HashSet<String>,
        state: PassState
    ) {
        this.callees = callees;
        this.own = own;
        this.locals = locals;
        this.globals = globals;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (!(e is FunctionCall(_))) {
            return e;
        }
        var call = _function_call(e);
        if (!_has_named(call.args)) {
            return e;
        }
        var base = _before_type_arguments(call.function);
        if (locals.contains(base) or globals.contains(base)) {
            return e;
        }
        var set = set_name(base);
        var found = Optional<Callee[]>.Empty;
        if (own.is_value()) {
            found = own.value().try_get(set);
        }
        if (!found.is_value()) {
            found = callees.function_set(set);
        }
        if (!found.is_value()) {
            found = callees.constructors_of(call.function);
        }
        if (!found.is_value()) {
            found = callees.constructors_of(base);
        }
        if (found.is_value()) {
            return bind_call(e, found.value(), callees.literals, state);
        }
        if (callees.externs.contains(base)) {
            _report_extern(state, base, call.args);
        }
        return e;
    }
}

extend _Binder with Rewriter;

## What `bind_calls` does at each expression of a global's initializer.
struct _GlobalBinder {
    var callees: Callees;
    var state: PassState;

    construct(callees: Callees, state: PassState) {
        this.callees = callees;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (!(e is FunctionCall(_))) {
            return e;
        }
        var call = _function_call(e);
        if (!_has_named(call.args)) {
            return e;
        }
        var base = _before_type_arguments(call.function);
        var found = callees.functions_named(base);
        if (!found.is_value()) {
            found = callees.constructors_of(base);
        }
        if (found.is_value()) {
            return bind_call(e, found.value(), callees.literals, state);
        }
        if (callees.externs.contains(base)) {
            _report_extern(state, base, call.args);
        }
        return e;
    }
}

extend _GlobalBinder with Rewriter;

_function_call(e: Expression): FunctionCallExpression {
    if (e is FunctionCall(call)) {
        return call;
    }
    return FunctionCallExpression();
}

## Returns whether `args` names any argument.
##
## @param args the call's arguments
## @returns true when one is named
export has_named(args: Expression[]): bool {
    return _has_named(args);
}

## Reports naming arguments in a call through a function value of type
## `ty`.
##
## @param state the passes' state
## @param ty the value's type
## @param args the call's arguments
export report_function_value(state: PassState, ty: TypeName, args: Expression[]) {
    state.report(
        error_at(
            $"cannot name arguments in a call through a function value of type '{ty.display()}'", _first_named(args)
        )
    );
}

## Binds `receiver.method(args)` given the receiver's type.
##
## @param e the call
## @param receiver the receiver's type
## @param callees the module's callees
## @param state the passes' state
## @returns the bound call
export bind_method_call(e: Expression, receiver: TypeName, callees: Callees, state: PassState): Expression {
    if (!(e is MethodCall(_))) {
        return e;
    }
    var node = _method_call(e);
    if (!_has_named(node.args) or receiver.is_empty() or receiver.contains_auto()) {
        return e;
    }
    var receiver_name = receiver.to_string();
    # A method of an enum or another value type is the function `E::m`,
    # whose first parameter is the value.
    var key = value_type_key(state, receiver_name);
    var owner = key.is_value() ? key.value() : receiver_name;
    var is_static = method_is_static(state, owner, node.method);
    if (is_static.is_value()) {
        var list = callees.function_set(enum_method_name(owner, node.method));
        if (!list.is_value()) {
            return e;
        }
        ulong skip = is_static.value() ? 0 : 1;
        var shifted = Array<Callee>();
        for (var c in list.value()) {
            var params = Array<Parameter>();
            ulong i = skip;
            while (i < c.params.count) {
                params.append(c.params[i]);
                i += 1;
            }
            var renames = Array<OtherName>();
            for (var o in c.renames) {
                if (o.parameter >= skip) {
                    renames.append(OtherName(o.name, o.parameter - skip, o.deprecated));
                }
            }
            shifted.append(Callee(c.display, params, renames, c.loc));
        }
        return bind_call(e, shifted, callees.literals, state);
    }
    var list = callees.methods_of(receiver_name, node.method);
    if (list.is_value()) {
        return bind_call(e, list.value(), callees.literals, state);
    }
    return e;
}

_method_call(e: Expression): MethodCallExpression {
    if (e is MethodCall(node)) {
        return node;
    }
    return MethodCallExpression(Expression.ThisRef);
}

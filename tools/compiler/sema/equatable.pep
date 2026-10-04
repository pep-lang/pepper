## `[Equatable]`: `pepper_sema::equatable` in Pepper. A struct marked
## `[Equatable]` gets an `==` that compares the tuple of its fields with
## another's, and a `__hash` that hashes that tuple, before any pass runs.
## A field marked `[Equatable(exclude = true)]` (or `include = false`) is
## left out of both.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Kind,
    MemberRefExpression,
    Module,
    ReturnStatement,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeName,
    VariableDef
] from "model";
import [TUPLE] from "type_name";

## The attribute that derives `==` and `hash` from the fields, and, on a
## field, says whether that field takes part.
export const EQUATABLE_ATTRIBUTE = "Equatable";

## The synthesized method that hashes an `[Equatable]` struct's fields.
export const HASH_METHOD = "__hash";

## The `[Equatable]` or `[Equatable(...)]` among `attributes`.
_find_equatable(attributes: ast.Attribute[]): ast.Attribute? {
    for (var attribute in attributes) {
        if (attribute.name() == EQUATABLE_ATTRIBUTE) {
            return Optional<ast.Attribute>.Value(attribute);
        }
    }
    return Optional<ast.Attribute>.Empty;
}

## Gives every `[Equatable]` struct of `module` its `==` and `__hash`, and
## reports a misplaced or contradictory `[Equatable]`.
##
## @param module the model, changed in place
## @returns the first error
export derive_equatable(module: Module): Diagnostic? {
    for (var e in module.enums) {
        var attribute = _find_equatable(e.attributes);
        if (attribute.is_value()) {
            return Optional<Diagnostic>.Value(
                error_at(
                    $"'[{EQUATABLE_ATTRIBUTE}]' does not apply to enum '{e.name}': its cases carry no values, so it already compares and hashes by case",
                    Loc.at(e.loc.file, attribute.value().span)
                )
            );
        }
    }
    for (var st in module.structs) {
        var error = _derive_struct(st);
        if (error.is_value()) {
            return error;
        }
    }
    return Optional<Diagnostic>.Empty;
}

## An argument of an attribute call: its name, if it has one, and value.
struct _Argument {
    var name: String?;
    var value: ast.Expression;

    construct(name: String?, value: ast.Expression) {
        this.name = name;
        this.value = value;
    }
}

## The attribute's arguments in the order written; none for a bare
## `[Name]`.
_arguments(attribute: ast.Attribute): _Argument[] {
    var out = Array<_Argument>();
    match (attribute.body) {
        FunctionCall(_, arguments, _) => {
            for (var argument in arguments) {
                match (argument) {
                    NamedArgument(name, _, value, _) => {
                        out.append(_Argument(Optional<String>.Value(name), value));
                    }
                    else => {
                        out.append(_Argument(Optional<String>.Empty, argument));
                    }
                }
            }
        }
        else => {}
    }
    return out;
}

## Whether a field whose attributes are `attributes` takes part in the
## derived `==` and hash: unless its `[Equatable(...)]` says `include =
## false` or `exclude = true`. Positional arguments are `include`, then
## `exclude`.
_included(attributes: ast.Attribute[], file: uint): Result<bool, Diagnostic> {
    var attribute = _find_equatable(attributes);
    if (!attribute.is_value()) {
        return Result<bool, Diagnostic>.Ok(true);
    }
    var include = Optional<(bool, ast.Span)>.Empty;
    var exclude = Optional<(bool, ast.Span)>.Empty;
    ulong index = 0;
    for (var argument in _arguments(attribute.value())) {
        var name = argument.name.is_value() ? argument.name.value() : (index == 0 ? "include" : "exclude");
        var span = argument.value.span();
        var value = Optional<bool>.Empty;
        match (argument.value) {
            Literal(literal, _) => {
                match (literal) {
                    Bool(b) => {
                        value = Optional<bool>.Value(b);
                    }
                    else => {}
                }
            }
            else => {}
        }
        if (!value.is_value()) {
            return Result<bool, Diagnostic>.Err(
                error_at($"'{name}' of '[{EQUATABLE_ATTRIBUTE}]' must be 'true' or 'false'", Loc.at(file, span))
            );
        }
        if (name == "include") {
            include = Optional<(bool, ast.Span)>.Value((value.value(), span));
        } else {
            exclude = Optional<(bool, ast.Span)>.Value((value.value(), span));
        }
        index += 1;
    }
    if (include.is_value() and exclude.is_value()) {
        var (included, _) = include.value();
        var (excluded, at) = exclude.value();
        if (included == excluded) {
            return Result<bool, Diagnostic>.Err(
                error_at(
                    $"'include = {included}' and 'exclude = {excluded}' contradict each other; give one of them",
                    Loc.at(file, at)
                )
            );
        }
    }
    bool kept = true;
    if (include.is_value()) {
        var (included, _) = include.value();
        kept = included;
    }
    if (exclude.is_value()) {
        var (excluded, _) = exclude.value();
        kept = kept and !excluded;
    }
    return Result<bool, Diagnostic>.Ok(kept);
}

_derive_struct(st: StructDef): Diagnostic? {
    var file = st.loc.file;
    var equatable = _find_equatable(st.attributes);
    if (!equatable.is_value()) {
        for (var field in st.field_members) {
            var attribute = _find_equatable(field.attributes);
            if (attribute.is_value()) {
                return Optional<Diagnostic>.Value(
                    error_at(
                        $"'[{EQUATABLE_ATTRIBUTE}]' on a field applies only to a field of an '[{EQUATABLE_ATTRIBUTE}]' struct",
                        Loc.at(file, attribute.value().span)
                    ).with_note(
                        $"mark '{st.name}' '[{EQUATABLE_ATTRIBUTE}]' to derive '==' and 'hash' from its fields",
                        Optional<Location>.Value(location_of(st.loc))
                    )
                );
            }
        }
        return Optional<Diagnostic>.Empty;
    }
    var attribute_loc = Loc.at(file, equatable.value().span);
    if (_arguments(equatable.value()).count > 0) {
        return Optional<Diagnostic>.Value(
            error_at(
                $"'[{EQUATABLE_ATTRIBUTE}]' on '{st.name}' takes no arguments; 'include' and 'exclude' apply to its fields",
                attribute_loc
            )
        );
    }
    # Already derived (a module built once and applied again).
    for (var m in st.method_members) {
        if (m.name == HASH_METHOD) {
            return Optional<Diagnostic>.Empty;
        }
    }
    if (st.is_value()) {
        return Optional<Diagnostic>.Value(
            error_at(
                $"'[{EQUATABLE_ATTRIBUTE}]' does not apply to value type '{st.name}': a value already compares and hashes by its fields",
                attribute_loc
            )
        );
    }
    # An `==` taking another type is an overload beside the derived one.
    for (var own in st.method_members) {
        if (own.name == "==" and own.parameters.count == 1 and own.parameters[0].ty == st.ty) {
            return Optional<Diagnostic>.Value(
                error_at(
                    $"'{st.name}' is '[{EQUATABLE_ATTRIBUTE}]', so its '==' is derived and cannot be declared",
                    own.loc
                ).with_note(
                    $"remove this '==', or remove '[{EQUATABLE_ATTRIBUTE}]' to declare both '==' and 'hash' by hand",
                    Optional<Location>.Empty
                ).with_note($"'[{EQUATABLE_ATTRIBUTE}]' is here", Optional<Location>.Value(location_of(attribute_loc)))
            );
        }
    }
    var compared = Array<VariableDef>();
    for (var field in st.field_members) {
        var included = _included(field.attributes, file);
        if (included.is_err()) {
            return Optional<Diagnostic>.Value(included.error());
        }
        if (included.value()) {
            compared.append(field);
        }
    }
    Expression equal = Expression.BoolLiteral(true);
    Expression hash = Expression.IntLiteral(0);
    if (compared.count > 0) {
        equal = Expression.Binary(
            BinaryExpression(
                _tuple(compared, Expression.ThisRef),
                _tuple(compared, Expression.SymbolRef(SymbolRefExpression("other", st.ty.copy(), Loc.none()))),
                BinaryOp.Equal,
                Loc.none()
            )
        );
        hash = Expression.FunctionCall(
            FunctionCallExpression("hash", [_tuple(compared, Expression.ThisRef)], Loc.none())
        );
    }
    var parameter = VariableDef(
        name = "other", ty = st.ty.copy(), kind = Kind.Param, loc = attribute_loc, type_loc = Loc.none()
    );
    st.method_members.append(_method(st, "==", TypeName.named("bool"), [parameter], equal, attribute_loc));
    st.method_members.append(
        _method(st, HASH_METHOD, TypeName.named("u64"), Array<VariableDef>(), hash, attribute_loc)
    );
    return Optional<Diagnostic>.Empty;
}

## The tuple of `lhs`'s compared fields; a tuple has two elements or more,
## so one field is paired with `true`.
_tuple(compared: VariableDef[], lhs: Expression): Expression {
    var args = Array<Expression>();
    for (var field in compared) {
        args.append(Expression.MemberRef(MemberRefExpression(lhs.copy(), field.name, Loc.none())));
    }
    if (args.count == 1) {
        args.append(Expression.BoolLiteral(true));
    }
    return Expression.FunctionCall(FunctionCallExpression(TUPLE, args, Loc.none()));
}

## A synthesized method of `st` that returns `value`.
_method(st: StructDef, name: String, ty: TypeName, parameters: VariableDef[], value: Expression, at: Loc): FunctionDef {
    return FunctionDef(
        name = name,
        ty = ty,
        parameters = parameters,
        body = Optional<Block>.Value(
            Block("", [Statement.Return(ReturnStatement(Optional<Expression>.Value(value), at))])
        ),
        parent = Optional<String>.Value(st.ty.name),
        loc = at,
        owner = Loc.none()
    );
}

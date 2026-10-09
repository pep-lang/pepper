## `?` checks: `pepper_sema::passes::check_tries` in Pepper. Checks each
## `?` (lowered by the builder) once its operand's type is known: the operand
## is a `Result` or an `Optional`, the enclosing function returns the same
## kind, and a `Result`'s error converts to the function's error type.
## Without this check the lowered calls (`_propagates`, `_from_residual`)
## would fail with errors that name them.

import [Location] from compiler.diagnostic;
import [has_bare_attribute, IMPLICIT_ATTRIBUTE, TRY_LOCAL] from "builder";
import [error_at, location_of] from "common";
import [Block, FunctionDef, Module, StructDef, TypeName, VariableDef] from "model";
import [PassState] from "state";
import "type_name";

const _RESULT = "Result";
const _OPTIONAL = "Optional";

## Checks each `?` in the concrete code, as `check_tries::check_tries`
## does: generic bases are checked in their specializations.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_tries(module: Module, state: PassState) {
    for (var function in module.functions) {
        _check_tries_of(module, function, state);
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        for (var m in st.method_members) {
            _check_tries_of(module, m, state);
        }
        for (var c in st.constructors) {
            _check_tries_of(module, c, state);
        }
        _check_tries_of(module, st.destructor, state);
    }
}

_check_tries_of(module: Module, function: FunctionDef, state: PassState) {
    if (!function.is_generic_func and function.body.is_value()) {
        _check_tries_in(module, function, function.body.value(), state);
    }
}

_check_tries_in(module: Module, function: FunctionDef, block: Block, state: PassState) {
    for (var item in block.items) {
        match (item) {
            Declaration(declaration) => {
                if (declaration is Variable(v)) {
                    if (v.hidden and v.name.starts_with(TRY_LOCAL)) {
                        _check_try(module, function, v, state);
                    }
                }
            }
            Block(b) => {
                _check_tries_in(module, function, b, state);
            }
            Branch(b) => {
                _check_tries_in(module, function, b.if_block, state);
                if (b.else_block.is_value()) {
                    _check_tries_in(module, function, b.else_block.value(), state);
                }
            }
            While(w) => {
                _check_tries_in(module, function, w.block, state);
            }
            else => {}
        }
    }
}

## `Result` or `Optional` when `ty` is one; empty otherwise.
_try_kind(ty: TypeName): String {
    return ty.name == _RESULT or ty.name == _OPTIONAL ? ty.name : "";
}

## A `Result`'s error type: its second argument, else the default `Error`.
_error_type(ty: TypeName): TypeName {
    return ty.sub_types.count > 1 ? ty.sub_types[1] : TypeName.named("Error");
}

_check_try(module: Module, function: FunctionDef, hidden: VariableDef, state: PassState) {
    var operand = hidden.ty;
    if (operand.contains_auto()) {
        return;
    }
    var at = hidden.loc;
    var operand_kind = _try_kind(operand);
    if (operand_kind.size == 0) {
        state.report(error_at($"'?' requires a Result or an Optional, not '{operand.display()}'", at));
        return;
    }
    var returns = function.ty;
    if (returns.contains_auto()) {
        return;
    }
    if (_try_kind(returns) != operand_kind) {
        var article = operand_kind == _RESULT ? "a" : "an";
        state.report(
            error_at(
                $"'?' requires the enclosing function to return {article} {operand_kind}",
                at
            ).with_note(
                $"'{function.name}' returns '{returns.display()}'", Optional<Location>.Value(location_of(function.loc))
            )
        );
        return;
    }
    if (operand_kind == _OPTIONAL) {
        return;
    }
    var from = _error_type(operand);
    var to = _error_type(returns);
    if (from == to or _converts(module, from, to)) {
        return;
    }
    state.report(
        error_at(
            $"cannot convert error type '{from.display()}' to '{to.display()}'",
            at
        ).with_note(
            $"an [Implicit] constructor of '{to.display()}' from '{from.display()}' would convert it",
            Optional<Location>.Empty
        )
    );
}

## Whether a `from` converts to `to` where a `to` is expected: through an
## `[Implicit]` constructor of struct `to`, or as a value of a type that is
## not a struct.
_converts(module: Module, from: TypeName, to: TypeName): bool {
    for (var st in module.structs) {
        if (st.ty == to) {
            for (var c in st.constructors) {
                if (has_bare_attribute(c.attributes, IMPLICIT_ATTRIBUTE)) {
                    return c.parameters.count > 0 and c.parameters[0].ty == from;
                }
            }
            return false;
        }
    }
    return true;
}

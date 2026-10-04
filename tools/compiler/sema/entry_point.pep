## The program's entry point: `pepper_sema::passes::entry_point` in
## Pepper. A `main(args: String[])` is renamed `MAIN_WITH_ARGUMENTS`, and a
## `main()` that calls it with the runtime's `_pep_arguments()` takes its
## place.

import [Location] from compiler.diagnostic;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    Block, Expression, FunctionCallExpression, FunctionDef, Module, ReturnStatement, Statement, TypeName
] from "model";
import [PassState] from "state";

## The model name of a `main` that takes arguments.
export const MAIN_WITH_ARGUMENTS = "main@#args";

## The runtime function that supplies the arguments.
const _ARGUMENTS = "_pep_arguments";

## The attribute on the `main` that `pep-build --test` adds to the entry
## file.
export const TEST_MAIN_ATTRIBUTE = "TestMain";

## Rewrites a `main(args: String[])`, and reports any other parameter list
## on `main`, as `entry_point::lower_main_arguments` does.
##
## @param module the model, changed in place
## @param state the passes' state
export lower_main_arguments(module: Module, state: PassState) {
    _replace_main_with_test_main(module);
    var mains = Array<ulong>();
    ulong i = 0;
    while (i < module.functions.count) {
        var f = module.functions[i];
        if (f.name == "main" and !f.parent.is_value()) {
            mains.append(i);
        }
        i += 1;
    }
    if (mains.count >= 2) {
        state.report(
            error_at(
                "redefinition of 'main'",
                module.functions[mains[1]].loc
            ).with_note(
                "previous definition is here", Optional<Location>.Value(location_of(module.functions[mains[0]].loc))
            )
        );
        return;
    }
    if (mains.count == 0) {
        return;
    }
    var index = mains[0];
    var main = module.functions[index];
    if (main.parameters.count == 0) {
        return;
    }
    var param = main.parameters[0];
    if (main.parameters.count > 1 or !_is_string_array(param.ty) or main.generic_params.count > 0) {
        var at = main.parameters.count > 1 ? main.parameters[1].loc : param.type_loc;
        state.report(error_at("'main' must take no parameters or one 'String[]'", at.is_none() ? param.loc : at));
        return;
    }
    if (!main.body.is_value()) {
        return;
    }
    bool has_arguments = false;
    for (var f in module.functions) {
        if (f.name == _ARGUMENTS and !f.parent.is_value()) {
            has_arguments = true;
            break;
        }
    }
    if (!has_arguments) {
        state.report(error_at($"'main(args: String[])' needs '{_ARGUMENTS}' from the runtime", param.loc));
        return;
    }
    bool is_void = main.ty.name == "void" and main.ty.sub_types.count == 0;
    var ty = is_void ? TypeName.named("int") : main.ty.copy();
    main.name = MAIN_WITH_ARGUMENTS;
    var arguments = Expression.FunctionCall(FunctionCallExpression(_ARGUMENTS, Array<Expression>(), Loc.none()));
    var call = Expression.FunctionCall(FunctionCallExpression(MAIN_WITH_ARGUMENTS, [arguments], Loc.none()));
    var items = Array<Statement>();
    if (is_void) {
        items.append(Statement.Expression(call));
        items.append(
            Statement.Return(ReturnStatement(Optional<Expression>.Value(Expression.IntLiteral(0)), Loc.none()))
        );
    } else {
        items.append(Statement.Return(ReturnStatement(Optional<Expression>.Value(call), Loc.none())));
    }
    module.functions.append(
        FunctionDef(
            name = "main",
            ty = ty,
            body = Optional<Block>.Value(Block(name = "main", items = items)),
            # The declaration's location, so the build cache gives it the
            # same owner (its file) as the `main` it calls.
            loc = main.loc,
            owner = Loc.none()
        )
    );
}

## In a test build, drops every top-level `main` but the `[TestMain]` one.
_replace_main_with_test_main(module: Module) {
    bool any = false;
    for (var f in module.functions) {
        if (_is_test_main(f)) {
            any = true;
            break;
        }
    }
    if (!any) {
        return;
    }
    var kept = Array<FunctionDef>();
    for (var f in module.functions) {
        if (f.parent.is_value() or f.name != "main" or _is_test_main(f)) {
            kept.append(f);
        }
    }
    module.functions = kept;
}

_is_test_main(f: FunctionDef): bool {
    if (f.parent.is_value() or f.name != "main") {
        return false;
    }
    for (var a in f.attributes) {
        if (a.name() == TEST_MAIN_ATTRIBUTE) {
            return true;
        }
    }
    return false;
}

## `String[]`, as the builder spells it: `Array<String>`.
_is_string_array(ty: TypeName): bool {
    return ty.name == "Array"
        and ty.sub_types.count == 1
        and ty.sub_types[0].name == "String"
        and ty.sub_types[0].sub_types.count == 0;
}

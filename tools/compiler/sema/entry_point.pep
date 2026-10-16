## The program's entry point: `lower_main_arguments`. A
## `main(args: String[])` is renamed `MAIN_WITH_ARGUMENTS`, and a `main()`
## that calls it with the runtime's `_pep_arguments()` takes its place.
## `pep-build --entry <name>` starts the program in `name` instead, through
## a `main` that calls it.

import [Location] from compiler.diagnostic;
import [ENTRY_BUILD_OPTION, Target] from compiler.link;
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

## The name of the function the program starts in: `main`, or the one
## `pep-build --entry` names.
##
## @param target the compile target, whose build options name it
## @returns the function's name
export entry_function(target: Target): String {
    var named = target.build_options.try_get(ENTRY_BUILD_OPTION);
    return named.is_value() ? named.value() : "main";
}

## Rewrites a `main(args: String[])`, and reports any other parameter list
## on `main`. With `pep-build --entry <name>`, the function `name` is the
## entry point instead: every top-level `main` is dropped, and a `main`
## that calls `name` takes their place.
##
## @param module the model, changed in place
## @param state the passes' state
export lower_main_arguments(module: Module, state: PassState) {
    _replace_main_with_test_main(module);
    var entry = entry_function(state.target);
    if (entry != "main") {
        _drop_mains(module);
    }
    var mains = Array<ulong>();
    ulong i = 0;
    while (i < module.functions.count) {
        var f = module.functions[i];
        if (f.name == entry and !f.parent.is_value()) {
            mains.append(i);
        }
        i += 1;
    }
    if (mains.count >= 2) {
        state.report(
            error_at(
                $"redefinition of '{entry}'",
                module.functions[mains[1]].loc
            ).with_note(
                "previous definition is here", Optional<Location>.Value(location_of(module.functions[mains[0]].loc))
            )
        );
        return;
    }
    # A compilation unit other than the entry file's has none; the driver
    # reports an entry file without it (`--entry`).
    if (mains.count == 0) {
        return;
    }
    var index = mains[0];
    var main = module.functions[index];
    bool takes_arguments = main.parameters.count > 0;
    if (!takes_arguments and entry == "main") {
        return;
    }
    if (takes_arguments) {
        var param = main.parameters[0];
        if (main.parameters.count > 1 or !_is_string_array(param.ty) or main.generic_params.count > 0) {
            var at = main.parameters.count > 1 ? main.parameters[1].loc : param.type_loc;
            state.report(
                error_at($"'{entry}' must take no parameters or one 'String[]'", at.is_none() ? param.loc : at)
            );
            return;
        }
    }
    if (!main.body.is_value()) {
        return;
    }
    var arguments = Array<Expression>();
    if (takes_arguments) {
        if (!_has_arguments(module)) {
            state.report(
                error_at($"'{entry}(args: String[])' needs '{_ARGUMENTS}' from the runtime", main.parameters[0].loc)
            );
            return;
        }
        arguments.append(Expression.FunctionCall(FunctionCallExpression(_ARGUMENTS, Array<Expression>(), Loc.none())));
    }
    bool is_void = main.ty.name == "void" and main.ty.sub_types.count == 0;
    var ty = is_void ? TypeName.named("int") : main.ty.copy();
    if (entry == "main") {
        main.name = MAIN_WITH_ARGUMENTS;
    }
    var call = Expression.FunctionCall(FunctionCallExpression(main.name, arguments, Loc.none()));
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

## Whether the program has the runtime function that supplies the
## arguments.
_has_arguments(module: Module): bool {
    for (var f in module.functions) {
        if (f.name == _ARGUMENTS and !f.parent.is_value()) {
            return true;
        }
    }
    return false;
}

## Drops every top-level `main`, for an entry point of another name.
_drop_mains(module: Module) {
    var kept = Array<FunctionDef>();
    for (var f in module.functions) {
        if (f.parent.is_value() or f.name != "main") {
            kept.append(f);
        }
    }
    module.functions = kept;
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

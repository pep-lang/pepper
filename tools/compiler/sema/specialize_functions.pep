## Function specializations: `specialize_functions`. Each requested
## `larger<int>` is cloned from its generic base, the frozen template once
## the constraints are checked, with the type arguments substituted into its
## signature and body.

import [Module, Statement, StaticItem, TypeName] from "model";
import "replace_types";
import [specialization_too_deep, rewrite_static_calls] from "specialize_structs";
import [PassState] from "state";
import [parse_type_string, replace_map] from "type_name";

## Clones each requested function specialization from its generic base.
##
## @param module the model
## @param state the passes' state, which takes the first error
export specialize_functions(module: Module, state: PassState) {
    var specs = module.func_specs.copy();
    # Looked up once per spec, and a checked runtime brings many.
    var structs = HashSet<String>();
    for (var st in module.structs) {
        structs.insert(st.name);
        structs.insert(st.ty.to_string());
    }
    var functions = HashSet<String>();
    for (var f in module.functions) {
        functions.insert(f.name);
    }
    for (var spec in specs) {
        var spelled = spec.to_string();
        # Constructor-shaped specs are struct specs.
        if (structs.contains(spec.name) or structs.contains(spelled) or functions.contains(spelled)) {
            continue;
        }
        if (specialization_too_deep(module, spec, state)) {
            return;
        }
        var bases = module.templates.frozen ? module.templates.functions : module.functions;
        var base = Optional<FunctionDef>.Empty;
        for (var f in bases) {
            if (f.name == spec.name and f.is_generic_func) {
                base = Optional<FunctionDef>.Value(f);
                break;
            }
        }
        if (!base.is_value()) {
            continue;
        }
        var type_map = Array<(String, TypeName)>();
        ulong index = 0;
        while (index < base.value().generic_params.count) {
            var param = base.value().generic_params[index];
            # Missing arguments fall back to the parameter's default.
            if (index < spec.sub_types.count) {
                type_map.append((param.name, spec.sub_types[index]));
            } else if (param.default.is_value()) {
                type_map.append((param.name, param.default.value()));
            }
            index += 1;
        }
        # `count_all<int>(it)` for `count_all<T, I>`: the rest come from the
        # arguments, or `check_type_arguments` reports the call.
        if (type_map.count < base.value().generic_params.count) {
            continue;
        }
        var specialized = base.value().copy();
        # The instance's declared return type is the base's, with the
        # generic arguments substituted (`hash<T>` is `u64`).
        replace_map(specialized.ty, type_map);
        specialized.name = spelled;
        specialized.is_generic_func = false;
        for (var p in specialized.parameters) {
            replace_map(p.ty, type_map);
            if (p.default.is_value()) {
                replace_expression_types(p.default.value(), type_map);
            }
        }
        if (specialized.body.is_value()) {
            replace_body_types(specialized.body.value(), type_map);
        }
        rewrite_static_calls(specialized, type_map, Array<String>(), state);
        functions.insert(specialized.name);
        module.functions.append(specialized);
    }
}

## Replaces the types of `type_map` in `block`, as a function
## specialization does.
##
## @param block the block, changed in place
## @param type_map the parameters and their types
export replace_body_types(block: Block, type_map: Array<(String, TypeName)>) {
    ulong i = 0;
    while (i < block.items.count) {
        block.items[i] = _replace_statement_types(block.items[i], type_map);
        i += 1;
    }
}

_replace_statement_types(statement: Statement, type_map: Array<(String, TypeName)>): Statement {
    match (statement) {
        Expression(e) => {
            replace_expression_types(e, type_map);
        }
        Block(inner) => {
            replace_body_types(inner, type_map);
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                replace_map(variable.ty, type_map);
                if (variable.default.is_value()) {
                    replace_expression_types(variable.default.value(), type_map);
                }
            }
        }
        Branch(branch) => {
            replace_expression_types(branch.condition, type_map);
            replace_body_types(branch.if_block, type_map);
            if (branch.else_block.is_value()) {
                replace_body_types(branch.else_block.value(), type_map);
            }
        }
        While(loop) => {
            replace_expression_types(loop.condition, type_map);
            replace_body_types(loop.block, type_map);
        }
        Return(ret) => {
            if (ret.expr.is_value()) {
                replace_expression_types(ret.expr.value(), type_map);
            }
        }
        Static(block) => {
            _substitute(block, type_map);
            _replace_static_item_types(block.items, type_map);
        }
        else => {}
    }
    return statement;
}

_replace_static_item_types(items: StaticItem[], type_map: Array<(String, TypeName)>) {
    ulong i = 0;
    while (i < items.count) {
        match (items[i]) {
            For(node) => {
                _replace_static_item_types(node.body, type_map);
            }
            While(node) => {
                _replace_static_item_types(node.body, type_map);
            }
            Block(body) => {
                _replace_static_item_types(body, type_map);
            }
            If(node) => {
                _replace_static_item_types(node.then_items, type_map);
                _replace_static_item_types(node.else_items, type_map);
            }
            EmitIf(node) => {
                replace_expression_types(node.condition, type_map);
                _replace_static_item_types(node.then_items, type_map);
                _replace_static_item_types(node.else_items, type_map);
            }
            Emit(statement, at) => {
                items[i] = StaticItem.Emit(_replace_statement_types(statement, type_map), at);
            }
            else => {}
        }
        i += 1;
    }
}

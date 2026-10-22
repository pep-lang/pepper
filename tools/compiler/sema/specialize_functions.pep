## Function specializations: `specialize_functions`. Each requested
## `larger<int>` is cloned from its generic base, the frozen template once
## the constraints are checked, with the type arguments substituted into its
## signature and body.

import [FunctionDef, Module, Statement, StaticItem, StructDef, TypeName] from "model";
import "replace_types";
import [specialization_too_deep, rewrite_static_calls] from "specialize_structs";
import [GrowingList, PassMemo, PassState] from "state";
import [parse_type_string, replace_map] from "type_name";

## Clones each requested function specialization from its generic base.
##
## @param module the model
## @param state the passes' state, which takes the first error
export specialize_functions(module: Module, state: PassState) {
    var specs = module.func_specs.copy();
    # Looked up once per spec, and a checked runtime brings many: kept for
    # the unit's next round, which takes in only what was added since.
    var kept = state.unit_memos.try_get("specialize_functions");
    var memo = kept.is_value() ? (kept.value() as? _FunctionSpecsMemo).value() : _FunctionSpecsMemo();
    state.unit_memos["specialize_functions"] = memo;
    if (memo.specs_done > specs.count) {
        memo.specs_done = 0;
    }
    memo.update(module);
    var structs = memo.structs;
    var functions = memo.functions;
    for (var at in memo.specs_done..specs.count) {
        var spec = specs[at];
        var spelled = spec.to_string();
        # Constructor-shaped specs are struct specs.
        if (structs.contains(spec.name) or structs.contains(spelled) or functions.contains(spelled)) {
            continue;
        }
        if (specialization_too_deep(module, spec, state)) {
            return;
        }
        var base = memo.bases.try_get(spec.name);
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
    memo.specs_done = specs.count;
}

## What `specialize_functions` keeps for the compilation unit's next round
## (`PassState.unit_memos`): the structs' names and spelled types, the
## functions' names, the first generic base of each name, and how many specs
## were done. Specs only grow, at the end: a spec done is made, or cannot
## be, for good.
struct _FunctionSpecsMemo {
    var structs: HashSet<String> = HashSet<String>();
    var functions: HashSet<String> = HashSet<String>();
    var bases: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var specs_done: ulong = 0;
    var _structs: GrowingList<StructDef> = GrowingList<StructDef>();
    var _functions: GrowingList<FunctionDef> = GrowingList<FunctionDef>();
    var _bases_of: GrowingList<FunctionDef> = GrowingList<FunctionDef>();

    construct() {}

    ## Takes in what was added to `module` since.
    update(module: Module) {
        var (structure, fresh_structs) = _structs.since(module.structs);
        if (fresh_structs) {
            structs = HashSet<String>();
        }
        for (var at in structure..module.structs.count) {
            var st = module.structs[at];
            structs.insert(st.name);
            structs.insert(st.ty.to_string());
        }
        var (function, fresh_functions) = _functions.since(module.functions);
        if (fresh_functions) {
            functions = HashSet<String>();
        }
        for (var at in function..module.functions.count) {
            functions.insert(module.functions[at].name);
        }
        var of = module.templates.frozen ? module.templates.functions : module.functions;
        var (base, fresh_bases) = _bases_of.since(of);
        if (fresh_bases) {
            bases = HashMap<String, FunctionDef>();
        }
        for (var at in base..of.count) {
            var f = of[at];
            if (f.is_generic_func and !bases.contains(f.name)) {
                bases[f.name] = f;
            }
        }
    }
}

extend _FunctionSpecsMemo with PassMemo;

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

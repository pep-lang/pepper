## Generic uses recorded as specializations to make.
## Each
## concrete generic type a declaration names (`Array<int>`) becomes a
## struct spec, and each generic call (`max<int>(a, b)`) a function spec,
## or a struct spec when it constructs one; who asked first is kept for
## the depth limit.

import [unit_decls] from "checked";
import [is_closure_struct] from "closures";
import [Loc] from "loc";
import [
    Block,
    Expression,
    ExtensionDef,
    FunctionDef,
    GenericParam,
    Module,
    SpecRequest,
    StructDef,
    TypeFlags,
    TypeName,
    VariableDef
] from "model";
import [concrete_overrides] from "overloads";
import [for_each_place, Place, PlaceVisitor] from "places";
import [GrowingList, PassMemo, PassState] from "state";
import [type_ids] from "type_ids";
import [parse_type_string] from "type_name";
import [Rewriter] from "walk";

## The generic uses found so far, by name: who asked first, and where.
struct _Requests {
    var entries: Map<String, (String, Loc)> = Map<String, (String, Loc)>();

    request(name: String, by: String, loc: Loc) {
        if (!entries.contains(name)) {
            entries[name] = (by, loc);
        }
    }
}

## Where a variable's type is written, else its name.
_written(variable: VariableDef): Loc {
    return variable.type_loc.is_none() ? variable.loc : variable.type_loc;
}

## Whether `ty` names one of `params`, or a member's type in a static
## block (`field.Type`): unbound where it is written.
_contains_param(ty: TypeName, params: String[]): bool {
    if (ty.name.ends_with(".Type")) {
        return true;
    }
    # The names in a type are known once per distinct type (#210).
    var ids = type_ids();
    if (ids.is_value() and ty.sub_types.count > 0) {
        if (ids.value().facts(ty).member_type) {
            return true;
        }
        var names = ids.value().facts(ty).names;
        for (var p in params) {
            if (names.contains(p)) {
                return true;
            }
        }
        return false;
    }
    for (var p in params) {
        if (p == ty.name) {
            return true;
        }
    }
    for (var sub in ty.sub_types) {
        if (_contains_param(sub, params)) {
            return true;
        }
    }
    return false;
}

## Returns the names of `params`, in order.
##
## @param params a declaration's generic parameters
## @returns their names
export param_names(params: GenericParam[]): String[] {
    var out = Array<String>();
    for (var p in params) {
        out.append(p.name);
    }
    return out;
}

## The generic parameters an extension's methods can name: the target
## struct's own, when the extension names the generic base.
_extension_params(structs: StructDef[], ext: ExtensionDef): String[] {
    for (var st in structs) {
        if (st.name != ext.target.name) {
            continue;
        }
        bool extends_base = ext.target.sub_types.count == 0;
        if (!extends_base and st.generic_params.count == ext.target.sub_types.count) {
            extends_base = true;
            ulong i = 0;
            while (i < st.generic_params.count) {
                var arg = ext.target.sub_types[i];
                if (arg.sub_types.count > 0 or arg.name != st.generic_params[i].name) {
                    extends_base = false;
                }
                i += 1;
            }
        }
        return extends_base ? param_names(st.generic_params) : Array<String>();
    }
    return Array<String>();
}

## Whether `ty` is a generic type a declaration can ask for.
_is_requested(ty: TypeName, params: String[]): bool {
    return ty.is_generic() and !ty.name.starts_with("__") and !_contains_param(ty, params);
}

## Records each generic call and generic function value a walk meets.
struct _CallGatherer {
    var functions: _Requests;
    var params: String[];
    var owner: String;
    # Global initializers name no generic parameters to skip.
    var check_params: bool;

    construct(functions: _Requests, params: String[], owner: String, check_params: bool) {
        this.functions = functions;
        this.params = params;
        this.owner = owner;
        this.check_params = check_params;
    }

    rewrite(e: Expression): Expression {
        var function = "";
        var loc = Loc.none();
        match (e) {
            FunctionCall(node) => {
                function = node.function;
                loc = node.loc;
            }
            FunctionRef(node) => {
                function = node.function;
                loc = node.loc;
            }
            else => {
                return e;
            }
        }
        # Intrinsics are not specialized.
        if (function.starts_with("__") and !is_closure_struct(function)) {
            return e;
        }
        if (function.contains("<") and function.ends_with(">")) {
            if (!check_params or !_contains_param(parse_type_string(function), params)) {
                functions.request(function, owner, loc);
            }
        }
        return e;
    }
}

extend _CallGatherer with Rewriter;

## Gathers the calls of each place with the generic parameters it can name.
struct _CallsIn {
    var functions: _Requests;
    var module: Module;
    # The extension whose methods are being walked, and the parameters
    # they can name.
    var _extension: ExtensionDef = ExtensionDef();
    var _extension_names: String[] = Array<String>();

    construct(functions: _Requests, module: Module) {
        this.functions = functions;
        this.module = module;
    }

    visit(place: Place) {
        match (place.kind) {
            Global => {
                var global = place.variable.value();
                if (!module.checked.globals.contains(global.name)) {
                    # Global initializers name no generic parameters to skip.
                    place.rewrite(_CallGatherer(functions, Array<String>(), global.name, false));
                }
            }
            Function => {
                var function = place.function.value();
                place.rewrite(_CallGatherer(functions, param_names(function.generic_params), function.name, true));
            }
            Extension => {
                var ext = place.extension.value();
                # An extension's methods come one after another.
                if (!(_extension === ext)) {
                    _extension = ext;
                    _extension_names = _extension_params(module.structs, ext);
                }
                place.rewrite(_CallGatherer(functions, _extension_names, ext.target.name, true));
            }
            else => {
                var st = place.owner.value();
                place.rewrite(_CallGatherer(functions, param_names(st.generic_params), st.name, true));
            }
        }
    }
}

extend _CallsIn with PlaceVisitor;

## Records the generic types of local declarations, in nested blocks too.
_gather_locals(block: Block, structs: _Requests, params: String[], owner: String) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (_is_requested(variable.ty, params)) {
                        structs.request(variable.ty.to_string(), owner, _written(variable));
                    }
                }
            }
            Block(inner) => {
                _gather_locals(inner, structs, params, owner);
            }
            Branch(branch) => {
                _gather_locals(branch.if_block, structs, params, owner);
                if (branch.else_block.is_value()) {
                    _gather_locals(branch.else_block.value(), structs, params, owner);
                }
            }
            While(loop) => {
                _gather_locals(loop.block, structs, params, owner);
            }
            else => {}
        }
    }
}

## The symbol table `gather_generics` looks requests up in, and the specs
## made, by `_type_key`: kept for the compilation unit's next round
## (`PassState.unit_memos`), which takes in only what was appended since.
## A list a pass replaced is taken in again whole.
struct _GatherMemo {
    var function_index: HashMap<String, ulong> = HashMap<String, ulong>();
    var struct_index: HashMap<String, ulong> = HashMap<String, ulong>();
    var struct_spelled: HashSet<String> = HashSet<String>();
    var func_spelled: HashSet<String> = HashSet<String>();
    var functions: GrowingList<FunctionDef> = GrowingList<FunctionDef>();
    var structs: GrowingList<StructDef> = GrowingList<StructDef>();
    var struct_specs: GrowingList<TypeName> = GrowingList<TypeName>();
    var func_specs: GrowingList<TypeName> = GrowingList<TypeName>();

    construct() {}

    ## Brings the tables up to `module`'s lists: a later declaration of a
    ## name wins.
    update(module: Module) {
        var (function, fresh_functions) = functions.since(module.functions);
        if (fresh_functions) {
            function_index = HashMap<String, ulong>();
        }
        for (var at in function..module.functions.count) {
            function_index[module.functions[at].name] = at;
        }
        var (structure, fresh_structs) = structs.since(module.structs);
        if (fresh_structs) {
            struct_index = HashMap<String, ulong>();
        }
        for (var at in structure..module.structs.count) {
            var st = module.structs[at];
            struct_index[st.name] = at;
            if (st.ty.is_generic()) {
                struct_index[st.ty.to_string()] = at;
            }
        }
        var (struct_spec, fresh_struct_specs) = struct_specs.since(module.struct_specs);
        if (fresh_struct_specs) {
            struct_spelled = HashSet<String>();
        }
        for (var at in struct_spec..module.struct_specs.count) {
            struct_spelled.insert(_type_key(module.struct_specs[at]));
        }
        var (func_spec, fresh_func_specs) = func_specs.since(module.func_specs);
        if (fresh_func_specs) {
            func_spelled = HashSet<String>();
        }
        for (var at in func_spec..module.func_specs.count) {
            func_spelled.insert(_type_key(module.func_specs[at]));
        }
    }
}

extend _GatherMemo with PassMemo;

## Records the module's generic uses as struct and function specs.
##
## @param module the model, changed in place
## @param state the passes' state, which keeps the symbol table for the
##     compilation unit's next round
export gather_generics(module: Module, state: PassState) {
    concrete_overrides(module);
    var kept = state.unit_memos.try_get("gather_generics");
    var memo = kept.is_value() ? (kept.value() as? _GatherMemo).value() : _GatherMemo();
    state.unit_memos["gather_generics"] = memo;
    memo.update(module);
    var function_index = memo.function_index;
    var struct_index = memo.struct_index;
    var functions = _Requests();
    var structs = _Requests();
    # What a checked declaration asks for was made when it was checked:
    # only the compilation unit's own declarations, and the checked structs it
    # extended, ask for anything new.
    var decls = unit_decls(module);
    for (var st in decls.structs) {
        var params = param_names(st.generic_params);
        for (var field in st.field_members) {
            if (_is_requested(field.ty, params)) {
                structs.request(field.ty.to_string(), st.name, _written(field));
            }
        }
        for (var method in st.method_members) {
            if (_is_requested(method.ty, params)) {
                structs.request(method.ty.to_string(), st.name, method.loc);
            }
            for (var p in method.parameters) {
                if (_is_requested(p.ty, params)) {
                    structs.request(p.ty.to_string(), st.name, _written(p));
                }
            }
        }
        # A constructor no one calls is still declared, so its parameter
        # types are uses too (`construct(items: int[])`).
        for (var constructor in st.constructors) {
            for (var p in constructor.parameters) {
                if (_is_requested(p.ty, params)) {
                    structs.request(p.ty.to_string(), st.name, _written(p));
                }
            }
        }
    }
    for (var function in decls.functions) {
        var params = param_names(function.generic_params);
        # A generic function's own parameters (`Array<U>` in `f<U>`) are
        # not a use; its specializations' concrete types are.
        if (_is_requested(function.ty, params)) {
            structs.request(function.ty.to_string(), function.name, function.loc);
        }
        for (var p in function.parameters) {
            if (_is_requested(p.ty, params)) {
                structs.request(p.ty.to_string(), function.name, _written(p));
            }
        }
    }
    for (var global in module.globals) {
        if (module.checked.globals.contains(global.name)) {
            continue;
        }
        if (global.ty.is_generic() and !global.ty.name.starts_with("__")) {
            structs.request(global.ty.to_string(), global.name, _written(global));
        }
    }
    # The calls in every place of code: bodies, parameter defaults and
    # initializers (`var x = Array<int>()` at file scope).
    for_each_place(module, _CallsIn(functions, module), unit = true, fields = false);
    # Local declarations with no constructor call (`Array<int> a;`).
    for (var st in decls.structs) {
        var params = param_names(st.generic_params);
        for (var method in st.method_members) {
            if (method.body.is_value()) {
                _gather_locals(method.body.value(), structs, params, st.name);
            }
        }
        for (var constructor in st.constructors) {
            if (constructor.body.is_value()) {
                _gather_locals(constructor.body.value(), structs, params, st.name);
            }
        }
    }
    for (var function in decls.functions) {
        if (function.body.is_value()) {
            _gather_locals(function.body.value(), structs, param_names(function.generic_params), function.name);
        }
    }
    # Who asked for each, for the depth limit.
    for (var requests in [structs, functions]) {
        for (var (name, (by, loc)) in requests.entries) {
            var key = parse_type_string(name).to_string();
            if (!module.spec_requests.contains(key)) {
                module.spec_requests[key] = SpecRequest(by, loc);
            }
        }
    }
    var struct_specs = module.struct_specs.copy();
    # What the specs spell, which the memo took in from the module's list
    # and this round adds to.
    var struct_spelled = memo.struct_spelled;
    for (var (name, _) in structs.entries) {
        var ty = parse_type_string(name);
        if (struct_spelled.contains(_type_key(ty))) {
            continue;
        }
        var found = struct_index.try_get(ty.name);
        if (found.is_value()) {
            if (module.structs[found.value()].ty == ty) {
                continue;
            }
            struct_specs.append(ty);
            struct_spelled.insert(_type_key(ty));
        }
    }
    module.struct_specs = struct_specs;
    var func_specs = module.func_specs.copy();
    var func_spelled = memo.func_spelled;
    for (var (name, _) in functions.entries) {
        var ty = parse_type_string(name);
        if (func_spelled.contains(_type_key(ty))) {
            continue;
        }
        var st = struct_index.try_get(ty.name);
        if (st.is_value()) {
            if (!(module.structs[st.value()].ty == ty) and !struct_spelled.contains(_type_key(ty))) {
                module.struct_specs.append(ty.copy());
                struct_spelled.insert(_type_key(ty));
            }
            continue;
        }
        var f = function_index.try_get(ty.name);
        if (f.is_value() and module.functions[f.value()].ty == ty) {
            continue;
        }
        func_specs.append(ty);
        func_spelled.insert(_type_key(ty));
    }
    module.func_specs = func_specs;
    # What this round added is in the spellings already.
    memo.struct_specs.since(module.struct_specs);
    memo.func_specs.since(func_specs);
}

# Each of `types` by `_type_key`, to tell whether a type is among them.
_spelled_types(types: TypeName[]): HashSet<String> {
    var out = HashSet<String>();
    for (var t in types) {
        out.insert(_type_key(t));
    }
    return out;
}

# What tells `ty` apart as `==` does: its name, flags and arguments, not
# its labels.
_type_key(ty: TypeName): String {
    var ids = type_ids();
    if (ids.is_value()) {
        return $"#{ids.value().facts(ty).bare}";
    }
    var kind = ty.flags == TypeFlags.Function ? "f" : "s";
    if (ty.sub_types.count == 0) {
        return $"{ty.name}/{kind}";
    }
    var out = StringBuilder();
    out.append($"{ty.name}/{kind}<");
    for (var sub in ty.sub_types) {
        out.append(_type_key(sub));
        out.append(",");
    }
    out.append(">");
    return out.to_string();
}

_has_type(types: TypeName[], ty: TypeName): bool {
    for (var t in types) {
        if (t == ty) {
            return true;
        }
    }
    return false;
}

## Generic functions and methods named as values without type arguments:
## `type_arguments::bind_generic_function_values` and
## `generic_methods::bind_generic_method_values` in Pepper. Where a function
## type is expected, the expected type picks the specialization the value
## names.

import "builder";
import [
    for_each_selected_site, ModuleTables, rewrite_module, SiteFilter, SiteSelection, SiteVisitor
] from "closure_sites";
import [Loc] from "loc";
import [
    Block,
    Declaration,
    Expression,
    FunctionDef,
    FunctionRefExpression,
    MemberRefExpression,
    Module,
    Statement,
    SymbolRefExpression,
    TypeName
] from "model";
import "overload_select";
import "properties";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [GenericSignature, specialization] from "type_arguments";
import [FUNCTION] from "type_name";
import [Rewriter, rewrite_block] from "walk";

## A generic free function: its signature and declared return type.
struct _Generic {
    var signature: GenericSignature;
    var ret: TypeName;

    construct(signature: GenericSignature, ret: TypeName) {
        this.signature = signature;
        this.ret = ret;
    }
}

_is_unbound(e: Expression, generics: HashMap<String, _Generic>): bool {
    if (e is SymbolRef(node)) {
        return (node.ty.is_empty() or node.ty.is_auto()) and generics.contains(node.id);
    }
    return false;
}

struct _UnboundFinder {
    var generics: HashMap<String, _Generic>;

    construct(generics: HashMap<String, _Generic>) {
        this.generics = generics;
    }

    wants(e: Expression): bool {
        return _is_unbound(e, generics);
    }
}

extend _UnboundFinder with SiteFilter;

struct _FunctionValueBinder {
    var generics: HashMap<String, _Generic>;
    var generic_bases: HashSet<String>;
    var shadowed: HashSet<String>;
    var bound: HashMap<String, (String, TypeName)> = HashMap<String, (String, TypeName)>();

    construct(generics: HashMap<String, _Generic>, generic_bases: HashSet<String>, shadowed: HashSet<String>) {
        this.generics = generics;
        this.generic_bases = generic_bases;
        this.shadowed = shadowed;
    }

    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?) {
        if ((owner.is_value() and generic_bases.contains(owner.value())) or !_is_unbound(e, generics)) {
            return;
        }
        if (!(e is SymbolRef(_))) {
            return;
        }
        var node = _symbol(e);
        var key = _named_at(node.id, node.loc);
        if (shadowed.contains(key)) {
            return;
        }
        if (!expected.is_value() or !expected.value().is_callable() or expected.value().contains_auto()) {
            return;
        }
        var generic = generics[node.id];
        var args = generic.signature.infer_from_function_type(generic.ret, expected.value());
        if (!args.is_value()) {
            return;
        }
        var types = Array<TypeName>();
        types.append(generic.ret.copy());
        for (var p in generic.signature.parameter_types) {
            types.append(p.copy());
        }
        var ty = TypeName.with_args(FUNCTION, types);
        ulong i = 0;
        while (i < generic.signature.params.count and i < args.value().count) {
            ty.replace(generic.signature.params[i].name, args.value()[i]);
            i += 1;
        }
        if (ty.contains_auto()) {
            return;
        }
        bound[key] = (specialization(node.id, args.value()), ty);
    }
}

extend _FunctionValueBinder with SiteVisitor;

struct _FunctionValueRewriter {
    var bound: HashMap<String, (String, TypeName)>;

    construct(bound: HashMap<String, (String, TypeName)>) {
        this.bound = bound;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            var found = bound.try_get(_named_at(node.id, node.loc));
            if (found.is_value()) {
                var (function, ty) = found.value();
                return Expression.FunctionRef(FunctionRefExpression(function, ty, node.loc));
            }
        }
        return e;
    }
}

extend _FunctionValueRewriter with Rewriter;

## What `bind_generic_function_values` looks for: the generic functions,
## and the expressions that may name one without type arguments.
export struct GenericFunctionSearch {
    var generics: HashMap<String, _Generic>;
    var filter: SiteFilter;

    construct(generics: HashMap<String, _Generic>) {
        this.generics = generics;
        this.filter = _UnboundFinder(generics);
    }
}

## What `bind_generic_function_values` looks for in `module`, if it has
## generic functions.
##
## @param module the model
## @param state the passes' state
## @returns the search, or none when no function is generic
export generic_function_search(module: Module, state: PassState): GenericFunctionSearch? {
    var generics = HashMap<String, _Generic>();
    for (var f in module.functions) {
        if (f.is_generic_func and !f.name.contains("<")) {
            generics[f.name] = _Generic(GenericSignature(f, state), f.ty);
        }
    }
    if (generics.count == 0) {
        return Optional<GenericFunctionSearch>.Empty;
    }
    return Optional<GenericFunctionSearch>.Value(GenericFunctionSearch(generics));
}

## Names each generic function written without type arguments where a
## function type is expected by the specialization that type picks, as
## `type_arguments::bind_generic_function_values` does.
##
## @param module the model, changed in place
## @param state the passes' state
## @param tables the module's tables, built from it as it is now
## @param search what to look for, found in the module as it is now
## @param sites the code holding a candidate (`search.filter`), with the
##     extensions' own copies of their methods left out
## @returns whether it named any
export bind_generic_function_values(
    module: Module, state: PassState, tables: ModuleTables, search: GenericFunctionSearch, sites: SiteSelection
): bool {
    if (!sites.any()) {
        return false;
    }
    var generics = search.generics;
    var generic_bases = HashSet<String>();
    for (var f in module.functions) {
        if (f.is_generic_func) {
            generic_bases.insert(f.name);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0 and st.name == st.ty.name) {
            generic_bases.insert(st.name);
        }
    }
    var binder = _FunctionValueBinder(generics, generic_bases, _shadowed_names(module, generics));
    for_each_selected_site(tables, sites, binder);
    if (binder.bound.count == 0) {
        return false;
    }
    rewrite_module(module, _FunctionValueRewriter(binder.bound));
    return true;
}

_declared(block: Block, names: Array<String>) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    names.append(variable.name);
                }
            }
            Block(inner) => {
                _declared(inner, names);
            }
            Branch(branch) => {
                _declared(branch.if_block, names);
                if (branch.else_block.is_value()) {
                    _declared(branch.else_block.value(), names);
                }
            }
            While(loop) => {
                _declared(loop.block, names);
            }
            else => {}
        }
    }
}

struct _ShadowFinder {
    var names: HashSet<String>;
    var shadowed: HashSet<String>;

    construct(names: HashSet<String>, shadowed: HashSet<String>) {
        this.names = names;
        this.shadowed = shadowed;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            if (names.contains(node.id)) {
                shadowed.insert(_named_at(node.id, node.loc));
            }
        }
        return e;
    }
}

extend _ShadowFinder with Rewriter;

_shadow_in(function: FunctionDef, fields: String[], generics: HashMap<String, _Generic>, shadowed: HashSet<String>) {
    if (!function.body.is_value()) {
        return;
    }
    var all = Array<String>();
    for (var p in function.parameters) {
        all.append(p.name);
    }
    all.append_all(fields);
    _declared(function.body.value(), all);
    var names = HashSet<String>();
    for (var n in all) {
        if (generics.contains(n)) {
            names.insert(n);
        }
    }
    if (names.count == 0) {
        return;
    }
    rewrite_block(function.body.value(), _ShadowFinder(names, shadowed));
}

## The uses of the generics' names that a parameter, a local or a field of
## the enclosing struct of the same name hides, by name and location.
_shadowed_names(module: Module, generics: HashMap<String, _Generic>): HashSet<String> {
    var shadowed = HashSet<String>();
    for (var function in module.functions) {
        _shadow_in(function, Array<String>(), generics, shadowed);
    }
    for (var st in module.structs) {
        var fields = Array<String>();
        for (var f in st.field_members) {
            fields.append(f.name);
        }
        for (var method in st.method_members) {
            _shadow_in(method, fields, generics, shadowed);
        }
        for (var c in st.constructors) {
            _shadow_in(c, fields, generics, shadowed);
        }
        _shadow_in(st.destructor, fields, generics, shadowed);
    }
    return shadowed;
}

struct _MethodFinder {
    var names: HashSet<String>;

    construct(names: HashSet<String>) {
        this.names = names;
    }

    wants(e: Expression): bool {
        if (e is MemberRef(node)) {
            return names.contains(node.name);
        }
        return false;
    }
}

extend _MethodFinder with SiteFilter;

struct _MethodValueBinder {
    var module: Module;
    var names: HashSet<String>;
    var statics: StructTable;
    var state: PassState;
    var bound: HashMap<String, String> = HashMap<String, String>();

    construct(module: Module, names: HashSet<String>, statics: StructTable, state: PassState) {
        this.module = module;
        this.names = names;
        this.statics = statics;
        this.state = state;
    }

    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?) {
        if (!(e is MemberRef(_))) {
            return;
        }
        var node = _member(e);
        if (!names.contains(node.name)) {
            return;
        }
        if (!expected.is_value() or !expected.value().is_callable() or expected.value().contains_auto()) {
            return;
        }
        var owner_type = static_type_of(node.lhs, statics, current, state);
        if (!owner_type.is_value() or owner_type.value().contains_auto()) {
            return;
        }
        var key = owner_type.value().without_pointers().to_string();
        for (var st in module.structs) {
            if (st.ty.to_string() != key) {
                continue;
            }
            for (var m in st.method_members) {
                if (m.name == node.name) {
                    return;
                }
            }
            for (var base in st.generic_methods) {
                if (base.name != node.name) {
                    continue;
                }
                var signature = GenericSignature(base, state);
                # `Box<int>.map`: the receiver comes first.
                var want = expected.value().copy();
                if (!base.is_static and want.function_params().count == base.parameters.count + 1) {
                    want.sub_types.remove_at(1);
                }
                var args = signature.infer_from_function_type(base.ty, want);
                if (args.is_value()) {
                    bound[_named_at(node.name, node.loc)] = specialization(node.name, args.value());
                }
                return;
            }
            return;
        }
    }
}

extend _MethodValueBinder with SiteVisitor;

struct _MethodValueRewriter {
    var bound: HashMap<String, String>;

    construct(bound: HashMap<String, String>) {
        this.bound = bound;
    }

    rewrite(e: Expression): Expression {
        if (e is MemberRef(node)) {
            var found = bound.try_get(_named_at(node.name, node.loc));
            if (found.is_value()) {
                node.name = found.value();
            }
        }
        return e;
    }
}

extend _MethodValueRewriter with Rewriter;

## What `bind_generic_method_values` looks for: the generic methods' names,
## and the expressions that may name one as a value.
export struct GenericMethodSearch {
    var names: HashSet<String>;
    var filter: SiteFilter;

    construct(names: HashSet<String>) {
        this.names = names;
        this.filter = _MethodFinder(names);
    }
}

## What `bind_generic_method_values` looks for in `module`, if it has
## generic methods.
##
## @param module the model
## @returns the search, or none when no method is generic
export generic_method_search(module: Module): GenericMethodSearch? {
    var names = HashSet<String>();
    for (var st in module.structs) {
        for (var m in st.generic_methods) {
            names.insert(m.name);
        }
    }
    if (names.count == 0) {
        return Optional<GenericMethodSearch>.Empty;
    }
    return Optional<GenericMethodSearch>.Value(GenericMethodSearch(names));
}

## Names each generic method written as a value without type arguments
## where a function type is expected by the specialization that type picks
## (`b.map<long>`), as `generic_methods::bind_generic_method_values` does.
##
## @param module the model, changed in place
## @param state the passes' state
## @param tables the module's tables, built from it as it is now
## @param search what to look for, found in the module as it is now
## @param sites the code holding a candidate (`search.filter`)
## @returns whether it named any
export bind_generic_method_values(
    module: Module, state: PassState, tables: ModuleTables, search: GenericMethodSearch, sites: SiteSelection
): bool {
    if (!sites.any()) {
        return false;
    }
    var names = search.names;
    var binder = _MethodValueBinder(module, names, tables.statics(), state);
    for_each_selected_site(tables, sites, binder);
    if (binder.bound.count == 0) {
        return false;
    }
    rewrite_module(module, _MethodValueRewriter(binder.bound));
    return true;
}

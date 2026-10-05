## Expression sites with the type of the slot each flows into, and keeping
## closure types in step: `pepper_sema::passes::closures`' `sync_closures`,
## `for_each_site`, `for_each_applied_site_in` and
## `for_each_expression_mut` in Pepper.

import [CALL_METHOD, is_closure_struct, THIS_FIELD] from "closures";
import [BinaryOp, Block, Declaration, Expression, FunctionDef, Module, Statement, StructDef, TypeName] from "model";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [zero_for] from "synthesize";
import [GenericSignature] from "type_arguments";
import [FUNCTION, VOID] from "type_name";
import [Rewriter, rewrite_block, rewrite_children, rewrite_expression] from "walk";

## Returns the direct sub-expressions of `e`, in order, as
## `passes::children` lists them.
##
## @param e the expression
## @returns its children
export expression_children(e: Expression): Expression[] {
    var collector = _Collector();
    rewrite_children(e, collector);
    return collector.found;
}

struct _Collector {
    var found: Array<Expression> = Array<Expression>();

    construct() {}

    rewrite(e: Expression): Expression {
        found.append(e);
        return e;
    }
}

extend _Collector with Rewriter;

## Applies `rewriter` to every expression in `module`, as
## `closures::for_each_expression_mut` does: fields' and parameters'
## defaults, bodies, extensions' bodies and globals' initializers.
##
## @param module the model
## @param rewriter what to do at each expression
export rewrite_module(module: Module, rewriter: Rewriter) {
    for (var st in module.structs) {
        for (var field in st.field_members) {
            if (field.default.is_value()) {
                field.default = Optional<Expression>.Value(rewrite_expression(field.default.value(), rewriter));
            }
        }
        for (var method in st.method_members) {
            _rewrite_function(method, rewriter, true);
        }
        for (var c in st.constructors) {
            _rewrite_function(c, rewriter, true);
        }
        _rewrite_function(st.destructor, rewriter, true);
    }
    for (var function in module.functions) {
        _rewrite_function(function, rewriter, true);
    }
    for (var ext in module.extensions) {
        for (var method in ext.methods) {
            _rewrite_function(method, rewriter, false);
        }
    }
    for (var global in module.globals) {
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), rewriter));
        }
    }
}

_rewrite_function(function: FunctionDef, rewriter: Rewriter, defaults: bool) {
    if (defaults) {
        for (var p in function.parameters) {
            if (p.default.is_value()) {
                p.default = Optional<Expression>.Value(rewrite_expression(p.default.value(), rewriter));
            }
        }
    }
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), rewriter);
    }
}

## What a site walk does at each expression.
export trait SiteVisitor {
    ## Visits `e`, which flows into a slot of type `expected` when known,
    ## in code of struct `current` (if any) whose owner is `owner`.
    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?);
}

## Declared types the expected-type walk needs: `closures::Table`.
export struct SiteTable {
    ## Free function or struct constructor name to parameter types.
    var callables: HashMap<String, TypeName[]> = HashMap<String, TypeName[]>();
    ## Struct type to (field name to type).
    var fields: HashMap<String, HashMap<String, TypeName>> = HashMap<String, HashMap<String, TypeName>>();
    ## Struct type to (method name to parameter types).
    var methods: HashMap<String, HashMap<String, TypeName[]>> = HashMap<String, HashMap<String, TypeName[]>>();
    var globals: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Generic free functions, for calls whose type arguments are inferred.
    var generics: HashMap<String, GenericSignature> = HashMap<String, GenericSignature>();
    ## Struct type to generic methods, likewise.
    var generic_methods: HashMap<String, HashMap<String, GenericSignature>> = HashMap<String, HashMap<String, GenericSignature>>();
    var statics: StructTable;
    var state: PassState;

    ## Returns the table of `module`.
    ##
    ## @param module the model
    ## @param state the passes' state
    construct(module: Module, state: PassState, statics: StructTable? = Optional<StructTable>.Empty) {
        this.state = state;
        this.statics = statics.is_value() ? statics.value() : StructTable(module);
        # A generic base's parameter types name its own type parameters;
        # only its specializations give a closure argument its types.
        for (var f in module.functions) {
            if (!f.is_generic_func) {
                callables[f.name] = _parameter_types(f);
            }
        }
        for (var e in module.externs) {
            var types = Array<TypeName>();
            for (var p in e.parameters) {
                types.append(p.ty);
            }
            callables[e.name] = types;
        }
        for (var st in module.structs) {
            if (st.generic_params.count != 0) {
                continue;
            }
            for (var c in st.constructors) {
                callables[c.name] = _parameter_types(c);
            }
            fields[st.ty.to_string()] = _field_types(st);
            var by_name = HashMap<String, TypeName[]>();
            for (var m in st.method_members) {
                by_name[m.name] = _parameter_types(m);
            }
            methods[st.ty.to_string()] = by_name;
        }
        # A generic base's fields, in its own terms: what a closure created
        # in one of its methods captures from `this`.
        for (var st in module.structs) {
            if (st.generic_params.count != 0) {
                fields[st.ty.to_string()] = _field_types(st);
            }
        }
        for (var g in module.globals) {
            globals[g.name] = g.ty;
        }
        for (var f in module.functions) {
            if (f.is_generic_func) {
                generics[f.name] = GenericSignature(f, state);
            }
        }
        for (var st in module.structs) {
            if (st.generic_params.count == 0 and st.generic_methods.count != 0) {
                var by_name = HashMap<String, GenericSignature>();
                for (var m in st.generic_methods) {
                    by_name[m.name] = GenericSignature(m, state);
                }
                generic_methods[st.ty.to_string()] = by_name;
            }
        }
    }

    _field(owner: TypeName, name: String): TypeName? {
        var key = owner.to_string();
        while (key.ends_with("*")) {
            key = key.substr_bytes(0, key.size - 1);
        }
        var found = fields.try_get(key);
        return found.is_value() ? found.value().try_get(name) : Optional<TypeName>.Empty;
    }

    ## A generic call's parameter types, with what its arguments bind.
    generic_parameters(signature: GenericSignature, args: Expression[], current: TypeName?): TypeName[]? {
        var types = Array<TypeName?>();
        for (var arg in args) {
            if (arg is MakeClosure(node)) {
                types.append(Optional<TypeName>.Value(node.ty));
            } else {
                types.append(type_of(arg, current));
            }
        }
        var bindings = signature.bind(types);
        var out = Array<TypeName>();
        ulong i = 0;
        while (i < signature.parameter_types.count) {
            var ty = signature.expected(i, bindings);
            if (!ty.is_value()) {
                return Optional<TypeName[]>.Empty;
            }
            out.append(ty.value());
            i += 1;
        }
        return Optional<TypeName[]>.Value(out);
    }

    ## Returns the static type of `e` in a body of struct `current`, as
    ## well as it can be told.
    type_of(e: Expression, current: TypeName?): TypeName? {
        var ty = Optional<TypeName>.Empty;
        match (e) {
            SymbolRef(node) => {
                if (node.ty.contains_auto()) {
                    if (current.is_value()) {
                        ty = _field(current.value(), node.id);
                    }
                    if (!ty.is_value()) {
                        ty = globals.try_get(node.id);
                    }
                } else {
                    ty = static_type_of(e, statics, current, state);
                }
            }
            MemberRef(node) => {
                var lhs = type_of(node.lhs, current);
                if (lhs.is_value()) {
                    ty = _field(lhs.value(), node.name);
                }
            }
            MakeClosure(node) => {
                ty = Optional<TypeName>.Value(node.ty);
            }
            else => {
                ty = static_type_of(e, statics, current, state);
            }
        }
        if (ty.is_value() and (ty.value().is_empty() or ty.value().contains_auto())) {
            return Optional<TypeName>.Empty;
        }
        return ty;
    }
}

_parameter_types(f: FunctionDef): TypeName[] {
    var out = Array<TypeName>();
    for (var p in f.parameters) {
        out.append(p.ty);
    }
    return out;
}

_field_types(st: StructDef): HashMap<String, TypeName> {
    var out = HashMap<String, TypeName>();
    for (var f in st.field_members) {
        out[f.name] = f.ty;
    }
    return out;
}

## Picks the expressions a limited site walk is for: the walk visits only
## the functions, field defaults and global initializers holding one.
export trait SiteFilter {
    ## Whether the walk is for `e`.
    ##
    ## @param e the expression
    ## @returns whether to visit the code holding it
    wants(e: Expression): bool;
}

## Calls `visitor` at every expression of `module` with the type of the
## slot it flows into when known, as `closures::for_each_site` does.
##
## @param module the model
## @param state the passes' state
## @param visitor what to do at each site
export for_each_site(module: Module, state: PassState, visitor: SiteVisitor) {
    _sites_in_module(
        module, SiteTable(module, state), false, _select(module, false, Optional<SiteFilter>.Empty), visitor
    );
}

## Calls `visitor` at every expression site of `module`, skipping the
## extensions' own copies of their methods, as
## `closures::for_each_applied_site_in` does.
##
## @param module the model
## @param state the passes' state
## @param visitor what to do at each site
export for_each_applied_site(module: Module, state: PassState, visitor: SiteVisitor) {
    _sites_in_module(
        module, SiteTable(module, state), true, _select(module, true, Optional<SiteFilter>.Empty), visitor
    );
}

## The code a limited site walk goes through: each function, field
## default and global initializer holding an expression a filter wants.
export struct SiteSelection {
    ## Per piece of code, in the walk's order: whether to walk it.
    var walk: Array<bool>;
    ## Whether the extensions' own copies of their methods are left out.
    var applied: bool;

    construct(walk: Array<bool>, applied: bool) {
        this.walk = walk;
        this.applied = applied;
    }

    ## Whether any code holds an expression the filter wants.
    ##
    ## @returns whether the walk visits anything
    any(): bool {
        return walk.contains(true);
    }
}

## Selects the code of `module` holding an expression `filter` wants (all
## sites, or with `applied` those of `for_each_applied_site`), so that a
## visitor that acts on nothing else walks only that code, and nothing
## needs building when none does.
##
## @param module the model
## @param filter which expressions the visitor acts on
## @param applied whether to skip the extensions' own copies of their methods
## @returns the code to walk
export select_sites(module: Module, filter: SiteFilter, applied: bool): SiteSelection {
    return SiteSelection(_select(module, applied, Optional<SiteFilter>.Value(filter)), applied);
}

## Calls `visitor` at every expression site of the code `selection` holds,
## as `for_each_site` does in all of it.
##
## @param tables the tables of the model `selection` was made from,
##     unchanged since
## @param selection the code to walk
## @param visitor what to do at each site
export for_each_selected_site(tables: ModuleTables, selection: SiteSelection, visitor: SiteVisitor) {
    if (selection.any()) {
        _sites_in_module(tables.module, tables.sites(), selection.applied, selection.walk, visitor);
    }
}

## The struct and site tables of a module, built when first asked for and
## shared by the passes that run while the module stays as it was: each
## costs a walk over every function.
export struct ModuleTables {
    var module: Module;
    var state: PassState;
    var built_statics: StructTable? = Optional<StructTable>.Empty;
    var built_sites: SiteTable? = Optional<SiteTable>.Empty;
    ## The module's trait types, when the caller found them.
    var trait_types: TypeName[]?;

    ## Tables of `module`, none built yet.
    ##
    ## @param module the model
    ## @param state the passes' state
    ## @param trait_types the module's trait types, when already found
    construct(module: Module, state: PassState, trait_types: TypeName[]? = Optional<TypeName[]>.Empty) {
        this.module = module;
        this.state = state;
        this.trait_types = trait_types;
    }

    ## The module's struct table. Not to be first asked for in the middle
    ## of a walk over the module's code, which building it walks too.
    ##
    ## @returns the table
    statics(): StructTable {
        if (!built_statics.is_value()) {
            built_statics = Optional<StructTable>.Value(StructTable(module, trait_types));
        }
        return built_statics.value();
    }

    ## The module's site table, with its struct table.
    ##
    ## @returns the table
    sites(): SiteTable {
        if (!built_sites.is_value()) {
            built_sites = Optional<SiteTable>.Value(SiteTable(module, state, Optional<StructTable>.Value(statics())));
        }
        return built_sites.value();
    }

    ## Drops the tables, after a pass changed the module, which may use
    ## other trait types now.
    ##
    ## @param trait_types the module's trait types, when already found again
    reset(trait_types: TypeName[]? = Optional<TypeName[]>.Empty) {
        this.trait_types = trait_types;
        built_statics = Optional<StructTable>.Empty;
        built_sites = Optional<SiteTable>.Empty;
    }
}

## Whether `e`, or an expression inside it, is one `filter` wants.
_holds(e: Expression, filter: SiteFilter): bool {
    var holder = _Holder(filter);
    holder.rewrite(e);
    return holder.found;
}

## Looks through an expression for one its filter wants, and stops at the
## first.
struct _Holder {
    var filter: SiteFilter;
    var found: bool = false;

    construct(filter: SiteFilter) {
        this.filter = filter;
    }

    rewrite(e: Expression): Expression {
        if (!found) {
            if (filter.wants(e)) {
                found = true;
            } else {
                rewrite_children(e, this);
            }
        }
        return e;
    }
}

extend _Holder with Rewriter;

_block_holds(block: Block, filter: SiteFilter): bool {
    for (var statement in block.items) {
        match (statement) {
            Expression(e) => {
                if (_holds(e, filter)) {
                    return true;
                }
            }
            Block(inner) => {
                if (_block_holds(inner, filter)) {
                    return true;
                }
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.default.is_value() and _holds(variable.default.value(), filter)) {
                        return true;
                    }
                }
            }
            Branch(branch) => {
                if (_holds(branch.condition, filter) or _block_holds(branch.if_block, filter)) {
                    return true;
                }
                if (branch.else_block.is_value() and _block_holds(branch.else_block.value(), filter)) {
                    return true;
                }
            }
            While(loop) => {
                if (_holds(loop.condition, filter) or _block_holds(loop.block, filter)) {
                    return true;
                }
            }
            Return(r) => {
                if (r.expr.is_value() and _holds(r.expr.value(), filter)) {
                    return true;
                }
            }
            else => {}
        }
    }
    return false;
}

_function_holds(function: FunctionDef, filter: SiteFilter): bool {
    for (var p in function.parameters) {
        if (p.default.is_value() and _holds(p.default.value(), filter)) {
            return true;
        }
    }
    return function.body.is_value() and _block_holds(function.body.value(), filter);
}

## Wants the creations of a set of closures.
struct _CreatesClosure {
    var closures: HashSet<String>;

    construct(closures: HashSet<String>) {
        this.closures = closures;
    }

    wants(e: Expression): bool {
        if (e is MakeClosure(node)) {
            return closures.contains(node.closure);
        }
        return false;
    }
}

extend _CreatesClosure with SiteFilter;

## A visitor that passes its owner along.
struct _Owned {
    var owner: String?;
    var visitor: SiteVisitor;

    construct(owner: String?, visitor: SiteVisitor) {
        this.owner = owner;
        this.visitor = visitor;
    }

    visit(e: Expression, expected: TypeName?, current: TypeName?) {
        visitor.visit(owner, e, expected, current);
    }
}

## Which code of `module` a walk goes through, in the walk's order (the
## extensions' own copies of their methods left out when `applied`): all
## of it, or only the code holding an expression `filter` wants.
_select(module: Module, applied: bool, filter: SiteFilter?): Array<bool> {
    var walk = Array<bool>();
    for (var st in module.structs) {
        for (var field in st.field_members) {
            walk.append(
                field.default.is_value() and (!filter.is_value() or _holds(field.default.value(), filter.value()))
            );
        }
        for (var method in st.method_members) {
            walk.append(!filter.is_value() or _function_holds(method, filter.value()));
        }
        for (var c in st.constructors) {
            walk.append(!filter.is_value() or _function_holds(c, filter.value()));
        }
        walk.append(!filter.is_value() or _function_holds(st.destructor, filter.value()));
    }
    for (var function in module.functions) {
        walk.append(!filter.is_value() or _function_holds(function, filter.value()));
    }
    if (!applied) {
        for (var ext in module.extensions) {
            for (var method in ext.methods) {
                walk.append(!filter.is_value() or _function_holds(method, filter.value()));
            }
        }
    }
    for (var global in module.globals) {
        walk.append(
            global.default.is_value() and (!filter.is_value() or _holds(global.default.value(), filter.value()))
        );
    }
    return walk;
}

## Walks the sites of the code of `module` that `walk` picks, as `_select`
## ordered it.
_sites_in_module(module: Module, table: SiteTable, applied: bool, walk: Array<bool>, visitor: SiteVisitor) {
    ulong at = 0;
    for (var st in module.structs) {
        var current = Optional<TypeName>.Value(st.ty);
        var owned = _Owned(Optional<String>.Value(st.name), visitor);
        for (var field in st.field_members) {
            if (walk[at]) {
                _sites_in_expression(field.default.value(), Optional<TypeName>.Value(field.ty), table, current, owned);
            }
            at += 1;
        }
        var functions = Array<FunctionDef>();
        functions.append_all(st.method_members);
        functions.append_all(st.constructors);
        functions.append(st.destructor);
        for (var method in functions) {
            if (walk[at]) {
                _sites_in_function(method, table, current, owned);
            }
            at += 1;
        }
    }
    for (var function in module.functions) {
        if (walk[at]) {
            _sites_in_function(
                function, table, Optional<TypeName>.Empty, _Owned(Optional<String>.Value(function.name), visitor)
            );
        }
        at += 1;
    }
    if (!applied) {
        for (var ext in module.extensions) {
            for (var method in ext.methods) {
                if (walk[at]) {
                    _sites_in_function(
                        method,
                        table,
                        Optional<TypeName>.Value(ext.target),
                        _Owned(Optional<String>.Value(ext.target.name), visitor)
                    );
                }
                at += 1;
            }
        }
    }
    for (var global in module.globals) {
        if (walk[at]) {
            _sites_in_expression(
                global.default.value(),
                Optional<TypeName>.Value(global.ty),
                table,
                Optional<TypeName>.Empty,
                _Owned(Optional<String>.Empty, visitor)
            );
        }
        at += 1;
    }
}

_sites_in_function(function: FunctionDef, table: SiteTable, current: TypeName?, visitor: _Owned) {
    for (var p in function.parameters) {
        if (p.default.is_value()) {
            _sites_in_expression(p.default.value(), Optional<TypeName>.Value(p.ty), table, current, visitor);
        }
    }
    if (function.body.is_value()) {
        _sites_in_block(function.body.value(), function.ty, table, current, visitor);
    }
}

_sites_in_block(block: Block, ret: TypeName, table: SiteTable, current: TypeName?, visitor: _Owned) {
    var none = Optional<TypeName>.Empty;
    for (var statement in block.items) {
        match (statement) {
            Expression(e) => {
                _sites_in_expression(e, none, table, current, visitor);
            }
            Block(inner) => {
                _sites_in_block(inner, ret, table, current, visitor);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.default.is_value()) {
                        _sites_in_expression(
                            variable.default.value(), Optional<TypeName>.Value(variable.ty), table, current, visitor
                        );
                    }
                }
            }
            Branch(branch) => {
                _sites_in_expression(branch.condition, none, table, current, visitor);
                _sites_in_block(branch.if_block, ret, table, current, visitor);
                if (branch.else_block.is_value()) {
                    _sites_in_block(branch.else_block.value(), ret, table, current, visitor);
                }
            }
            While(loop) => {
                _sites_in_expression(loop.condition, none, table, current, visitor);
                _sites_in_block(loop.block, ret, table, current, visitor);
            }
            Return(r) => {
                if (r.expr.is_value()) {
                    _sites_in_expression(r.expr.value(), Optional<TypeName>.Value(ret), table, current, visitor);
                }
            }
            else => {}
        }
    }
}

_slot(params: TypeName[]?, index: ulong): TypeName? {
    if (params.is_value() and index < params.value().count) {
        return Optional<TypeName>.Value(params.value()[index]);
    }
    return Optional<TypeName>.Empty;
}

## Visits `e`, which flows into a slot of type `expected` when known, and
## every expression inside it.
_sites_in_expression(e: Expression, expected: TypeName?, table: SiteTable, current: TypeName?, visitor: _Owned) {
    # A function type may be partly known: its known parts still type the
    # closure.
    var known = Optional<TypeName>.Empty;
    if (expected.is_value() and (!expected.value().contains_auto() or expected.value().is_function_type())) {
        known = expected;
    }
    visitor.visit(e, known, current);
    var none = Optional<TypeName>.Empty;
    match (e) {
        FunctionCall(node) => {
            var params = table.callables.try_get(node.function);
            if (!params.is_value()) {
                var signature = table.generics.try_get(node.function);
                if (signature.is_value()) {
                    params = table.generic_parameters(signature.value(), node.args, current);
                }
            }
            ulong i = 0;
            while (i < node.args.count) {
                _sites_in_expression(node.args[i], _slot(params, i), table, current, visitor);
                i += 1;
            }
        }
        MethodCall(node) => {
            var params = Optional<TypeName[]>.Empty;
            var receiver = table.type_of(node.this_value, current);
            if (receiver.is_value()) {
                var owner = receiver.value().to_string();
                var by_name = table.methods.try_get(owner);
                if (by_name.is_value()) {
                    params = by_name.value().try_get(node.method);
                }
                if (!params.is_value()) {
                    var generic = table.generic_methods.try_get(owner);
                    if (generic.is_value()) {
                        var signature = generic.value().try_get(node.method);
                        if (signature.is_value()) {
                            params = table.generic_parameters(signature.value(), node.args, current);
                        }
                    }
                }
            }
            _sites_in_expression(node.this_value, none, table, current, visitor);
            ulong i = 0;
            while (i < node.args.count) {
                _sites_in_expression(node.args[i], _slot(params, i), table, current, visitor);
                i += 1;
            }
        }
        Invoke(node) => {
            var params = Optional<TypeName[]>.Empty;
            var callee = table.type_of(node.callee, current);
            if (callee.is_value()) {
                params = Optional<TypeName[]>.Value(callee.value().function_params());
            }
            _sites_in_expression(node.callee, none, table, current, visitor);
            ulong i = 0;
            while (i < node.args.count) {
                _sites_in_expression(node.args[i], _slot(params, i), table, current, visitor);
                i += 1;
            }
        }
        Binary(node) => {
            if (node.op == BinaryOp.Assign) {
                _sites_in_expression(node.lhs, none, table, current, visitor);
                _sites_in_expression(node.rhs, table.type_of(node.lhs, current), table, current, visitor);
            } else {
                _sites_in_expression(node.lhs, none, table, current, visitor);
                _sites_in_expression(node.rhs, none, table, current, visitor);
            }
        }
        Ternary(node) => {
            _sites_in_expression(node.condition, none, table, current, visitor);
            _sites_in_expression(node.true_expr, expected, table, current, visitor);
            _sites_in_expression(node.false_expr, expected, table, current, visitor);
        }
        WithSubject(scoped) => {
            _sites_in_expression(scoped.subject, none, table, current, visitor);
            _sites_in_expression(scoped.body, expected, table, current, visitor);
        }
        else => {
            for (var child in expression_children(e)) {
                _sites_in_expression(child, none, table, current, visitor);
            }
        }
    }
}

## What a closure's creations teach about its types.
struct _Learned {
    ## The function type of the slot a creation flows into.
    var expected: TypeName? = Optional<TypeName>.Empty;
    ## Types of the constructor arguments (the captured values).
    var captures: Array<TypeName?> = Array<TypeName?>();

    construct() {}
}

## Learns closure types at each site creating one.
struct _Learner {
    var table: SiteTable;
    var learned: HashMap<String, _Learned> = HashMap<String, _Learned>();

    construct(table: SiteTable) {
        this.table = table;
    }

    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?) {
        if (!(e is MakeClosure(_))) {
            return;
        }
        var node = _make_closure(e);
        if (!learned.contains(node.closure)) {
            learned[node.closure] = _Learned();
        }
        var entry = learned[node.closure];
        # A C function pointer slot types a closure like the plain function
        # type of its signature.
        var slot = Optional<TypeName>.Empty;
        if (expected.is_value()) {
            var t = expected.value();
            if (t.is_function_type()) {
                slot = expected;
            } else if (t.is_extern_function_type()) {
                slot = Optional<TypeName>.Value(TypeName.with_args(FUNCTION, t.sub_types));
            }
        }
        if (slot.is_value()) {
            # A fully known type wins over a partly known one.
            if (!entry.expected.is_value()
                or (entry.expected.value().contains_auto() and !slot.value().contains_auto())) {
                entry.expected = slot;
            }
        }
        if (node.value is FunctionCall(call)) {
            while (entry.captures.count < call.args.count) {
                entry.captures.append(Optional<TypeName>.Empty);
            }
            ulong i = 0;
            while (i < call.args.count) {
                if (!entry.captures[i].is_value()) {
                    var ty = table.type_of(call.args[i], current);
                    if (ty.is_value() and !ty.value().contains_auto()) {
                        entry.captures[i] = ty;
                    }
                }
                i += 1;
            }
        }
    }
}

extend _Learner with SiteVisitor;

_make_closure(e: Expression): MakeClosureExpression {
    if (e is MakeClosure(node)) {
        return node;
    }
    return MakeClosureExpression(Expression.ThisRef);
}

## The capture fields of closure struct `st`, after `__invoke` and
## `__destroy`, in order.
_capture_fields(st: StructDef): ulong[] {
    var out = Array<ulong>();
    ulong i = 0;
    while (i < st.field_members.count) {
        var name = st.field_members[i].name;
        if (!name.starts_with("__") or name == THIS_FIELD) {
            out.append(i);
        }
        i += 1;
    }
    return out;
}

_call_method(st: StructDef): FunctionDef? {
    for (var m in st.method_members) {
        if (m.name == CALL_METHOD) {
            return Optional<FunctionDef>.Value(m);
        }
    }
    return Optional<FunctionDef>.Empty;
}

## Whether closure struct `st` has a type `_apply_learned` could fill.
_has_unknown_types(st: StructDef): bool {
    for (var i in _capture_fields(st)) {
        if (st.field_members[i].ty.contains_auto()) {
            return true;
        }
    }
    var call = _call_method(st);
    if (!call.is_value()) {
        return false;
    }
    if (call.value().ty.is_auto()) {
        return true;
    }
    for (var p in call.value().parameters) {
        if (p.ty.contains_auto()) {
            return true;
        }
    }
    return false;
}

## Gives closure struct `st` the types `learned` found for it.
_apply_learned(st: StructDef, learned: _Learned, state: PassState): bool {
    bool changed = false;
    var fields = _capture_fields(st);
    ulong k = 0;
    while (k < fields.count) {
        var field = st.field_members[fields[k]];
        if (!field.ty.contains_auto() or k >= learned.captures.count or !learned.captures[k].is_value()) {
            k += 1;
            continue;
        }
        var ty = learned.captures[k].value();
        field.ty = ty;
        var init = $"__init_{field.name}";
        for (var c in st.constructors) {
            for (var p in c.parameters) {
                if (p.name == init) {
                    p.ty = ty;
                }
            }
        }
        # The constructor zero-initializes every field first; the zero was
        # chosen while the type was unknown.
        for (var c in st.constructors) {
            if (!c.body.is_value()) {
                continue;
            }
            for (var statement in c.body.value().items) {
                if (statement is Expression(e)) {
                    if (e is Binary(node)) {
                        if (node.op == BinaryOp.Assign and _zeroes_field(node.lhs, field.name) and _is_zero(node.rhs)) {
                            node.rhs = zero_for(state, ty);
                        }
                    }
                }
            }
        }
        changed = true;
        k += 1;
    }
    if (!learned.expected.is_value()) {
        return changed;
    }
    var call = _call_method(st);
    if (!call.is_value()) {
        return changed;
    }
    var expected = learned.expected.value();
    var params = expected.function_params();
    var method = call.value();
    if (params.count == method.parameters.count) {
        ulong i = 0;
        while (i < params.count) {
            if (method.parameters[i].ty.contains_auto() and !params[i].contains_auto()) {
                method.parameters[i].ty = params[i];
                changed = true;
            }
            i += 1;
        }
    }
    var ret = expected.function_return();
    if (ret.is_value() and method.ty.is_auto() and !ret.value().contains_auto()) {
        method.ty = ret.value();
        changed = true;
    }
    return changed;
}

_zeroes_field(lhs: Expression, name: String): bool {
    if (lhs is MemberRef(member)) {
        return member.lhs is ThisRef and member.name == name;
    }
    return false;
}

_is_zero(e: Expression): bool {
    match (e) {
        IntLiteral(value) => {
            return value == 0;
        }
        FloatLiteral(_) => {
            return true;
        }
        PointerLiteral => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Keeps each `MakeClosure`'s function type in step with its closure's
## `__call`.
struct _Signatures {
    var signatures: HashMap<String, TypeName>;
    var changed: bool = false;

    construct(signatures: HashMap<String, TypeName>) {
        this.signatures = signatures;
    }

    rewrite(e: Expression): Expression {
        if (e is MakeClosure(node)) {
            var signature = signatures.try_get(node.closure);
            if (signature.is_value() and !(node.ty == signature.value())) {
                node.ty = signature.value();
                changed = true;
            }
        }
        return e;
    }
}

extend _Signatures with Rewriter;

## Fills in closure types the literals left out, and keeps each
## `MakeClosure`'s function type in step with its `__call`, as
## `closures::sync_closures` does.
##
## @param module the model, changed in place
## @param state the passes' state
## @returns whether anything changed
export sync_closures(module: Module, state: PassState): bool {
    bool any = false;
    for (var st in module.structs) {
        if (is_closure_struct(st.name)) {
            any = true;
        }
    }
    if (!any) {
        return false;
    }
    # Only functions creating a closure with an unknown type have anything
    # to teach.
    var unknown = HashSet<String>();
    for (var st in module.structs) {
        if (is_closure_struct(st.name) and _has_unknown_types(st)) {
            unknown.insert(st.ty.to_string());
            unknown.insert(st.name);
        }
    }
    var learned = HashMap<String, _Learned>();
    if (unknown.count > 0) {
        var creating = select_sites(module, _CreatesClosure(unknown), false);
        if (creating.any()) {
            var learner = _Learner(SiteTable(module, state));
            _sites_in_module(module, learner.table, false, creating.walk, learner);
            learned = learner.learned;
        }
    }
    bool changed = false;
    for (var st in module.structs) {
        if (!is_closure_struct(st.name)) {
            continue;
        }
        var found = learned.try_get(st.ty.to_string());
        if (!found.is_value()) {
            found = learned.try_get(st.name);
        }
        if (found.is_value() and _apply_learned(st, found.value(), state)) {
            changed = true;
        }
        # An expression body of a closure that returns nothing is a
        # statement, not a returned value.
        var call = _call_method(st);
        if (call.is_value() and call.value().ty.to_string() == VOID and call.value().body.is_value()) {
            var body = call.value().body.value();
            if (body.items.count == 1) {
                if (body.items[0] is Return(r)) {
                    if (r.expr.is_value()) {
                        body.items[0] = Statement.Expression(r.expr.value());
                        changed = true;
                    }
                }
            }
        }
    }
    # Each creation's function type follows its closure's `__call`.
    var signatures = HashMap<String, TypeName>();
    for (var st in module.structs) {
        if (!is_closure_struct(st.name)) {
            continue;
        }
        var call = _call_method(st);
        if (call.is_value()) {
            var types = Array<TypeName>();
            types.append(call.value().ty);
            types.append_all(_parameter_types(call.value()));
            signatures[st.ty.to_string()] = TypeName.with_args(FUNCTION, types);
        }
    }
    var keeper = _Signatures(signatures);
    rewrite_module(module, keeper);
    return changed or keeper.changed;
}

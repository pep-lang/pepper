## Expression sites with the type of the slot each flows into, and keeping
## closure types in step: `sync_closures`, `for_each_site`,
## `for_each_applied_site` and `rewrite_module`.

import [checked_decls, unit_decls] from "checked";
import [CALL_METHOD, is_closure_struct, THIS_FIELD] from "closures";
import [is_trait] from "enums";
import [BinaryOp, Block, Declaration, Expression, FunctionDef, Module, Statement, StructDef, TypeName] from "model";
import [CheckedDecls] from "pending";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [zero_for] from "synthesize";
import [GenericSignature] from "type_arguments";
import [FUNCTION, VOID] from "type_name";
import [Rewriter, rewrite_block, rewrite_children, rewrite_expression] from "walk";

## Returns the direct sub-expressions of `e`, in order, as
## `rewrite_children` visits them.
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

## Applies `rewriter` to every expression in `module`: fields' and parameters'
## defaults, bodies, extensions' bodies and globals' initializers.
##
## @param module the model
## @param rewriter what to do at each expression
export rewrite_module(module: Module, rewriter: Rewriter) {
    var decls = unit_decls(module);
    for (var st in decls.structs) {
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
    for (var function in decls.functions) {
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

## Applies `rewriter` to the expressions of the code `walk` picks, in
## `_select_each`'s order over all of `module`, as `rewrite_module` does to
## all of it.
_rewrite_selected(module: Module, walk: Array<bool>, rewriter: Rewriter) {
    var decls = unit_decls(module);
    ulong at = 0;
    for (var st in decls.structs) {
        for (var field in st.field_members) {
            if (walk[at]) {
                field.default = Optional<Expression>.Value(rewrite_expression(field.default.value(), rewriter));
            }
            at += 1;
        }
        for (var method in st.method_members) {
            if (walk[at]) {
                _rewrite_function(method, rewriter, true);
            }
            at += 1;
        }
        for (var c in st.constructors) {
            if (walk[at]) {
                _rewrite_function(c, rewriter, true);
            }
            at += 1;
        }
        if (walk[at]) {
            _rewrite_function(st.destructor, rewriter, true);
        }
        at += 1;
    }
    for (var function in decls.functions) {
        if (walk[at]) {
            _rewrite_function(function, rewriter, true);
        }
        at += 1;
    }
    for (var ext in module.extensions) {
        for (var method in ext.methods) {
            if (walk[at]) {
                _rewrite_function(method, rewriter, false);
            }
            at += 1;
        }
    }
    for (var global in module.globals) {
        if (walk[at]) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), rewriter));
        }
        at += 1;
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

## Declared types the expected-type walk needs. The compilation unit's own
## declarations are taken in when it is built; a checked one is looked up when
## the walk first names it (`CheckedDecls`).
export struct SiteTable {
    ## Free function or struct constructor name to parameter types: the
    ## compilation unit's functions, then the externs, then its constructors,
    ## each kind over the one before; and the checked ones found so far.
    var _functions: HashMap<String, TypeName[]> = HashMap<String, TypeName[]>();
    var _externs: HashMap<String, TypeName[]> = HashMap<String, TypeName[]>();
    var _constructors: HashMap<String, TypeName[]> = HashMap<String, TypeName[]>();
    var _checked_callables: HashMap<String, TypeName[]?> = HashMap<String, TypeName[]?>();
    ## Struct type to (field name to type).
    var _fields: HashMap<String, HashMap<String, TypeName>> = HashMap<String, HashMap<String, TypeName>>();
    ## Struct type to (method name to parameter types).
    var _methods: HashMap<String, HashMap<String, TypeName[]>> = HashMap<String, HashMap<String, TypeName[]>>();
    var _globals: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Generic free functions, for calls whose type arguments are inferred.
    var _generics: HashMap<String, GenericSignature> = HashMap<String, GenericSignature>();
    ## Struct type to generic methods, likewise.
    var _generic_methods: HashMap<String, HashMap<String, GenericSignature>> = HashMap<String, HashMap<String, GenericSignature>>();
    # The struct types whose checked entries `_checked_struct` took in.
    var _checked_structs: HashSet<String> = HashSet<String>();
    var _checked: CheckedDecls;
    var statics: StructTable;
    var state: PassState;

    ## Returns the table of `module`.
    ##
    ## @param module the model
    ## @param state the passes' state
    construct(module: Module, state: PassState, statics: StructTable? = Optional<StructTable>.Empty) {
        this.state = state;
        this.statics = statics.is_value() ? statics.value() : StructTable(module, memo = state.trait_types_memo());
        _checked = checked_decls(module, state);
        var decls = unit_decls(module);
        # A generic base's parameter types name its own type parameters;
        # only its specializations give a closure argument its types.
        for (var f in decls.functions) {
            if (!f.is_generic_func) {
                _functions[f.name] = _parameter_types(f);
            }
        }
        for (var e in module.externs) {
            var types = Array<TypeName>();
            for (var p in e.parameters) {
                types.append(p.ty);
            }
            _externs[e.name] = types;
        }
        for (var st in decls.structs) {
            if (st.generic_params.count != 0) {
                continue;
            }
            for (var c in st.constructors) {
                _constructors[c.name] = _parameter_types(c);
            }
            _add_struct(st);
        }
        # A generic base's fields, in its own terms: what a closure created
        # in one of its methods captures from `this`.
        for (var st in decls.structs) {
            if (st.generic_params.count != 0) {
                _fields[st.ty.to_string()] = _field_types(st);
            }
        }
        for (var g in module.globals) {
            if (!module.checked.globals.contains(g.name)) {
                _globals[g.name] = g.ty;
            }
        }
        for (var f in decls.functions) {
            if (f.is_generic_func) {
                _generics[f.name] = GenericSignature(f, state);
            }
        }
    }

    # Takes in struct `st`, not a generic base: its fields, methods and
    # generic methods.
    _add_struct(st: StructDef) {
        var key = st.ty.to_string();
        _fields[key] = _field_types(st);
        var by_name = HashMap<String, TypeName[]>();
        for (var m in st.method_members) {
            by_name[m.name] = _parameter_types(m);
        }
        _methods[key] = by_name;
        if (st.generic_methods.count != 0) {
            var generic = HashMap<String, GenericSignature>();
            for (var m in st.generic_methods) {
                generic[m.name] = GenericSignature(m, state);
            }
            _generic_methods[key] = generic;
        }
    }

    # Takes in the checked struct of type `key`, once, unless the compilation
    # unit's own entry for it stands.
    _checked_struct(key: String) {
        if (_fields.contains(key) or !_checked_structs.insert(key)) {
            return;
        }
        var st = _checked.structs.try_get(key);
        if (!st.is_value()) {
            return;
        }
        if (st.value().generic_params.count != 0) {
            _fields[key] = _field_types(st.value());
        } else {
            _add_struct(st.value());
        }
    }

    ## The parameter types of the free function or constructor a call
    ## names, if any.
    ##
    ## @param name the name the call gives it
    ## @returns the parameter types
    callable(name: String): TypeName[]? {
        var own = _constructors.try_get(name);
        if (own.is_value()) {
            return own;
        }
        var checked = _checked_callables.try_get(name);
        if (!checked.is_value()) {
            var found = Optional<TypeName[]>.Empty;
            var c = _checked.constructors.try_get(name);
            if (c.is_value()) {
                found = Optional<TypeName[]>.Value(_parameter_types(c.value()));
            }
            _checked_callables[name] = found;
            checked = Optional<TypeName[]?>.Value(found);
        }
        if (checked.value().is_value()) {
            return checked.value();
        }
        var external = _externs.try_get(name);
        if (external.is_value()) {
            return external;
        }
        var function = _functions.try_get(name);
        if (function.is_value()) {
            return function;
        }
        var f = _checked.functions.try_get(name);
        if (f.is_value()) {
            var types = _parameter_types(f.value());
            _functions[name] = types;
            return Optional<TypeName[]>.Value(types);
        }
        return Optional<TypeName[]>.Empty;
    }

    ## The generic free function a call names, if any.
    ##
    ## @param name the function's name
    ## @returns its signature
    generic(name: String): GenericSignature? {
        var found = _generics.try_get(name);
        if (found.is_value()) {
            return found;
        }
        var f = _checked.generic_functions.try_get(name);
        if (!f.is_value()) {
            return Optional<GenericSignature>.Empty;
        }
        var signature = GenericSignature(f.value(), state);
        _generics[name] = signature;
        return Optional<GenericSignature>.Value(signature);
    }

    ## The parameter types of method `name` of struct type `owner`, if any.
    ##
    ## @param owner the struct's type
    ## @param name the method's name
    ## @returns the parameter types
    method(owner: String, name: String): TypeName[]? {
        _checked_struct(owner);
        var by_name = _methods.try_get(owner);
        return by_name.is_value() ? by_name.value().try_get(name) : Optional<TypeName[]>.Empty;
    }

    ## Generic method `name` of struct type `owner`, if any.
    ##
    ## @param owner the struct's type
    ## @param name the method's name
    ## @returns its signature
    generic_method(owner: String, name: String): GenericSignature? {
        _checked_struct(owner);
        var by_name = _generic_methods.try_get(owner);
        return by_name.is_value() ? by_name.value().try_get(name) : Optional<GenericSignature>.Empty;
    }

    ## The type of global `name`, if any.
    ##
    ## @param name the global's name
    ## @returns its type
    global(name: String): TypeName? {
        var own = _globals.try_get(name);
        return own.is_value() ? own : _checked.globals.try_get(name);
    }

    _field(owner: TypeName, name: String): TypeName? {
        var key = owner.without_pointers().to_string();
        _checked_struct(key);
        var found = _fields.try_get(key);
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
                        ty = global(node.id);
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
## slot it flows into when known.
##
## @param module the model
## @param state the passes' state
## @param visitor what to do at each site
export for_each_site(module: Module, state: PassState, visitor: SiteVisitor) {
    _sites_in_module(module, SiteTable(module, state), false, _select_all(module, false), visitor);
}

## Calls `visitor` at every expression site of `module`, skipping the
## extensions' own copies of their methods.
##
## @param module the model
## @param state the passes' state
## @param visitor what to do at each site
export for_each_applied_site(module: Module, state: PassState, visitor: SiteVisitor) {
    _sites_in_module(module, SiteTable(module, state), true, _select_all(module, true), visitor);
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
    var filters = Array<SiteFilter>();
    filters.append(filter);
    var applies = Array<bool>();
    applies.append(applied);
    return SiteSelection(_select_each(module, filters, applies)[0], applied);
}

## Selects the code of `module` for each of `filters`, as `select_sites`
## does, in one walk for all of them.
##
## @param module the model
## @param filters which expressions each visitor acts on
## @param applied per filter, whether to skip the extensions' own copies of
##     their methods
## @returns the code to walk, per filter
export select_sites_each(module: Module, filters: Array<SiteFilter>, applied: Array<bool>): Array<SiteSelection> {
    var walks = _select_each(module, filters, applied);
    var selections = Array<SiteSelection>();
    for (var i in 0..filters.count) {
        selections.append(SiteSelection(walks[i], applied[i]));
    }
    return selections;
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
            built_statics = Optional<StructTable>.Value(StructTable(module, trait_types, state.trait_types_memo()));
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

## Looks through code for the expressions its filters want, one walk for
## all of them, and stops once each has found one.
struct _Holder {
    var filters: Array<SiteFilter>;
    ## Per filter: whether the code looked through holds one it wants.
    var found: Array<bool> = Array<bool>();
    ## How many filters have found none yet.
    var missing: ulong = 0;

    construct(filters: Array<SiteFilter>) {
        this.filters = filters;
    }

    ## Starts over on new code, none found.
    clear() {
        if (found.count != filters.count) {
            found = Array<bool>();
            for (var filter in filters) {
                found.append(false);
            }
        } else {
            for (var i in 0..found.count) {
                found[i] = false;
            }
        }
        missing = filters.count;
    }

    ## Looks through `e`.
    ##
    ## @returns whether every filter has found one
    holds(e: Expression): bool {
        rewrite(e);
        return missing == 0;
    }

    rewrite(e: Expression): Expression {
        if (missing == 0) {
            return e;
        }
        for (var i in 0..filters.count) {
            if (!found[i] and filters[i].wants(e)) {
                found[i] = true;
                missing -= 1;
            }
        }
        if (missing > 0) {
            rewrite_children(e, this);
        }
        return e;
    }
}

extend _Holder with Rewriter;

_block_holds(block: Block, holder: _Holder): bool {
    for (var statement in block.items) {
        match (statement) {
            Expression(e) => {
                if (holder.holds(e)) {
                    return true;
                }
            }
            Block(inner) => {
                if (_block_holds(inner, holder)) {
                    return true;
                }
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.default.is_value() and holder.holds(variable.default.value())) {
                        return true;
                    }
                }
            }
            Branch(branch) => {
                if (holder.holds(branch.condition) or _block_holds(branch.if_block, holder)) {
                    return true;
                }
                if (branch.else_block.is_value() and _block_holds(branch.else_block.value(), holder)) {
                    return true;
                }
            }
            While(loop) => {
                if (holder.holds(loop.condition) or _block_holds(loop.block, holder)) {
                    return true;
                }
            }
            Return(r) => {
                if (r.expr.is_value() and holder.holds(r.expr.value())) {
                    return true;
                }
            }
            else => {}
        }
    }
    return false;
}

## Looks through `function` with `holder`, which holds the result.
_look_through_function(function: FunctionDef, holder: _Holder) {
    holder.clear();
    for (var p in function.parameters) {
        if (p.default.is_value() and holder.holds(p.default.value())) {
            return;
        }
    }
    if (function.body.is_value()) {
        _block_holds(function.body.value(), holder);
    }
}

## Looks through an initializer with `holder`, which holds the result.
_look_through_default(default: Expression?, holder: _Holder) {
    holder.clear();
    if (default.is_value()) {
        holder.holds(default.value());
    }
}

## Wants the creations of any closure.
struct _CreatesAnyClosure {
    construct() {}

    wants(e: Expression): bool {
        return e is MakeClosure(_);
    }
}

extend _CreatesAnyClosure with SiteFilter;

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
## of it.
_select_all(module: Module, applied: bool): Array<bool> {
    var decls = unit_decls(module);
    var walk = Array<bool>();
    for (var st in decls.structs) {
        for (var field in st.field_members) {
            walk.append(field.default.is_value());
        }
        for (var method in st.method_members) {
            walk.append(true);
        }
        for (var c in st.constructors) {
            walk.append(true);
        }
        walk.append(true);
    }
    for (var function in decls.functions) {
        walk.append(true);
    }
    if (!applied) {
        for (var ext in module.extensions) {
            for (var method in ext.methods) {
                walk.append(true);
            }
        }
    }
    for (var global in module.globals) {
        walk.append(global.default.is_value());
    }
    return walk;
}

## Notes, per filter of `holder`, whether the code it just looked through
## holds an expression the filter wants; `extension` code is left out of
## the walks of the `applied` filters.
_note_found(holder: _Holder, applied: Array<bool>, extension: bool, walks: Array<Array<bool>>) {
    for (var i in 0..walks.count) {
        if (!extension or !applied[i]) {
            walks[i].append(holder.found[i]);
        }
    }
}

## Which code of `module` each of `filters` picks, in the walk's order (the
## extensions' own copies of their methods left out where `applied`): the
## code holding an expression the filter wants. One walk serves them all.
_select_each(module: Module, filters: Array<SiteFilter>, applied: Array<bool>): Array<Array<bool>> {
    var decls = unit_decls(module);
    var walks = Array<Array<bool>>();
    for (var filter in filters) {
        walks.append(Array<bool>());
    }
    var holder = _Holder(filters);
    for (var st in decls.structs) {
        for (var field in st.field_members) {
            _look_through_default(field.default, holder);
            _note_found(holder, applied, false, walks);
        }
        for (var method in st.method_members) {
            _look_through_function(method, holder);
            _note_found(holder, applied, false, walks);
        }
        for (var c in st.constructors) {
            _look_through_function(c, holder);
            _note_found(holder, applied, false, walks);
        }
        _look_through_function(st.destructor, holder);
        _note_found(holder, applied, false, walks);
    }
    for (var function in decls.functions) {
        _look_through_function(function, holder);
        _note_found(holder, applied, false, walks);
    }
    for (var ext in module.extensions) {
        for (var method in ext.methods) {
            _look_through_function(method, holder);
            _note_found(holder, applied, true, walks);
        }
    }
    for (var global in module.globals) {
        _look_through_default(global.default, holder);
        _note_found(holder, applied, false, walks);
    }
    return walks;
}

## Walks the sites of the code of `module` that `walk` picks, as `_select`
## ordered it.
_sites_in_module(module: Module, table: SiteTable, applied: bool, walk: Array<bool>, visitor: SiteVisitor) {
    var decls = unit_decls(module);
    ulong at = 0;
    for (var st in decls.structs) {
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
    for (var function in decls.functions) {
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
            var params = table.callable(node.function);
            if (!params.is_value()) {
                var signature = table.generic(node.function);
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
                params = table.method(owner, node.method);
                if (!params.is_value()) {
                    var signature = table.generic_method(owner, node.method);
                    if (signature.is_value()) {
                        params = table.generic_parameters(signature.value(), node.args, current);
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
    if (!ret.is_value()) {
        return changed;
    }
    if (method.ty.is_auto() and !ret.value().contains_auto()) {
        method.ty = ret.value();
        return true;
    }
    if (!is_trait(state, ret.value())) {
        return changed;
    }
    # The slot returns a trait whose arguments the body's struct binds
    # (`Iterator<U>` from `ArrayIterator<int>`): the body's type is
    # inferred first, and the closure returns the trait once it is known.
    if (ret.value().contains_auto()) {
        if (method.ty.is_auto()) {
            state.trait_return_closures.insert(st.name);
        }
        return changed;
    }
    if (!state.trait_return_closures.contains(st.name)) {
        return changed;
    }
    state.trait_return_closures.remove(st.name);
    if (method.ty == ret.value()) {
        return changed;
    }
    method.ty = ret.value();
    return true;
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
## `MakeClosure`'s function type in step with its `__call`.
##
## @param module the model, changed in place
## @param state the passes' state
## @returns whether anything changed
export sync_closures(module: Module, state: PassState): bool {
    # A checked unit's closures are in step already, and no code walked
    # here creates one: only the compilation unit's own closures can change.
    var own = unit_decls(module).structs;
    bool any = false;
    for (var st in own) {
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
    for (var st in own) {
        if (is_closure_struct(st.name) and (_has_unknown_types(st) or state.trait_return_closures.contains(st.name))) {
            unknown.insert(st.ty.to_string());
            unknown.insert(st.name);
        }
    }
    # One walk finds both the code creating a closure, whose types the
    # end of this keeps in step, and the code creating one of those.
    var filters = Array<SiteFilter>();
    filters.append(_CreatesClosure(unknown));
    filters.append(_CreatesAnyClosure());
    var applied = Array<bool>();
    applied.append(false);
    applied.append(false);
    var walks = _select_each(module, filters, applied);
    var learned = HashMap<String, _Learned>();
    if (unknown.count > 0 and walks[0].contains(true)) {
        var learner = _Learner(SiteTable(module, state));
        _sites_in_module(module, learner.table, false, walks[0], learner);
        learned = learner.learned;
    }
    bool changed = false;
    for (var st in own) {
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
    for (var st in own) {
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
    # Nothing above creates a closure or moves a creation.
    var keeper = _Signatures(signatures);
    _rewrite_selected(module, walks[1], keeper);
    return changed or keeper.changed;
}

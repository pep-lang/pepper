## Implicit types: `pepper_sema::passes::resolve_implicit_types` in Pepper.
## Each `auto` variable takes the type of its initializer, each unresolved
## name the type of what it names, each function declared without a return
## type the type its returns agree on, and calls to overload sets and
## generic functions the member or specialization their arguments select.
## Property accesses, calls through function values, calls on enum values
## and operators a number type's extension declares are rewritten on the
## way. Return types feed callers and closure types feed their creations,
## so the pass repeats while anything changes (at most eight times).

import [binary_result, conditional_result, int_literal_type, is_numeric_type] from "arithmetic";
import [enum_method_name, getter_name] from "builder";
import [ModuleTables, rewrite_module, sync_closures] from "closure_sites";
import [MAIN_WITH_ARGUMENTS] from "entry_point";
import [call_on_value, case_value_type, FieldTypes, is_enum, method_read] from "enums";
import [bind_generic_function_values, bind_generic_method_values] from "generic_values";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    FunctionRefExpression,
    InvokeExpression,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeName,
    UnaryExpression,
    UnaryOp,
    VariableDef
] from "model";
import [bind_method_call, Callees, has_named, report_function_value] from "named_arguments";
import [set_name] from "names";
import [is_comparison, op_name, simd_result, weak_result] from "operators";
import [apply_choice, arg_info, ArgInfo, bind_function_values, Choice, method_target, Overloads] from "overload_select";
import [lower_property, Properties, PropertySite] from "properties";
import [PassState] from "state";
import [instance, trait_def, used_trait_types] from "traits";
import [labeled_tuple_literal_type, tuple_constructor_labels, tuple_literal_type] from "tuple_literals";
import [GenericSignature, record_conformances, specialization] from "type_arguments";
import [FUNCTION, parse_type_string, replace_map, VOID] from "type_name";
import [is_value_type, method_is_static, value_type_key] from "value_types";
import [Rewriter, rewrite_expression] from "walk";

## The keys of the number types and `bool`: `value_types::NUMBER_KEYS`.
_number_keys(): String[] {
    return ["i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "bool"];
}

## How many arguments the methods of one name take: the name (an overload
## set's members share their set's name), and the fewest and most.
struct _Arity {
    var name: String;
    var fewest: ulong;
    var most: ulong;

    construct(name: String, fewest: ulong, most: ulong) {
        this.name = name;
        this.fewest = fewest;
        this.most = most;
    }
}

_method_arities(st: StructDef): Array<_Arity> {
    var out = Array<_Arity>();
    for (var m in st.method_members) {
        ulong fewest = 0;
        for (var p in m.parameters) {
            if (!p.default.is_value()) {
                fewest += 1;
            }
        }
        out.append(_Arity(set_name(m.name), fewest, m.parameters.count));
    }
    return out;
}

_takes(arities: Array<_Arity>, name: String, count: ulong): bool {
    var set = set_name(name);
    for (var a in arities) {
        if (a.name == set and count >= a.fewest and count <= a.most) {
            return true;
        }
    }
    return false;
}

_function_type(ret: TypeName, params: TypeName[]): TypeName {
    var args = Array<TypeName>();
    args.append(ret);
    args.append_all(params);
    return TypeName.with_args(FUNCTION, args);
}

## Free functions that can be referenced by name as values:
## `function_types::referenceable_functions`.
_referenceable_functions(module: Module): Array<(String, TypeName)> {
    var out = Array<(String, TypeName)>();
    for (var f in module.functions) {
        if (f.is_generic_func or f.name.contains("<") or !(f.body.is_value() or module.stripped.contains(f.loc))) {
            continue;
        }
        var params = Array<TypeName>();
        for (var p in f.parameters) {
            params.append(p.ty);
        }
        out.append((f.name, _function_type(f.ty.is_auto() ? TypeName.void() : f.ty, params)));
    }
    for (var e in module.externs) {
        if (e.is_variadic) {
            continue;
        }
        var params = Array<TypeName>();
        for (var p in e.parameters) {
            params.append(p.ty);
        }
        out.append((e.name, _function_type(e.ty.is_auto() ? TypeName.void() : e.ty, params)));
    }
    return out;
}

_first_wins(map: HashMap<String, TypeName>, key: String, value: TypeName) {
    if (!map.contains(key)) {
        map[key] = value;
    }
}

_before_angle(text: String): String {
    var at = text.find("<");
    return at < 0 ? text : text.substr_bytes(0, at as ulong);
}

## Program-wide lookup tables, built once per run of the pass. Where a name
## is declared twice, the first declaration wins.
struct _ImplicitTables {
    ## What calls with named arguments bind to.
    var callees: Callees;
    ## Struct field tables: struct type string, then fields.
    var structs: Array<(String, Array<VariableDef>)> = Array<(String, Array<VariableDef>)>();
    ## Struct type string to its positions in `structs`, in order.
    var struct_index: HashMap<String, Array<ulong>> = HashMap<String, Array<ulong>>();
    var struct_names: HashSet<String> = HashSet<String>();
    var struct_bases: HashSet<String> = HashSet<String>();
    ## Struct method tables: struct type string, then (method, return type).
    var methods: Array<(String, Array<(String, TypeName)>)> = Array<(String, Array<(String, TypeName)>)>();
    var method_index: HashMap<String, Array<ulong>> = HashMap<String, Array<ulong>>();
    ## Struct type string to how many arguments each of its methods takes.
    var arities: HashMap<String, Array<_Arity>> = HashMap<String, Array<_Arity>>();
    ## Free-function and extern name to return type.
    var functions: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Free functions usable as values: name to function type.
    var function_types: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Generic methods: struct type string to (method name, declaration).
    var generic_methods: HashMap<String, Array<(String, GenericSignature)>> = HashMap<String, Array<(String, GenericSignature)>>();
    var generic_method_names: HashSet<String> = HashSet<String>();
    ## Generic free functions: name to declaration.
    var generic_functions: HashMap<String, GenericSignature> = HashMap<String, GenericSignature>();
    ## Global variables: name to type.
    var globals: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Struct declared name to its type.
    var struct_types: HashMap<String, TypeName> = HashMap<String, TypeName>();
    var properties: Properties;

    construct(module: Module, state: PassState) {
        callees = Callees(module);
        properties = Properties(module);
        for (var st in module.structs) {
            var key = st.ty.to_string();
            structs.append((key, st.field_members.copy()));
            var own = Array<(String, TypeName)>();
            for (var m in st.method_members) {
                own.append((m.name, m.ty));
            }
            methods.append((key, own));
            struct_names.insert(key);
            struct_bases.insert(_before_angle(key));
            if (!arities.contains(key)) {
                arities[key] = _method_arities(st);
            }
            if (st.generic_methods.count != 0) {
                var generic = Array<(String, GenericSignature)>();
                for (var m in st.generic_methods) {
                    generic.append((m.name, GenericSignature(m, state)));
                    generic_method_names.insert(m.name);
                }
                generic_methods[key] = generic;
            }
            if (!struct_types.contains(st.name)) {
                struct_types[st.name] = st.ty;
            }
        }
        # Trait types used as values: what `var x = s.take()` returns.
        for (var ty in used_trait_types(module)) {
            var def = trait_def(module.traits, ty);
            if (def.is_value()) {
                var own = Array<(String, TypeName)>();
                for (var m in instance(def.value(), ty).methods) {
                    own.append((m.name, m.ty));
                }
                methods.append((ty.to_string(), own));
            }
        }
        ulong i = 0;
        while (i < structs.count) {
            var (key, _) = structs[i];
            if (!struct_index.contains(key)) {
                struct_index[key] = Array<ulong>();
            }
            struct_index[key].append(i);
            i += 1;
        }
        i = 0;
        while (i < methods.count) {
            var (key, _) = methods[i];
            if (!method_index.contains(key)) {
                method_index[key] = Array<ulong>();
            }
            method_index[key].append(i);
            i += 1;
        }
        for (var f in module.functions) {
            _first_wins(functions, f.name, f.ty);
        }
        for (var e in module.externs) {
            _first_wins(functions, e.name, e.ty);
        }
        for (var f in module.functions) {
            if (f.is_generic_func and !generic_functions.contains(f.name)) {
                generic_functions[f.name] = GenericSignature(f, state);
            }
        }
        for (var (name, ty) in _referenceable_functions(module)) {
            _first_wins(function_types, name, ty);
        }
        for (var g in module.globals) {
            _first_wins(globals, g.name, g.ty);
        }
    }
}

## The struct whose methods are being resolved: its fields with resolved
## types, and its methods. It stands in for the struct's table entries.
struct _OwnStruct {
    var name: String;
    var fields: Array<VariableDef>;
    var methods: Array<(String, TypeName)>;

    construct(name: String, fields: Array<VariableDef>, methods: Array<(String, TypeName)>) {
        this.name = name;
        this.fields = fields;
        this.methods = methods;
    }
}

## The scopes of the code being walked, and what typing it needs.
struct _TypeScopes {
    var tables: _ImplicitTables;
    var state: PassState;
    var own: _OwnStruct? = Optional<_OwnStruct>.Empty;
    ## Parameters per scope; index 0 holds none.
    var params: Array<Array<VariableDef>> = Array<Array<VariableDef>>();
    ## Local symbols per scope; scope 0 holds what the global initializers
    ## declare after `tables.globals`.
    var symbols: Array<Array<(String, TypeName)>> = Array<Array<(String, TypeName)>>();
    ## While walking a function with no declared return type: the types of
    ## its `return <value>` statements.
    var returns: Array<TypeName>? = Optional<Array<TypeName>>.Empty;
    var overloads: Overloads;
    ## The generic parameters of the code being walked.
    var unbound: Array<String> = Array<String>();
    ## Calls resolved to an overload set's member, shared by every scope.
    var resolved: Array<(Loc, String)>;
    ## Walking a generic base: calls are not inferred here.
    var generic_base: bool = false;
    var in_constructor: bool = false;
    ## The function or method being walked, and where it is declared.
    var function: String = "";
    var function_loc: Loc = Loc.none();

    construct(tables: _ImplicitTables, overloads: Overloads, resolved: Array<(Loc, String)>, state: PassState) {
        this.tables = tables;
        this.overloads = overloads;
        this.resolved = resolved;
        this.state = state;
        params.append(Array<VariableDef>());
        symbols.append(Array<(String, TypeName)>());
    }

    push() {
        params.append(Array<VariableDef>());
        symbols.append(Array<(String, TypeName)>());
    }

    pop() {
        params.pop();
        symbols.pop();
    }

    ## A local declared in the code being walked (not a global).
    local(name: String): TypeName? {
        ulong i = symbols.count;
        while (i > 1) {
            i -= 1;
            for (var (symbol, ty) in symbols[i]) {
                if (symbol == name) {
                    return Optional<TypeName>.Value(ty);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    symbol(name: String): TypeName? {
        var found = local(name);
        if (found.is_value()) {
            return found;
        }
        found = tables.globals.try_get(name);
        if (found.is_value()) {
            return found;
        }
        for (var (symbol, ty) in symbols[0]) {
            if (symbol == name) {
                return Optional<TypeName>.Value(ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    param(name: String): TypeName? {
        ulong i = params.count;
        while (i > 0) {
            i -= 1;
            for (var p in params[i]) {
                if (p.name == name) {
                    return Optional<TypeName>.Value(p.ty);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## The field tables of struct type `key`, in order.
    field_tables(key: String): Array<Array<VariableDef>> {
        var out = Array<Array<VariableDef>>();
        if (own.is_value() and own.value().name == key) {
            out.append(own.value().fields);
            return out;
        }
        var found = tables.struct_index.try_get(key);
        if (found.is_value()) {
            for (var i in found.value()) {
                var (_, fields) = tables.structs[i];
                out.append(fields);
            }
        }
        return out;
    }

    ## The method tables of struct type `key`, in order.
    method_tables(key: String): Array<Array<(String, TypeName)>> {
        var out = Array<Array<(String, TypeName)>>();
        if (own.is_value() and own.value().name == key) {
            out.append(own.value().methods);
            return out;
        }
        var found = tables.method_index.try_get(key);
        if (found.is_value()) {
            for (var i in found.value()) {
                var (_, methods) = tables.methods[i];
                out.append(methods);
            }
        }
        return out;
    }

    ## Declared type of field `name` on struct type `ty`.
    field_type(ty: TypeName, name: String): TypeName? {
        var all = field_tables(ty.to_string());
        if (all.count == 0) {
            return Optional<TypeName>.Empty;
        }
        for (var f in all[0]) {
            if (f.name == name) {
                return Optional<TypeName>.Value(f.ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## Declared return type of method `name` on struct type `ty`.
    method_return(ty: TypeName, name: String): TypeName? {
        var all = method_tables(ty.to_string());
        if (all.count == 0) {
            return Optional<TypeName>.Empty;
        }
        for (var (m, ret) in all[0]) {
            if (m == name) {
                return Optional<TypeName>.Value(ret);
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## Whether struct type `ty` declares a method `name`; an overloaded
    ## method is declared under its members' names.
    has_method(ty: TypeName, name: String): bool {
        for (var methods in method_tables(ty.to_string())) {
            for (var (m, _) in methods) {
                if (m.starts_with(name) and (m.size == name.size or set_name(m) == name)) {
                    return true;
                }
            }
        }
        return false;
    }

    ## Whether a bare call of `name` with `count` arguments in a method of
    ## `ty` calls one of its methods: class scope first, unless no method by
    ## that name takes `count` arguments and a free function `name` exists.
    calls_method(ty: TypeName, name: String, count: ulong): bool {
        if (!has_method(ty, name)) {
            return false;
        }
        bool free = tables.functions.contains(name)
            or tables.generic_functions.contains(name)
            or overloads.is_set(name);
        if (!free) {
            return true;
        }
        var arities = tables.arities.try_get(ty.to_string());
        return !arities.is_value() or _takes(arities.value(), name, count);
    }

    ## Function type of the free function `name`, when a bare `name` in
    ## value position refers to it.
    function_value(name: String, current: TypeName?): TypeName? {
        if (param(name).is_value() or symbol(name).is_value()) {
            return Optional<TypeName>.Empty;
        }
        if (current.is_value()) {
            if (field_type(current.value(), name).is_value() or has_method(current.value(), name)) {
                return Optional<TypeName>.Empty;
            }
        }
        return tables.function_types.try_get(name);
    }

    ## When a call `name(args)` calls through a function value, the callee
    ## expression and its function type.
    value_callee(name: String, current: TypeName?): (Expression, TypeName)? {
        var declared = param(name);
        if (!declared.is_value()) {
            declared = symbol(name);
        }
        if (declared.is_value()) {
            var ty = declared.value();
            if (!ty.is_callable()) {
                return Optional<(Expression, TypeName)>.Empty;
            }
            var callee = Expression.SymbolRef(SymbolRefExpression(name, ty.copy(), Loc.none()));
            return Optional<(Expression, TypeName)>.Value((callee, ty));
        }
        if (!current.is_value()) {
            return Optional<(Expression, TypeName)>.Empty;
        }
        var field = field_type(current.value(), name);
        if (!field.is_value() or !field.value().is_callable() or has_method(current.value(), name)) {
            return Optional<(Expression, TypeName)>.Empty;
        }
        var callee = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, name, Loc.none()));
        return Optional<(Expression, TypeName)>.Value((callee, field.value()));
    }

    _mentions_unbound(ty: TypeName): bool {
        for (var p in unbound) {
            if (ty.mentions(p)) {
                return true;
            }
        }
        return false;
    }

    ## What resolution knows about each of `args`.
    _infos(args: Expression[], current: TypeName?): Array<ArgInfo> {
        var infos = Array<ArgInfo>();
        for (var arg in args) {
            infos.append(arg_info(arg, overloads, Optional<TypeName>.Value(type_of(arg, current))));
        }
        return infos;
    }

    ## The overload set a call `function(args)` names, unless a local,
    ## parameter or member by that name shadows it.
    overload_call(function: String, current: TypeName?): (String, Optional<TypeName[]>)? {
        var none = Optional<(String, Optional<TypeName[]>)>.Empty;
        if (overloads.is_empty() or !overloads.is_set(overloads.call_set_name(function))) {
            return none;
        }
        var (base, explicit) = overloads.call_set(function);
        if (!overloads.is_set(base) or value_callee(base, current).is_value()) {
            return none;
        }
        if (current.is_value()
            and (has_method(current.value(), base) or field_type(current.value(), base).is_value())) {
            return none;
        }
        return Optional<(String, Optional<TypeName[]>)>.Value((base, explicit));
    }

    ## Resolves `function(args)` against its overload set, when it names one
    ## and its arguments decide.
    select_overload(function: String, args: Expression[], at: Loc, current: TypeName?): Choice? {
        var call = overload_call(function, current);
        if (!call.is_value()) {
            return Optional<Choice>.Empty;
        }
        var (base, explicit) = call.value();
        var infos = _infos(args, current);
        # In a generic body, the specializations decide.
        for (var info in infos) {
            if (info.ty.is_value() and _mentions_unbound(info.ty.value())) {
                return Optional<Choice>.Empty;
            }
        }
        var outcome = overloads.select(base, explicit, infos, at);
        if (outcome is Chosen(choice)) {
            return Optional<Choice>.Value(choice);
        }
        return Optional<Choice>.Empty;
    }

    ## Resolves `receiver.method(args)` against the method overload set of
    ## the receiver's struct, when its arguments decide.
    select_method_overload(
        receiver: TypeName, method: String, args: Expression[], at: Loc, current: TypeName?
    ): Choice? {
        var infos = _infos(args, current);
        if (_mentions_unbound(receiver)) {
            return Optional<Choice>.Empty;
        }
        for (var info in infos) {
            if (info.ty.is_value() and _mentions_unbound(info.ty.value())) {
                return Optional<Choice>.Empty;
            }
        }
        var outcome = overloads.select_method(receiver, method, infos, at);
        if (outcome is Chosen(choice)) {
            return Optional<Choice>.Value(choice);
        }
        return Optional<Choice>.Empty;
    }

    ## What each argument's type says about a generic call's type
    ## arguments.
    argument_types(args: Expression[], current: TypeName?): Array<TypeName?> {
        var out = Array<TypeName?>();
        for (var arg in args) {
            if (arg is MakeClosure(node)) {
                out.append(Optional<TypeName>.Value(node.ty));
                continue;
            }
            var ty = type_of(arg, current);
            out.append(
                !ty.is_empty() and !ty.contains_auto() ? Optional<TypeName>.Value(ty) : Optional<TypeName>.Empty
            );
        }
        return out;
    }

    ## The function a binary operator with a number on the left calls, when
    ## the number type's extension declares that operator, and whether its
    ## result is negated (`!=` through `==`).
    number_operator(
        op: BinaryOp, lhs: Expression, lhs_type: TypeName?, rhs: Expression, current: TypeName?
    ): (String, bool)? {
        var none = Optional<(String, bool)>.Empty;
        var name = op_name(op);
        if (_is_assignment(op) or name.size == 0) {
            return none;
        }
        bool any = false;
        for (var key in _number_keys()) {
            if (_wanted(key, op, name)) {
                any = true;
                break;
            }
        }
        if (!any) {
            return none;
        }
        var left = lhs_type.is_value() ? lhs_type.value().to_string() : type_of(lhs, current).to_string();
        if (is_enum(state, left)) {
            return none;
        }
        var key = value_type_key(state, left);
        if (!key.is_value() or !_wanted(key.value(), op, name)) {
            return none;
        }
        var rhs_type = type_of(rhs, current);
        if (rhs_type.is_empty()
            or rhs_type.is_auto()
            or rhs_type.is_pointer()
            or is_value_type(state, rhs_type)
            or is_enum(state, rhs_type.to_string())) {
            return none;
        }
        if (_declares(key.value(), name)) {
            return Optional<(String, bool)>.Value((enum_method_name(key.value(), name), false));
        }
        return Optional<(String, bool)>.Value((enum_method_name(key.value(), "=="), true));
    }

    _declares(key: String, method: String): bool {
        var is_static = method_is_static(state, key, method);
        return is_static.is_value() and !is_static.value();
    }

    _wanted(key: String, op: BinaryOp, name: String): bool {
        return _declares(key, name) or (op == BinaryOp.NotEqual and _declares(key, "=="));
    }

    ## Best-effort type of an expression: `typeOfExpr`.
    type_of(e: Expression, current: TypeName?): TypeName {
        match (e) {
            Destructure(node) => {
                return type_of(node.value, current);
            }
            Move(node) => {
                return type_of(node.value, current);
            }
            StaticCase(node) => {
                return node.ty;
            }
            Subject(node) => {
                return node.ty;
            }
            WithSubject(scoped) => {
                return type_of(scoped.body, current);
            }
            MatchArm(_) => {
                return TypeName.boolean();
            }
            CaseValue(value) => {
                var subject = type_of(value.subject, current);
                var result = case_value_type(state, value, subject, _ScopeFields(this, subject));
                if (result is Ok(ty)) {
                    if (ty.is_value()) {
                        return ty.value();
                    }
                }
                return TypeName.auto();
            }
            MemberRef(node) => {
                var lhs_type = type_of(node.lhs, current);
                if (lhs_type.is_empty() or lhs_type.is_auto()) {
                    return TypeName.auto();
                }
                var element = lhs_type.tuple_element(node.name);
                if (element.is_value()) {
                    return element.value();
                }
                for (var fields in field_tables(lhs_type.to_string())) {
                    for (var f in fields) {
                        if (f.name == node.name) {
                            return f.ty;
                        }
                    }
                }
                # A property read before it is lowered: its getter's type.
                if (tables.properties.find(lhs_type, node.name).is_value()) {
                    var ret = method_return(lhs_type, getter_name(node.name));
                    if (ret.is_value()) {
                        return ret.value();
                    }
                }
                return TypeName.auto();
            }
            SymbolRef(node) => {
                return _symbol_type(node.id, current);
            }
            FunctionRef(node) => {
                return node.ty;
            }
            MakeClosure(node) => {
                return node.ty.contains_auto() ? TypeName.auto() : node.ty;
            }
            Invoke(node) => {
                var ret = type_of(node.callee, current).function_return();
                return ret.is_value() ? ret.value() : TypeName.auto();
            }
            ThisRef => {
                return current.is_value() ? current.value() : TypeName.auto();
            }
            MethodCall(node) => {
                return _method_call_type(node, current);
            }
            ForIterator(source) => {
                var source_type = type_of(source, current);
                if (source_type.is_empty() or source_type.is_auto()) {
                    return TypeName.auto();
                }
                var all = method_tables(source_type.to_string());
                if (all.count == 0) {
                    return TypeName.auto();
                }
                for (var (m, iterator) in all[0]) {
                    if (m == "iterate") {
                        return iterator;
                    }
                }
                return source_type;
            }
            Unary(node) => {
                if (node.op == UnaryOp.LogicalNot) {
                    return TypeName.boolean();
                }
                return type_of(node.operand, current);
            }
            Binary(node) => {
                return _binary_type(node, current);
            }
            IntLiteral(value) => {
                return TypeName.named(int_literal_type(value));
            }
            FloatLiteral(_) => {
                return TypeName.named("f64");
            }
            BoolLiteral(_) => {
                return TypeName.boolean();
            }
            StringLiteral(_) => {
                return TypeName.named("String");
            }
            PointerLiteral => {
                return TypeName.void_pointer();
            }
            FunctionCall(node) => {
                return _call_type(node, current);
            }
            Address(_, _) => {
                return TypeName.named("u64");
            }
            RefCount(_, _) => {
                return TypeName.named("u32");
            }
            CountStep(_) => {
                return TypeName.named("u32");
            }
            FunctionPointer(_) => {
                return TypeName.named("void*");
            }
            Weak(op, ty, _) => {
                return weak_result(op, ty);
            }
            AtomicLoad(ty, _) => {
                return ty;
            }
            Allocate(ty) => {
                return ty;
            }
            Default(ty) => {
                return ty;
            }
            IsPod(_) => {
                return TypeName.boolean();
            }
            SizeOf(_) => {
                return TypeName.named("u64");
            }
            AtomicStore(_, _, _) => {
                return TypeName.named("void");
            }
            ConstructAt(_, _) => {
                return TypeName.named("void");
            }
            AtomicCmpXchg(_, _, _, _) => {
                return TypeName.named("bool");
            }
            AtomicFetch(_, ty, _, _) => {
                return ty;
            }
            Simd(node) => {
                return simd_result(node.op, node.ty);
            }
            Index(node) => {
                return _index_type(e, node.lhs, current);
            }
            ArrayIndex(node) => {
                if (!node.ty.is_empty() and !node.ty.is_auto()) {
                    return node.ty;
                }
                return _index_type(e, node.lhs, current);
            }
            Cast(node) => {
                return node.ty;
            }
            Ternary(node) => {
                var ty = type_of(node.true_expr, current);
                if (ty.is_auto() and node.true_expr is NoMatch) {
                    return type_of(node.false_expr, current);
                }
                var false_type = type_of(node.false_expr, current);
                var a = ty.to_string();
                var b = false_type.to_string();
                if (!false_type.is_auto() and is_numeric_type(state, a) and is_numeric_type(state, b)) {
                    return TypeName.named(conditional_result(state, a, b));
                }
                return ty;
            }
            else => {
                return TypeName.auto();
            }
        }
    }

    _symbol_type(id: String, current: TypeName?): TypeName {
        # `this` inside a method is the parent struct type.
        if (id == "this" and current.is_value()) {
            return current.value();
        }
        # Parameters shadow globals.
        var found = param(id);
        if (found.is_value()) {
            return found.value();
        }
        found = local(id);
        if (found.is_value()) {
            return found.value();
        }
        # A bare field in its struct's methods; fields shadow globals.
        if (current.is_value()) {
            found = field_type(current.value(), id);
            if (found.is_value()) {
                return found.value();
            }
        }
        found = symbol(id);
        if (found.is_value()) {
            return found.value();
        }
        # A bare property in its struct's methods.
        if (current.is_value() and tables.properties.find(current.value(), id).is_value()) {
            found = method_return(current.value(), getter_name(id));
            if (found.is_value()) {
                return found.value();
            }
        }
        # The name of a struct.
        if (tables.struct_names.contains(id)) {
            return TypeName.named(id);
        }
        # A free function used as a value.
        found = function_value(id, current);
        if (found.is_value()) {
            return found.value();
        }
        return TypeName.auto();
    }

    _method_call_type(node: MethodCallExpression, current: TypeName?): TypeName {
        var this_type = type_of(node.this_value, current);
        if (this_type.is_empty() or this_type.is_auto()) {
            return TypeName.auto();
        }
        # A method of an enum or another value type is the function `E::m`.
        var text = this_type.to_string();
        var key = value_type_key(state, text);
        var owner = key.is_value() ? key.value() : text;
        if (_declares(owner, node.method)) {
            var all = Array<Expression>();
            all.append(node.this_value);
            all.append_all(node.args);
            var call = Expression.FunctionCall(
                FunctionCallExpression(enum_method_name(owner, node.method), all, node.loc)
            );
            return type_of(call, current);
        }
        if (overloads.is_method_set(this_type, node.method)) {
            var choice = select_method_overload(this_type, node.method, node.args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        for (var methods in method_tables(text)) {
            for (var (m, ret) in methods) {
                if (m == node.method) {
                    return ret;
                }
            }
        }
        # `obj.callback(x)` calls through a field of function type.
        var field = field_type(this_type, node.method);
        if (field.is_value()) {
            var ret = field.value().function_return();
            if (ret.is_value()) {
                return ret.value();
            }
        }
        return TypeName.auto();
    }

    _binary_type(node: BinaryExpression, current: TypeName?): TypeName {
        if (_is_assignment(node.op)) {
            return type_of(node.lhs, current);
        }
        if (is_comparison(node.op) or node.op == BinaryOp.LogicalAnd or node.op == BinaryOp.LogicalOr) {
            return TypeName.boolean();
        }
        var lhs_type = type_of(node.lhs, current);
        if (lhs_type.is_empty() or lhs_type.is_auto()) {
            return TypeName.auto();
        }
        var number = number_operator(node.op, node.lhs, Optional<TypeName>.Value(lhs_type), node.rhs, current);
        if (number.is_value()) {
            var (function, _) = number.value();
            var args = Array<Expression>();
            args.append(node.lhs);
            args.append(node.rhs);
            return type_of(Expression.FunctionCall(FunctionCallExpression(function, args, node.loc)), current);
        }
        var name = op_name(node.op);
        if (overloads.is_method_set(lhs_type, name)) {
            var args = Array<Expression>();
            args.append(node.rhs);
            var choice = select_method_overload(lhs_type, name, args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        var ret = method_return(lhs_type, name);
        if (ret.is_value()) {
            return ret.value();
        }
        var rhs_type = type_of(node.rhs, current);
        var promoted = binary_result(state, node.op, lhs_type.to_string(), rhs_type.to_string());
        return promoted.is_value() ? TypeName.named(promoted.value()) : lhs_type;
    }

    _call_type(node: FunctionCallExpression, current: TypeName?): TypeName {
        var function = node.function;
        if (tuple_constructor_labels(function).is_value()) {
            var types = Array<TypeName>();
            for (var a in node.args) {
                types.append(type_of(a, current));
            }
            var ty = labeled_tuple_literal_type(function, types);
            return ty.is_value() ? ty.value() : TypeName.auto();
        }
        if (function.starts_with("__tuple<")) {
            return parse_type_string(function);
        }
        # A call through a local, parameter or field of function type.
        var callee = value_callee(function, current);
        if (callee.is_value()) {
            var (_, ty) = callee.value();
            var ret = ty.function_return();
            return ret.is_value() ? ret.value() : TypeName.auto();
        }
        # Inside a method, a bare call naming one of the struct's own
        # methods is that method; a converted string literal still
        # constructs `String`.
        if (current.is_value() and !_is_converted_literal(node)) {
            var st = current.value();
            if (!has_method(st, function) or calls_method(st, function, node.args.count)) {
                var all = method_tables(st.to_string());
                if (all.count > 0) {
                    for (var (m, ret) in all[0]) {
                        if (m == function) {
                            return ret;
                        }
                    }
                }
            }
        }
        # A call to an overloaded function has the type of the member its
        # arguments select, once they do.
        if (overload_call(function, current).is_value()) {
            var choice = select_overload(function, node.args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        # A generic function called without type arguments has no type
        # until they are inferred.
        if (!function.contains("<") and tables.generic_functions.contains(function)) {
            return TypeName.auto();
        }
        var declared = tables.functions.try_get(function);
        if (declared.is_value()) {
            return declared.value();
        }
        var name = _before_angle(function).trim();
        if (name.size == 0) {
            return TypeName.auto();
        }
        # Intrinsics carry no declared function; type them by name.
        match (name) {
            "__address" => {
                return TypeName.named("u64");
            }
            "__refcount" => {
                return TypeName.named("u32");
            }
            "__atomic_load", "__default", "__copy_object" => {
                var parsed = parse_type_string(function);
                return parsed.sub_types.count > 0 ? parsed.sub_types[0] : TypeName.auto();
            }
            "__is_pod" => {
                return TypeName.boolean();
            }
            "__caller_location" => {
                return TypeName.named("char*");
            }
            "__atomic_store", "__construct_at" => {
                return TypeName.named("void");
            }
            "__atomic_cmpxchg" => {
                return TypeName.named("bool");
            }
            else => {}
        }
        # A generic call spelled with its arguments before it is
        # specialized: the base's return type with the arguments
        # substituted.
        var signature = tables.generic_functions.try_get(name);
        if (signature.is_value()) {
            var base = tables.functions.try_get(name);
            if (base.is_value()) {
                var args = parse_type_string(function).sub_types;
                if (args.count > 0) {
                    var map = Array<(String, TypeName)>();
                    ulong i = 0;
                    while (i < signature.value().params.count and i < args.count) {
                        map.append((signature.value().params[i].name, args[i]));
                        i += 1;
                    }
                    var ty = base.value().copy();
                    replace_map(ty, map);
                    return ty;
                }
            }
        }
        declared = tables.functions.try_get(name);
        if (declared.is_value()) {
            return declared.value();
        }
        # A constructor-style call `Name<...>(...)`, or one of several
        # overloaded constructors (`Name$2`).
        var constructed = set_name(function);
        if (tables.struct_bases.contains(_before_angle(constructed).trim())) {
            return parse_type_string(constructed);
        }
        return TypeName.auto();
    }

    _index_type(e: Expression, lhs: Expression, current: TypeName?): TypeName {
        var lhs_type = type_of(lhs, current);
        var element = _pointee(lhs_type);
        if (element.is_value()) {
            return element.value();
        }
        # A struct receiver whose `[]` is not lowered yet: typed as the
        # `x.__index_get(i)` call it becomes.
        if (e is Index(node)) {
            if (!lhs_type.is_empty() and !lhs_type.is_auto()) {
                var args = Array<Expression>();
                args.append(node.rhs);
                var call = Expression.MethodCall(MethodCallExpression(node.lhs, "__index_get", args, node.loc));
                return type_of(call, current);
            }
        }
        return TypeName.auto();
    }
}

## The fields of a `match` subject's struct, in the walk's scope.
struct _ScopeFields {
    var scopes: _TypeScopes;
    var subject: TypeName;

    construct(scopes: _TypeScopes, subject: TypeName) {
        this.scopes = scopes;
        this.subject = subject;
    }

    field(name: String): TypeName? {
        return scopes.field_type(subject, name);
    }
}

extend _ScopeFields with FieldTypes;

## The element type of a raw pointer, `__ptr<T>` or `T*`; none for any
## other type, and for a `void` pointer.
_pointee(ty: TypeName): TypeName? {
    var element = TypeName();
    if (ty.name == "__ptr" and ty.sub_types.count == 1) {
        element = ty.sub_types[0];
    } else if (ty.sub_types.count == 0 and ty.name.ends_with("*")) {
        element = parse_type_string(ty.name.substr_bytes(0, ty.name.size - 1));
    } else {
        return Optional<TypeName>.Empty;
    }
    return element.to_string() != VOID ? Optional<TypeName>.Value(element) : Optional<TypeName>.Empty;
}

## Where a property access is written, for `lower_property`.
struct _PropertyAt {
    var scopes: _TypeScopes;
    var current_struct: TypeName?;

    construct(scopes: _TypeScopes, current_struct: TypeName?) {
        this.scopes = scopes;
        this.current_struct = current_struct;
    }

    current(): TypeName? {
        return current_struct;
    }

    in_constructor(): bool {
        return scopes.in_constructor;
    }

    function(): String {
        return scopes.function;
    }

    function_loc(): Loc {
        return scopes.function_loc;
    }

    type_of(e: Expression): TypeName {
        return scopes.type_of(e, current_struct);
    }

    is_local(name: String): bool {
        return scopes.param(name).is_value() or scopes.symbol(name).is_value();
    }
}

extend _PropertyAt with PropertySite;

## Types each `Subject` of a `match` expression or `is` test as the value
## its `WithSubject` examines, once that is known.
struct _SubjectFiller {
    var scopes: _TypeScopes;
    var current: TypeName?;

    construct(scopes: _TypeScopes, current: TypeName?) {
        this.scopes = scopes;
        this.current = current;
    }

    rewrite(e: Expression): Expression {
        if (e is WithSubject(scoped)) {
            var ty = scopes.type_of(scoped.subject, current);
            if (!ty.is_auto() and !ty.is_empty()) {
                scoped.body = rewrite_expression(scoped.body, _SubjectTyper(scoped.id, ty));
            }
        }
        return e;
    }
}

extend _SubjectFiller with Rewriter;

struct _SubjectTyper {
    var id: ulong;
    var ty: TypeName;

    construct(id: ulong, ty: TypeName) {
        this.id = id;
        this.ty = ty;
    }

    rewrite(e: Expression): Expression {
        if (e is Subject(node)) {
            if (node.id == id) {
                node.ty = ty.copy();
            }
        }
        return e;
    }
}

extend _SubjectTyper with Rewriter;

## What `resolve_each` does at each expression.
struct _ImplicitResolver {
    var scopes: _TypeScopes;
    var current: TypeName?;

    construct(scopes: _TypeScopes, current: TypeName?) {
        this.scopes = scopes;
        this.current = current;
    }

    rewrite(e: Expression): Expression {
        var state = scopes.state;
        e = lower_property(e, scopes.tables.properties, _PropertyAt(scopes, current), state);
        e = _bind_named_arguments(e);
        _resolve_overload(e);
        _resolve_method_overload(e);
        _infer_type_arguments(e);
        # `(a, b)`: spell out its tuple type once the elements' are known.
        if (e is FunctionCall(node)) {
            if (tuple_constructor_labels(node.function).is_value()) {
                var types = Array<TypeName>();
                for (var a in node.args) {
                    types.append(scopes.type_of(a, current));
                }
                var ty = tuple_literal_type(types);
                if (ty.is_value()) {
                    node.function = ty.value().to_string();
                }
            }
        }
        # Calls through function values: `f(x)` on a local, parameter,
        # global or field of function type.
        if (e is FunctionCall(node)) {
            var callee = scopes.value_callee(node.function, current);
            if (callee.is_value()) {
                var (target, _) = callee.value();
                # The callee stands for the name the call spells.
                if (target is SymbolRef(symbol)) {
                    symbol.loc = node.loc;
                }
                if (target is MemberRef(member)) {
                    member.loc = node.loc;
                }
                return Expression.Invoke(InvokeExpression(target, node.args));
            }
        }
        # A value a `match` pattern binds: report patterns that do not fit.
        if (e is CaseValue(value)) {
            var subject = scopes.type_of(value.subject, current);
            var result = case_value_type(state, value, subject, _ScopeFields(scopes, subject));
            if (result is Err(d)) {
                state.report(d);
            }
            return e;
        }
        # `2.0 * v`: an operator on a number with an extension operator for
        # the right operand calls it.
        if (e is Binary(node)) {
            var number = scopes.number_operator(node.op, node.lhs, Optional<TypeName>.Empty, node.rhs, current);
            if (number.is_value()) {
                var (function, negated) = number.value();
                var args = Array<Expression>();
                args.append(node.lhs);
                args.append(node.rhs);
                var call = Expression.FunctionCall(FunctionCallExpression(function, args, node.loc));
                return negated ? Expression.Unary(UnaryExpression(call, UnaryOp.LogicalNot, node.loc)) : call;
            }
        }
        # `c.name()` on an enum value calls `Color::name(c)`; `x.__acquire()`
        # and `x.__release()` stay method calls for every type.
        if (e is MethodCall(node)) {
            bool refcount_step = (node.method == "__acquire" or node.method == "__release") and node.args.count == 0;
            if (!refcount_step) {
                var this_type = scopes.type_of(node.this_value, current).to_string();
                var key = value_type_key(state, this_type);
                bool value_method = key.is_value() and method_is_static(state, key.value(), node.method).is_value();
                if (is_enum(state, this_type) or value_method) {
                    var owner = key.is_value() ? key.value() : this_type;
                    var call = call_on_value(state, owner, node.method, node.this_value, node.args, node.loc);
                    return call.is_value() ? call.value() : e;
                }
            }
        }
        # `c.name` without a call: a value type's methods have no value form.
        if (e is MemberRef(node)) {
            var lhs_type = scopes.type_of(node.lhs, current).to_string();
            var key = value_type_key(state, lhs_type);
            if (!key.is_value() and is_enum(state, lhs_type)) {
                key = Optional<String>.Value(lhs_type);
            }
            if (key.is_value()) {
                var error = method_read(state, key.value(), node.name, node.loc);
                if (error.is_value()) {
                    state.report(error.value());
                    return e;
                }
            }
        }
        if (e is MethodCall(node)) {
            var this_type = scopes.type_of(node.this_value, current);
            if (!scopes.has_method(this_type, node.method)) {
                var field = scopes.field_type(this_type, node.method);
                if (field.is_value() and field.value().is_callable()) {
                    var callee = Expression.MemberRef(MemberRefExpression(node.this_value, node.method, node.loc));
                    return Expression.Invoke(InvokeExpression(callee, node.args));
                }
            }
        }
        # A bare free-function name in value position is a function value;
        # any other unresolved name takes its declaration's type.
        if (e is SymbolRef(node)) {
            if (node.ty.is_auto() and node.id != "this") {
                var function_type = scopes.function_value(node.id, current);
                if (function_type.is_value()) {
                    return Expression.FunctionRef(
                        FunctionRefExpression(node.id, function_type.value().copy(), node.loc)
                    );
                }
                var resolved = scopes._symbol_type(node.id, current);
                if (!resolved.is_empty() and !resolved.is_auto()) {
                    node.ty = resolved.copy();
                }
            }
        }
        return e;
    }

    ## Binds a method call's named arguments once its receiver's type is
    ## known, and reports naming the arguments of a call through a function
    ## value.
    _bind_named_arguments(e: Expression): Expression {
        var state = scopes.state;
        match (e) {
            MethodCall(node) => {
                if (!has_named(node.args)) {
                    return e;
                }
                var receiver = scopes.type_of(node.this_value, current);
                if (receiver.is_empty() or receiver.contains_auto()) {
                    return e;
                }
                if (!scopes.has_method(receiver, node.method)) {
                    var field = scopes.field_type(receiver, node.method);
                    if (field.is_value() and field.value().is_callable()) {
                        report_function_value(state, field.value(), node.args);
                        return e;
                    }
                }
                return bind_method_call(e, receiver, scopes.tables.callees, state);
            }
            FunctionCall(node) => {
                if (has_named(node.args)) {
                    var callee = scopes.value_callee(node.function, current);
                    if (callee.is_value()) {
                        var (_, ty) = callee.value();
                        report_function_value(state, ty, node.args);
                    }
                }
            }
            Invoke(node) => {
                if (has_named(node.args)) {
                    var ty = scopes.type_of(node.callee, current);
                    if (!ty.is_empty() and !ty.contains_auto()) {
                        report_function_value(state, ty, node.args);
                    }
                }
            }
            else => {}
        }
        return e;
    }

    ## Rewrites a call to an overloaded function to the member its
    ## arguments select.
    _resolve_overload(e: Expression) {
        if (e is FunctionCall(node)) {
            var choice = scopes.select_overload(node.function, node.args, node.loc, current);
            if (choice.is_value()) {
                node.function = apply_choice(node.args, choice.value());
                scopes.resolved.append((node.loc, choice.value().callee));
            }
        }
    }

    ## Rewrites a call of an overloaded method to the member its arguments
    ## select.
    _resolve_method_overload(e: Expression) {
        if (!(e is MethodCall(_)) or scopes.overloads.is_empty()) {
            return;
        }
        var node = _method_call_of(e);
        # Typing the receiver is costly: first rule out a name no struct
        # overloads.
        if (!scopes.overloads.is_any_method_set(node.method)) {
            return;
        }
        var receiver = scopes.type_of(node.this_value, current);
        if (receiver.is_empty() or receiver.contains_auto() or !scopes.overloads.is_method_set(receiver, node.method)) {
            return;
        }
        var choice = scopes.select_method_overload(receiver, node.method, node.args, node.loc, current);
        if (choice.is_value()) {
            node.method = apply_choice(node.args, choice.value());
            scopes.resolved.append((node.loc, method_target(receiver, choice.value().callee)));
        }
    }

    ## A call to a generic function or method without (all) its type
    ## arguments becomes a call to the specialization its arguments select.
    _infer_type_arguments(e: Expression) {
        if (scopes.generic_base) {
            return;
        }
        if (e is MethodCall(node)) {
            # An operator method (`<`) is never generic.
            if (!_starts_name(node.method)) {
                return;
            }
            var written = parse_type_string(node.method);
            if (!scopes.tables.generic_method_names.contains(written.name)) {
                return;
            }
            var owner = scopes.type_of(node.this_value, current);
            if (owner.contains_auto() or scopes.has_method(owner, node.method)) {
                return;
            }
            var key = owner.to_string();
            while (key.ends_with("*")) {
                key = key.substr_bytes(0, key.size - 1);
            }
            var methods = scopes.tables.generic_methods.try_get(key);
            if (!methods.is_value()) {
                return;
            }
            for (var (name, signature) in methods.value()) {
                if (name != written.name) {
                    continue;
                }
                var types = scopes.argument_types(node.args, current);
                var type_args = node.method.contains("<") ?
                    signature.complete(written.sub_types, types) :
                    signature.infer(types);
                if (type_args.is_value()) {
                    node.method = specialization(written.name, type_args.value());
                }
                return;
            }
            return;
        }
        if (!(e is FunctionCall(_))) {
            return;
        }
        var call = _function_call_of(e);
        if (call.function.contains("<")) {
            if (_starts_name(call.function)) {
                _complete_type_arguments(call);
            }
            return;
        }
        var signature = scopes.tables.generic_functions.try_get(call.function);
        if (!signature.is_value() or scopes.value_callee(call.function, current).is_value()) {
            return;
        }
        # Inside a method, a bare call may be one of the struct's methods.
        if (current.is_value()) {
            var st = current.value();
            if (scopes.calls_method(st, call.function, call.args.count)
                or scopes.field_type(st, call.function).is_value()) {
                return;
            }
        }
        var type_args = signature.value().infer(scopes.argument_types(call.args, current));
        if (type_args.is_value()) {
            call.function = specialization(call.function, type_args.value());
        }
    }

    ## A call writing only the leading type arguments takes the rest from
    ## its arguments (or their defaults).
    _complete_type_arguments(call: FunctionCallExpression) {
        var written = parse_type_string(call.function);
        var signature = scopes.tables.generic_functions.try_get(written.name);
        if (!signature.is_value()) {
            return;
        }
        if (written.sub_types.count >= signature.value().params.count
            or scopes.value_callee(written.name, current).is_value()) {
            return;
        }
        var type_args = signature.value().complete(written.sub_types, scopes.argument_types(call.args, current));
        if (type_args.is_value()) {
            call.function = specialization(written.name, type_args.value());
        }
    }
}

extend _ImplicitResolver with Rewriter;

_starts_name(text: String): bool {
    if (text.size == 0) {
        return false;
    }
    var b = text.bytes()[0];
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 or b >= 128;
}

_method_call_of(e: Expression): MethodCallExpression {
    if (e is MethodCall(node)) {
        return node;
    }
    return MethodCallExpression(Expression.ThisRef);
}

_function_call_of(e: Expression): FunctionCallExpression {
    if (e is FunctionCall(node)) {
        return node;
    }
    return FunctionCallExpression();
}

## Resolves `e`: its subjects, then each expression in it.
_resolve_expression(e: Expression, scopes: _TypeScopes, current: TypeName?): Expression {
    e = rewrite_expression(e, _SubjectFiller(scopes, current));
    e = rewrite_expression(e, _ImplicitResolver(scopes, current));
    return rewrite_expression(e, _SubjectFiller(scopes, current));
}

_resolve_block(block: Block, scopes: _TypeScopes, current: TypeName?) {
    ulong i = 0;
    while (i < block.items.count) {
        _resolve_statement(block, i, scopes, current);
        i += 1;
    }
}

_resolve_statement(block: Block, index: ulong, scopes: _TypeScopes, current: TypeName?) {
    match (block.items[index]) {
        Expression(e) => {
            block.items[index] = Statement.Expression(_resolve_expression(e, scopes, current));
        }
        Block(inner) => {
            scopes.push();
            _resolve_block(inner, scopes, current);
            scopes.pop();
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                # Resolve `auto` from the default value.
                if (variable.ty.is_auto() and variable.default.is_value()) {
                    var ty = scopes.type_of(variable.default.value(), current);
                    if (!ty.is_empty() and !ty.is_auto()) {
                        variable.ty = ty.copy();
                    }
                }
                if (variable.default.is_value()) {
                    variable.default = Optional<Expression>.Value(
                        _resolve_expression(variable.default.value(), scopes, current)
                    );
                }
                scopes.symbols[scopes.symbols.count - 1].append((variable.name, variable.ty));
            }
        }
        Branch(branch) => {
            branch.condition = _resolve_expression(branch.condition, scopes, current);
            scopes.push();
            _resolve_block(branch.if_block, scopes, current);
            scopes.pop();
            if (branch.else_block.is_value()) {
                scopes.push();
                _resolve_block(branch.else_block.value(), scopes, current);
                scopes.pop();
            }
        }
        While(loop) => {
            loop.condition = _resolve_expression(loop.condition, scopes, current);
            scopes.push();
            _resolve_block(loop.block, scopes, current);
            scopes.pop();
        }
        Return(r) => {
            if (r.expr.is_value()) {
                var value = _resolve_expression(r.expr.value(), scopes, current);
                r.expr = Optional<Expression>.Value(value);
                var ty = scopes.type_of(value, current);
                if (scopes.returns.is_value()) {
                    scopes.returns.value().append(ty);
                }
            }
        }
        else => {}
    }
}

## Default arguments are resolved in the declaring scope (no locals).
_resolve_parameter_defaults(parameters: VariableDef[], scopes: _TypeScopes, current: TypeName?) {
    for (var p in parameters) {
        if (p.default.is_value()) {
            p.default = Optional<Expression>.Value(_resolve_expression(p.default.value(), scopes, current));
        }
    }
}

## Whether `function`'s return type is inferred from its returns.
_infers_return(function: FunctionDef): bool {
    return function.ty.is_auto() and !function.is_generic_func;
}

## Gives `function` the type its returns agree on: `void` when it returns
## no value (`int` for the entry point), the first resolved return type
## otherwise. Returns whether the type changed.
_finish_return_inference(function: FunctionDef, scopes: _TypeScopes): bool {
    if (!scopes.returns.is_value()) {
        return false;
    }
    var returns = scopes.returns.value();
    scopes.returns = Optional<Array<TypeName>>.Empty;
    if (returns.count == 0) {
        bool entry = !function.parent.is_value() and (function.name == "main" or function.name == MAIN_WITH_ARGUMENTS);
        function.ty = TypeName.named(entry ? "int" : "void");
        return true;
    }
    for (var ty in returns) {
        if (!ty.is_empty() and !ty.is_auto()) {
            function.ty = ty.copy();
            return true;
        }
    }
    return false;
}

_returns_for(function: FunctionDef): Array<TypeName>? {
    return _infers_return(function) ?
        Optional<Array<TypeName>>.Value(Array<TypeName>()) :
        Optional<Array<TypeName>>.Empty;
}

## Walks `function`'s body in a scope of its own.
_resolve_body(function: FunctionDef, scopes: _TypeScopes, current: TypeName?) {
    scopes.function = function.name;
    scopes.function_loc = function.loc;
    scopes.push();
    scopes.params[scopes.params.count - 1] = function.parameters.copy();
    _resolve_block(function.body.value(), scopes, current);
    scopes.pop();
}

## One run of the pass; returns whether a function's return type was
## inferred or a call resolved.
_resolve_once(module: Module, state: PassState): bool {
    bool inferred = false;
    var tables = _ImplicitTables(module, state);
    var overloads = Overloads(module, state);
    var resolved = Array<(Loc, String)>();
    # Structs first: methods see field types.
    for (var st in module.structs) {
        var current = Optional<TypeName>.Value(st.ty);
        var scopes = _TypeScopes(tables, overloads, resolved, state);
        for (var p in st.generic_params) {
            scopes.unbound.append(p.name);
        }
        # A generic base (`Box` of `Box<T>`), not a specialization.
        scopes.generic_base = st.ty.is_generic() and st.name == st.ty.name;
        for (var field in st.field_members) {
            if (field.ty.is_auto() and field.default.is_value()) {
                var ty = scopes.type_of(field.default.value(), current);
                if (!ty.is_empty() and !ty.is_auto()) {
                    field.ty = ty.copy();
                }
            }
            # A default calling an overloaded constructor or function picks
            # its member.
            if (field.default.is_value()) {
                field.default = Optional<Expression>.Value(
                    rewrite_expression(field.default.value(), _OverloadOnly(scopes, current))
                );
            }
        }
        # Method bodies see this struct's resolved fields and its methods
        # in place of its table entries.
        var own_methods = Array<(String, TypeName)>();
        for (var m in st.method_members) {
            own_methods.append((m.name, m.ty));
        }
        scopes.own = Optional<_OwnStruct>.Value(_OwnStruct(st.ty.to_string(), st.field_members.copy(), own_methods));
        for (var c in st.constructors) {
            _resolve_parameter_defaults(c.parameters, scopes, current);
            if (c.body.is_value()) {
                scopes.in_constructor = true;
                _resolve_body(c, scopes, current);
                scopes.in_constructor = false;
            }
        }
        if (st.destructor.body.is_value()) {
            _resolve_body(st.destructor, scopes, current);
        }
        for (var method in st.method_members) {
            # A specialization's methods keep the base's name as parent.
            var method_struct = st.ty;
            if (method.parent.is_value() and method.parent.value() != st.ty.name) {
                var found = tables.struct_types.try_get(method.parent.value());
                if (found.is_value()) {
                    method_struct = found.value();
                }
            }
            var here = Optional<TypeName>.Value(method_struct);
            _resolve_parameter_defaults(method.parameters, scopes, here);
            scopes.returns = _returns_for(method);
            if (method.body.is_value()) {
                _resolve_body(method, scopes, here);
            } else {
                scopes.returns = Optional<Array<TypeName>>.Empty;
            }
            if (_finish_return_inference(method, scopes)) {
                inferred = true;
            }
        }
    }
    # Free functions.
    for (var function in module.functions) {
        if (!function.body.is_value()) {
            continue;
        }
        var none = Optional<TypeName>.Empty;
        var scopes = _TypeScopes(tables, overloads, resolved, state);
        for (var p in function.generic_params) {
            scopes.unbound.append(p.name);
        }
        scopes.generic_base = function.is_generic_func;
        var returns = _returns_for(function);
        _resolve_parameter_defaults(function.parameters, scopes, none);
        scopes.returns = returns;
        _resolve_body(function, scopes, none);
        if (_finish_return_inference(function, scopes)) {
            inferred = true;
        }
    }
    # Global variables: one shared scope so later globals see earlier ones.
    var scopes = _TypeScopes(tables, overloads, resolved, state);
    var none = Optional<TypeName>.Empty;
    for (var global in module.globals) {
        if (global.ty.is_auto() and global.default.is_value()) {
            var ty = scopes.type_of(global.default.value(), none);
            if (!ty.is_empty() and !ty.is_auto()) {
                global.ty = ty.copy();
            }
        }
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(_resolve_expression(global.default.value(), scopes, none));
        }
        scopes.symbols[0].append((global.name, global.ty));
    }
    if (resolved.count > 0) {
        inferred = true;
    }
    module.call_targets.append_all(resolved);
    return inferred;
}

## Resolves only the overloaded calls in a field's default.
struct _OverloadOnly {
    var resolver: _ImplicitResolver;

    construct(scopes: _TypeScopes, current: TypeName?) {
        resolver = _ImplicitResolver(scopes, current);
    }

    rewrite(e: Expression): Expression {
        resolver._resolve_overload(e);
        return e;
    }
}

extend _OverloadOnly with Rewriter;

## Resolves `auto` variable types, unresolved names, inferred return types
## and overloaded and generic calls, as
## `resolve_implicit_types::resolve_implicit_types` does.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_implicit_types(module: Module, state: PassState) {
    record_conformances(module, state);
    # Inferring a return type can type the callers' locals, and closure
    # types and inferred types feed each other: repeat while anything
    # changes, at most eight times.
    ulong round = 0;
    while (round < 8) {
        bool synced = sync_closures(module, state);
        # The binding passes share tables while none of them changes the
        # module.
        var tables = ModuleTables(module, state);
        bool bound = bind_function_values(module, state, tables);
        if (bound) {
            tables.reset();
        }
        bool specialized = bind_generic_function_values(module, state, tables);
        if (specialized) {
            tables.reset();
        }
        bool methods = bind_generic_method_values(module, state, tables);
        if (!_resolve_once(module, state) and !synced and !bound and !specialized and !methods) {
            break;
        }
        round += 1;
    }
    sync_closures(module, state);
}

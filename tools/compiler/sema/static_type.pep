## Static types: `pepper_sema::static_type` in Pepper. A table of the
## module's struct fields and methods, and `static_type_of`, which computes
## an expression's static type as well as it can. (A checked runtime's
## table is not consulted: these passes run over programs without one.)

import [binary_result, conditional_result, int_literal_type, is_numeric_type] from "arithmetic";
import [case_value_type, FieldTypes] from "enums";
import [BinaryOp, Expression, FunctionDef, Module, StructDef, TraitType, TypeName, UnaryOp] from "model";
import [set_name] from "names";
import [is_comparison, is_overflow_test, op_name, weak_result] from "operators";
import [PassState, TraitTypeMemo] from "state";
import [instance, trait_def, trait_types_of] from "traits";
import [labeled_tuple_literal_type, tuple_constructor_labels] from "tuple_literals";
import [parse_type_string] from "type_name";

## What a value of a struct (or trait) type has.
export struct StructInfo {
    ## Its fields and their types, in order.
    var fields: Array<(String, TypeName)> = Array<(String, TypeName)>();
    ## Its method names; an overloaded method also answers to its set's
    ## name.
    var methods: HashSet<String> = HashSet<String>();
    ## Method name to return type.
    var returns: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## The unary operators declared: `-`, `~`, `!`, `!!` as instance
    ## methods without parameters.
    var unary_operators: HashSet<String> = HashSet<String>();

    construct() {}

    ## Returns the type of field `name`, or none.
    field(name: String): TypeName? {
        for (var (f, ty) in fields) {
            if (f == name) {
                return Optional<TypeName>.Value(ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    _add_methods(methods: FunctionDef[]) {
        for (var m in methods) {
            this.methods.insert(m.name);
            this.methods.insert(set_name(m.name));
            returns[m.name] = m.ty;
            if (!m.is_static and m.parameters.count == 0) {
                var at = m.name.find("$");
                var base = at < 0 ? m.name : m.name.substr_bytes(0, at as ulong);
                if (base == "-" or base == "~" or base == "!" or base == "!!") {
                    unary_operators.insert(base);
                }
            }
        }
    }
}

_struct_info(st: StructDef): StructInfo {
    var info = StructInfo();
    for (var f in st.field_members) {
        info.fields.append((f.name, f.ty));
    }
    info._add_methods(st.method_members);
    return info;
}

## The spelling of `st`'s type and its `StructTable` entry: a checked
## struct's from `memo` while its fields and methods stay the same, since
## its fields' types were final when it was checked.
_named_info(module: Module, st: StructDef, memo: TraitTypeMemo?): (String, StructInfo) {
    if (!memo.is_value() or !module.checked.structs.contains(st.name)) {
        return (st.ty.to_string(), _struct_info(st));
    }
    var fields = st.field_members.count;
    var methods = st.method_members.count;
    var kept = memo.value().infos.try_get(st.name);
    if (kept.is_value()) {
        var (kept_fields, kept_methods, name, info) = kept.value();
        if (kept_fields == fields and kept_methods == methods) {
            return (name, info);
        }
    }
    var name = st.ty.to_string();
    var info = _struct_info(st);
    memo.value().infos[st.name] = (fields, methods, name, info);
    return (name, info);
}

_trait_info(t: TraitType): StructInfo {
    var info = StructInfo();
    info._add_methods(t.methods);
    return info;
}

## The structs (and trait types) and functions of a module, for static
## types.
export struct StructTable {
    var structs: HashMap<String, StructInfo> = HashMap<String, StructInfo>();
    ## Free-function and extern name to return type.
    var functions: HashMap<String, TypeName> = HashMap<String, TypeName>();

    ## Returns the table of `module`.
    ##
    ## @param module the model
    ## @param trait_types the module's trait types, when already found
    ## @param memo what earlier passes found of the trait types in the
    ##     checked declarations (`PassState.trait_memo`)
    construct(
        module: Module,
        trait_types: TypeName[]? = Optional<TypeName[]>.Empty,
        memo: TraitTypeMemo? = Optional<TraitTypeMemo>.Empty
    ) {
        for (var st in module.structs) {
            var (name, info) = _named_info(module, st, memo);
            # Also key the generic base (`Array<T>` as `Array`) so lookups
            # before specialization resolve; never clobber a concrete entry.
            if (name != st.ty.name and !structs.contains(st.ty.name)) {
                structs[st.ty.name] = info;
            }
            structs[name] = info;
        }
        # Traits used as types: the specialized instances first, then each
        # base.
        for (var ty in trait_types_of(module, trait_types, memo)) {
            var def = trait_def(module.traits, ty);
            if (def.is_value() and !structs.contains(ty.to_string())) {
                structs[ty.to_string()] = _trait_info(instance(def.value(), ty));
            }
        }
        for (var def in module.traits) {
            if (!structs.contains(def.name)) {
                structs[def.name] = _trait_info(instance(def, TypeName.named(def.name)));
            }
        }
        for (var f in module.functions) {
            functions[f.name] = f.ty;
        }
        for (var e in module.externs) {
            functions[e.name] = e.ty;
        }
    }

    ## Returns the return type of free function or extern `name`.
    function(name: String): TypeName? {
        return functions.try_get(name);
    }

    ## Returns the struct info filed under `name`.
    get(name: String): StructInfo? {
        return structs.try_get(name);
    }

    ## Returns the struct info for a type: the exact specialization first
    ## (`Array<int>`), then the generic base (`Array`).
    lookup(ty: TypeName): StructInfo? {
        var text = ty.to_string();
        var exact = structs.try_get(text);
        if (exact.is_value()) {
            return exact;
        }
        var at = text.find("<");
        return structs.try_get(at < 0 ? text : text.substr_bytes(0, at as ulong));
    }
}

## The fields of the struct a `match` subject's type names.
struct _TableFields {
    var info: StructInfo?;

    construct(info: StructInfo?) {
        this.info = info;
    }

    field(name: String): TypeName? {
        return info.is_value() ? info.value().field(name) : Optional<TypeName>.Empty;
    }
}

extend _TableFields with FieldTypes;

_known(ty: TypeName): TypeName? {
    return Optional<TypeName>.Value(ty);
}

## Returns the static type of `e` as well as it can be told, or none, as
## `static_type::of` does.
##
## @param e the expression
## @param table the module's struct table
## @param current the struct whose code `e` is in, if any
## @param state the passes' state
## @returns the type
export static_type_of(e: Expression, table: StructTable, current: TypeName?, state: PassState): TypeName? {
    var none = Optional<TypeName>.Empty;
    match (e) {
        SymbolRef(node) => {
            return node.ty.is_empty() or node.ty.is_auto() ? none : _known(node.ty);
        }
        ThisRef => {
            return current;
        }
        StringLiteral(node) => {
            return _known(TypeName.named(node.is_raw ? "char*" : "String"));
        }
        StaticString(_) => {
            return _known(TypeName.named("String"));
        }
        PointerLiteral => {
            return _known(TypeName.void_pointer());
        }
        BoolLiteral(_) => {
            return _known(TypeName.boolean());
        }
        IntLiteral(value) => {
            return _known(TypeName.named(int_literal_type(value)));
        }
        FloatLiteral(_) => {
            return _known(TypeName.named("f64"));
        }
        Destructure(node) => {
            return static_type_of(node.value, table, current, state);
        }
        Move(node) => {
            return static_type_of(node.value, table, current, state);
        }
        StaticCase(node) => {
            return _known(node.ty);
        }
        Subject(node) => {
            return node.ty.is_auto() ? none : _known(node.ty);
        }
        WithSubject(scoped) => {
            return static_type_of(scoped.body, table, current, state);
        }
        MatchArm(_) => {
            return _known(TypeName.boolean());
        }
        CaseValue(value) => {
            var subject = static_type_of(value.subject, table, current, state);
            if (!subject.is_value()) {
                return none;
            }
            var result = case_value_type(state, value, subject.value(), _TableFields(table.lookup(subject.value())));
            if (result is Ok(ty)) {
                return ty;
            }
            return none;
        }
        MemberRef(node) => {
            var lhs = static_type_of(node.lhs, table, current, state);
            if (lhs.is_value()) {
                var element = lhs.value().tuple_element(node.name);
                if (element.is_value()) {
                    return element;
                }
            }
            # Specialized clones keep unsubstituted annotations on bare
            # symbols, so both the annotation and the enclosing struct's
            # field table are tried; a pointer's exact pointee first.
            var candidates = Array<TypeName>();
            if (lhs.is_value()) {
                candidates.append(lhs.value());
            }
            if (node.lhs is SymbolRef(symbol)) {
                if (current.is_value()) {
                    var info = table.lookup(current.value());
                    if (info.is_value()) {
                        var field = info.value().field(symbol.id);
                        if (field.is_value()) {
                            candidates.append(field.value());
                        }
                    }
                }
            }
            for (var lhs_type in candidates) {
                var keys = Array<TypeName>();
                var text = lhs_type.to_string();
                if (text.ends_with("*")) {
                    keys.append(TypeName.named(text.substr_bytes(0, text.size - 1)));
                }
                keys.append(lhs_type);
                for (var key in keys) {
                    var info = table.lookup(key);
                    if (info.is_value()) {
                        var field = info.value().field(node.name);
                        if (field.is_value()) {
                            return field;
                        }
                    }
                }
            }
            return none;
        }
        MethodCall(node) => {
            var this_type = static_type_of(node.this_value, table, current, state);
            if (!this_type.is_value()) {
                return none;
            }
            var info = table.lookup(this_type.value());
            return info.is_value() ? info.value().returns.try_get(node.method) : none;
        }
        Weak(op, ty, _) => {
            return _known(weak_result(op, ty));
        }
        Allocate(ty) => {
            return _known(ty);
        }
        CountStep(_) => {
            return _known(TypeName.named("u32"));
        }
        FunctionPointer(_) => {
            return _known(TypeName.named("void*"));
        }
        ForIterator(source) => {
            var source_type = static_type_of(source, table, current, state);
            if (!source_type.is_value()) {
                return none;
            }
            var info = table.lookup(source_type.value());
            if (!info.is_value()) {
                return none;
            }
            var iterator = info.value().returns.try_get("iterate");
            return iterator.is_value() ? iterator : source_type;
        }
        Index(node) => {
            var lhs = static_type_of(node.lhs, table, current, state);
            if (!lhs.is_value()) {
                return none;
            }
            # A pointer receiver indexes raw: the element is the pointee.
            var text = lhs.value().to_string();
            if (text.ends_with("*")) {
                return _known(parse_type_string(text.substr_bytes(0, text.size - 1)));
            }
            var info = table.lookup(lhs.value());
            return info.is_value() ? info.value().returns.try_get("__index_get") : none;
        }
        ArrayIndex(node) => {
            if (!node.ty.is_auto()) {
                return _known(node.ty);
            }
            var lhs = static_type_of(node.lhs, table, current, state);
            if (!lhs.is_value()) {
                return none;
            }
            var text = lhs.value().to_string();
            return text.ends_with("*") ? _known(parse_type_string(text.substr_bytes(0, text.size - 1))) : none;
        }
        FunctionCall(node) => {
            if (tuple_constructor_labels(node.function).is_value()) {
                var types = Array<TypeName>();
                for (var a in node.args) {
                    var t = static_type_of(a, table, current, state);
                    types.append(t.is_value() ? t.value() : TypeName.auto());
                }
                return labeled_tuple_literal_type(node.function, types);
            }
            if (node.function.starts_with("__tuple<")) {
                return _known(parse_type_string(node.function));
            }
            var declared = table.function(node.function);
            if (declared.is_value()) {
                return declared;
            }
            # A constructor-style call `Name<...>(...)`, or one of several
            # overloaded constructors (`Name$2`).
            var name = node.function;
            var dollar = name.rfind("$");
            if (dollar >= 0) {
                var index = name.substr_bytes(dollar as ulong + 1, name.size - dollar as ulong - 1);
                bool digits = index.size > 0;
                for (var b in index.bytes()) {
                    if (b < 48 or b > 57) {
                        digits = false;
                    }
                }
                if (digits) {
                    name = name.substr_bytes(0, dollar as ulong);
                }
            }
            var ty = parse_type_string(name);
            return table.lookup(ty).is_value() ? _known(ty) : none;
        }
        Binary(node) => {
            if (_is_assignment(node.op)) {
                return static_type_of(node.lhs, table, current, state);
            }
            if (is_comparison(node.op)
                or is_overflow_test(node.op)
                or node.op == BinaryOp.LogicalAnd
                or node.op == BinaryOp.LogicalOr) {
                return _known(TypeName.boolean());
            }
            var lhs = static_type_of(node.lhs, table, current, state);
            if (!lhs.is_value()) {
                return none;
            }
            var info = table.lookup(lhs.value());
            if (info.is_value()) {
                var ret = info.value().returns.try_get(op_name(node.op));
                if (ret.is_value()) {
                    return ret;
                }
            }
            var rhs = static_type_of(node.rhs, table, current, state);
            var promoted = binary_result(
                state, node.op, lhs.value().to_string(), rhs.is_value() ? rhs.value().to_string() : ""
            );
            return promoted.is_value() ? _known(TypeName.named(promoted.value())) : lhs;
        }
        Ternary(node) => {
            var true_type = static_type_of(node.true_expr, table, current, state);
            if (!true_type.is_value()) {
                return none;
            }
            var false_type = static_type_of(node.false_expr, table, current, state);
            if (false_type.is_value()) {
                var a = true_type.value().to_string();
                var b = false_type.value().to_string();
                if (is_numeric_type(state, a) and is_numeric_type(state, b)) {
                    return _known(TypeName.named(conditional_result(state, a, b)));
                }
            }
            return true_type;
        }
        Unary(node) => {
            if (node.op == UnaryOp.LogicalNot) {
                return _known(TypeName.boolean());
            }
            if (node.op == UnaryOp.Neg or node.op == UnaryOp.BitNot) {
                return static_type_of(node.operand, table, current, state);
            }
            return none;
        }
        Cast(node) => {
            return _known(node.ty);
        }
        Default(ty) => {
            return _known(ty);
        }
        IsPod(_) => {
            return _known(TypeName.boolean());
        }
        SizeOf(_) => {
            return _known(TypeName.named("u64"));
        }
        FunctionRef(node) => {
            return _known(node.ty);
        }
        MakeClosure(node) => {
            return node.ty.contains_auto() ? none : _known(node.ty);
        }
        ToTrait(node) => {
            return _known(node.to);
        }
        FromTrait(node) => {
            return _known(node.test ? TypeName.boolean() : node.to);
        }
        Invoke(node) => {
            var callee = static_type_of(node.callee, table, current, state);
            return callee.is_value() ? callee.value().function_return() : none;
        }
        else => {
            return none;
        }
    }
}

## Static types. A table of the
## module's struct fields and methods, and `static_type_of`, which computes
## an expression's static type as well as it can. (A checked runtime's
## table is not consulted: these passes run over programs without one.)

import [binary_result, conditional_result, int_literal_type, is_numeric_type] from "arithmetic";
import "closures";
import [case_value_type, FieldTypes] from "enums";
import [param_names] from "generics";
import [
    BinaryOp, Expression, FunctionCallExpression, FunctionDef, Module, StructDef, TraitType, TypeName, UnaryOp
] from "model";
import [is_comparison, is_overflow_test, op_name, weak_result] from "operators";
import [PassMemo, PassState, TraitTypeMemo] from "state";
import [StructInfo] from "struct_info";
import [instance, trait_def, trait_types_of] from "traits";
import [labeled_tuple_literal_type, tuple_constructor_labels] from "tuple_literals";
import [parse_type_string, replace_map] from "type_name";

_struct_info(st: StructDef): StructInfo {
    var info = StructInfo();
    for (var f in st.field_members) {
        info.fields.append((f.name, f.ty));
    }
    info._add_methods(st.method_members);
    info.generic_methods = st.generic_methods;
    for (var p in st.generic_params) {
        info.params.append(p.name);
    }
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

# The memo's table of `module`'s checked declarations, built again when
# the checked declarations have grown since, a checked struct's fields or
# methods have (a generic method specialized for it, say), or
# `apply_extensions` dropped it.
_checked_table(module: Module, memo: TraitTypeMemo): StructTable {
    ulong fields = 0;
    ulong methods = 0;
    for (var st in module.structs) {
        if (module.checked.structs.contains(st.name)) {
            fields += st.field_members.count;
            methods += st.method_members.count;
        }
    }
    var counts = (module.checked.structs.count as ulong, module.checked.functions.count as ulong, fields, methods);
    var kept = memo.checked_table.is_value() ? memo.checked_table.value() as? StructTable : Optional<StructTable>.Empty;
    if (!kept.is_value() or memo.checked_counts != counts) {
        var table = StructTable._checked(module, memo);
        memo.checked_table = Optional<PassMemo>.Value(table);
        memo.checked_counts = counts;
        return table;
    }
    return kept.value();
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
    ## Generic declaration's name to its entry, whose types are written in
    ## its own parameters (`Box` to `Box<T>`'s).
    var generics: HashMap<String, StructInfo> = HashMap<String, StructInfo>();
    ## Generic function's name to its declaration.
    var generic_functions: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    # With a memo, the checked declarations' table, shared by the passes:
    # this one holds the rest and looks there for what it lacks.
    var _base: StructTable? = Optional<StructTable>.Empty;

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
        if (memo.is_value()) {
            _base = Optional<StructTable>.Value(_checked_table(module, memo.value()));
        }
        bool shared = _base.is_value();
        for (var st in module.structs) {
            if (shared and module.checked.structs.contains(st.name)) {
                continue;
            }
            _add_struct(module, st, memo);
        }
        # Traits used as types: the specialized instances first, then each
        # base.
        for (var ty in trait_types_of(module, trait_types, memo)) {
            var def = trait_def(module.traits, ty);
            if (def.is_value() and !_has(ty.to_string())) {
                structs[ty.to_string()] = _trait_info(instance(def.value(), ty));
            }
        }
        for (var def in module.traits) {
            if (!_has(def.name)) {
                var info = _trait_info(instance(def, TypeName.named(def.name)));
                structs[def.name] = info;
                if (def.generic_params.count > 0) {
                    info.params = param_names(def.generic_params);
                    generics[def.name] = info;
                }
            }
        }
        for (var f in module.functions) {
            if (shared and module.checked.functions.contains(f.name)) {
                continue;
            }
            if (f.generic_params.count > 0) {
                generic_functions[f.name] = f;
            }
            if (!_returns_own_parameter(f)) {
                functions[f.name] = f.ty;
            }
        }
        for (var e in module.externs) {
            functions[e.name] = e.ty;
        }
    }

    # The table of `module`'s checked structs and functions alone.
    static _checked(module: Module, memo: TraitTypeMemo): StructTable {
        var out = StructTable._empty();
        for (var st in module.structs) {
            if (module.checked.structs.contains(st.name)) {
                out._add_struct(module, st, Optional<TraitTypeMemo>.Value(memo));
            }
        }
        for (var f in module.functions) {
            if (!module.checked.functions.contains(f.name)) {
                continue;
            }
            if (f.generic_params.count > 0) {
                out.generic_functions[f.name] = f;
            }
            if (!_returns_own_parameter(f)) {
                out.functions[f.name] = f.ty;
            }
        }
        return out;
    }

    # An empty table.
    static _empty(): StructTable {
        return StructTable(Module(), memo = Optional<TraitTypeMemo>.Empty);
    }

    # Files `st` under its spelled type and, for a specialization, also
    # under its generic base (`Array<T>` as `Array`) so lookups before
    # specialization resolve; never clobbering a concrete entry.
    _add_struct(module: Module, st: StructDef, memo: TraitTypeMemo?) {
        var (name, info) = _named_info(module, st, memo);
        if (name != st.ty.name and !_has(st.ty.name)) {
            structs[st.ty.name] = info;
        }
        structs[name] = info;
        if (st.generic_params.count > 0 and st.name == st.ty.name) {
            generics[st.name] = info;
        }
    }

    # Whether this table, or the checked one under it, files `name`.
    _has(name: String): bool {
        return structs.contains(name) or (_base.is_value() and _base.value().structs.contains(name));
    }

    ## Returns the return type of free function or extern `name`.
    function(name: String): TypeName? {
        var own = functions.try_get(name);
        if (own.is_value() or !_base.is_value()) {
            return own;
        }
        return _base.value().functions.try_get(name);
    }

    ## Returns `field`, the type of field `name` of `receiver`'s
    ## specialization, labeled as `receiver`'s type arguments are
    ## (`TypeName.labeled_through`).
    ##
    ## @param field the field's type in the specialization
    ## @param receiver the type the field is read through
    ## @param name the field's name
    ## @returns the type, labeled
    labeled_field(field: TypeName, receiver: TypeName, name: String): TypeName {
        var generic = _generic(receiver);
        var declared = generic.is_value() ? generic.value().field(name) : Optional<TypeName>.Empty;
        return declared.is_value() ? field.labeled_through(receiver, declared.value(), generic.value().params) : field;
    }

    # `ret`, what method `name` of `receiver`'s specialization returns,
    # labeled as `receiver`'s type arguments are.
    _labeled_return(ret: TypeName, receiver: TypeName, name: String): TypeName {
        var generic = _generic(receiver);
        var declared = generic.is_value() ? generic.value().returns.try_get(name) : Optional<TypeName>.Empty;
        return declared.is_value() ? ret.labeled_through(receiver, declared.value(), generic.value().params) : ret;
    }

    ## Returns `ty`, the type of a call written with labeled type
    ## arguments `labeled` (`FunctionCallExpression.labeled`), with their
    ## labels: a generic function's declared result with them put in
    ## (`TypeName.labeled_through`), else the type as written
    ## (`TypeName.as_written`).
    ##
    ## @param ty the call's type, unlabeled
    ## @param labeled the type the call is written with, if it has labels
    ## @returns the type, labeled
    labeled_call(ty: TypeName, labeled: TypeName?): TypeName {
        if (!labeled.is_value()) {
            return ty;
        }
        var name = labeled.value().name;
        var own = generic_functions.try_get(name);
        var generic = own.is_value() or !_base.is_value() ? own : _base.value().generic_functions.try_get(name);
        if (generic.is_value()) {
            return ty.labeled_through(labeled.value(), generic.value().ty, param_names(generic.value().generic_params));
        }
        return ty.as_written(labeled);
    }

    ## Returns `ret`, what a generic method call of `receiver` written with
    ## labeled type arguments `labeled` (`MethodCallExpression.labeled`)
    ## returns, with their labels: the method's declared result with them
    ## put in (`TypeName.labeled_through`).
    ##
    ## @param ret the call's type, unlabeled
    ## @param receiver the receiver's type
    ## @param labeled the method as written, if its type arguments have labels
    ## @returns the type, labeled
    labeled_method_call(ret: TypeName, receiver: TypeName, labeled: TypeName?): TypeName {
        if (!labeled.is_value()) {
            return ret;
        }
        var info = lookup(receiver.without_pointers());
        if (info.is_value()) {
            for (var m in info.value().generic_methods) {
                if (m.name == labeled.value().name) {
                    return ret.labeled_through(labeled.value(), m.ty, param_names(m.generic_params));
                }
            }
        }
        return ret;
    }

    # The entry of `receiver`'s generic declaration when its type arguments
    # have labels to give back; most receivers have none.
    _generic(receiver: TypeName): StructInfo? {
        if (!receiver.labels_arguments()) {
            return Optional<StructInfo>.Empty;
        }
        var own = generics.try_get(receiver.name);
        if (own.is_value() or !_base.is_value()) {
            return own;
        }
        return _base.value().generics.try_get(receiver.name);
    }

    ## Returns the struct info filed under `name`.
    get(name: String): StructInfo? {
        var own = structs.try_get(name);
        if (own.is_value() or !_base.is_value()) {
            return own;
        }
        return _base.value().structs.try_get(name);
    }

    ## Returns the struct info for a type: the exact specialization first
    ## (`Array<int>`), then the generic base (`Array`).
    lookup(ty: TypeName): StructInfo? {
        var text = ty.to_string();
        var exact = get(text);
        if (exact.is_value()) {
            return exact;
        }
        var at = text.find("<");
        return get(at < 0 ? text : text.substr_bytes(0, at as ulong));
    }

    ## Returns the return type of method `name` of type `ty`. When only the
    ## generic base is filed, its own parameters are replaced by `ty`'s type
    ## arguments: `_literal_append` of `Array<int>` returns `Array<int>`,
    ## not the base's `Array<T>`.
    ##
    ## @param ty the receiver's type
    ## @param name the method's name
    ## @returns the return type, or none
    method_return(ty: TypeName, name: String): TypeName? {
        var info = lookup(ty);
        if (!info.is_value()) {
            return Optional<TypeName>.Empty;
        }
        var ret = info.value().returns.try_get(name);
        var params = info.value().params;
        if (!ret.is_value()) {
            return ret;
        }
        if (params.count == 0 or params.count != ty.sub_types.count) {
            return Optional<TypeName>.Value(_labeled_return(ret.value(), ty, name));
        }
        var type_map = Array<(String, TypeName)>();
        for (var i in 0..params.count) {
            type_map.append((params[i], ty.sub_types[i]));
        }
        var out = ret.value().copy();
        replace_map(out, type_map);
        return Optional<TypeName>.Value(out);
    }
}

extend StructTable with PassMemo;

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

# Whether `f` is generic and its return type names one of its own type
# parameters (`_array_literal<T>(first: T): Array<T>`). A call to it has no
# static type until its type arguments are inferred: that `T` is not the
# caller's.
_returns_own_parameter(f: FunctionDef): bool {
    for (var p in f.generic_params) {
        if (f.ty.mentions(p.name)) {
            return true;
        }
    }
    return false;
}

_known(ty: TypeName): TypeName? {
    return Optional<TypeName>.Value(ty);
}

# The type of call `node`, before the labels it is written with.
_call_type(node: FunctionCallExpression, table: StructTable, current: TypeName?, state: PassState): TypeName? {
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
    return table.lookup(ty).is_value() ? _known(ty) : Optional<TypeName>.Empty;
}

## Returns the static type of `e` as well as it can be told, or none.
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
            return _known(node.is_raw ? TypeName.pointer_to(TypeName.named("char")) : TypeName.named("String"));
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
                var pointee = lhs_type.pointee();
                if (pointee.is_value()) {
                    keys.append(pointee.value());
                }
                keys.append(lhs_type);
                for (var key in keys) {
                    var info = table.lookup(key);
                    if (info.is_value()) {
                        var field = info.value().field(node.name);
                        if (field.is_value()) {
                            return _known(table.labeled_field(field.value(), key, node.name));
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
            var ret = table.method_return(this_type.value(), node.method);
            return ret.is_value() ?
                _known(table.labeled_method_call(ret.value(), this_type.value(), node.labeled)) :
                ret;
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
            return _known(TypeName.void_pointer());
        }
        ForIterator(source) => {
            var source_type = static_type_of(source, table, current, state);
            if (!source_type.is_value()) {
                return none;
            }
            if (!table.lookup(source_type.value()).is_value()) {
                return none;
            }
            var iterator = table.method_return(source_type.value(), "iterate");
            return iterator.is_value() ? iterator : source_type;
        }
        Index(node) => {
            var lhs = static_type_of(node.lhs, table, current, state);
            if (!lhs.is_value()) {
                return none;
            }
            # A pointer receiver indexes raw: the element is the pointee.
            var pointee = lhs.value().pointee();
            if (pointee.is_value()) {
                return _known(pointee.value().copy());
            }
            return table.method_return(lhs.value(), "__index_get");
        }
        ArrayIndex(node) => {
            if (!node.ty.is_auto()) {
                return _known(node.ty);
            }
            var lhs = static_type_of(node.lhs, table, current, state);
            if (!lhs.is_value()) {
                return none;
            }
            var pointee = lhs.value().pointee();
            return pointee.is_value() ? _known(pointee.value().copy()) : none;
        }
        FunctionCall(node) => {
            var ty = _call_type(node, table, current, state);
            return ty.is_value() ? _known(table.labeled_call(ty.value(), node.labeled)) : ty;
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
            var ret = table.method_return(lhs.value(), op_name(node.op));
            if (ret.is_value()) {
                return ret;
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

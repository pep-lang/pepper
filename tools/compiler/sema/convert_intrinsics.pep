## The compiler's intrinsics: `pepper_sema::passes::convert_intrinsics` in
## Pepper. `__ptr<T>` types become `T*`, and calls such as `__is_pod<T>()`,
## `__address<T>(v)`, the atomics, the weak-reference operations and
## `__simd_<op>` become the intrinsic nodes codegen lowers;
## `__function_pointer(f)` becomes a `FunctionPointer`.

import [Diagnostic] from compiler.diagnostic;
import [error_at] from "common";
import [Loc] from "loc";
import [
    AtomicFetchOp,
    Block,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    FunctionPointerExpression,
    Module,
    SimdExpression,
    SimdOp,
    Statement,
    StructDef,
    TypeName,
    WeakOp
] from "model";
import [PassState] from "state";
import "static_blocks";
import [parse_type_string] from "type_name";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Every SIMD operation, with the name after `__simd_` that calls it.
_simd_operations(): Array<(SimdOp, String)> {
    return [
        (SimdOp.Splat, "splat"),
        (SimdOp.Add, "add"),
        (SimdOp.Subtract, "subtract"),
        (SimdOp.Multiply, "multiply"),
        (SimdOp.Divide, "divide"),
        (SimdOp.Remainder, "remainder"),
        (SimdOp.And, "and"),
        (SimdOp.Or, "or"),
        (SimdOp.Xor, "xor"),
        (SimdOp.ShiftLeft, "shift_left"),
        (SimdOp.ShiftRight, "shift_right"),
        (SimdOp.Negate, "negate"),
        (SimdOp.Not, "not"),
        (SimdOp.Equal, "equal"),
        (SimdOp.NotEqual, "not_equal"),
        (SimdOp.Less, "less"),
        (SimdOp.LessEqual, "less_equal"),
        (SimdOp.Greater, "greater"),
        (SimdOp.GreaterEqual, "greater_equal"),
        (SimdOp.Select, "select"),
        (SimdOp.Minimum, "minimum"),
        (SimdOp.Maximum, "maximum"),
        (SimdOp.Abs, "abs"),
        (SimdOp.RotateLeft, "rotate_left"),
        (SimdOp.RotateRight, "rotate_right"),
        (SimdOp.SquareRoot, "square_root"),
        (SimdOp.Floor, "floor"),
        (SimdOp.Ceiling, "ceiling"),
        (SimdOp.Sum, "sum"),
        (SimdOp.ReduceMinimum, "reduce_minimum"),
        (SimdOp.ReduceMaximum, "reduce_maximum"),
        (SimdOp.Any, "any"),
        (SimdOp.All, "all"),
        (SimdOp.ToBits, "to_bits"),
        (SimdOp.Extract, "extract"),
        (SimdOp.Insert, "insert"),
        (SimdOp.Shuffle, "shuffle"),
        (SimdOp.Reverse, "reverse"),
        (SimdOp.InterleaveLow, "interleave_low"),
        (SimdOp.InterleaveHigh, "interleave_high"),
        (SimdOp.Load, "load"),
        (SimdOp.LoadAligned, "load_aligned"),
        (SimdOp.Store, "store"),
        (SimdOp.StoreAligned, "store_aligned"),
        (SimdOp.Convert, "convert"),
        (SimdOp.Reinterpret, "reinterpret"),
        (SimdOp.Lanes, "lanes"),
        (SimdOp.LaneBits, "lane_bits"),
        (SimdOp.IsSigned, "is_signed")
    ];
}

## How many arguments SIMD operation `op` takes.
_simd_arity(op: SimdOp): ulong {
    if (op == SimdOp.IsSigned or op == SimdOp.LaneBits or op == SimdOp.Lanes) {
        return 0;
    }
    if (op == SimdOp.Abs
        or op == SimdOp.All
        or op == SimdOp.Any
        or op == SimdOp.Ceiling
        or op == SimdOp.Convert
        or op == SimdOp.Floor
        or op == SimdOp.Load
        or op == SimdOp.LoadAligned
        or op == SimdOp.Negate
        or op == SimdOp.Not
        or op == SimdOp.ReduceMaximum
        or op == SimdOp.ReduceMinimum
        or op == SimdOp.Reinterpret
        or op == SimdOp.Reverse
        or op == SimdOp.Splat
        or op == SimdOp.SquareRoot
        or op == SimdOp.Sum
        or op == SimdOp.ToBits) {
        return 1;
    }
    if (op == SimdOp.Insert or op == SimdOp.Select) {
        return 3;
    }
    return 2;
}

## `ty` with each `__ptr<T>` written `T*`, inner first, so `__ptr<__ptr<int>>`
## is `int**` and `Array<__ptr<char>>` is `Array<char*>`.
_convert_pointer_type(ty: TypeName, state: PassState) {
    for (var sub in ty.sub_types) {
        _convert_pointer_type(sub, state);
    }
    if (ty.name == "__ptr") {
        if (ty.sub_types.count != 1) {
            state.report(
                Diagnostic.error(
                    $"__ptr<T> takes exactly one type argument, {ty.sub_types.count} given in '{ty.to_string()}'"
                )
            );
            return;
        }
        var pointee = ty.sub_types[0].to_string();
        var converted = TypeName.named($"{pointee}*");
        ty.name = converted.name;
        ty.sub_types = converted.sub_types;
        ty.flags = converted.flags;
        ty.labels = converted.labels;
    }
}

## Converts the types an expression node carries.
_convert_node_types(e: Expression, state: PassState) {
    match (e) {
        Cast(node) => {
            _convert_pointer_type(node.ty, state);
        }
        SizeOf(ty) => {
            _convert_pointer_type(ty, state);
        }
        IsPod(ty) => {
            _convert_pointer_type(ty, state);
        }
        Default(ty) => {
            _convert_pointer_type(ty, state);
        }
        StaticCase(node) => {
            _convert_pointer_type(node.ty, state);
        }
        Subject(node) => {
            _convert_pointer_type(node.ty, state);
        }
        Allocate(ty) => {
            _convert_pointer_type(ty, state);
        }
        RefCount(ty, _) => {
            _convert_pointer_type(ty, state);
        }
        Address(ty, _) => {
            _convert_pointer_type(ty, state);
        }
        Weak(_, ty, _) => {
            _convert_pointer_type(ty, state);
        }
        AtomicLoad(ty, _) => {
            _convert_pointer_type(ty, state);
        }
        AtomicStore(ty, _, _) => {
            _convert_pointer_type(ty, state);
        }
        AtomicCmpXchg(ty, _, _, _) => {
            _convert_pointer_type(ty, state);
        }
        AtomicFetch(_, ty, _, _) => {
            _convert_pointer_type(ty, state);
        }
        Simd(node) => {
            _convert_pointer_type(node.ty, state);
        }
        else => {}
    }
}

## The type argument a call spells (`T` of `__address<T>`), else its name.
_intrinsic_type(function: String): TypeName {
    var parsed = parse_type_string(function);
    if (parsed.sub_types.count > 0) {
        return parsed.sub_types[0];
    }
    return TypeName.named(parsed.name);
}

struct _IntrinsicConverter {
    var state: PassState;

    construct(state: PassState) {
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        _convert_node_types(e, state);
        if (e is FunctionCall(node)) {
            var out = _convert_call(node.function, node.args, node.loc);
            if (out.is_value()) {
                # The intrinsic node the call became.
                _convert_node_types(out.value(), state);
                return out.value();
            }
        }
        return e;
    }

    _convert_call(function: String, args: Expression[], loc: Loc): Expression? {
        var none = Optional<Expression>.Empty;
        var at = function.find("<");
        var base = at < 0 ? function : function.substr_bytes(0, at as ulong);
        if (base == "__is_pod" or base == "__default") {
            # The inner type, so later specialization passes can substitute
            # generic parameters.
            var ty = _intrinsic_type(function);
            return Optional<Expression>.Value(base == "__is_pod" ? Expression.IsPod(ty) : Expression.Default(ty));
        }
        if (base == "__refcount" and args.count == 1) {
            return Optional<Expression>.Value(Expression.RefCount(_intrinsic_type(function), args[0]));
        }
        for (var (
            op, name
        ) in [(WeakOp.From, "__weak_from"), (WeakOp.Upgrade, "__weak_upgrade"), (WeakOp.Expired, "__weak_expired")]) {
            if (base == name and args.count == 1) {
                return Optional<Expression>.Value(Expression.Weak(op, _intrinsic_type(function), args[0]));
            }
        }
        if (base == "__address" and args.count == 1) {
            return Optional<Expression>.Value(Expression.Address(_intrinsic_type(function), args[0]));
        }
        if (base == "__atomic_load" and args.count == 1) {
            return Optional<Expression>.Value(Expression.AtomicLoad(_intrinsic_type(function), args[0]));
        }
        if (base == "__atomic_store" and args.count == 2) {
            return Optional<Expression>.Value(Expression.AtomicStore(_intrinsic_type(function), args[0], args[1]));
        }
        if (base == "__construct_at" and args.count == 2) {
            return Optional<Expression>.Value(Expression.ConstructAt(args[0], args[1]));
        }
        if (base == "__atomic_cmpxchg" and args.count == 3) {
            return Optional<Expression>.Value(
                Expression.AtomicCmpXchg(_intrinsic_type(function), args[0], args[1], args[2])
            );
        }
        var fetch = "__atomic_fetch_";
        if (base.starts_with(fetch) and args.count == 2) {
            var which = base.substr_bytes(fetch.size, base.size - fetch.size);
            for (var (
                op,
                name
            ) in [
                (AtomicFetchOp.Add, "add"),
                (AtomicFetchOp.Sub, "sub"),
                (AtomicFetchOp.And, "and"),
                (AtomicFetchOp.Or, "or"),
                (AtomicFetchOp.Xor, "xor")
            ]) {
                if (which == name) {
                    return Optional<Expression>.Value(
                        Expression.AtomicFetch(op, _intrinsic_type(function), args[0], args[1])
                    );
                }
            }
            return none;
        }
        var simd = "__simd_";
        if (base.starts_with(simd)) {
            var which = base.substr_bytes(simd.size, base.size - simd.size);
            for (var (op, name) in _simd_operations()) {
                if (which != name) {
                    continue;
                }
                var arity = _simd_arity(op);
                if (args.count != arity) {
                    var many = args.count > arity ? "many" : "few";
                    state.report(
                        error_at($"too {many} arguments to '{base}': expected {arity}, have {args.count}", loc)
                    );
                    return none;
                }
                var parsed = parse_type_string(function);
                var ty = parsed.sub_types.count > 0 ? parsed.sub_types[0] : TypeName.named("int");
                return Optional<Expression>.Value(
                    Expression.Simd(SimdExpression(op = op, ty = ty, args = args, loc = loc))
                );
            }
        }
        return none;
    }
}

extend _IntrinsicConverter with Rewriter;

## Converts the types of the locals `block` declares, anywhere in it.
_convert_block_declarations(block: Block, converter: _IntrinsicConverter, state: PassState) {
    for (var item in block.items) {
        match (item) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    _convert_pointer_type(variable.ty, state);
                    if (variable.default.is_value()) {
                        variable.default = Optional<Expression>.Value(
                            rewrite_expression(variable.default.value(), converter)
                        );
                    }
                }
            }
            Block(inner) => {
                _convert_block_declarations(inner, converter, state);
            }
            Branch(branch) => {
                _convert_block_declarations(branch.if_block, converter, state);
                if (branch.else_block.is_value()) {
                    _convert_block_declarations(branch.else_block.value(), converter, state);
                }
            }
            While(loop) => {
                _convert_block_declarations(loop.block, converter, state);
            }
            else => {}
        }
    }
}

_convert_intrinsics_of(function: FunctionDef, converter: _IntrinsicConverter, state: PassState) {
    _convert_pointer_type(function.ty, state);
    for (var p in function.parameters) {
        _convert_pointer_type(p.ty, state);
    }
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), converter);
        _convert_block_declarations(function.body.value(), converter, state);
    }
}

## `__function_pointer(f)` calls become `FunctionPointer` nodes: a free
## function, or a static method of `owner`.
struct _FunctionPointers {
    var owner: TypeName?;
    var statics: HashSet<String>;
    var free_functions: HashSet<String>;
    var state: PassState;

    construct(owner: TypeName?, statics: HashSet<String>, free_functions: HashSet<String>, state: PassState) {
        this.owner = owner;
        this.statics = statics;
        this.free_functions = free_functions;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(node)) {
            if (node.function == "__function_pointer") {
                return _pointer(e, node);
            }
        }
        return e;
    }

    _pointer(e: Expression, node: FunctionCallExpression): Expression {
        if (node.args.count != 1) {
            var many = node.args.count > 1 ? "many" : "few";
            state.report(
                error_at($"too {many} arguments to '__function_pointer': expected 1, have {node.args.count}", node.loc)
            );
            return e;
        }
        var arg = node.args[0];
        var name = Optional<String>.Empty;
        match (arg) {
            SymbolRef(symbol) => {
                name = Optional<String>.Value(symbol.id);
            }
            FunctionRef(reference) => {
                name = Optional<String>.Value(reference.function);
            }
            MemberRef(member) => {
                if (member.lhs is ThisRef) {
                    name = Optional<String>.Value(member.name);
                }
            }
            else => {}
        }
        if (!name.is_value()) {
            state.report(error_at("'__function_pointer' expects the name of a function", _expression_loc(arg)));
            return e;
        }
        if (owner.is_value() and statics.contains(name.value())) {
            return Expression.FunctionPointer(
                FunctionPointerExpression(
                    owner = Optional<TypeName>.Value(owner.value().copy()), function = name.value(), loc = node.loc
                )
            );
        }
        if (free_functions.contains(name.value())) {
            return Expression.FunctionPointer(FunctionPointerExpression(function = name.value(), loc = node.loc));
        }
        state.report(error_at($"use of undeclared identifier '{name.value()}'", _expression_loc(arg)));
        return e;
    }
}

extend _FunctionPointers with Rewriter;

## Converts the intrinsics of every function, global and struct, as
## `convert_intrinsics::convert_intrinsics` does.
##
## @param module the model, changed in place
## @param state the passes' state, which takes the first error
export convert_intrinsics(module: Module, state: PassState) {
    var free_functions = HashSet<String>();
    for (var f in module.functions) {
        free_functions.insert(f.name);
    }
    var free = _FunctionPointers(Optional<TypeName>.Empty, HashSet<String>(), free_functions, state);
    for (var f in module.functions) {
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), free);
        }
    }
    for (var st in module.structs) {
        var statics = HashSet<String>();
        for (var m in st.method_members) {
            if (m.is_static) {
                statics.insert(m.name);
            }
        }
        var pointers = _FunctionPointers(Optional<TypeName>.Value(st.ty.copy()), statics, free_functions, state);
        for (var m in _bodies_of(st)) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), pointers);
            }
        }
    }
    var converter = _IntrinsicConverter(state);
    for (var f in module.functions) {
        _convert_intrinsics_of(f, converter, state);
    }
    for (var g in module.globals) {
        _convert_pointer_type(g.ty, state);
        if (g.default.is_value()) {
            g.default = Optional<Expression>.Value(rewrite_expression(g.default.value(), converter));
        }
    }
    # A trait's signatures, which its instances copy for the calls through a
    # value. The bodies of default methods are converted in the structs
    # they are copied into.
    for (var t in module.traits) {
        for (var m in t.methods) {
            _convert_pointer_type(m.ty, state);
            for (var p in m.parameters) {
                _convert_pointer_type(p.ty, state);
            }
        }
    }
    for (var st in module.structs) {
        for (var f in st.field_members) {
            _convert_pointer_type(f.ty, state);
        }
        for (var m in st.method_members) {
            _convert_intrinsics_of(m, converter, state);
        }
        for (var c in st.constructors) {
            _convert_intrinsics_of(c, converter, state);
        }
        _convert_intrinsics_of(st.destructor, converter, state);
    }
    _convert_trait_references(module, state);
}

_bodies_of(st: StructDef): FunctionDef[] {
    var out = Array<FunctionDef>();
    out.append_all(st.method_members);
    out.append_all(st.constructors);
    out.append(st.destructor);
    return out;
}

## The type a reference to a trait-typed variable carries, converted like
## the variable's declaration: only trait types, since elsewhere a
## reference's `__ptr<S>` spelling tells a raw pointer from a reference to
## struct `S`.
_convert_trait_references(module: Module, state: PassState) {
    var traits = HashSet<String>();
    for (var t in module.traits) {
        traits.insert(t.name);
    }
    if (traits.count == 0) {
        return;
    }
    var converter = _TraitReferenceConverter(traits, state);
    for (var f in module.functions) {
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), converter);
        }
    }
    for (var st in module.structs) {
        for (var m in _bodies_of(st)) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), converter);
            }
        }
    }
}

struct _TraitReferenceConverter {
    var traits: HashSet<String>;
    var state: PassState;

    construct(traits: HashSet<String>, state: PassState) {
        this.traits = traits;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            if (traits.contains(node.ty.name)) {
                _convert_pointer_type(node.ty, state);
            }
        }
        return e;
    }
}

extend _TraitReferenceConverter with Rewriter;

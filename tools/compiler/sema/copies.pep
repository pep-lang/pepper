## Deep copies for `copy(value)` (`runtime/copy.pep`):
## `pepper_sema::passes::copies` in Pepper. Once `T` is concrete, each
## `__copy<T>(value, copies)` call the runtime's `_Copies.copy<T>` makes
## becomes what copying a `T` means: the value itself for a thread-safe `T`,
## `copies._copy_object<T>(value)` for a struct (which gets a synthesized
## `__copy()` method, or calls its own `Copyable<T>.copy()`), a new tuple of
## the elements' copies, `copies._copy_trait<T>(value)` for a trait value
## (each trait gets a `_pep_copy_trait` member, and each struct declaring a
## trait the method behind it), and a call of `_pep_copy_failed<T>` that
## panics for anything else. The copies a program asks for are checked
## through everything they reach, and one that cannot be made is an error at
## the `copy(x)` that asked, with a note for each field on the way.
## `__census<T>(slot, waiting)` lowers here too.

import compiler.ast;
import [demangle, Diagnostic, Edit, Fix, Location] from compiler.diagnostic;
import "apply_extensions";
import [attribute_name] from "attributes";
import [payload_field, TAG_FIELD] from "builder";
import "common";
import "constraints";
import [Loc, NO_FILE] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Kind,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    ReturnStatement,
    Statement,
    StringLiteralExpression,
    StructDef,
    SymbolRefExpression,
    TraitDef,
    TypeName,
    VariableDef
] from "model";
import [ThreadSafeStructs, unsafe_part_in] from "shared_types";
import [PassMemo, PassState] from "state";
import [attribute_string] from "static_blocks";
import [trait_def] from "traits";
import [FUNCTION, parse_type_string, SHARED_FUNCTION] from "type_name";
import [Rewriter, rewrite_block] from "walk";

## The intrinsic `_Copies.copy<T>` lowers to.
const _COPY_INTRINSIC = "__copy";

## The intrinsic `_Copies._copy_object<T>` calls for a struct's new copy.
const _COPY_OBJECT_INTRINSIC = "__copy_object";

## The intrinsic `MutexGuard.exit` calls before it unlocks.
const _CENSUS_INTRINSIC = "__census";

## The runtime function a census of a copyable `T` lowers to.
const _CENSUS_FUNCTION = "_pep_check_sync";

## `[NotCopyable("why")]`: a struct that must never be copied.
const _NOT_COPYABLE_ATTRIBUTE = "NotCopyable";

## `[Isolated]`: a guard, which never leaves its `with` block.
const _ISOLATED_ATTRIBUTE = "Isolated";

## The struct the runtime keeps copies in: a copy's context.
const _COPIES = "_Copies";

## The runtime function that returns the running copy's context.
const _CONTEXT_FUNCTION = "_pep_copies";

## The synthesized method that copies a struct.
const _COPY_METHOD = "__copy";

## The synthesized method that copies a value struct.
const _COPY_VALUE_METHOD = "_pep_copy_value";

## The synthesized method that points a copy's weak fields at copies.
const _FIX_WEAK_METHOD = "_pep_fix_weak";

## How a struct implements `Copyable<T>`.
enum _CopyMethod {
    ## `copy(): T`.
    Current,
    ## The deprecated `copy(copies: Copies): T`.
    Deprecated,
}

## Why a type cannot be copied.
enum _BlockerKind {
    Destructor,
    RawPointerField,
    NotCopyable,
    PlainFunction,
    RawPointer,
    Weak,
}

struct _Blocker {
    var kind: _BlockerKind;
    var ty: TypeName;
    var field: String = "";
    var field_ty: TypeName = TypeName();
    var why: String = "";
    var loc: Loc = Loc.none();

    construct(kind: _BlockerKind, ty: TypeName) {
        this.kind = kind;
        this.ty = ty;
    }

    ## What the type is, after "which".
    what(): String {
        match (kind) {
            Destructor, RawPointerField => {
                return "is not trivially copyable";
            }
            NotCopyable => {
                return "cannot be copied";
            }
            PlainFunction => {
                return "is a plain function value";
            }
            RawPointer => {
                return "is a raw pointer";
            }
            Weak => {
                return "is a weak reference";
            }
        }
    }
}

## How a value of some type is copied.
enum _CopyPlan {
    ## Thread-safe: the value itself.
    Same,
    ## A struct copied by its `__copy()` method, and how it implements
    ## `Copyable<T>` if it does.
    Object(copyable: _CopyMethod?),
    ## A tuple with an element that is not thread-safe.
    Tuple,
    ## A trait value: the struct behind it, through the vtable.
    Trait,
    Blocked(blocker: _Blocker),
}

## One step from a type to a type it contains: a field, or a `copy<X>(...)`
## call in the owner's `Copyable` method.
struct _Hop {
    var is_field: bool;
    var owner: TypeName;
    var field: String;
    var copied: TypeName;
    var loc: Loc;

    construct(is_field: bool, owner: TypeName, field: String, copied: TypeName, loc: Loc) {
        this.is_field = is_field;
        this.owner = owner;
        this.field = field;
        this.copied = copied;
        this.loc = loc;
    }
}

## The method that copies a value of a value struct, and whether it takes
## the context.
struct _ValueCopy {
    var method: String;
    var takes_context: bool;

    construct(method: String, takes_context: bool) {
        this.method = method;
        this.takes_context = takes_context;
    }
}

## What a `__copy<T>` call lowers to.
enum _LoweringKind {
    Same,
    Object,
    Value,
    Tuple,
    Trait,
    Fail,
}

struct _Lowering {
    var kind: _LoweringKind;
    var value_copy: _ValueCopy = _ValueCopy("", false);
    var parts: Array<_Part> = Array<_Part>();
    var message: String = "";

    construct(kind: _LoweringKind) {
        this.kind = kind;
    }
}

## How a tuple copies one element.
enum _PartKind {
    Same,
    Object,
    Value,
    Tuple,
    Trait,
}

struct _Part {
    var kind: _PartKind;
    var ty: TypeName = TypeName();
    var value_copy: _ValueCopy = _ValueCopy("", false);
    var parts: Array<_Part> = Array<_Part>();

    construct(kind: _PartKind) {
        this.kind = kind;
    }
}

_struct_named(module: Module, ty: TypeName): StructDef? {
    var name = ty.to_string();
    for (var st in module.structs) {
        if (st.name == name) {
            return Optional<StructDef>.Value(st);
        }
    }
    return Optional<StructDef>.Empty;
}

## The reason of `[NotCopyable("why")]`, when the struct has one: empty for
## a bare `[NotCopyable]`.
_not_copyable(module: Module, st: StructDef): String? {
    for (var a in st.attributes) {
        var name = attribute_name(a);
        if (name.is_value() and name.value() == _NOT_COPYABLE_ATTRIBUTE) {
            var why = attribute_string(module, a, st.loc.file, "reason");
            return Optional<String>.Value(why.is_value() ? why.value() : "");
        }
    }
    return Optional<String>.Empty;
}

_is_deprecated_copy_method(method: FunctionDef): bool {
    return method.name == "copy" and method.parameters.count == 1 and method.parameters[0].ty.name == _COPIES;
}

_declares_copyable(st: StructDef): bool {
    for (var t in st.traits) {
        if (t.name == _COPYABLE_TRAIT) {
            return true;
        }
    }
    return false;
}

_is_current_copy_method(method: FunctionDef): bool {
    return method.name == "copy" and method.parameters.count == 0 and !method.is_static;
}

## How `st` implements `Copyable<T>`, if it does.
_copy_method(st: StructDef): _CopyMethod? {
    if (_declares_copyable(st)) {
        for (var m in st.method_members) {
            if (_is_current_copy_method(m)) {
                return Optional<_CopyMethod>.Value(_CopyMethod.Current);
            }
        }
    }
    for (var m in st.method_members) {
        if (_is_deprecated_copy_method(m)) {
            return Optional<_CopyMethod>.Value(_CopyMethod.Deprecated);
        }
    }
    return Optional<_CopyMethod>.Empty;
}

_is_current(how: _CopyMethod?): bool {
    if (how.is_value()) {
        if (how.value() is Current) {
            return true;
        }
    }
    return false;
}

## Whether `method` of `st` is its `Copyable<T>` implementation.
_is_copy_method_of(st: StructDef, method: FunctionDef): bool {
    var how = _copy_method(st);
    if (!how.is_value()) {
        return false;
    }
    return _is_current(how) ? _is_current_copy_method(method) : _is_deprecated_copy_method(method);
}

## The `T` of each `copy<T>(...)` call in `function`, with its location.
_copy_calls(function: FunctionDef): Array<(TypeName, Loc)> {
    var finder = _CopyCalls();
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), finder);
    }
    return finder.found;
}

struct _CopyCalls {
    var found: Array<(TypeName, Loc)> = Array<(TypeName, Loc)>();

    construct() {}

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                _add(node.function, node.loc);
            }
            MethodCall(node) => {
                _add(node.method, node.loc);
            }
            else => {}
        }
        return e;
    }

    _add(name: String, loc: Loc) {
        if (name.starts_with("copy<")) {
            var parsed = parse_type_string(name);
            if (parsed.sub_types.count > 0) {
                found.append((parsed.sub_types[0], loc));
            }
        }
    }
}

extend _CopyCalls with Rewriter;

_is_head_field(field: VariableDef): bool {
    return field.name == "__refcount" or field.name == "__weakcount";
}

_known_loc(a: Loc, b: Loc): Loc {
    return !a.is_none() ? a : b;
}

_plan(module: Module, safe: ThreadSafeStructs, ty: TypeName): _CopyPlan {
    if (!unsafe_part_in(ty, safe).is_value()) {
        return _CopyPlan.Same;
    }
    if (ty.is_weak()) {
        return _CopyPlan.Blocked(_Blocker(_BlockerKind.Weak, ty));
    }
    if (ty.is_function_type()) {
        return _CopyPlan.Blocked(_Blocker(_BlockerKind.PlainFunction, ty));
    }
    if (ty.is_pointer()) {
        return _CopyPlan.Blocked(_Blocker(_BlockerKind.RawPointer, ty));
    }
    if (trait_def(module.traits, ty).is_value()) {
        return _CopyPlan.Trait;
    }
    if (ty.is_tuple()) {
        return _CopyPlan.Tuple;
    }
    var found = _struct_named(module, ty);
    if (!found.is_value()) {
        return _CopyPlan.Same;
    }
    var st = found.value();
    var why = _not_copyable(module, st);
    if (why.is_value()) {
        var blocker = _Blocker(_BlockerKind.NotCopyable, ty);
        blocker.why = why.value();
        blocker.loc = st.loc;
        return _CopyPlan.Blocked(blocker);
    }
    var how = _copy_method(st);
    if (how.is_value()) {
        return _CopyPlan.Object(how);
    }
    if (st.destructor.body.is_value() and st.destructor.body.value().items.count > 0) {
        var blocker = _Blocker(_BlockerKind.Destructor, ty);
        blocker.loc = st.loc;
        return _CopyPlan.Blocked(blocker);
    }
    for (var field in st.field_members) {
        if (field.ty.is_pointer()) {
            var blocker = _Blocker(_BlockerKind.RawPointerField, ty);
            blocker.field = field.name;
            blocker.field_ty = field.ty;
            blocker.loc = _known_loc(field.type_loc, field.loc);
            return _CopyPlan.Blocked(blocker);
        }
    }
    return _CopyPlan.Object(Optional<_CopyMethod>.Empty);
}

## The types a copy of `ty` copies in turn, each with the step that reaches
## it.
_contained(module: Module, ty: TypeName, copyable: bool): Array<(TypeName, _Hop)> {
    var out = Array<(TypeName, _Hop)>();
    var found = _struct_named(module, ty);
    if (!found.is_value()) {
        return out;
    }
    var st = found.value();
    if (copyable) {
        for (var m in st.method_members) {
            if (_is_copy_method_of(st, m)) {
                for (var (copied, loc) in _copy_calls(m)) {
                    out.append((copied, _Hop(false, ty, "", copied, loc)));
                }
            }
        }
        return out;
    }
    for (var f in st.field_members) {
        if (!_is_head_field(f) and !f.ty.is_weak()) {
            out.append((f.ty, _Hop(true, ty, f.name, TypeName(), _known_loc(f.type_loc, f.loc))));
        }
    }
    return out;
}

## The first type `ty` reaches that cannot be copied, with the steps from
## `ty` to it.
_first_blocker(module: Module, safe: ThreadSafeStructs, ty: TypeName): (Array<_Hop>, _Blocker)? {
    var path = Array<_Hop>();
    var seen = HashSet<String>();
    var blocker = _visit_blocker(module, safe, ty, path, seen);
    if (!blocker.is_value()) {
        return Optional<(Array<_Hop>, _Blocker)>.Empty;
    }
    return Optional<(Array<_Hop>, _Blocker)>.Value((path, blocker.value()));
}

_visit_blocker(
    module: Module, safe: ThreadSafeStructs, ty: TypeName, path: Array<_Hop>, seen: HashSet<String>
): _Blocker? {
    var none = Optional<_Blocker>.Empty;
    if (!seen.insert(ty.to_string())) {
        return none;
    }
    bool copyable = false;
    match (_plan(module, safe, ty)) {
        Same, Trait => {
            return none;
        }
        Blocked(blocker) => {
            return Optional<_Blocker>.Value(blocker);
        }
        Object(how) => {
            copyable = how.is_value();
        }
        Tuple => {}
    }
    for (var (inner, hop) in _contained(module, ty, copyable)) {
        path.append(hop);
        var blocker = _visit_blocker(module, safe, inner, path, seen);
        if (blocker.is_value()) {
            return blocker;
        }
        path.pop();
    }
    return none;
}

# Model builders.

_symbol(id: String, ty: TypeName): Expression {
    return Expression.SymbolRef(SymbolRefExpression(id, ty, Loc.none()));
}

_member(lhs: Expression, name: String): Expression {
    return Expression.MemberRef(MemberRefExpression(lhs, name, Loc.none()));
}

_method_call(this_value: Expression, method: String, args: Expression[]): Expression {
    return Expression.MethodCall(MethodCallExpression(this_value, method, args, Loc.none()));
}

_assign(lhs: Expression, rhs: Expression): Statement {
    return Statement.Expression(Expression.Binary(BinaryExpression(lhs, rhs, BinaryOp.Assign, Loc.none())));
}

_variable(name: String, ty: TypeName, default: Expression?, kind: Kind): VariableDef {
    return VariableDef(name, ty, default, false, kind, loc = Loc.none(), type_loc = Loc.none());
}

_copies_type(): TypeName {
    return TypeName.named(_COPIES);
}

_return(value: Expression): Statement {
    return Statement.Return(ReturnStatement(Optional<Expression>.Value(value), Loc.none()));
}

## A synthesized method of `st` that takes the copy's context as `copies`.
_context_method(st: StructDef, name: String, ty: TypeName, items: Statement[]): FunctionDef {
    var method = _plain_method(st, name, ty, items);
    method.parameters.append(_variable("copies", _copies_type(), Optional<Expression>.Empty, Kind.Param));
    return method;
}

## A synthesized method of `st` with no parameters.
_plain_method(st: StructDef, name: String, ty: TypeName, items: Statement[]): FunctionDef {
    return FunctionDef(
        name,
        ty,
        body = Optional<Block>.Value(Block(name, items)),
        parent = Optional<String>.Value(st.name),
        loc = st.loc,
        owner = Loc.none()
    );
}

## `_pep_copies()`: the context of the copy running on this thread.
_context(): Expression {
    return Expression.FunctionCall(FunctionCallExpression(_CONTEXT_FUNCTION, Array<Expression>(), Loc.none()));
}

## The `__copy()` method of `st`, and its `_pep_fix_weak` when it has weak
## fields to point at copies.
_copy_methods(st: StructDef, safe: ThreadSafeStructs, copyable: _CopyMethod?): Array<FunctionDef> {
    var this_ty = TypeName.named(st.name);
    var methods = Array<FunctionDef>();
    if (copyable.is_value()) {
        var args = Array<Expression>();
        if (!_is_current(copyable)) {
            args.append(_context());
        }
        var body = Array<Statement>();
        body.append(_return(_method_call(Expression.ThisRef, "copy", args)));
        methods.append(_plain_method(st, _COPY_METHOD, this_ty, body));
        return methods;
    }
    var items = Array<Statement>();
    items.append(
        Statement.Declaration(
            Declaration.Variable(
                _variable("copies", _copies_type(), Optional<Expression>.Value(_context()), Kind.Variable)
            )
        )
    );
    items.append(
        Statement.Declaration(
            Declaration.Variable(
                _variable("__made", this_ty, Optional<Expression>.Value(Expression.Allocate(this_ty)), Kind.Variable)
            )
        )
    );
    items.append(
        Statement.Expression(
            _method_call(
                _symbol("copies", _copies_type()),
                $"register<{st.name}>",
                [Expression.ThisRef, _symbol("__made", this_ty)]
            )
        )
    );
    var weak_fields = Array<(String, TypeName)>();
    for (var field in st.field_members) {
        if (_is_head_field(field)) {
            continue;
        }
        var value = _member(Expression.ThisRef, field.name);
        if (unsafe_part_in(field.ty, safe).is_value()) {
            if (field.ty.is_weak()) {
                weak_fields.append((field.name, field.ty.sub_types[0]));
            } else {
                value = _method_call(_symbol("copies", _copies_type()), $"copy<{field.ty}>", [value]);
            }
        }
        items.append(_assign(_member(_symbol("__made", this_ty), field.name), value));
    }
    if (weak_fields.count > 0) {
        items.append(
            Statement.Expression(
                _method_call(
                    _symbol("copies", _copies_type()), "_defer", [_member(_symbol("__made", this_ty), _FIX_WEAK_METHOD)]
                )
            )
        );
        var fixes = Array<Statement>();
        for (var (field, target) in weak_fields) {
            var current = _member(Expression.ThisRef, field);
            fixes.append(
                _assign(
                    _member(Expression.ThisRef, field),
                    _method_call(_symbol("copies", _copies_type()), $"_weak<{target}>", [current])
                )
            );
        }
        methods.append(_context_method(st, _FIX_WEAK_METHOD, TypeName.void(), fixes));
    }
    items.append(_return(_symbol("__made", this_ty)));
    methods.insert(0, _plain_method(st, _COPY_METHOD, this_ty, items));
    return methods;
}

## How a value of value struct `ty` is copied; none when `ty` is no value
## struct.
_value_copy_method(module: Module, ty: TypeName, copyable: _CopyMethod?): _ValueCopy? {
    var st = _struct_named(module, ty);
    if (!st.is_value() or !st.value().is_value()) {
        return Optional<_ValueCopy>.Empty;
    }
    if (!copyable.is_value()) {
        return Optional<_ValueCopy>.Value(_ValueCopy(_COPY_VALUE_METHOD, true));
    }
    return Optional<_ValueCopy>.Value(_ValueCopy("copy", !_is_current(copyable)));
}

## `value.method(copies)`, or `value.method()` when it takes no context.
_call_value_copy(how: _ValueCopy, value: Expression, copies: Expression, loc: Loc): Expression {
    var args = Array<Expression>();
    if (how.takes_context) {
        args.append(copies.copy());
    }
    return Expression.MethodCall(MethodCallExpression(value, how.method, args, loc));
}

## The `_pep_copy_value` method of value struct `st`.
_copy_value_method(st: StructDef, safe: ThreadSafeStructs): FunctionDef {
    var this_ty = TypeName.named(st.name);
    var items = Array<Statement>();
    items.append(
        Statement.Declaration(
            Declaration.Variable(
                _variable("__made", this_ty, Optional<Expression>.Value(Expression.ThisRef), Kind.Variable)
            )
        )
    );
    if (!st.has_union_layout()) {
        for (var field in st.field_members) {
            _copy_field(field, safe, this_ty, items);
        }
        items.append(_return(_symbol("__made", this_ty)));
        return _context_method(st, _COPY_VALUE_METHOD, this_ty, items);
    }
    # A value enum's cases share storage: only the case `this` holds has
    # values to copy.
    for (var case in st.enum_cases.value()) {
        var stores = Array<Statement>();
        for (var field in st.field_members) {
            for (var (value, _) in case.payload) {
                if (payload_field(case.name, value) == field.name) {
                    _copy_field(field, safe, this_ty, stores);
                }
            }
        }
        if (stores.is_empty) {
            continue;
        }
        var is_case = Expression.Binary(
            BinaryExpression(
                _member(Expression.ThisRef, TAG_FIELD), Expression.IntLiteral(case.value), BinaryOp.Equal, Loc.none()
            )
        );
        items.append(Statement.Branch(Branch(is_case, Block("", stores))));
    }
    items.append(_return(_symbol("__made", this_ty)));
    return _context_method(st, _COPY_VALUE_METHOD, this_ty, items);
}

# `__made.field = copies.copy<T>(this.field)`, appended to `items`, when
# `field` is not thread-safe.
_copy_field(field: VariableDef, safe: ThreadSafeStructs, this_ty: TypeName, items: Array<Statement>) {
    if (!unsafe_part_in(field.ty, safe).is_value() or field.ty.is_weak()) {
        return;
    }
    var original = _member(Expression.ThisRef, field.name);
    items.append(
        _assign(
            _member(_symbol("__made", this_ty), field.name),
            _method_call(_symbol("copies", _copies_type()), $"copy<{field.ty}>", [original])
        )
    );
}

# The pass.

## The `T` of a call `name<T>(...)` with `count` arguments, whose name before
## `<` is `intrinsic`.
_intrinsic_type(e: Expression, intrinsic: String, count: ulong): TypeName? {
    var none = Optional<TypeName>.Empty;
    if (e is FunctionCall(node)) {
        if (node.args.count != count) {
            return none;
        }
        var at = node.function.find("<");
        var base = at < 0 ? node.function : node.function.substr_bytes(0, at as ulong);
        if (base != intrinsic) {
            return none;
        }
        var parsed = parse_type_string(node.function);
        if (parsed.sub_types.count > 0) {
            return Optional<TypeName>.Value(parsed.sub_types[0]);
        }
    }
    return none;
}

## The compiled functions (`_compiled_functions`) holding a call of
## `__copy<T>`, `__copy_object<T>` or `__census<T>`, in order.
_intrinsic_holders(module: Module): Array<FunctionDef> {
    var out = Array<FunctionDef>();
    var finder = _IntrinsicFinder();
    for (var function in _compiled_functions(module)) {
        finder.found = false;
        _rewrite_function(function, finder);
        if (finder.found) {
            out.append(function);
        }
    }
    return out;
}

## Notes whether a walk met a call of a copy intrinsic.
struct _IntrinsicFinder {
    var found: bool = false;

    construct() {}

    rewrite(e: Expression): Expression {
        if (found) {
            return e;
        }
        if (e is FunctionCall(node)) {
            var at = node.function.find("<");
            var base = at < 0 ? node.function : node.function.substr_bytes(0, at as ulong);
            found = base == _COPY_INTRINSIC or base == _COPY_OBJECT_INTRINSIC or base == _CENSUS_INTRINSIC;
        }
        return e;
    }
}

extend _IntrinsicFinder with Rewriter;

## Every function body that is compiled: not a generic base.
_compiled_functions(module: Module): Array<FunctionDef> {
    var out = Array<FunctionDef>();
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            out.append(f);
        }
    }
    for (var st in module.structs) {
        if (st.name == st.ty.name and st.ty.is_generic()) {
            continue;
        }
        for (var m in st.method_members) {
            if (!m.is_generic_func) {
                out.append(m);
            }
        }
        out.append_all(st.constructors);
    }
    return out;
}

_rewrite_function(function: FunctionDef, rewriter: Rewriter) {
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), rewriter);
    }
}

## The copies the program asks for: each `copy<T>(x)` call in compiled code
## outside a `Copyable` implementation.
_requests(module: Module): Array<(TypeName, Loc)> {
    var found = Array<(TypeName, Loc)>();
    var copyable = HashSet<String>();
    for (var st in module.structs) {
        if (_is_current(_copy_method(st))) {
            copyable.insert(st.name);
        }
    }
    for (var function in _compiled_functions(module)) {
        var implements = _is_deprecated_copy_method(function)
            or (_is_current_copy_method(function)
                and function.parent.is_value()
                and copyable.contains(function.parent.value()));
        # The runtime's `copy<T>` copies for its caller, whose call is the
        # request.
        var runtime_copy = !function.parent.is_value() and function.name.starts_with("copy<");
        if (implements
            or runtime_copy
            or function.name == _COPY_METHOD
            or function.name == _COPY_VALUE_METHOD
            or function.name == _COPY_TRAIT_METHOD) {
            continue;
        }
        for (var (ty, loc) in _copy_calls(function)) {
            if (!_has_type(found, ty)) {
                found.append((ty, loc));
            }
        }
    }
    return found;
}

_has_type(list: Array<(TypeName, Loc)>, ty: TypeName): bool {
    for (var (t, _) in list) {
        if (t == ty) {
            return true;
        }
    }
    return false;
}

_needs(needed: Array<(String, Optional<_CopyMethod>)>, name: String, copyable: _CopyMethod?) {
    for (var (n, _) in needed) {
        if (n == name) {
            return;
        }
    }
    needed.append((name, copyable));
}

## Lowers every concrete `__copy<T>` call and synthesizes the `__copy()`
## methods they need, as `copies::synthesize_copies` does. Reports a copy
## the program asks for that cannot be made.
##
## @param module the model, changed in place
## @param state the passes' state
## @returns whether it added anything the specialization loop must
##   specialize
export synthesize_copies(module: Module, state: PassState): bool {
    var safe = ThreadSafeStructs(module, state);
    for (var (ty, loc) in _requests(module)) {
        var blocked = _first_blocker(module, safe, ty);
        if (blocked.is_value()) {
            var (path, blocker) = blocked.value();
            state.report(_cannot_copy(module, state, ty, loc, path, blocker));
            return false;
        }
    }
    # Few functions hold the intrinsics (the runtime's `_Copies` methods
    # and their specializations, `MutexGuard.exit`): one walk finds them,
    # and the lowerings below walk only those. What the lowerings and
    # `_add_trait_copies` add holds none.
    var holders = _intrinsic_holders(module);
    var censuses_added = _lower_censuses(module, safe, holders);
    _lower_copy_objects(module, holders);
    var traits_added = _add_trait_copies(module, safe, state);
    var collector = _CopyIntrinsics();
    for (var function in holders) {
        _rewrite_function(function, collector);
    }
    var calls = collector.calls;
    if (calls.count == 0) {
        return censuses_added or traits_added;
    }
    # What each `__copy<T>` becomes.
    var lowered = Array<(TypeName, _Lowering)>();
    var needed = Array<(String, Optional<_CopyMethod>)>();
    for (var (ty, _) in calls) {
        var lowering = _Lowering(_LoweringKind.Same);
        match (_plan(module, safe, ty)) {
            Same => {}
            Object(copyable) => {
                _needs(needed, ty.to_string(), copyable);
                var how = _value_copy_method(module, ty, copyable);
                if (how.is_value()) {
                    lowering = _Lowering(_LoweringKind.Value);
                    lowering.value_copy = how.value();
                } else {
                    lowering = _Lowering(_LoweringKind.Object);
                }
            }
            Tuple => {
                var blocked = _first_blocker(module, safe, ty);
                if (blocked.is_value()) {
                    var (_, blocker) = blocked.value();
                    lowering = _Lowering(_LoweringKind.Fail);
                    lowering.message = $"cannot copy '{ty.display()}', which {blocker.what()}";
                } else {
                    lowering = _Lowering(_LoweringKind.Tuple);
                    lowering.parts = _tuple_parts(module, safe, ty, needed);
                }
            }
            Trait => {
                lowering = _Lowering(_LoweringKind.Trait);
            }
            Blocked(blocker) => {
                lowering = _Lowering(_LoweringKind.Fail);
                lowering.message = $"cannot copy '{ty.display()}', which {blocker.what()}";
            }
        }
        lowered.append((ty, lowering));
    }
    var added = traits_added;
    for (var (name, copyable) in needed) {
        var found = Optional<StructDef>.Empty;
        for (var st in module.structs) {
            if (st.name == name) {
                found = Optional<StructDef>.Value(st);
                break;
            }
        }
        if (!found.is_value()) {
            continue;
        }
        var st = found.value();
        bool has = false;
        for (var m in st.method_members) {
            if (m.name == _COPY_METHOD or m.name == _COPY_VALUE_METHOD) {
                has = true;
            }
        }
        if (has) {
            continue;
        }
        if (st.is_value()) {
            if (copyable.is_value()) {
                continue;
            }
            st.method_members.append(_copy_value_method(st, safe));
        } else {
            st.method_members.append_all(_copy_methods(st, safe, copyable));
        }
        _extended(module, state, st);
        added = true;
    }
    var lowerer = _CopyLowering(lowered);
    for (var function in holders) {
        _rewrite_function(function, lowerer);
    }
    var failed = false;
    for (var (_, lowering) in lowered) {
        if (lowering.kind is Fail) {
            failed = true;
        }
    }
    return added or censuses_added or failed;
}

## Collects the `T` of each `__copy<T>` call, with its location.
struct _CopyIntrinsics {
    var calls: Array<(TypeName, Loc)> = Array<(TypeName, Loc)>();

    construct() {}

    rewrite(e: Expression): Expression {
        var ty = _intrinsic_type(e, _COPY_INTRINSIC, 2);
        if (ty.is_value() and !_has_type(calls, ty.value())) {
            calls.append((ty.value(), _expression_loc(e)));
        }
        return e;
    }
}

extend _CopyIntrinsics with Rewriter;

## Replaces each `__copy<T>(value, copies)` by what it lowers to.
struct _CopyLowering {
    var lowered: Array<(TypeName, _Lowering)>;

    construct(lowered: Array<(TypeName, _Lowering)>) {
        this.lowered = lowered;
    }

    rewrite(e: Expression): Expression {
        var ty = _intrinsic_type(e, _COPY_INTRINSIC, 2);
        if (!ty.is_value()) {
            return e;
        }
        var found = Optional<_Lowering>.Empty;
        for (var (t, lowering) in lowered) {
            if (t == ty.value()) {
                found = Optional<_Lowering>.Value(lowering);
                break;
            }
        }
        if (!found.is_value()) {
            return e;
        }
        if (e is FunctionCall(node)) {
            return _lower(ty.value(), found.value(), node.args[0], node.args[1], node.loc);
        }
        return e;
    }

    _lower(ty: TypeName, lowering: _Lowering, value: Expression, copies: Expression, loc: Loc): Expression {
        match (lowering.kind) {
            Same => {
                return value;
            }
            Object => {
                return Expression.MethodCall(MethodCallExpression(copies, $"_copy_object<{ty}>", [value], loc));
            }
            Value => {
                return _call_value_copy(lowering.value_copy, value, copies, loc);
            }
            Tuple => {
                return _copy_tuple(ty, lowering.parts, value, copies, loc);
            }
            Trait => {
                return Expression.MethodCall(MethodCallExpression(copies, $"_copy_trait<{ty}>", [value], loc));
            }
            Fail => {
                return _copy_failed(ty, lowering.message, loc);
            }
        }
    }
}

extend _CopyLowering with Rewriter;

## `_pep_copy_failed<T>("message")`, which panics.
# Marks `st`, which this pass just added methods to, as extended when it is
# a checked struct: the layer's to walk and to record, as one an extension
# or a specialized method changed.
_extended(module: Module, state: PassState, st: StructDef) {
    if (!module.checked.structs.contains(st.name)) {
        return;
    }
    state.extended_checked.insert(st.name);
    module.extended_checked.insert(st.name);
    state.trait_memo.checked_table = Optional<PassMemo>.Empty;
    state.trait_memo.checked_types = Optional<(TypeName[], HashSet<String>, HashSet<String>, HashSet<String>)>.Empty;
}

_copy_failed(ty: TypeName, message: String, loc: Loc): Expression {
    var literal = Expression.StringLiteral(StringLiteralExpression(message, true, Loc.none()));
    return Expression.FunctionCall(FunctionCallExpression($"_pep_copy_failed<{ty}>", [literal], loc));
}

## Lowers every `__copy_object<T>(value)` whose `T` is a struct to
## `value.__copy()`, in `holders`, the functions holding intrinsics.
_lower_copy_objects(module: Module, holders: FunctionDef[]) {
    var structs = HashSet<String>();
    for (var st in module.structs) {
        structs.insert(st.name);
    }
    var lowering = _CopyObjects(structs);
    for (var function in holders) {
        _rewrite_function(function, lowering);
    }
}

struct _CopyObjects {
    var structs: HashSet<String>;

    construct(structs: HashSet<String>) {
        this.structs = structs;
    }

    rewrite(e: Expression): Expression {
        var ty = _intrinsic_type(e, _COPY_OBJECT_INTRINSIC, 1);
        if (!ty.is_value() or !structs.contains(ty.value().to_string())) {
            return e;
        }
        if (e is FunctionCall(node)) {
            return Expression.MethodCall(
                MethodCallExpression(node.args[0], _COPY_METHOD, Array<Expression>(), node.loc)
            );
        }
        return e;
    }
}

extend _CopyObjects with Rewriter;

## Lowers every concrete `__census<T>(slot, waiting)`: to a
## `_pep_check_sync<T>` call when a `T` can be copied, and to the slot alone
## otherwise, in `holders`, the functions holding intrinsics. Returns
## whether it added a call to specialize.
_lower_censuses(module: Module, safe: ThreadSafeStructs, holders: FunctionDef[]): bool {
    var collector = _Censuses();
    for (var function in holders) {
        _rewrite_function(function, collector);
    }
    var checked = Array<(TypeName, bool)>();
    for (var ty in collector.types) {
        bool can = false;
        match (_plan(module, safe, ty)) {
            Same, Trait => {}
            else => {
                can = !_first_blocker(module, safe, ty).is_value();
            }
        }
        checked.append((ty, can));
    }
    var lowering = _CensusLowering(checked);
    for (var function in holders) {
        _rewrite_function(function, lowering);
    }
    return lowering.added;
}

struct _Censuses {
    var types: Array<TypeName> = Array<TypeName>();

    construct() {}

    rewrite(e: Expression): Expression {
        var ty = _intrinsic_type(e, _CENSUS_INTRINSIC, 2);
        if (ty.is_value()) {
            for (var t in types) {
                if (t == ty.value()) {
                    return e;
                }
            }
            types.append(ty.value());
        }
        return e;
    }
}

extend _Censuses with Rewriter;

struct _CensusLowering {
    var checked: Array<(TypeName, bool)>;
    var added: bool = false;

    construct(checked: Array<(TypeName, bool)>) {
        this.checked = checked;
    }

    rewrite(e: Expression): Expression {
        var ty = _intrinsic_type(e, _CENSUS_INTRINSIC, 2);
        if (!ty.is_value()) {
            return e;
        }
        for (var (t, can) in checked) {
            if (t == ty.value()) {
                if (e is FunctionCall(node)) {
                    var slot = node.args[0];
                    var waiting = node.args[1];
                    if (!can) {
                        return slot;
                    }
                    added = true;
                    var locked = Expression.StringLiteral(
                        StringLiteralExpression($"Mutex<{t.display()}>", true, Loc.none())
                    );
                    return Expression.FunctionCall(
                        FunctionCallExpression($"{_CENSUS_FUNCTION}<{t}>", [slot, waiting, locked], node.loc)
                    );
                }
            }
        }
        return e;
    }
}

extend _CensusLowering with Rewriter;

## How to copy each element of tuple `ty`, whose elements can all be
## copied; records each struct element in `needed`.
_tuple_parts(
    module: Module, safe: ThreadSafeStructs, ty: TypeName, needed: Array<(String, Optional<_CopyMethod>)>
): Array<_Part> {
    var out = Array<_Part>();
    for (var element in ty.sub_types) {
        var part = _Part(_PartKind.Same);
        match (_plan(module, safe, element)) {
            Object(copyable) => {
                _needs(needed, element.to_string(), copyable);
                var how = _value_copy_method(module, element, copyable);
                if (how.is_value()) {
                    part = _Part(_PartKind.Value);
                    part.value_copy = how.value();
                } else {
                    part = _Part(_PartKind.Object);
                    part.ty = element;
                }
            }
            Tuple => {
                part = _Part(_PartKind.Tuple);
                part.ty = element;
                part.parts = _tuple_parts(module, safe, element, needed);
            }
            Trait => {
                part = _Part(_PartKind.Trait);
                part.ty = element;
            }
            else => {}
        }
        out.append(part);
    }
    return out;
}

## `(copy of value.0, copy of value.1, ...)`.
_copy_tuple(ty: TypeName, parts: Array<_Part>, value: Expression, copies: Expression, loc: Loc): Expression {
    var args = Array<Expression>();
    ulong i = 0;
    for (var part in parts) {
        var element = Expression.MemberRef(MemberRefExpression(value.copy(), $"{i}", loc));
        match (part.kind) {
            Same => {
                args.append(element);
            }
            Object => {
                args.append(
                    Expression.MethodCall(
                        MethodCallExpression(copies.copy(), $"_copy_object<{part.ty}>", [element], loc)
                    )
                );
            }
            Value => {
                args.append(_call_value_copy(part.value_copy, element, copies, loc));
            }
            Tuple => {
                args.append(_copy_tuple(part.ty, part.parts, element, copies, loc));
            }
            Trait => {
                args.append(
                    Expression.MethodCall(MethodCallExpression(copies.copy(), $"copy<{part.ty}>", [element], loc))
                );
            }
        }
        i += 1;
    }
    return Expression.FunctionCall(FunctionCallExpression(ty.to_string(), args, loc));
}

## Makes every trait copyable through its values: each trait gets a
## `_pep_copy_trait(copies): Tr` member, and each concrete struct that
## declares a trait the method that fills that vtable slot. Returns whether
## it added anything.
_add_trait_copies(module: Module, safe: ThreadSafeStructs, state: PassState): bool {
    var added = false;
    for (var def in module.traits) {
        bool has = false;
        for (var m in def.methods) {
            if (m.name == _COPY_TRAIT_METHOD) {
                has = true;
            }
        }
        if (!has) {
            def.methods.append(_trait_copy_member(def));
            added = true;
        }
    }
    var wanting = Array<StructDef>();
    for (var st in module.structs) {
        if (st.name == st.ty.name and st.ty.is_generic()) {
            continue;
        }
        bool declares = false;
        for (var t in st.traits) {
            if (trait_def(module.traits, t).is_value()) {
                declares = true;
            }
        }
        bool has = false;
        for (var m in st.method_members) {
            if (m.name == _COPY_TRAIT_METHOD) {
                has = true;
            }
        }
        if (declares and !has) {
            wanting.append(st);
        }
    }
    for (var st in wanting) {
        var this_ty = TypeName.named(st.name);
        # A struct that cannot be copied panics, naming what blocks it.
        var blocked = Optional<(Array<_Hop>, _Blocker)>.Empty;
        if (ast.has_attribute(st.attributes, _ISOLATED_ATTRIBUTE)) {
            # A guard never leaves its `with` block, so a copy of one would
            # be a second lock.
            blocked = Optional<(Array<_Hop>, _Blocker)>.Value(
                (Array<_Hop>(), _Blocker(_BlockerKind.NotCopyable, this_ty))
            );
        } else {
            blocked = _first_blocker(module, safe, this_ty);
        }
        var copied: Expression;
        if (!blocked.is_value()) {
            copied = _method_call(_symbol("copies", _copies_type()), $"copy<{this_ty}>", [Expression.ThisRef]);
        } else {
            var (path, blocker) = blocked.value();
            var message = path.count == 0 ?
                $"cannot copy the '{this_ty.display()}' behind a trait value, which {blocker.what()}" :
                $"cannot copy the '{this_ty.display()}' behind a trait value because it contains '{blocker.ty.display()}', which {blocker.what()}";
            copied = _copy_failed(this_ty, message, Loc.none());
        }
        var body = Array<Statement>();
        body.append(_return(copied));
        st.method_members.append(_context_method(st, _COPY_TRAIT_METHOD, this_ty, body));
        _extended(module, state, st);
        added = true;
    }
    return added;
}

## The trait member `_pep_copy_trait(copies: _Copies): Tr<T, ...>` of `def`.
_trait_copy_member(def: TraitDef): FunctionDef {
    var args = Array<TypeName>();
    for (var p in def.generic_params) {
        args.append(TypeName.named(p.name));
    }
    var parameters = Array<VariableDef>();
    parameters.append(_variable("copies", _copies_type(), Optional<Expression>.Empty, Kind.Param));
    return FunctionDef(
        _COPY_TRAIT_METHOD,
        TypeName.with_args(def.name, args),
        parameters = parameters,
        loc = def.loc,
        owner = Loc.none()
    );
}

# The error.

## Where the program asks to copy a `ty`: the `copy(x)` call in the
## earliest file.
_request_site(module: Module, ty: TypeName): Loc? {
    var finder = _RequestSites($"copy<{ty}>");
    for (var f in module.functions) {
        _rewrite_function(f, finder);
    }
    for (var st in module.structs) {
        for (var m in st.method_members) {
            _rewrite_function(m, finder);
        }
        for (var c in st.constructors) {
            _rewrite_function(c, finder);
        }
    }
    var best = Optional<Loc>.Empty;
    for (var loc in finder.found) {
        if (!best.is_value() or loc.file < best.value().file) {
            best = Optional<Loc>.Value(loc);
        }
    }
    return best;
}

struct _RequestSites {
    var spec: String;
    var found: Array<Loc> = Array<Loc>();

    construct(spec: String) {
        this.spec = spec;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                if (node.function == spec and !node.loc.is_none()) {
                    found.append(node.loc);
                }
            }
            MethodCall(node) => {
                if (node.method == spec and !node.loc.is_none()) {
                    found.append(node.loc);
                }
            }
            else => {}
        }
        return e;
    }
}

extend _RequestSites with Rewriter;

## `ty` as the user writes it.
_written(ty: TypeName): String {
    var shown = demangle($"'{ty.display()}'");
    var start: ulong = shown.starts_with("'") ? 1 : 0;
    var end = shown.size;
    while (end > start and shown.substr_bytes(end - 1, 1) == "'") {
        end -= 1;
    }
    while (start < end and shown.substr_bytes(start, 1) == "'") {
        start += 1;
    }
    return shown.substr_bytes(start, end - start);
}

## The `Copyable` skeleton for `ty`, as the note shows it and as the fix
## inserts it.
_skeleton(ty: TypeName, indent: String): String {
    var t = _written(ty);
    var lines = [
        $"extend {t} with Copyable<{t}> {{",
        $"    copy(): {t} {{",
        "        # Build the copy; copy each struct field with copy(field).",
        $"        panic(\"copying '{t}' is not implemented\");",
        "        return this;",
        "    }",
        "}"
    ];
    var out = Array<String>();
    for (var line in lines) {
        out.append(indent + line);
    }
    return "\n".join(out);
}

_cannot_copy(
    module: Module, state: PassState, root: TypeName, fallback: Loc, path: Array<_Hop>, blocker: _Blocker
): Diagnostic {
    var message = path.count == 0 ?
        $"cannot copy '{root.display()}', which {blocker.what()}" :
        $"cannot copy '{root.display()}' because it contains '{blocker.ty.display()}', which {blocker.what()}";
    var site = _request_site(module, root);
    var at = site.is_value() ? site.value() : fallback;
    var diagnostic = Diagnostic.error(message).at(location_of(at));
    for (var hop in path) {
        if (hop.is_field) {
            var step = hop.owner.is_tuple() ? $"element {hop.field}" : $"field '{hop.field}'";
            diagnostic = diagnostic.with_note(
                $"'{hop.owner.display()}' reaches it through {step}", known_location(hop.loc)
            );
        } else if (at.file == hop.loc.file) {
            # A runtime container's `copy` method is not the program's to
            # change: point only at a `Copyable` method in the error's file.
            diagnostic = diagnostic.with_note(
                $"'{hop.owner.display()}' copies a '{hop.copied.display()}' here", known_location(hop.loc)
            );
        } else {
            diagnostic = diagnostic.with_note(
                $"'{hop.owner.display()}' copies its values of type '{hop.copied.display()}'", Optional<Location>.Empty
            );
        }
    }
    var decl = Loc.none();
    match (blocker.kind) {
        Destructor => {
            diagnostic = diagnostic.with_note(
                $"'{blocker.ty.display()}' has a destructor, so copying its fields would release what it owns twice",
                known_location(blocker.loc)
            );
            decl = blocker.loc;
        }
        RawPointerField => {
            diagnostic = diagnostic.with_note(
                $"'{blocker.ty.display()}' has raw pointer field '{blocker.field}' of type '{blocker.field_ty.display()}'",
                known_location(blocker.loc)
            );
            var st = _struct_named(module, blocker.ty);
            if (st.is_value()) {
                decl = st.value().loc;
            }
        }
        NotCopyable => {
            var why = blocker.why.is_empty ? "cannot be copied" : blocker.why;
            return diagnostic.with_note($"'{blocker.ty.display()}' {why}", known_location(blocker.loc));
        }
        PlainFunction => {
            var shared = blocker.ty;
            if (shared.is_function_type()) {
                shared = TypeName.with_args(SHARED_FUNCTION, shared.sub_types);
                shared.flags = blocker.ty.flags;
                shared.labels = blocker.ty.labels;
            }
            return diagnostic.with_note(
                $"a plain function value may capture values that are not thread-safe; declare the type '{shared.display()}' to pass it by reference",
                Optional<Location>.Empty
            );
        }
        RawPointer => {
            return diagnostic.with_note(
                "the compiler cannot tell what a raw pointer points at; wrap it in a struct that implements 'Copyable<T>'",
                Optional<Location>.Empty
            );
        }
        Weak => {
            return diagnostic.with_note(
                "keep the weak reference in a struct field, such as the one in 'Weak<T>', which copies it",
                Optional<Location>.Empty
            );
        }
    }
    # A struct that is not trivially copyable can say how it is copied.
    diagnostic = diagnostic.with_note(
        $"implement 'Copyable<{_written(blocker.ty)}>' to say how to copy it:\n{_skeleton(blocker.ty, "    ")}",
        Optional<Location>.Empty
    );
    # The editor applies a fix to the file it shows: offer one when the
    # struct is declared in the file the error is in.
    if (!decl.is_none() and !at.is_none() and at.file == decl.file) {
        var end = _struct_end(state, decl);
        if (end.is_value()) {
            var insert = Location(decl.file as ulong, ast.Span(end.value(), end.value()));
            diagnostic = diagnostic.with_fix(
                Fix($"Implement Copyable<{_written(blocker.ty)}>", insert, $"\n\n{_skeleton(blocker.ty, "")}")
            );
        }
    }
    return diagnostic;
}

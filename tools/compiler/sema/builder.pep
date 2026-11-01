## The builder. It makes the sema model of one linked file's syntax tree:
## `for`, `with`, `match`, `is`, `?`, destructuring, ranges, collection
## literals and properties lower to simpler statements and expressions, and
## the checks that need only the syntax report their errors.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [contains_platform_predicate, deprecation_of, is_deprecation] from compiler.link;
import [_is_assignment] from "closures";
import [make_unsigned_literal] from "literals";
import [Loc] from "loc";
import [
    AccessorKind,
    BinaryExpression,
    BinaryOp,
    Block,
    Bound,
    Branch,
    CaseChoice,
    CasePattern,
    CaseValue,
    CastExpression,
    CastKind,
    ClosureLiteral,
    Declaration,
    DestructureExpression,
    ElementName,
    EmitIfStaticItem,
    EnumCaseDef,
    EnumDef,
    Expression,
    ExtensionDef,
    ExternDef,
    ForStaticItem,
    FunctionCallExpression,
    FunctionDef,
    GenericParam,
    IfStaticItem,
    IndexExpression,
    InvokeExpression,
    JumpStaticItem,
    Kind,
    LoopBreak,
    LoopBreakKind,
    MatchArmTest,
    MatchSite,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    ModuleStaticBlock,
    NamedArgumentExpression,
    PropertyDef,
    ReturnStatement,
    Statement,
    StaticBlock,
    StaticCaseExpression,
    StaticItem,
    StaticMember,
    StaticValue,
    StringLiteralExpression,
    StructDef,
    SubjectExpression,
    SymbolRefExpression,
    TernaryExpression,
    TraitDef,
    TypeAliasDef,
    TypeName,
    TypeUse,
    UnaryExpression,
    UnaryOp,
    UseContext,
    VarStaticItem,
    VariableDef,
    While,
    WhileStaticItem,
    WithSubject
] from "model";
import [_declared_in] from "named_arguments";
import [AUTO, POINTER, TUPLE] from "type_name";
import [Rewriter, rewrite_block, rewrite_children, rewrite_expression, rewrite_statement] from "walk";

## What a build step makes, or the error that stops the build.
type Built<T> = Result<T, Diagnostic>;

## The call a range `a..b` lowers to (runtime/range.pep).
export const RANGE_FUNCTION = "_range";

## What the hidden iterator of each `for` loop is named, before its number.
export const FOR_ITERATOR = "__for_iterator_";
## The type of a `const` initialized with a string literal.
export const STRING_CONSTANT = "StringConstant";
## The name `e as? T` binds the converted value to.
export const CAST_VALUE = "__cast_value";
## The hidden local that holds a `?` operand: `__try_0`, `__try_1`, ...
export const TRY_LOCAL = "__try_";
## A hidden local holding an operand evaluated before a later `?`, or the
## value of an `&&` or `||` whose right operand uses `?`.
export const VALUE_LOCAL = "__value_";
## The hidden local holding the value of a `?:` or `match` with a `?` in a
## branch; its initializer only gives it a type.
export const BRANCH_LOCAL = "__branch_";
## The compile-time API's name inside a `static` block.
export const REFLECT = "reflect";
## The function an interpolated string (`$"{x}"`) calls on each value.
export const INTERPOLATE = "_pep_interpolate";
## The field of a reference enum's object that says which case it is.
export const TAG_FIELD = "__tag";
## The attribute that makes a struct shareable between threads.
export const SHARED_ATTRIBUTE = "Shared";
## The attribute that makes a struct a value.
export const VALUE_ATTRIBUTE = "Value";
## The attribute that lets a one-argument constructor convert implicitly.
export const IMPLICIT_ATTRIBUTE = "Implicit";

## The attribute that gives a module-scope variable a separate value on
## every thread.
export const THREAD_LOCAL_ATTRIBUTE = "ThreadLocal";
## The name of a property's storage inside its accessors.
export const PROPERTY_FIELD = "field";
## The name of the value a property's `set` accessor receives.
export const PROPERTY_VALUE = "value";

## Returns whether every enum has method `name` without declaring it.
##
## @param name the method
## @returns true for `name` and `from_value`
export is_enum_built_in_method(name: String): bool {
    return name == "name" or name == "from_value";
}

## The intrinsic `unsafe_cast<T>(value)`.
const _UNSAFE_CAST = "unsafe_cast";

## Whether `name` is a method of a reflected member, case or function that
## emits code.
_is_emitting_method(name: String): bool {
    return name == "get" or name == "set" or name == "call" or name == "matches";
}

## The most steps one chain of a collection literal holds.
const _LITERAL_CHUNK: ulong = 16;
## The method that joins two chains of a long collection literal.
const _LITERAL_THEN = "_literal_then";

## Builds the model of `module`, the syntax tree of file `file`, with every
## location pointing into that file. Hidden locals are numbered from zero in
## each file. Members the passes synthesize come later.
##
## @param module the file's linked syntax tree
## @param file the file's index in the program
## @returns the model, or the first error
export build_file(module: ast.Module, file: uint): Result<Module, Diagnostic> {
    var builder = _Builder(file);
    var built = builder.build_module(module);
    if (builder.type_error.is_value()) {
        return Result<Module, Diagnostic>.Err(builder.type_error.value());
    }
    if (built.is_ok()) {
        var out = built.value();
        out.type_uses = builder.type_uses;
        out.use_contexts = builder.use_contexts;
        out.literal_args = builder.literal_args;
        out.properties = builder.properties;
    }
    return built;
}

## The getter method of property `name`.
##
## @param name the property
## @returns the method's name
export getter_name(name: String): String {
    return "__get_" + name;
}

## The setter method of property `name`.
##
## @param name the property
## @returns the method's name
export setter_name(name: String): String {
    return "__set_" + name;
}

## The storage field of property `name` when its `get` has a body.
##
## @param name the property
## @returns the field's name
export storage_name(name: String): String {
    return "__field_" + name;
}

## The field of a reference enum's object that holds `value` of case `case`:
## `Text.text`.
##
## @param case the case
## @param value the case's value
## @returns the field's name
export payload_field(case: String, value: String): String {
    return $"{case}.{value}";
}

## Returns whether `attributes` include a bare `[name]`.
##
## @param attributes the attributes
## @param name the attribute's name
## @returns true when one is `[name]`
export has_bare_attribute(attributes: ast.Attribute[], name: String): bool {
    for (var a in attributes) {
        if (a.body is SymbolRef(id, _)) {
            if (id == name) {
                return true;
            }
        }
    }
    return false;
}

## The free function a method `method` of enum `enum_name` becomes:
## `Color::name`, with an operator's `<` and `>` spelled `{` and `}`.
##
## @param enum_name the enum
## @param method the method, with any type arguments
## @returns the function's name
export enum_method_name(enum_name: String, method: String): String {
    var name = method;
    var type_arguments = "";
    var at = method.find("<");
    if (at > 0 and method.ends_with(">")) {
        name = method.substr_bytes(0, at as ulong);
        type_arguments = method.substr_bytes(at as ulong, method.size - at as ulong);
    }
    if (name.contains("<") or name.contains(">")) {
        name = name.replace("<", "{").replace(">", "}");
    }
    return $"{enum_name}::{name}{type_arguments}";
}

## The `this` parameter of an instance method of enum `enum_name`.
##
## @param enum_name the enum
## @returns the parameter
export enum_this_parameter(enum_name: String): VariableDef {
    return VariableDef(
        name = "this",
        ty = TypeName.named(enum_name),
        kind = Kind.Param,
        loc = Loc.none(),
        type_loc = Loc.none(),
        is_const = true
    );
}

## The smallest and largest value of an integer type.
##
## @param name the type's name
## @returns the range
export integer_range(name: String): (long, long) {
    match (name) {
        "i8", "char" => {
            return (-128, 127);
        }
        "u8", "byte" => {
            return (0, 255);
        }
        "i16", "short" => {
            return (-32768, 32767);
        }
        "u16", "ushort" => {
            return (0, 65535);
        }
        "u32", "uint" => {
            return (0, 4294967295);
        }
        "i64", "long", "u64", "ulong" => {
            # `ulong`'s top half is past `long`; a case value is a `long`.
            return (-9223372036854775807 - 1, 9223372036854775807);
        }
        else => {
            return (-2147483648, 2147483647);
        }
    }
}

## The constructor a tuple literal calls before its type is known:
## `__tuple`, or `__tuple(line,column)` for a labeled literal.
##
## @param labels the literal's labels
## @returns the constructor's name
export tuple_constructor_name(labels: String[]): String {
    if (labels.count == 0) {
        return TUPLE;
    }
    return $"{TUPLE}({",".join(labels)})";
}

## `ty`, built from `t`, when a tuple written in `t` labels its elements:
## a call's function string spells `ty` without them.
_labeled(t: ast.TypeName, ty: TypeName): TypeName? {
    return _has_labels(t) ? Optional<TypeName>.Value(ty) : Optional<TypeName>.Empty;
}

## Whether a tuple written in `t` labels its elements.
_has_labels(t: ast.TypeName): bool {
    if (t.labels.count > 0) {
        return true;
    }
    for (var a in t.generic_types) {
        if (_has_labels(a)) {
            return true;
        }
    }
    return false;
}

## The arithmetic intrinsic a call to `name` stands for.
_intrinsic(name: String): BinaryOp? {
    match (name) {
        "__wrapping_add" => {
            return Optional<BinaryOp>.Value(BinaryOp.WrappingAdd);
        }
        "__wrapping_sub" => {
            return Optional<BinaryOp>.Value(BinaryOp.WrappingSub);
        }
        "__wrapping_mul" => {
            return Optional<BinaryOp>.Value(BinaryOp.WrappingMul);
        }
        "__add_overflows" => {
            return Optional<BinaryOp>.Value(BinaryOp.AddOverflows);
        }
        "__sub_overflows" => {
            return Optional<BinaryOp>.Value(BinaryOp.SubOverflows);
        }
        "__mul_overflows" => {
            return Optional<BinaryOp>.Value(BinaryOp.MulOverflows);
        }
        else => {
            return Optional<BinaryOp>.Empty;
        }
    }
}

_binary_op(op: String): BinaryOp? {
    match (op) {
        "+" => {
            return Optional<BinaryOp>.Value(BinaryOp.Add);
        }
        "-" => {
            return Optional<BinaryOp>.Value(BinaryOp.Sub);
        }
        "*" => {
            return Optional<BinaryOp>.Value(BinaryOp.Mul);
        }
        "/" => {
            return Optional<BinaryOp>.Value(BinaryOp.Div);
        }
        "%" => {
            return Optional<BinaryOp>.Value(BinaryOp.Mod);
        }
        "<<" => {
            return Optional<BinaryOp>.Value(BinaryOp.LShift);
        }
        ">>" => {
            return Optional<BinaryOp>.Value(BinaryOp.RShift);
        }
        "&" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitAnd);
        }
        "&&", "and" => {
            return Optional<BinaryOp>.Value(BinaryOp.LogicalAnd);
        }
        "|" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitOr);
        }
        "||", "or" => {
            return Optional<BinaryOp>.Value(BinaryOp.LogicalOr);
        }
        "^" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitXor);
        }
        "==" => {
            return Optional<BinaryOp>.Value(BinaryOp.Equal);
        }
        ">=" => {
            return Optional<BinaryOp>.Value(BinaryOp.GreaterEqual);
        }
        "<=" => {
            return Optional<BinaryOp>.Value(BinaryOp.LessEqual);
        }
        ">" => {
            return Optional<BinaryOp>.Value(BinaryOp.Greater);
        }
        "<" => {
            return Optional<BinaryOp>.Value(BinaryOp.Less);
        }
        "!=" => {
            return Optional<BinaryOp>.Value(BinaryOp.NotEqual);
        }
        "**" => {
            return Optional<BinaryOp>.Value(BinaryOp.Pow);
        }
        "===" => {
            return Optional<BinaryOp>.Value(BinaryOp.Identical);
        }
        "!==" => {
            return Optional<BinaryOp>.Value(BinaryOp.NotIdentical);
        }
        "=" => {
            return Optional<BinaryOp>.Value(BinaryOp.Assign);
        }
        "+=" => {
            return Optional<BinaryOp>.Value(BinaryOp.AddAssign);
        }
        "-=" => {
            return Optional<BinaryOp>.Value(BinaryOp.SubAssign);
        }
        "*=" => {
            return Optional<BinaryOp>.Value(BinaryOp.MulAssign);
        }
        "/=" => {
            return Optional<BinaryOp>.Value(BinaryOp.DivAssign);
        }
        "%=" => {
            return Optional<BinaryOp>.Value(BinaryOp.ModAssign);
        }
        "<<=" => {
            return Optional<BinaryOp>.Value(BinaryOp.LShiftAssign);
        }
        ">>=" => {
            return Optional<BinaryOp>.Value(BinaryOp.RShiftAssign);
        }
        "&=" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitAndAssign);
        }
        "|=" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitOrAssign);
        }
        "^=" => {
            return Optional<BinaryOp>.Value(BinaryOp.BitXorAssign);
        }
        else => {
            return Optional<BinaryOp>.Empty;
        }
    }
}

_unary_op(op: String, prefix: bool): UnaryOp? {
    match (op) {
        "+" => {
            return Optional<UnaryOp>.Value(UnaryOp.Pos);
        }
        "-" => {
            return Optional<UnaryOp>.Value(UnaryOp.Neg);
        }
        "++" => {
            return Optional<UnaryOp>.Value(prefix ? UnaryOp.PreInc : UnaryOp.PostInc);
        }
        "--" => {
            return Optional<UnaryOp>.Value(prefix ? UnaryOp.PreDec : UnaryOp.PostDec);
        }
        "!" => {
            return Optional<UnaryOp>.Value(UnaryOp.LogicalNot);
        }
        "~" => {
            return Optional<UnaryOp>.Value(UnaryOp.BitNot);
        }
        else => {
            return Optional<UnaryOp>.Empty;
        }
    }
}

## Where a diagnostic about `at` points.
_location(at: Loc): Location {
    return Location(at.file as ulong, at.span);
}

## The error `message` at `at`.
_error(message: String, at: Loc): Diagnostic {
    return Diagnostic.error(message).at(_location(at));
}

## `diagnostic` with the note `message` at `at`.
_noted(diagnostic: Diagnostic, message: String, at: Loc): Diagnostic {
    return diagnostic.with_note(message, Optional<Location>.Value(_location(at)));
}

## `diagnostic` with the note `message`, at no place.
_noted_nowhere(diagnostic: Diagnostic, message: String): Diagnostic {
    return diagnostic.with_note(message, Optional<Location>.Empty);
}

## A reference to `id`, of a type not inferred yet, at `at`.
_symbol(id: String, at: Loc): Expression {
    return Expression.SymbolRef(SymbolRefExpression(id = id, ty = TypeName.auto(), loc = at));
}

## `receiver.method(args)` at `at`; `labeled` is the method as written,
## when its type arguments' tuples have labels.
_method_call(
    receiver: Expression, method: String, args: Expression[], at: Loc, labeled: TypeName? = Optional<TypeName>.Empty
): Expression {
    return Expression.MethodCall(
        MethodCallExpression(receiver, method = method, args = args, loc = at, labeled = labeled)
    );
}

## `function(args)` at `at`; `labeled` is the type a call naming a type
## is written with, when its tuples have labels.
_call(function: String, args: Expression[], at: Loc, labeled: TypeName? = Optional<TypeName>.Empty): Expression {
    return Expression.FunctionCall(
        FunctionCallExpression(function = function, args = args, loc = at, labeled = labeled)
    );
}

## `lhs op rhs` at `at`.
_binary(op: BinaryOp, lhs: Expression, rhs: Expression, at: Loc): Expression {
    return Expression.Binary(BinaryExpression(lhs, rhs, op = op, loc = at));
}

## `lhs.name` at `at`.
_member(lhs: Expression, name: String, at: Loc): Expression {
    return Expression.MemberRef(MemberRefExpression(lhs, name = name, loc = at));
}

## A hidden local `name` initialized with `value`, at `at`.
_hidden(name: String, value: Expression, at: Loc): VariableDef {
    return VariableDef(
        name = name,
        ty = TypeName.auto(),
        default = Optional<Expression>.Value(value),
        hidden = true,
        loc = at,
        type_loc = Loc.none()
    );
}

## The declaration of `variable` as a statement.
_declare(variable: VariableDef): Statement {
    return Statement.Declaration(Declaration.Variable(variable));
}

## An unnamed block of `items`.
_block_of(items: Statement[]): Block {
    return Block(items = items);
}

## Element `index` of the hidden tuple local `tuple`, at `at`.
_tuple_element(tuple: String, index: ulong, at: Loc): Expression {
    return _member(_symbol(tuple, at), $"{index}", at);
}

## Element `index` of the tuple `subject`: `subject.0`.
_element_path(subject: Expression, index: ulong, at: Loc): Expression {
    return _member(subject.copy(), $"{index}", at);
}

## A function with no parameters and an empty body, as a struct's
## `__acquire` and `__release` start.
_empty_method(parent: String, name: String): FunctionDef {
    return FunctionDef(
        name = name,
        ty = TypeName.void(),
        body = Optional<Block>.Value(Block()),
        parent = Optional<String>.Value(parent),
        loc = Loc.none(),
        owner = Loc.none()
    );
}

## The `[Implicit]` attribute among `attributes`, if there is one.
_implicit_attribute(attributes: ast.Attribute[]): ast.Attribute? {
    for (var a in attributes) {
        if (a.body is SymbolRef(id, _)) {
            if (id == IMPLICIT_ATTRIBUTE) {
                return Optional<ast.Attribute>.Value(a);
            }
        }
    }
    return Optional<ast.Attribute>.Empty;
}

## The bare `[name]` attribute among `attributes`, if there is one.
_bare_attribute(attributes: ast.Attribute[], name: String): ast.Attribute? {
    for (var a in attributes) {
        if (a.body is SymbolRef(id, _)) {
            if (id == name) {
                return Optional<ast.Attribute>.Value(a);
            }
        }
    }
    return Optional<ast.Attribute>.Empty;
}

## The value of an integer constant: a literal, a character literal, or
## either negated.
_constant_integer(e: ast.Expression): long? {
    match (e) {
        Literal(value, _) => {
            match (value) {
                Integer(v) => {
                    return Optional<long>.Value(v);
                }
                Unsigned(v) => {
                    return Optional<long>.Value(unsafe_cast<long>(v));
                }
                Char(v) => {
                    return Optional<long>.Value(v as long);
                }
                else => {}
            }
        }
        Unary(op, prefix, operand, _) => {
            if (prefix and op == "-") {
                var inner = _constant_integer(operand);
                if (inner.is_value()) {
                    return Optional<long>.Value((0 as long).wrapping_sub(inner.value()));
                }
            } else if (prefix and op == "+") {
                return _constant_integer(operand);
            }
        }
        else => {}
    }
    return Optional<long>.Empty;
}

## The element type an array literal takes in a slot of type `ty`: the `T`
## of `Array<T>`, or the `K` of `HashSet<K>`.
_literal_element(ty: TypeName): TypeName? {
    if ((ty.name == "Array" or ty.name == "HashSet") and ty.sub_types.count == 1) {
        return Optional<TypeName>.Value(ty.sub_types[0]);
    }
    return Optional<TypeName>.Empty;
}

## The key and value types of `HashMap<K, V>`.
_map_types(ty: TypeName): (TypeName, TypeName)? {
    if (ty.name == "HashMap" and ty.sub_types.count == 2) {
        return Optional<(TypeName, TypeName)>.Value((ty.sub_types[0], ty.sub_types[1]));
    }
    return Optional<(TypeName, TypeName)>.Empty;
}

## The id of the subject of the long collection literal at `at`.
_literal_subject_id(at: Loc): ulong {
    return ((1 as ulong) << 61) | ((at.file as ulong) << 32) | at.span.start;
}

## The collection literal `start` followed by `steps`, each the arguments of
## one call of method `step`, at `at`: one chain of calls, or for more than
## `_LITERAL_CHUNK` steps a balanced tree of short chains over one
## subject.
_build_literal(start: Expression, steps: Expression[][], step: String, subject: TypeName, at: Loc): Expression {
    if (steps.count <= _LITERAL_CHUNK) {
        return _chain(start, steps, 0, steps.count, step, at);
    }
    var id = _literal_subject_id(at);
    var level = Array<Expression>();
    ulong i = 0;
    while (i < steps.count) {
        var end = i + _LITERAL_CHUNK;
        if (end > steps.count) {
            end = steps.count;
        }
        var head = Expression.Subject(SubjectExpression(id = id, ty = subject.copy(), loc = at));
        level.append(_chain(head, steps, i, end, step, at));
        i = end;
    }
    while (level.count > 1) {
        var next = Array<Expression>();
        ulong j = 0;
        while (j < level.count) {
            if (j + 1 < level.count) {
                next.append(_method_call(level[j], _LITERAL_THEN, [level[j + 1]], at));
            } else {
                next.append(level[j]);
            }
            j += 2;
        }
        level = next;
    }
    return Expression.WithSubject(WithSubject(start, level[0], id = id, loc = at));
}

## `receiver.step(steps[from])...step(steps[to - 1])`.
_chain(receiver: Expression, steps: Expression[][], from: ulong, to: ulong, step: String, at: Loc): Expression {
    var out = receiver;
    ulong i = from;
    while (i < to) {
        out = _method_call(out, step, steps[i], at);
        i += 1;
    }
    return out;
}

## The context a build step saved, to restore when it is done.
struct _SavedContext {
    var context: UseContext;
    var index: ulong?;

    construct(context: UseContext, index: ulong?) {
        this.context = context;
        this.index = index;
    }
}

## A name a pattern may bind, as `match_bindings` sees it: a bare name in a
## tuple pattern or a nested case pattern (`element`), or a value the case
## of `pattern` carries at `index` (a payload).
struct _Leaf {
    var name: String;
    var span: ast.Span;
    var payload: bool;
    var path: Expression;
    var key: String[];
    var pattern: ast.Pattern?;
    var index: ulong;

    construct(
        name: String,
        span: ast.Span,
        payload: bool,
        path: Expression,
        key: String[],
        pattern: ast.Pattern?,
        index: ulong
    ) {
        this.name = name;
        this.span = span;
        this.payload = payload;
        this.path = path;
        this.key = key;
        this.pattern = pattern;
        this.index = index;
    }
}

## A name an arm binds: the value it reads, and where it is bound.
struct _Binding {
    var name: String;
    var value: Expression;
    var at: Loc;

    construct(name: String, value: Expression, at: Loc) {
        this.name = name;
        this.value = value;
        this.at = at;
    }
}

## One arm of a `match` statement as `lower_match_statement` takes it.
struct _Arm {
    var patterns: ast.Pattern[];
    var guard: ast.Expression?;
    var body: ast.Block;

    construct(patterns: ast.Pattern[], guard: ast.Expression?, body: ast.Block) {
        this.patterns = patterns;
        this.guard = guard;
        this.body = body;
    }
}

## The names bound inside a `static` block, innermost scope last.
struct _StaticNames {
    var compile_time: HashSet<String>[] = Array<HashSet<String>>();
    var runtime: HashSet<String>[] = Array<HashSet<String>>();
    ## The compile-time loops around the statement being built.
    var loops: ulong;
    ## The statement is in a branch of a runtime `if`.
    var in_runtime_if: bool;
    ## The block is at module scope, where nothing is emitted.
    var module_scope: bool;

    construct(module_scope: bool) {
        this.module_scope = module_scope;
        push();
    }

    push() {
        compile_time.append(HashSet<String>());
        runtime.append(HashSet<String>());
    }

    pop() {
        compile_time.pop();
        runtime.pop();
    }

    ## Whether the innermost binding of `name` is a runtime one.
    is_runtime(name: String): bool {
        ulong i = compile_time.count;
        while (i > 0) {
            i -= 1;
            if (runtime[i].contains(name)) {
                return true;
            }
            if (compile_time[i].contains(name)) {
                return false;
            }
        }
        return false;
    }

    declare(name: String, is_runtime: bool) {
        var last = compile_time.count - 1;
        if (is_runtime) {
            runtime[last].insert(name);
            compile_time[last].remove(name);
        } else {
            compile_time[last].insert(name);
            runtime[last].remove(name);
        }
    }

    compile_time_names(): HashSet<String> {
        var names = HashSet<String>();
        names.insert(REFLECT);
        ulong i = 0;
        while (i < compile_time.count) {
            for (var name in compile_time[i]) {
                names.insert(name);
            }
            for (var name in runtime[i]) {
                names.remove(name);
            }
            i += 1;
        }
        return names;
    }

    ## Whether `expr` uses a runtime name of the block, or emits code itself.
    mentions_runtime(expr: ast.Expression): bool {
        var found = !module_scope and _emits(expr);
        var names = Array<String>();
        _symbols(expr, names);
        for (var name in names) {
            if (is_runtime(name)) {
                found = true;
            }
        }
        return found;
    }
}

## Whether `expr` calls `get`, `set`, `call` or `matches` on something.
_emits(expr: ast.Expression): bool {
    match (expr) {
        FunctionCall(function, arguments, _) => {
            if (function is MemberAccess(_, name, _, _)) {
                if (_is_emitting_method(name)) {
                    return true;
                }
            }
            if (_emits(function)) {
                return true;
            }
            for (var a in arguments) {
                if (_emits(a)) {
                    return true;
                }
            }
            return false;
        }
        Unary(_, _, operand, _) => {
            return _emits(operand);
        }
        Binary(lhs, _, rhs, _) => {
            return _emits(lhs) or _emits(rhs);
        }
        Index(lhs, rhs, _) => {
            return _emits(lhs) or _emits(rhs);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return _emits(condition) or _emits(true_expr) or _emits(false_expr);
        }
        MemberAccess(lhs, _, _, _) => {
            return _emits(lhs);
        }
        NamedArgument(_, _, value, _) => {
            return _emits(value);
        }
        else => {
            return false;
        }
    }
}

## Every name `expr` refers to as a value, closure bodies included, in order.
_symbols(expr: ast.Expression, out: String[]) {
    match (expr) {
        SymbolRef(id, _) => {
            out.append(id);
        }
        TypeLiteral(type_name) => {
            var parts = type_name.name.split_once(".");
            if (parts.is_value()) {
                out.append(parts.value().0);
            }
        }
        Unary(_, _, operand, _) => {
            _symbols(operand, out);
        }
        Cast(inner, _, _, _, _) => {
            _symbols(inner, out);
        }
        Binary(lhs, _, rhs, _) => {
            _symbols(lhs, out);
            _symbols(rhs, out);
        }
        Index(lhs, rhs, _) => {
            _symbols(lhs, out);
            _symbols(rhs, out);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            _symbols(condition, out);
            _symbols(true_expr, out);
            _symbols(false_expr, out);
        }
        MemberAccess(lhs, _, _, _) => {
            _symbols(lhs, out);
        }
        FunctionCall(function, arguments, _) => {
            _symbols(function, out);
            for (var a in arguments) {
                _symbols(a, out);
            }
        }
        NamedArgument(_, _, value, _) => {
            _symbols(value, out);
        }
        Closure(closure) => {
            _block_symbols(closure.body, out);
        }
        Tuple(elements, _, _) => {
            for (var e in elements) {
                _symbols(e, out);
            }
        }
        ArrayLiteral(elements, _) => {
            for (var e in elements) {
                _symbols(e, out);
            }
        }
        MapLiteral(entries, _) => {
            for (var entry in entries) {
                _symbols(entry.key, out);
                _symbols(entry.value, out);
            }
        }
        Match(m) => {
            _symbols(m.value, out);
            for (var arm in m.arms) {
                if (arm.guard.is_value()) {
                    _symbols(arm.guard.value(), out);
                }
            }
            for (var arm in m.arms) {
                _symbols(arm.value, out);
            }
            if (m.else_value.is_value()) {
                _symbols(m.else_value.value(), out);
            }
        }
        Is(value, _, _, _) => {
            _symbols(value, out);
        }
        else => {}
    }
}

_block_symbols(block: ast.Block, out: String[]) {
    for (var statement in block.statements) {
        match (statement) {
            Expression(e) => {
                _symbols(e, out);
            }
            Declaration(declaration) => {
                if (declaration is Variable(v)) {
                    if (v.default_value.is_value()) {
                        _symbols(v.default_value.value(), out);
                    }
                }
            }
            Return(value, _) => {
                if (value.is_value()) {
                    _symbols(value.value(), out);
                }
            }
            Block(inner) => {
                _block_symbols(inner, out);
            }
            Branch(condition, if_block, else_block, _) => {
                _symbols(condition, out);
                _block_symbols(if_block, out);
                if (else_block.is_value()) {
                    _block_symbols(else_block.value(), out);
                }
            }
            While(condition, body, _) => {
                _symbols(condition, out);
                _block_symbols(body, out);
            }
            For(_, _, iterable, body, _) => {
                _symbols(iterable, out);
                _block_symbols(body, out);
            }
            else => {}
        }
    }
}

## Whether `expr` uses at least one of the compile-time `names` and nothing
## else: no runtime value, function, closure or `match`. `_pep_interpolate`
## is allowed.
_is_compile_time(expr: ast.Expression, names: HashSet<String>): bool {
    var any = Array<bool>();
    return _only_compile_time(expr, names, any) and any.count > 0;
}

_only_compile_time(expr: ast.Expression, names: HashSet<String>, any: bool[]): bool {
    match (expr) {
        Literal(_, _) => {
            return true;
        }
        SymbolRef(id, _) => {
            if (names.contains(id)) {
                any.append(true);
                return true;
            }
            return false;
        }
        TypeLiteral(type_name) => {
            var parts = type_name.name.split_once(".");
            if (parts.is_value() and names.contains(parts.value().0)) {
                any.append(true);
                return true;
            }
            return false;
        }
        Unary(_, _, operand, _) => {
            return _only_compile_time(operand, names, any);
        }
        Binary(lhs, _, rhs, _) => {
            return _only_compile_time(lhs, names, any) and _only_compile_time(rhs, names, any);
        }
        Index(lhs, rhs, _) => {
            return _only_compile_time(lhs, names, any) and _only_compile_time(rhs, names, any);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return _only_compile_time(condition, names, any)
                and _only_compile_time(true_expr, names, any)
                and _only_compile_time(false_expr, names, any);
        }
        MemberAccess(lhs, _, _, _) => {
            return _only_compile_time(lhs, names, any);
        }
        FunctionCall(function, arguments, _) => {
            var callee = false;
            if (function is SymbolRef(id, _)) {
                callee = id == INTERPOLATE;
            }
            if (!callee) {
                callee = _only_compile_time(function, names, any);
            }
            if (!callee) {
                return false;
            }
            for (var a in arguments) {
                if (!_only_compile_time(a, names, any)) {
                    return false;
                }
            }
            return true;
        }
        NamedArgument(_, _, value, _) => {
            return _only_compile_time(value, names, any);
        }
        else => {
            return false;
        }
    }
}

## The source `statement` covers, for `--emit-static`.
_written(statement: ast.Statement): ast.Span {
    if (statement is Expression(e)) {
        return e.extent();
    }
    return statement.span();
}

_contains_is(expr: ast.Expression): bool {
    match (expr) {
        Is(_, _, _, _) => {
            return true;
        }
        Binary(lhs, _, rhs, _) => {
            return _contains_is(lhs) or _contains_is(rhs);
        }
        Unary(_, _, operand, _) => {
            return _contains_is(operand);
        }
        else => {
            return false;
        }
    }
}

## Whether `e` uses `?` outside a closure body.
_has_try(e: ast.Expression): bool {
    match (e) {
        Unary(op, _, operand, _) => {
            return op == "?" or _has_try(operand);
        }
        Binary(lhs, _, rhs, _) => {
            return _has_try(lhs) or _has_try(rhs);
        }
        Index(lhs, rhs, _) => {
            return _has_try(lhs) or _has_try(rhs);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return _has_try(condition) or _has_try(true_expr) or _has_try(false_expr);
        }
        MemberAccess(lhs, _, _, _) => {
            return _has_try(lhs);
        }
        Cast(inner, _, _, _, _) => {
            return _has_try(inner);
        }
        FunctionCall(function, arguments, _) => {
            if (_has_try(function)) {
                return true;
            }
            for (var a in arguments) {
                if (_has_try(a)) {
                    return true;
                }
            }
            return false;
        }
        NamedArgument(_, _, value, _) => {
            return _has_try(value);
        }
        Is(value, _, _, _) => {
            return _has_try(value);
        }
        Tuple(elements, _, _) => {
            for (var element in elements) {
                if (_has_try(element)) {
                    return true;
                }
            }
            return false;
        }
        ArrayLiteral(elements, _) => {
            for (var element in elements) {
                if (_has_try(element)) {
                    return true;
                }
            }
            return false;
        }
        MapLiteral(entries, _) => {
            for (var entry in entries) {
                if (_has_try(entry.key) or _has_try(entry.value)) {
                    return true;
                }
            }
            return false;
        }
        Match(m) => {
            if (_has_try(m.value)) {
                return true;
            }
            for (var arm in m.arms) {
                if (_has_try(arm.value)) {
                    return true;
                }
            }
            return m.else_value.is_value() and _has_try(m.else_value.value());
        }
        else => {
            return false;
        }
    }
}

## The expression a statement evaluates before anything else, where its
## `?`s are lifted from.
_head(statement: ast.Statement): ast.Expression? {
    match (statement) {
        Expression(e) => {
            return Optional<ast.Expression>.Value(e);
        }
        Declaration(declaration) => {
            if (declaration is Variable(v)) {
                return v.default_value;
            }
        }
        Branch(condition, _, _, _) => {
            return Optional<ast.Expression>.Value(condition);
        }
        For(_, _, iterable, _, _) => {
            return Optional<ast.Expression>.Value(iterable);
        }
        With(_, scope, _, _, _) => {
            return Optional<ast.Expression>.Value(scope);
        }
        Return(value, _) => {
            return value;
        }
        Destructure(_, value, _, _) => {
            return Optional<ast.Expression>.Value(value);
        }
        Match(m) => {
            return Optional<ast.Expression>.Value(m.value);
        }
        else => {}
    }
    return Optional<ast.Expression>.Empty;
}

## `statement` with its head replaced by `head`.
_with_head(statement: ast.Statement, head: ast.Expression): ast.Statement {
    match (statement) {
        Expression(_) => {
            return ast.Statement.Expression(head);
        }
        Declaration(declaration) => {
            if (declaration is Variable(v)) {
                var copy = _copy_variable(v);
                copy.default_value = Optional<ast.Expression>.Value(head);
                return ast.Statement.Declaration(ast.Declaration.Variable(copy));
            }
        }
        Branch(_, if_block, else_block, span) => {
            return ast.Statement.Branch(head, if_block, else_block, span);
        }
        For(binding, pattern, _, body, span) => {
            return ast.Statement.For(binding, pattern, head, body, span);
        }
        With(binding, _, body, else_block, span) => {
            return ast.Statement.With(binding, head, body, else_block, span);
        }
        Return(_, span) => {
            return ast.Statement.Return(Optional<ast.Expression>.Value(head), span);
        }
        Destructure(bindings, _, is_const, span) => {
            return ast.Statement.Destructure(bindings, head, is_const, span);
        }
        Match(m) => {
            var copy = ast.Match(head);
            copy.arms = m.arms;
            copy.else_block = m.else_block;
            copy.else_span = m.else_span;
            copy.keyword_span = m.keyword_span;
            copy.span = m.span;
            return ast.Statement.Match(copy);
        }
        else => {}
    }
    return statement;
}

## A shallow copy of `v`.
_copy_variable(v: ast.VariableDecl): ast.VariableDecl {
    var out = ast.VariableDecl();
    out.attributes = v.attributes;
    out.name = v.name;
    out.name_span = v.name_span;
    out.type_name = v.type_name;
    out.default_value = v.default_value;
    out.is_const = v.is_const;
    out.span = v.span;
    out.is_exported = v.is_exported;
    out.is_private = v.is_private;
    return out;
}

## `receiver.method(arguments)` in the syntax tree, located at `at`.
_ast_method_call(receiver: ast.Expression, method: String, arguments: ast.Expression[], at: ast.Span): ast.Expression {
    return ast.Expression.FunctionCall(ast.Expression.MemberAccess(receiver, method, at, at), arguments, at);
}

## Whether `e` is a `?:` or `match` with a `?` in a branch, outside a
## closure body.
_branch_has_try(e: ast.Expression): bool {
    if (e is Ternary(_, true_expr, false_expr, _)) {
        return _has_try(true_expr) or _has_try(false_expr);
    }
    if (e is Match(m)) {
        for (var arm in m.arms) {
            if (_has_try(arm.value)) {
                return true;
            }
        }
        return m.else_value.is_value() and _has_try(m.else_value.value());
    }
    return false;
}

## Whether an operand of `operands` uses `?`.
_any_has_try(operands: ast.Expression[]): bool {
    for (var operand in operands) {
        if (_has_try(operand)) {
            return true;
        }
    }
    return false;
}

## Whether evaluating `e`, its `?`s already lifted, can do something a
## later `?` must not run before: a call (other than a `?`'s read of its
## hidden local), `++`, `--` or an assignment.
_has_effect(e: ast.Expression): bool {
    match (e) {
        Unary(op, _, operand, _) => {
            return op == "++" or op == "--" or _has_effect(operand);
        }
        Binary(lhs, op, rhs, _) => {
            var binary = _binary_op(op);
            return (binary.is_value() and _is_assignment(binary.value())) or _has_effect(lhs) or _has_effect(rhs);
        }
        Index(lhs, rhs, _) => {
            return _has_effect(lhs) or _has_effect(rhs);
        }
        Ternary(condition, true_expr, false_expr, _) => {
            return _has_effect(condition) or _has_effect(true_expr) or _has_effect(false_expr);
        }
        MemberAccess(lhs, _, _, _) => {
            return _has_effect(lhs);
        }
        Cast(inner, _, _, _, _) => {
            return _has_effect(inner);
        }
        FunctionCall(function, arguments, _) => {
            if (function is MemberAccess(lhs, name, _, _)) {
                if (lhs is SymbolRef(id, _)) {
                    return !(name == "value" and id.starts_with(TRY_LOCAL) and arguments.count == 0);
                }
            }
            return true;
        }
        NamedArgument(_, _, value, _) => {
            return _has_effect(value);
        }
        Is(value, _, _, _) => {
            return _has_effect(value);
        }
        Tuple(elements, _, _) => {
            return _any_has_effect(elements);
        }
        ArrayLiteral(elements, _) => {
            return _any_has_effect(elements);
        }
        MapLiteral(entries, _) => {
            for (var entry in entries) {
                if (_has_effect(entry.key) or _has_effect(entry.value)) {
                    return true;
                }
            }
            return false;
        }
        Match(m) => {
            if (_has_effect(m.value)) {
                return true;
            }
            for (var arm in m.arms) {
                if (_has_effect(arm.value) or (arm.guard.is_value() and _has_effect(arm.guard.value()))) {
                    return true;
                }
            }
            return m.else_value.is_value() and _has_effect(m.else_value.value());
        }
        else => {
            return false;
        }
    }
}

## Whether evaluating an element of `elements` can have an effect
## (`_has_effect`).
_any_has_effect(elements: ast.Expression[]): bool {
    for (var element in elements) {
        if (_has_effect(element)) {
            return true;
        }
    }
    return false;
}

## A block that assigns `value` to `target`, or evaluates it when there is
## none, located at `value`.
_branch_block(target: String?, value: ast.Expression): ast.Block {
    var at = value.span();
    var out = ast.Block(at);
    var statement = value;
    if (target.is_value()) {
        statement = ast.Expression.Binary(ast.Expression.SymbolRef(target.value(), at), "=", value, at);
    }
    out.statements = [ast.Statement.Expression(statement)];
    return out;
}

## Who declares a property, for `property_members`.
struct _PropertyOwner {
    ## `_STRUCT_OWNER`, `_TRAIT_OWNER`, `_EXTENSION_OWNER` or `_ENUM_OWNER`.
    var kind: int;
    ## The struct, trait, extended struct or enum.
    var name: String;
    ## A struct's `[Shared]` attribute, if it has one.
    var shared: ast.Attribute?;

    construct(kind: int, name: String, shared: ast.Attribute?) {
        this.kind = kind;
        this.name = name;
        this.shared = shared;
    }
}

const _STRUCT_OWNER = 0;
const _TRAIT_OWNER = 1;
const _EXTENSION_OWNER = 2;
const _ENUM_OWNER = 3;

## The members a property lowers to.
struct _PropertyMembers {
    var storage: VariableDef?;
    var accessors: FunctionDef[];

    construct(storage: VariableDef?, accessors: FunctionDef[]) {
        this.storage = storage;
        this.accessors = accessors;
    }
}

## Replaces `field` with the property's storage in an accessor body.
struct _FieldReplacer {
    var storage: String;

    construct(storage: String) {
        this.storage = storage;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            if (node.id == PROPERTY_FIELD) {
                return _member(Expression.ThisRef, storage, node.loc);
            }
        }
        return e;
    }
}

extend _FieldReplacer with Rewriter;

## Finds a use of `field` in an accessor body.
struct _FieldFinder {
    var found: bool;

    construct() {}

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            if (node.id == PROPERTY_FIELD) {
                found = true;
            }
        }
        return e;
    }
}

extend _FieldFinder with Rewriter;

## Replaces each name an arm binds with the value it reads, in a `match`
## expression's arm value or an arm's guard. A closure there captures the
## value it reads (`closures`, the subject of a `WithSubject`).
struct _ArmBinder {
    var bindings: _Binding[];

    construct(bindings: _Binding[]) {
        this.bindings = bindings;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            for (var b in bindings) {
                if (b.name == node.id) {
                    return b.value.copy();
                }
            }
        }
        if (e is ClosureLiteral(closure)) {
            # Its body too, but not a name its parameters or its own locals
            # hide.
            var hidden = HashSet<String>();
            for (var p in closure.parameters) {
                hidden.insert(p.name);
            }
            _declared_in(closure.body, hidden);
            var visible = Array<_Binding>();
            for (var b in bindings) {
                if (!hidden.contains(b.name)) {
                    visible.append(b);
                }
            }
            rewrite_block(closure.body, _ArmBinder(visible));
            return e;
        }
        return rewrite_children(e, this);
    }
}

extend _ArmBinder with Rewriter;

## Collects the locals that `move(x)` hands over.
struct _MovedNames {
    var names = HashSet<String>();

    construct() {}

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(node)) {
            if (node.function == "move" and node.args.count == 1) {
                if (node.args[0] is SymbolRef(moved)) {
                    names.insert(moved.id);
                }
            }
        }
        return e;
    }
}

extend _MovedNames with Rewriter;

## The locals `items` (and the blocks and closures in them) move.
_moved_names(items: Statement[]): HashSet<String> {
    var finder = _MovedNames();
    rewrite_block(Block(items = items), finder);
    return finder.names;
}

## Whether `items[start..end]` declares a local named in `names`.
_declares_one_of_names(items: Statement[], start: ulong, end: ulong, names: HashSet<String>): bool {
    for (var i in start..end) {
        if (items[i] is Declaration(declaration)) {
            if (declaration is Variable(variable)) {
                if (names.contains(variable.name)) {
                    return true;
                }
            }
        }
    }
    return false;
}

## Makes each `?`'s read of its hidden local, `__try_N.value()`, move the
## operand out of it, so the operand is released with the read.
struct _TryReleaser {
    construct() {}

    rewrite(e: Expression): Expression {
        if (e is MethodCall(node)) {
            if (node.this_value is SymbolRef(local)) {
                if (node.method == "value" and local.id.starts_with(TRY_LOCAL)) {
                    node.this_value = Expression.Move(MoveExpression(node.this_value, node.loc));
                }
            }
        }
        return e;
    }
}

extend _TryReleaser with Rewriter;

## Returns whether two keys of pattern elements are the same.
_same_key(a: String[], b: String[]): bool {
    if (a.count != b.count) {
        return false;
    }
    ulong i = 0;
    while (i < a.count) {
        if (a[i] != b[i]) {
            return false;
        }
        i += 1;
    }
    return true;
}

## `key` with `part` appended.
_key_with(key: String[], part: String): String[] {
    var out = key.copy();
    out.append(part);
    return out;
}

## The builder's state while it builds one file.
struct _Builder {
    ## The file being built, whose index every location carries.
    var file: uint;
    ## The first bad type `type_name_from` met (a tuple's labels, or
    ## `__ptr` without exactly one argument), reported when the build
    ## finishes.
    var type_error: Diagnostic? = Optional<Diagnostic>.Empty;
    ## The declared return type of the function or closure being built.
    var return_type: ast.TypeName? = Optional<ast.TypeName>.Empty;
    ## The generic types written with arguments so far.
    var type_uses: TypeUse[] = Array<TypeUse>();
    ## The contexts of `type_uses`.
    var use_contexts: UseContext[] = Array<UseContext>();
    ## The context where types are being built.
    var context: UseContext = UseContext();
    ## The index of `context` in `use_contexts`, once a use recorded it.
    var context_index: ulong? = Optional<ulong>.Empty;
    ## Where each literal argument of the calls built so far is written.
    var literal_args: Array<(Loc, ulong, Loc)> = Array<(Loc, ulong, Loc)>();
    ## The properties built so far.
    var properties: PropertyDef[] = Array<PropertyDef>();
    ## The hidden-local counters.
    var tuples: ulong = 0;
    var for_loops: ulong = 0;
    # The labels of the loops around the statement being built, innermost
    # last, which `break label;` and `continue label;` may name.
    var labels: Array<(String, ast.Span)> = Array<(String, ast.Span)>();
    # The label a `Labeled` statement gives the loop it is building, until
    # that loop takes it (`_take_label`).
    var pending_label: String = "";
    var with_blocks: ulong = 0;
    var matches: ulong = 0;
    var tries: ulong = 0;
    ## Whether the expression being built only gives a hidden local its
    ## type (`branches`), so a `?` reads its operand's value.
    var typing_only = false;
    ## The compile-time names where a `static` block's emitted statement is
    ## being built; empty outside a `static` block.
    var compile_time: HashSet<String>? = Optional<HashSet<String>>.Empty;

    construct(file: uint) {
        this.file = file;
    }

    ## `span` in the file being built.
    loc(span: ast.Span): Loc {
        return Loc.at(this.file, span);
    }

    ## `span` in the file being built, or no location when it is empty.
    _type_loc(span: ast.Span): Loc {
        return span.start == span.end ? Loc.none() : loc(span);
    }

    ## Records where each literal among `arguments` of the call at `call` is
    ## written (`-1` included).
    record_literal_args(call: Loc, arguments: ast.Expression[]) {
        ulong i = 0;
        for (var argument in arguments) {
            match (argument) {
                Literal(_, span) => {
                    literal_args.append((call, i, loc(span)));
                }
                Unary(_, _, operand, span) => {
                    if (operand is Literal(_, _)) {
                        literal_args.append((call, i, loc(span)));
                    }
                }
                else => {}
            }
            i += 1;
        }
    }

    ## Makes `changed` the context until `leave` restores what this returns.
    enter(changed: UseContext): _SavedContext {
        var saved = _SavedContext(context, context_index);
        context = changed;
        context_index = Optional<ulong>.Empty;
        return saved;
    }

    ## Restores the context `enter` saved, if it saved one.
    leave(saved: _SavedContext?) {
        if (saved.is_value()) {
            context = saved.value().context;
            context_index = saved.value().index;
        }
    }

    ## Enters a context that carries `attributes`, so a use inside it is
    ## skipped when a `[Target(...)]` among them removes it.
    with_attributes(attributes: ast.Attribute[]): _SavedContext? {
        if (attributes.count == 0) {
            return Optional<_SavedContext>.Empty;
        }
        var changed = context.copy();
        changed.conditions.append_all(attributes);
        return Optional<_SavedContext>.Value(enter(changed));
    }

    ## Records a use of `ty` whose arguments are at `args`.
    push_type_use(ty: TypeName, args: Loc[]) {
        if (context_index.is_empty()) {
            use_contexts.append(context);
            context_index = Optional<ulong>.Value(use_contexts.count - 1);
        }
        type_uses.append(TypeUse(ty = ty, args = args, context = context_index.value()));
    }

    ## Enters the scope of `params`, and of `extend extension` when given, so
    ## the type uses recorded inside know them.
    in_generic_scope(params: ast.GenericParam[], extension: ast.TypeName?): _SavedContext? {
        var recorded = type_uses.count;
        var built = Array<GenericParam>();
        for (var p in params) {
            if (!p.is_argument) {
                built.append(generic_param_from(p));
            }
        }
        var extended = Optional<TypeName>.Empty;
        if (extension.is_value()) {
            extended = Optional<TypeName>.Value(type_name_from(extension.value()));
        }
        type_uses.truncate(recorded);
        if (built.count == 0 and extended.is_empty()) {
            return Optional<_SavedContext>.Empty;
        }
        var changed = context.copy();
        changed.scope.append_all(built);
        if (extended.is_value()) {
            changed.extension = extended;
        }
        return Optional<_SavedContext>.Value(enter(changed));
    }

    ## Records `t`, a generic type written with arguments, as `ty`.
    record_type_use(t: ast.TypeName, ty: TypeName) {
        var named = !t.name.starts_with("__") and !t.name.ends_with("[]") and t.name != "Tuple";
        if (!named or t.generic_types.count == 0) {
            return;
        }
        var args = Array<Loc>();
        for (var a in t.generic_types) {
            if (a.span.start == a.span.end) {
                return;
            }
            args.append(loc(a.span));
        }
        push_type_use(ty.copy(), args);
    }

    ## Rejects a labeled tuple literal whose labels differ from those of the
    ## labeled tuple type `expected` it initializes or returns.
    check_literal_labels(expected: ast.TypeName, value: ast.Expression): Built<bool> {
        match (value) {
            Tuple(elements, labels, _) => {
                if (expected.name != ast.TUPLE_TYPE or expected.generic_types.count != elements.count) {
                    return Built<bool>.Ok(true);
                }
                if (expected.labels.count > 0) {
                    ulong i = 0;
                    while (i < labels.count) {
                        if (labels[i].name != expected.labels[i]) {
                            var shown = type_name_from(expected).display();
                            var message = $"label '{labels[i].name}' does not match '{expected.labels[i]}', the label of element {i} of '{shown}'";
                            return Built<bool>.Err(_error(message, loc(labels[i].span)));
                        }
                        i += 1;
                    }
                }
                ulong j = 0;
                while (j < elements.count) {
                    check_literal_labels(expected.generic_types[j], elements[j])?;
                    j += 1;
                }
            }
            else => {}
        }
        return Built<bool>.Ok(true);
    }

    ## The sema type of the type written `t`: `int[]` is `Array<int>`,
    ## `Tuple<A, B>` is `(A, B)`, and a generic type's use is recorded. A
    ## pointer is `__ptr<T>` however it is written, since the parser makes
    ## that of `T*`.
    type_name_from(t: ast.TypeName): TypeName {
        var args = Array<TypeName>();
        for (var a in t.generic_types) {
            args.append(type_name_from(a));
        }
        if (t.name.ends_with("[]")) {
            var base = ast.TypeName(t.name.substr_bytes(0, t.name.size - 2), ast.Span());
            base.generic_types = t.generic_types;
            base.labels = t.labels;
            var element = type_name_from(base);
            return TypeName.with_args("Array", [element]);
        }
        if (t.name == "Tuple" and args.count >= 2) {
            return TypeName.with_args(TUPLE, args);
        }
        if (t.name == POINTER and args.count != 1 and type_error.is_empty()) {
            type_error = Optional<Diagnostic>.Value(
                _error(
                    $"__ptr<T> takes exactly one type argument, {args.count} given in '{t.to_string()}'", loc(t.span)
                )
            );
        }
        if (args.count == 0) {
            return TypeName.named(t.name);
        }
        check_labels(t);
        var ty = TypeName.with_args(t.name, args);
        ty.labels = t.labels.copy();
        record_type_use(t, ty);
        return ty;
    }

    ## Records an error for a tuple type that labels some elements but not
    ## all, or uses one label twice.
    check_labels(t: ast.TypeName) {
        var error = Optional<Diagnostic>.Empty;
        ulong i = 0;
        while (i < t.labels.count and error.is_empty()) {
            if (t.labels[i].is_empty) {
                ulong j = 0;
                while (j < t.labels.count and t.labels[j].is_empty) {
                    j += 1;
                }
                if (j == t.labels.count) {
                    j = 0;
                }
                var message = $"missing label for element {i} of a labeled tuple: label every element or none";
                error = Optional<Diagnostic>.Value(
                    _noted(
                        _error(message, loc(t.generic_types[i].span)),
                        $"element labeled '{t.labels[j]}' here",
                        loc(t.generic_types[j].span)
                    )
                );
            }
            i += 1;
        }
        if (error.is_empty()) {
            ulong k = 1;
            while (k < t.labels.count and error.is_empty()) {
                ulong first = 0;
                while (first < k) {
                    if (t.labels[first] == t.labels[k]) {
                        error = Optional<Diagnostic>.Value(
                            _noted(
                                _error($"duplicate label '{t.labels[k]}' in tuple type", loc(t.generic_types[k].span)),
                                "previous label here",
                                loc(t.generic_types[first].span)
                            )
                        );
                        break;
                    }
                    first += 1;
                }
                k += 1;
            }
        }
        if (error.is_value() and type_error.is_empty()) {
            type_error = error;
        }
    }

    generic_param_from(p: ast.GenericParam): GenericParam {
        var at = loc(p.name_span);
        var bounds = Array<Bound>();
        for (var b in p.bounds) {
            var ty = type_name_from(b);
            bounds.append(Bound(ty = ty, loc = loc(b.span)));
        }
        var default = Optional<TypeName>.Empty;
        var default_loc = Loc.none();
        if (p.default.is_value()) {
            default = Optional<TypeName>.Value(type_name_from(p.default.value()));
            default_loc = loc(p.default.value().span);
        }
        return GenericParam(
            name = p.name,
            loc = at,
            bounds = bounds,
            default = default,
            default_loc = default_loc,
            is_argument = p.is_argument
        );
    }

    ## A call's arguments: positional ones first, then named ones.
    call_arguments(arguments: ast.Expression[]): Built<Expression[]> {
        var out = Array<Expression>();
        var named = Optional<ast.Span>.Empty;
        for (var argument in arguments) {
            match (argument) {
                NamedArgument(name, name_span, value, _) => {
                    if (named.is_empty()) {
                        named = Optional<ast.Span>.Value(name_span);
                    }
                    var built = expression(value)?;
                    out.append(
                        Expression.NamedArgument(NamedArgumentExpression(built, name = name, loc = loc(name_span)))
                    );
                }
                else => {
                    if (named.is_value()) {
                        var error = _error("positional argument cannot follow a named argument", loc(argument.span()));
                        return Built<Expression[]>.Err(_noted(error, "first named argument here", loc(named.value())));
                    }
                    var built = expression(argument)?;
                    out.append(built);
                }
            }
        }
        return Built<Expression[]>.Ok(out);
    }

    expression(expr: ast.Expression): Built<Expression> {
        # `field.name` in a statement a `static` block emits.
        var placeholder = static_placeholder(expr)?;
        if (placeholder.is_value()) {
            return Built<Expression>.Ok(placeholder.value());
        }
        match (expr) {
            NamedArgument(_, name_span, _, _) => {
                return Built<Expression>.Err(_error("a named argument can only appear in a call", loc(name_span)));
            }
            Literal(value, span) => {
                match (value) {
                    String(text) => {
                        return Built<Expression>.Ok(
                            Expression.StringLiteral(StringLiteralExpression(value = text, loc = loc(span)))
                        );
                    }
                    Integer(v) => {
                        return Built<Expression>.Ok(Expression.IntLiteral(v));
                    }
                    Unsigned(v) => {
                        return Built<Expression>.Ok(make_unsigned_literal(v, loc(span)));
                    }
                    Float(v) => {
                        return Built<Expression>.Ok(Expression.FloatLiteral(v));
                    }
                    Bool(v) => {
                        return Built<Expression>.Ok(Expression.BoolLiteral(v));
                    }
                    Char(v) => {
                        # A `byte`: the cast gives it that type where nothing
                        # else does.
                        var cast = CastExpression(
                            Expression.IntLiteral(v as long),
                            ty = TypeName.named("byte"),
                            loc = loc(span),
                            kind = CastKind.Synthesized
                        );
                        return Built<Expression>.Ok(Expression.Cast(cast));
                    }
                    Null => {
                        return Built<Expression>.Ok(Expression.PointerLiteral);
                    }
                }
            }
            SymbolRef(id, span) => {
                if (id == "this") {
                    return Built<Expression>.Ok(Expression.ThisRef);
                }
                return Built<Expression>.Ok(_symbol(id, loc(span)));
            }
            TypeLiteral(type_name) => {
                var ty = type_name_from(type_name);
                # `make<int>` with no parentheses: a call, unless it names a
                # method (`convert_member_refs`) or needs arguments.
                return Built<Expression>.Ok(
                    Expression.FunctionCall(
                        FunctionCallExpression(
                            ty.to_string(), Array<Expression>(), loc(type_name.span), _labeled(type_name, ty), true
                        )
                    )
                );
            }
            SizeOf(type_name) => {
                return Built<Expression>.Ok(Expression.SizeOf(type_name_from(type_name)));
            }
            Unary(op, prefix, operand, span) => {
                if (op == "?" and !prefix) {
                    if (typing_only) {
                        var read_at = ast.Span(span.end - 1, span.end);
                        return expression(_ast_method_call(operand, "value", Array<ast.Expression>(), read_at));
                    }
                    # A `?` that `lift` left: not in a statement of a function body.
                    var at = loc(ast.Span(span.end - 1, span.end));
                    return Built<Expression>.Err(_error("'?' can be used only in a statement of a function body", at));
                }
                var unary = _unary_op(op, prefix);
                if (unary.is_empty()) {
                    return Built<Expression>.Err(_error($"unsupported unary operator '{op}'", loc(span)));
                }
                var built = expression(operand)?;
                return Built<Expression>.Ok(
                    Expression.Unary(UnaryExpression(built, op = unary.value(), loc = loc(span)))
                );
            }
            Cast(inner, type_name, span, keyword_span, optional) => {
                if (optional) {
                    return optional_cast(inner, type_name, keyword_span, span);
                }
                var built = expression(inner)?;
                var ty = type_name_from(type_name);
                return Built<Expression>.Ok(
                    Expression.Cast(CastExpression(built, ty = ty, loc = loc(keyword_span), kind = CastKind.Static))
                );
            }
            Binary(lhs, op, rhs, span) => {
                if (op == ".." or op == "..>") {
                    # `a..b` is `_range(a, b, false)` and `a..>b` is
                    # `_range(a, b, true)`, located at the operator.
                    var low = expression(lhs)?;
                    var high = expression(rhs)?;
                    var at = loc(ast.Span(span.start, span.start + op.size));
                    return Built<Expression>.Ok(
                        _call(RANGE_FUNCTION, [low, high, Expression.BoolLiteral(op == "..>")], at)
                    );
                }
                var binary = _binary_op(op);
                if (binary.is_empty()) {
                    return Built<Expression>.Err(_error($"unsupported binary operator '{op}'", loc(span)));
                }
                var left = expression(lhs)?;
                var right = expression(rhs)?;
                return Built<Expression>.Ok(_binary(binary.value(), left, right, loc(span)));
            }
            Ternary(condition, true_expr, false_expr, _) => {
                var c = expression(condition)?;
                var t = expression(true_expr)?;
                var f = expression(false_expr)?;
                return Built<Expression>.Ok(Expression.Ternary(TernaryExpression(c, t, f)));
            }
            Index(lhs, rhs, span) => {
                var left = expression(lhs)?;
                var right = expression(rhs)?;
                return Built<Expression>.Ok(Expression.Index(IndexExpression(left, right, loc = loc(span))));
            }
            MemberAccess(lhs, name, name_span, _) => {
                if (name.starts_with("__") and name != "__release" and name != "__acquire") {
                    var message = $"'{name}' is a reserved (synthesized) member and cannot be accessed from source code";
                    return Built<Expression>.Err(_error(message, loc(name_span)));
                }
                var left = expression(lhs)?;
                return Built<Expression>.Ok(_member(left, member_name(name, name_span).0, loc(name_span)));
            }
            FunctionCall(function, arguments, _) => {
                return function_call(function, arguments);
            }
            Tuple(elements, labels, span) => {
                # `(a, b)` calls the tuple constructor; a labeled literal
                # `(line: 3, column: 7)` calls `__tuple(line,column)`.
                ulong i = 0;
                while (i < labels.count) {
                    ulong first = 0;
                    while (first < i) {
                        if (labels[first].name == labels[i].name) {
                            var error = _error($"duplicate label '{labels[i].name}' in tuple", loc(labels[i].span));
                            return Built<Expression>.Err(_noted(error, "previous label here", loc(labels[first].span)));
                        }
                        first += 1;
                    }
                    i += 1;
                }
                var names = Array<String>();
                for (var label in labels) {
                    names.append(label.name);
                }
                var args = Array<Expression>();
                for (var element in elements) {
                    var built = expression(element)?;
                    args.append(built);
                }
                return Built<Expression>.Ok(_call(tuple_constructor_name(names), args, loc(span)));
            }
            ArrayLiteral(elements, span) => {
                return array_literal(elements, span, Optional<TypeName>.Empty);
            }
            MapLiteral(entries, span) => {
                return map_literal(entries, span, Optional<(TypeName, TypeName)>.Empty);
            }
            Match(m) => {
                return match_expression(m);
            }
            Is(value, pattern, keyword_span, _) => {
                return is_expression(value, pattern, keyword_span);
            }
            Closure(closure) => {
                var parameters = Array<VariableDef>();
                for (var p in closure.parameters) {
                    var built = variable_def(p, Kind.Param)?;
                    parameters.append(built);
                }
                var ty = type_name_from(closure.return_type);
                var saved = return_type;
                var saved_labels = labels;
                return_type = Optional<ast.TypeName>.Value(closure.return_type);
                # A closure's body is a function of its own: no loop outside
                # it can be named.
                labels = Array<(String, ast.Span)>();
                var body = block(closure.body)?;
                return_type = saved;
                labels = saved_labels;
                var literal = ClosureLiteral(
                    parameters = parameters,
                    ty = ty,
                    body = body,
                    expression_body = closure.expression_body,
                    loc = loc(closure.span)
                );
                return Built<Expression>.Ok(Expression.ClosureLiteral(literal));
            }
            # `parse.parse` desugars these; only `parse_written` keeps them.
            Interpolated(_, _) => {}
            FormatString(_, _, _, _) => {}
            Parenthesized(_, _) => {}
        }
        return Built<Expression>.Err(_error("unsupported expression", loc(expr.span())));
    }

    ## A call `function(arguments)`: a method call, a constructor or function
    ## call, an intrinsic, or a call of a function value.
    function_call(function: ast.Expression, arguments: ast.Expression[]): Built<Expression> {
        if (function is MemberAccess(lhs, name, name_span, _)) {
            # `__release`/`__acquire` are callable from source: explicit
            # reference counting is the escape hatch for object lifetimes.
            if (name.starts_with("__") and name != "__release" and name != "__acquire") {
                var message = $"'{name}' is a reserved (synthesized) method and cannot be called from source code";
                return Built<Expression>.Err(_error(message, loc(name_span)));
            }
            record_literal_args(loc(name_span), arguments);
            var receiver = expression(lhs)?;
            var args = call_arguments(arguments)?;
            var (method, labeled) = member_name(name, name_span);
            return Built<Expression>.Ok(_method_call(receiver, method, args, loc(name_span), labeled));
        }
        match (function) {
            TypeLiteral(type_name) => {
                if (type_name.name == _UNSAFE_CAST) {
                    return build_unsafe_cast(type_name, arguments);
                }
            }
            SymbolRef(id, span) => {
                if (id == _UNSAFE_CAST) {
                    return Built<Expression>.Err(
                        _error("'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'", loc(span))
                    );
                }
            }
            else => {}
        }
        var name = "";
        var labeled = Optional<TypeName>.Empty;
        match (function) {
            TypeLiteral(type_name) => {
                var ty = type_name_from(type_name);
                name = ty.to_string();
                labeled = _labeled(type_name, ty);
            }
            SymbolRef(id, _) => {
                name = id;
            }
            Literal(value, _) => {
                name = value.to_string();
            }
            else => {
                # Any other callee (`fs[0](x)`, `make_adder(1)(2)`) is an
                # expression producing a function value.
                var callee = expression(function)?;
                var args = call_arguments(arguments)?;
                return Built<Expression>.Ok(Expression.Invoke(InvokeExpression(callee, args = args)));
            }
        }
        var at = loc(function.span());
        # The arithmetic intrinsics (`__wrapping_add(a, b)`, ...) are
        # operators without syntax.
        var intrinsic = _intrinsic(name);
        if (intrinsic.is_value()
            and arguments.count == 2
            and !(arguments[0] is NamedArgument(_, _, _, _))
            and !(arguments[1] is NamedArgument(_, _, _, _))) {
            var left = expression(arguments[0])?;
            var right = expression(arguments[1])?;
            return Built<Expression>.Ok(_binary(intrinsic.value(), left, right, at));
        }
        record_literal_args(at, arguments);
        var args = call_arguments(arguments)?;
        return Built<Expression>.Ok(_call(name, args, at, labeled));
    }

    ## Member `name` as sema spells it, and as written when its type
    ## arguments' tuples have labels: the parser keeps a generic method's
    ## type arguments in the name as source writes them
    ## (`pass<(a: int, b: int)>`), which sema spells as types
    ## (`pass<__tuple<int, int>>`).
    member_name(name: String, span: ast.Span): (String, TypeName?) {
        var none = Optional<TypeName>.Empty;
        if (!name.contains("<")) {
            return (name, none);
        }
        var written = ast.parse_type_text(name, span);
        if (written.generic_types.count == 0 or written.to_string() != name) {
            return (name, none);
        }
        var args = Array<TypeName>();
        for (var a in written.generic_types) {
            args.append(type_name_from(a));
        }
        var ty = TypeName.with_args(written.name, args);
        return (ty.to_string(), ty.labels_arguments() ? Optional<TypeName>.Value(ty) : none);
    }

    ## `unsafe_cast<T>(value)`: a reinterpret cast of `value` to `T`, located
    ## at the `unsafe_cast` name.
    build_unsafe_cast(type_name: ast.TypeName, arguments: ast.Expression[]): Built<Expression> {
        var at = loc(ast.Span(type_name.span.start, type_name.span.start + _UNSAFE_CAST.size));
        if (type_name.generic_types.count != 1) {
            return Built<Expression>.Err(
                _error($"'unsafe_cast' takes 1 type argument, have {type_name.generic_types.count}", at)
            );
        }
        if (arguments.count != 1) {
            var which = arguments.count == 0 ? "few" : "many";
            return Built<Expression>.Err(
                _error($"too {which} arguments to 'unsafe_cast': expected 1, have {arguments.count}", at)
            );
        }
        if (arguments[0] is NamedArgument(_, name_span, _, _)) {
            return Built<Expression>.Err(_error("'unsafe_cast' takes no named arguments", loc(name_span)));
        }
        var built = expression(arguments[0])?;
        var ty = type_name_from(type_name.generic_types[0]);
        return Built<Expression>.Ok(Expression.Cast(CastExpression(built, ty = ty, loc = at, kind = CastKind.Unsafe)));
    }

    ## `[a, b, c]`: `_array_literal(a)._literal_append(b)._literal_append(c)`,
    ## its element type `element` when the literal initializes an `Array` or
    ## `HashSet` slot.
    array_literal(elements: ast.Expression[], span: ast.Span, element: TypeName?): Built<Expression> {
        if (elements.count == 0) {
            if (element.is_value()) {
                return Built<Expression>.Ok(
                    _call($"Array<{element.value().to_string()}>", Array<Expression>(), loc(span))
                );
            }
            var message = "empty array literal has no element type; declare the variable's type or write 'Array<T>()'";
            return Built<Expression>.Err(_error(message, loc(span)));
        }
        var function = element.is_value() ? $"_array_literal<{element.value().to_string()}>" : "_array_literal";
        var first = typed_expression(elements[0], element)?;
        var start = _call(function, [first], loc(span));
        var steps = Array<Expression[]>();
        ulong i = 1;
        while (i < elements.count) {
            var item = typed_expression(elements[i], element)?;
            steps.append([item]);
            i += 1;
        }
        return Built<Expression>.Ok(_build_literal(start, steps, "_literal_append", TypeName.auto(), loc(span)));
    }

    ## `[k1: v1, k2: v2]`: `_map_literal(k1, v1)._literal_insert(k2, v2)`,
    ## typed by the declared `HashMap<K, V>` when there is one.
    map_literal(entries: ast.MapEntry[], span: ast.Span, types: (TypeName, TypeName)?): Built<Expression> {
        if (entries.count == 0) {
            if (types.is_value()) {
                var (key, value) = types.value();
                return Built<Expression>.Ok(
                    _call($"HashMap<{key.to_string()}, {value.to_string()}>", Array<Expression>(), loc(span))
                );
            }
            var message = "empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'";
            return Built<Expression>.Err(_error(message, loc(span)));
        }
        var function = "_map_literal";
        var key_type = Optional<TypeName>.Empty;
        var value_type = Optional<TypeName>.Empty;
        if (types.is_value()) {
            var (key, value) = types.value();
            function = $"_map_literal<{key.to_string()}, {value.to_string()}>";
            key_type = Optional<TypeName>.Value(key);
            value_type = Optional<TypeName>.Value(value);
        }
        var first_key = typed_expression(entries[0].key, key_type)?;
        var first_value = typed_expression(entries[0].value, value_type)?;
        var start = _call(function, [first_key, first_value], loc(span));
        var steps = Array<Expression[]>();
        ulong i = 1;
        while (i < entries.count) {
            var k = typed_expression(entries[i].key, key_type)?;
            var v = typed_expression(entries[i].value, value_type)?;
            steps.append([k, v]);
            i += 1;
        }
        return Built<Expression>.Ok(_build_literal(start, steps, "_literal_insert", TypeName.auto(), loc(span)));
    }

    ## `expr` initializing a slot of type `ty`: a collection literal takes its
    ## types from it.
    typed_expression(expr: ast.Expression, ty: TypeName?): Built<Expression> {
        if (ty.is_value()) {
            match (expr) {
                ArrayLiteral(elements, span) => {
                    var element = _literal_element(ty.value());
                    if (element.is_value()) {
                        return array_literal(elements, span, element);
                    }
                }
                MapLiteral(entries, span) => {
                    var types = _map_types(ty.value());
                    if (types.is_value()) {
                        return map_literal(entries, span, types);
                    }
                }
                else => {}
            }
        }
        return expression(expr);
    }

    ## Checks the form of a `[Deprecated(...)]` among `attributes`.
    check_deprecation(attributes: ast.Attribute[]): Built<bool> {
        var found = deprecation_of(attributes);
        if (found.is_err()) {
            var e = found.error();
            return Built<bool>.Err(_error(e.message, loc(e.span)));
        }
        return Built<bool>.Ok(true);
    }

    ## Rejects a `[Deprecated]` on `what`, which no code refers to by name.
    reject_deprecation(attributes: ast.Attribute[], what: String): Built<bool> {
        for (var a in attributes) {
            if (is_deprecation(a)) {
                return Built<bool>.Err(_error($"'Deprecated' cannot be applied to {what}", loc(a.span)));
            }
        }
        return Built<bool>.Ok(true);
    }

    ## `[Implicit]` is a constructor attribute: anywhere else it is an error,
    ## at the attribute.
    reject_implicit(attributes: ast.Attribute[]): Built<bool> {
        var attribute = _implicit_attribute(attributes);
        if (attribute.is_value()) {
            return Built<bool>.Err(
                _error($"'{IMPLICIT_ATTRIBUTE}' applies only to constructors", loc(attribute.value().span))
            );
        }
        return Built<bool>.Ok(true);
    }

    ## `[ThreadLocal]` gives a module-scope variable one value per thread:
    ## on `what` (a field, a parameter) it is an error, at the attribute.
    reject_thread_local(attributes: ast.Attribute[], what: String): Built<bool> {
        for (var a in attributes) {
            if (a.body is SymbolRef(id, _)) {
                if (id == THREAD_LOCAL_ATTRIBUTE) {
                    return Built<bool>.Err(
                        _error(
                            $"'{THREAD_LOCAL_ATTRIBUTE}' applies only to a module-scope variable, not {what}",
                            loc(a.span)
                        )
                    );
                }
            }
        }
        return Built<bool>.Ok(true);
    }

    variable_def(decl: ast.VariableDecl, kind: Kind): Built<VariableDef> {
        var saved = with_attributes(decl.attributes);
        var built = variable_in_context(decl, kind);
        leave(saved);
        return built;
    }

    variable_in_context(decl: ast.VariableDecl, kind: Kind): Built<VariableDef> {
        check_deprecation(decl.attributes)?;
        reject_implicit(decl.attributes)?;
        if (kind == Kind.Field) {
            reject_thread_local(decl.attributes, "a field")?;
            # A struct's layout is the same on every platform (#294).
            for (var a in decl.attributes) {
                if (contains_platform_predicate(a.body)) {
                    return Built<VariableDef>.Err(
                        _error(
                            "a struct field cannot carry a platform selection; select the whole struct instead",
                            loc(a.span)
                        )
                    );
                }
            }
        } else if (kind == Kind.Param) {
            reject_thread_local(decl.attributes, "a parameter")?;
        }
        var ty = type_name_from(decl.type_name);
        # `const X = "text";` is a `StringConstant`: it keeps the literal's
        # constant bytes and allocates nothing.
        if (decl.is_const and ty.is_auto() and decl.default_value.is_value()) {
            if (decl.default_value.value() is Literal(value, _)) {
                if (value is String(_)) {
                    ty = TypeName.named(STRING_CONSTANT);
                }
            }
        }
        var default = Optional<Expression>.Empty;
        if (decl.default_value.is_value()) {
            check_literal_labels(decl.type_name, decl.default_value.value())?;
            # `long[] a = [1, 2]`: the declared type types a collection literal.
            var built = typed_expression(decl.default_value.value(), Optional<TypeName>.Value(ty))?;
            default = Optional<Expression>.Value(built);
        }
        return Built<VariableDef>.Ok(
            VariableDef(
                name = decl.name,
                ty = ty,
                default = default,
                kind = kind,
                attributes = decl.attributes,
                loc = loc(decl.name_span),
                type_loc = _type_loc(decl.type_name.span),
                is_const = decl.is_const
            )
        );
    }

    block(b: ast.Block): Built<Block> {
        var saved = with_attributes(b.attributes);
        var built = block_in_context(b);
        leave(saved);
        return built;
    }

    block_in_context(b: ast.Block): Built<Block> {
        var items = Array<Statement>();
        # Where each declaration that uses `?` starts and ends in `items`.
        var tried = Array<(ulong, ulong)>();
        for (var statement in b.statements) {
            # A statement using `?` lowers to several, its hidden locals first.
            var lowered = lift(statement)?;
            if (lowered.is_value()) {
                if (statement is Declaration(_) or statement is Destructure(_, _, _, _)) {
                    tried.append((items.count, items.count + lowered.value().count));
                }
                items.append_all(lowered.value());
                continue;
            }
            # A destructuring declaration's locals belong to the enclosing
            # block, so it lowers to several statements in place.
            if (statement is Destructure(bindings, value, is_const, _)) {
                var built = destructure(bindings, value, is_const)?;
                items.append_all(built);
            } else {
                var built = this.statement(statement)?;
                items.append(built);
            }
        }
        if (tried.count > 0) {
            # A `?` operand's hidden local holds its value to the end of the
            # block; when the block moves a local declared from it, the
            # read moves the operand out instead, so the local can be the
            # value's only reference (#266).
            var moved = _moved_names(items);
            for (var (start, end) in tried) {
                if (_declares_one_of_names(items, start, end, moved)) {
                    for (var i in start..end) {
                        items[i] = rewrite_statement(items[i], _TryReleaser());
                    }
                }
            }
        }
        return Built<Block>.Ok(Block(items = items, attributes = b.attributes));
    }

    statement(s: ast.Statement): Built<Statement> {
        match (s) {
            Expression(e) => {
                if (e is Binary(lhs, op, rhs, span)) {
                    if (op == "=" and lhs is Tuple(_, _, _)) {
                        return destructuring_assignment(lhs, rhs, span);
                    }
                }
                var built = expression(e)?;
                return Built<Statement>.Ok(Statement.Expression(built));
            }
            Destructure(bindings, value, is_const, _) => {
                var items = destructure(bindings, value, is_const)?;
                return Built<Statement>.Ok(Statement.Block(_block_of(items)));
            }
            Block(inner) => {
                var built = block(inner)?;
                return Built<Statement>.Ok(Statement.Block(built));
            }
            Declaration(d) => {
                var built = declaration(d)?;
                return Built<Statement>.Ok(Statement.Declaration(built));
            }
            Branch(condition, if_block, else_block, _) => {
                var lowered = is_branch(condition, if_block, else_block)?;
                if (lowered.is_value()) {
                    return Built<Statement>.Ok(lowered.value());
                }
                check_branch_hints(if_block.attributes, "an 'if'")?;
                var c = expression(condition)?;
                var then_block = block(if_block)?;
                var otherwise = Optional<Block>.Empty;
                if (else_block.is_value()) {
                    var built = block(else_block.value())?;
                    otherwise = Optional<Block>.Value(built);
                }
                return Built<Statement>.Ok(Statement.Branch(Branch(c, if_block = then_block, else_block = otherwise)));
            }
            While(condition, body, _) => {
                var lowered = is_loop(condition, body)?;
                if (lowered.is_value()) {
                    return Built<Statement>.Ok(lowered.value());
                }
                var label = _take_label();
                var c = expression(condition)?;
                var built = block(body)?;
                return Built<Statement>.Ok(Statement.While(While(c, block = built, label = label)));
            }
            For(binding, pattern, iterable, body, span) => {
                return for_loop(binding, pattern, iterable, body, span);
            }
            With(binding, scope, body, else_block, span) => {
                return with_block(binding, scope, body, else_block, span);
            }
            Match(m) => {
                return match_statement(m);
            }
            Static(static_block) => {
                var built = build_static_block(static_block, false)?;
                return Built<Statement>.Ok(Statement.Static(built));
            }
            Return(value, span) => {
                if (value.is_value() and return_type.is_value()) {
                    check_literal_labels(return_type.value(), value.value())?;
                }
                var built = Optional<Expression>.Empty;
                var at = loc(span);
                if (value.is_value()) {
                    var e = expression(value.value())?;
                    built = Optional<Expression>.Value(e);
                    at = loc(value.value().span());
                }
                return Built<Statement>.Ok(Statement.Return(ReturnStatement(expr = built, loc = at)));
            }
            LoopBreak(is_continue, label, label_span, _) => {
                if (!label.is_empty and _label_at(label).is_empty()) {
                    return Built<Statement>.Err(_error($"use of undeclared label '{label}'", loc(label_span)));
                }
                var kind = is_continue ? LoopBreakKind.Continue : LoopBreakKind.Break;
                return Built<Statement>.Ok(Statement.LoopBreak(LoopBreak(kind = kind, label = label)));
            }
            Labeled(label, label_span, loop, _) => {
                var outer = _label_at(label);
                if (outer.is_value()) {
                    return Built<Statement>.Err(
                        _noted(
                            _error($"label '{label}' is already the label of a loop around it", loc(label_span)),
                            "the outer loop is labeled here",
                            loc(outer.value())
                        )
                    );
                }
                labels.append((label, label_span));
                pending_label = label;
                var built = lowered(loop)?;
                labels.remove_at(labels.count - 1);
                if (built.count == 1) {
                    return Built<Statement>.Ok(built[0]);
                }
                return Built<Statement>.Ok(Statement.Block(_block_of(built)));
            }
        }
        return Built<Statement>.Err(_error("unsupported statement", loc(s.span())));
    }

    ## The hidden local holding the tuple a destructuring reads:
    ## `var __tuple_N = Destructure(value, count);`, and its name.
    hidden_tuple(value: ast.Expression, count: ulong): Built<(VariableDef, String)> {
        var at = loc(value.span());
        var built = expression(value)?;
        return Built<(VariableDef, String)>.Ok(hidden_tuple_of(built, count, at));
    }

    ## `hidden_tuple` of a value already built, located at `at`.
    hidden_tuple_of(value: Expression, count: ulong, at: Loc): (VariableDef, String) {
        var name = $"__tuple_{tuples}";
        tuples += 1;
        var destructured = Expression.Destructure(DestructureExpression(value, count = count, loc = at));
        return (_hidden(name, destructured, at), name);
    }

    ## Lowers `var (a, b: T, _) = value;` to a hidden tuple local and one
    ## local per named element.
    destructure(bindings: ast.DestructureBinding[], value: ast.Expression, is_const: bool): Built<Statement[]> {
        var (hidden, tuple) = hidden_tuple(value, bindings.count)?;
        var items = [_declare(hidden)];
        var bound = bind_elements(tuple, bindings, is_const)?;
        items.append_all(bound);
        return Built<Statement[]>.Ok(items);
    }

    ## `var name = tuple.index;` for each binding of a pattern over the hidden
    ## tuple local `tuple`, skipping `_`.
    bind_elements(tuple: String, bindings: ast.DestructureBinding[], is_const: bool): Built<Statement[]> {
        var items = Array<Statement>();
        ulong index = 0;
        while (index < bindings.count) {
            var binding = bindings[index];
            var at = loc(binding.name_span);
            if (binding.nested.count > 0) {
                var (hidden, inner) = hidden_tuple_of(_tuple_element(tuple, index, at), binding.nested.count, at);
                items.append(_declare(hidden));
                var nested = bind_elements(inner, binding.nested, is_const)?;
                items.append_all(nested);
            } else if (binding.name != "_") {
                var ty = type_name_from(binding.type_name);
                var element = _tuple_element(tuple, index, at);
                items.append(
                    _declare(
                        VariableDef(
                            name = binding.name,
                            ty = ty,
                            default = Optional<Expression>.Value(element),
                            loc = at,
                            type_loc = _type_loc(binding.type_name.span),
                            is_const = is_const
                        )
                    )
                );
            }
            index += 1;
        }
        return Built<Statement[]>.Ok(items);
    }

    ## Lowers `(a, b.f, _) = value;` to a block of a hidden tuple local and an
    ## assignment per place.
    destructuring_assignment(lhs: ast.Expression, rhs: ast.Expression, span: ast.Span): Built<Statement> {
        if (lhs is Tuple(elements, labels, _)) {
            if (labels.count > 0) {
                var message = "a destructuring assignment cannot have labels: list the places alone";
                return Built<Statement>.Err(_error(message, loc(labels[0].span)));
            }
            var (hidden, tuple) = hidden_tuple(rhs, elements.count)?;
            var items = [_declare(hidden)];
            assign_elements(tuple, elements, span, items)?;
            return Built<Statement>.Ok(Statement.Block(_block_of(items)));
        }
        return Built<Statement>.Err(_error("expected a tuple of places", loc(span)));
    }

    ## `place = tuple.index;` for each place of `(a, b.f, _) = ...`.
    assign_elements(tuple: String, places: ast.Expression[], span: ast.Span, items: Statement[]): Built<bool> {
        ulong index = 0;
        while (index < places.count) {
            var place = places[index];
            var skip = false;
            if (place is SymbolRef(id, _)) {
                skip = id == "_";
            }
            if (!skip) {
                var at = loc(place.span());
                if (place is Tuple(elements, labels, _)) {
                    if (labels.count > 0) {
                        var message = "a destructuring assignment cannot have labels: list the places alone";
                        return Built<bool>.Err(_error(message, loc(labels[0].span)));
                    }
                    var (hidden, inner) = hidden_tuple_of(_tuple_element(tuple, index, at), elements.count, at);
                    items.append(_declare(hidden));
                    assign_elements(inner, elements, span, items)?;
                } else {
                    var target = expression(place)?;
                    items.append(
                        Statement.Expression(
                            _binary(BinaryOp.Assign, target, _tuple_element(tuple, index, at), loc(span))
                        )
                    );
                }
            }
            index += 1;
        }
        return Built<bool>.Ok(true);
    }

    ## Where `label` labels a loop around the statement being built, if it
    ## does.
    _label_at(label: String): ast.Span? {
        for (var (name, span) in labels) {
            if (name == label) {
                return Optional<ast.Span>.Value(span);
            }
        }
        return Optional<ast.Span>.Empty;
    }

    ## The label a `Labeled` statement gave the loop being built, or empty;
    ## the loop takes it, so a loop in its body gets none.
    _take_label(): String {
        var label = pending_label;
        pending_label = "";
        return label;
    }

    ## Lowers `for (var x in source) body` to a block of the hidden iterator
    ## and a `while (iterator.next())` whose body declares `x`.
    for_loop(
        binding: ast.VariableDecl,
        pattern: ast.DestructureBinding[],
        iterable: ast.Expression,
        body: ast.Block,
        span: ast.Span
    ): Built<Statement> {
        var label = _take_label();
        var iterator = $"{FOR_ITERATOR}{for_loops}";
        for_loops += 1;
        # The hidden code is located at the iterable, its calls at `for`.
        var at = loc(iterable.span());
        var keyword = loc(ast.Span(span.start, span.start + 3));
        var source = expression(iterable)?;
        var hidden_iterator = _hidden(iterator, Expression.ForIterator(source), at);
        var current = _method_call(_symbol(iterator, at), "current", Array<Expression>(), keyword);
        var items = Array<Statement>();
        if (pattern.count == 0) {
            var element = variable_def(binding, Kind.Variable)?;
            element.default = Optional<Expression>.Value(current);
            items.append(_declare(element));
        } else {
            # `for (var (k, v) in pairs)`: destructure each element.
            var (hidden, tuple) = hidden_tuple_of(current, pattern.count, loc(binding.span));
            items.append(_declare(hidden));
            var bound = bind_elements(tuple, pattern, false)?;
            items.append_all(bound);
        }
        var inner = block(body)?;
        items.append(Statement.Block(inner));
        var condition = _method_call(_symbol(iterator, at), "next", Array<Expression>(), keyword);
        # A label names the `while`, where `continue` goes on to the next
        # element.
        var loop = Statement.While(While(condition, block = _block_of(items), label = label));
        return Built<Statement>.Ok(Statement.Block(_block_of([_declare(hidden_iterator), loop])));
    }

    ## Lowers `with (var x = scope) body else other` to a block of the hidden
    ## scope, the entered value, and an `if` on `WithEntered(x)`.
    with_block(
        binding: ast.VariableDecl?, scope: ast.Expression, body: ast.Block, else_block: ast.Block?, span: ast.Span
    ): Built<Statement> {
        var n = with_blocks;
        with_blocks += 1;
        var scope_name = $"__with_scope_{n}";
        var at = loc(scope.span());
        var scope_value = expression(scope)?;
        var hidden_scope = _hidden(scope_name, scope_value, at);
        # `enter()` is located at `with`.
        var enter = _method_call(
            _symbol(scope_name, at), "enter", Array<Expression>(), loc(ast.Span(span.start, span.start + 4))
        );
        var value = _hidden($"__with_value_{n}", enter, at);
        if (binding.is_value()) {
            value = variable_def(binding.value(), Kind.Variable)?;
            value.default = Optional<Expression>.Value(enter);
        }
        var entered = Expression.WithEntered(_symbol(value.name, value.loc));
        var then_block = block(body)?;
        var otherwise = Optional<Block>.Empty;
        if (else_block.is_value()) {
            var built = block(else_block.value())?;
            otherwise = Optional<Block>.Value(built);
        }
        var branch = Statement.Branch(Branch(entered, if_block = then_block, else_block = otherwise));
        return Built<Statement>.Ok(Statement.Block(_block_of([_declare(hidden_scope), _declare(value), branch])));
    }

    ## `match (e) { A, B => { x } else => { z } }`: a hidden subject local
    ## and a chain of `if (MatchArm(...))` branches.
    match_statement(m: ast.Match): Built<Statement> {
        for (var arm in m.arms) {
            check_branch_hints(arm.body.attributes, "a 'match' arm")?;
        }
        if (m.else_block.is_value()) {
            check_branch_hints(m.else_block.value().attributes, "a 'match' arm")?;
        }
        var arms = Array<_Arm>();
        for (var arm in m.arms) {
            arms.append(_Arm(arm.patterns, arm.guard, arm.body));
        }
        var else_arm = Optional<(Loc, Block)>.Empty;
        if (m.else_block.is_value()) {
            var at = loc(m.else_span);
            var built = block(m.else_block.value())?;
            else_arm = Optional<(Loc, Block)>.Value((at, built));
        }
        return lower_match_statement(m.value, m.keyword_span, arms, else_arm, false);
    }

    ## The next `match` number (`__match_N`, `MatchSite.id`).
    next_match(): ulong {
        var n = matches;
        matches += 1;
        return n;
    }

    ## The statement form of a `match`; `partial` for an `if` or `while`
    ## whose condition is an `is` test.
    lower_match_statement(
        value: ast.Expression, keyword: ast.Span, arms: _Arm[], else_arm: (Loc, Block)?, partial: bool
    ): Built<Statement> {
        var n = next_match();
        var subject = $"__match_{n}";
        var at = loc(value.span());
        var subject_value = expression(value)?;
        var hidden = _hidden(subject, subject_value, at);
        var else_loc = Optional<Loc>.Empty;
        var chain = Optional<Block>.Empty;
        if (else_arm.is_value()) {
            var (l, b) = else_arm.value();
            else_loc = Optional<Loc>.Value(l);
            chain = Optional<Block>.Value(b);
        }
        var site = MatchSite(id = n, keyword = loc(keyword), else_arm = else_loc, partial = partial);
        var subject_ref = _symbol(subject, at);
        var tests = Array<Expression>();
        var bodies = Array<Block>();
        for (var arm in arms) {
            var cases = Array<CasePattern>();
            for (var p in arm.patterns) {
                var built = case_pattern(p, subject_ref)?;
                cases.append(built);
            }
            var body = block(arm.body)?;
            var (bindings, element_names) = match_bindings(arm.patterns, subject_ref)?;
            var test = arm_test(subject_ref, cases, site, element_names, arm.guard, bindings)?;
            var items = Array<Statement>();
            for (var b in bindings) {
                items.append(
                    _declare(
                        VariableDef(
                            name = b.name,
                            ty = TypeName.auto(),
                            default = Optional<Expression>.Value(b.value),
                            loc = b.at,
                            type_loc = Loc.none(),
                            is_const = true
                        )
                    )
                );
            }
            var moved = _moved_names(body.items);
            var drops = false;
            for (var b in bindings) {
                drops = drops or moved.contains(b.name);
            }
            if (drops) {
                # The arm moves a binding: the subject lets go of its value
                # once the bindings hold it, so a binding can be the only
                # reference (#266).
                var drop = Expression.Move(MoveExpression(_symbol(subject, at), at));
                items.append(Statement.Expression(drop));
            }
            items.append_all(body.items);
            body.items = items;
            tests.append(test);
            bodies.append(body);
        }
        if (tests.count == 0) {
            var test = arm_test(
                subject_ref,
                Array<CasePattern>(),
                site,
                Array<ElementName>(),
                Optional<ast.Expression>.Empty,
                Array<_Binding>()
            )?;
            tests.append(test);
            bodies.append(Block());
        }
        ulong i = tests.count;
        while (i > 0) {
            i -= 1;
            var branch = Statement.Branch(Branch(tests[i], if_block = bodies[i], else_block = chain));
            chain = Optional<Block>.Value(_block_of([branch]));
        }
        var items = [_declare(hidden)];
        if (chain.is_value()) {
            items.append_all(chain.value().items);
        }
        return Built<Statement>.Ok(Statement.Block(_block_of(items)));
    }

    ## The error for attributes above `what` other than one `[Likely]` or
    ## `[Unlikely]`.
    check_branch_hints(attributes: ast.Attribute[], what: String): Built<bool> {
        var seen = Optional<ast.Attribute>.Empty;
        for (var attribute in attributes) {
            var at = loc(attribute.span);
            var name = attribute.name();
            if (name == "Likely" or name == "Unlikely") {
                if (!(attribute.body is SymbolRef(_, _))) {
                    return Built<bool>.Err(_error($"'{name}' takes no arguments", at));
                }
            } else {
                var shown = name.is_empty ? "attribute" : name;
                return Built<bool>.Err(
                    _error($"'{shown}' cannot mark {what}; only '[Likely]' or '[Unlikely]' can", at)
                );
            }
            if (seen.is_value()) {
                var error = _error($"only one of '[Likely]' or '[Unlikely]' can mark {what}", at);
                return Built<bool>.Err(_noted(error, $"'{seen.value().name()}' is here", loc(seen.value().span)));
            }
            seen = Optional<ast.Attribute>.Value(attribute);
        }
        return Built<bool>.Ok(true);
    }

    ## `if (x is P(a)) { ... } else { ... }`: the `match` statement over `x`.
    is_branch(condition: ast.Expression, if_block: ast.Block, else_block: ast.Block?): Built<Statement?> {
        if (condition is Is(value, pattern, keyword_span, _)) {
            check_branch_hints(if_block.attributes, "an 'if'")?;
            var else_arm = Optional<(Loc, Block)>.Empty;
            if (else_block.is_value()) {
                var built = block(else_block.value())?;
                else_arm = Optional<(Loc, Block)>.Value((Loc.none(), built));
            }
            var arms = [_Arm([pattern], Optional<ast.Expression>.Empty, if_block)];
            var lowered = lower_match_statement(value, keyword_span, arms, else_arm, true)?;
            return Built<Statement?>.Ok(Optional<Statement>.Value(lowered));
        }
        return Built<Statement?>.Ok(Optional<Statement>.Empty);
    }

    ## `while (x is P(a)) { body }`: `while (true) { match (x) { P(a) => {
    ## body } else => { break; } } }`.
    is_loop(condition: ast.Expression, body: ast.Block): Built<Statement?> {
        if (condition is Is(value, pattern, keyword_span, _)) {
            var label = _take_label();
            var stop = _block_of([Statement.LoopBreak(LoopBreak(kind = LoopBreakKind.Break))]);
            var arms = [_Arm([pattern], Optional<ast.Expression>.Empty, body)];
            var lowered = lower_match_statement(
                value, keyword_span, arms, Optional<(Loc, Block)>.Value((Loc.none(), stop)), true
            )?;
            var loop = Statement.While(
                While(Expression.BoolLiteral(true), block = _block_of([lowered]), label = label)
            );
            return Built<Statement?>.Ok(Optional<Statement>.Value(loop));
        }
        return Built<Statement?>.Ok(Optional<Statement>.Empty);
    }

    ## `match (e) { A, B => x, else => z }`: `WithSubject(N, e, MatchArm(...)
    ## ? x : z)`, each name a pattern binds replaced in its arm's value.
    match_expression(m: ast.MatchExpression): Built<Expression> {
        var n = next_match();
        var at = loc(m.value.span());
        var else_loc = Optional<Loc>.Empty;
        if (m.else_value.is_value()) {
            else_loc = Optional<Loc>.Value(loc(m.else_span));
        }
        var site = MatchSite(id = n, keyword = loc(m.keyword_span), else_arm = else_loc);
        var subject = Expression.Subject(SubjectExpression(id = n, ty = TypeName.auto(), loc = at));
        var chain = Expression.NoMatch;
        if (m.else_value.is_value()) {
            chain = expression(m.else_value.value())?;
        }
        var tests = Array<Expression>();
        var values = Array<Expression>();
        for (var arm in m.arms) {
            var patterns = Array<CasePattern>();
            for (var p in arm.patterns) {
                var built = case_pattern(p, subject)?;
                patterns.append(built);
            }
            var value = expression(arm.value)?;
            var (bindings, element_names) = match_bindings(arm.patterns, subject)?;
            value = bind_in_expression(value, bindings);
            var test = arm_test(subject, patterns, site, element_names, arm.guard, bindings)?;
            tests.append(test);
            values.append(value);
        }
        if (tests.count == 0) {
            var test = arm_test(
                subject,
                Array<CasePattern>(),
                site,
                Array<ElementName>(),
                Optional<ast.Expression>.Empty,
                Array<_Binding>()
            )?;
            tests.append(test);
            values.append(Expression.NoMatch);
        }
        ulong i = tests.count;
        while (i > 0) {
            i -= 1;
            chain = Expression.Ternary(TernaryExpression(tests[i], values[i], chain));
        }
        var subject_value = expression(m.value)?;
        return Built<Expression>.Ok(Expression.WithSubject(WithSubject(subject_value, chain, id = n, loc = at)));
    }

    ## `e as? T`: `match (e) { T(value) => Optional<T>.Value(value), else =>
    ## Optional<T>.Empty }`.
    optional_cast(
        value: ast.Expression, type_name: ast.TypeName, keyword: ast.Span, span: ast.Span
    ): Built<Expression> {
        var optional = ast.TypeName("Optional", type_name.span);
        optional.generic_types = [type_name];
        var bound = ast.Pattern();
        bound.case_name = CAST_VALUE;
        bound.case_span = type_name.span;
        bound.span = type_name.span;
        var pattern = ast.Pattern();
        pattern.case_name = type_name.to_string();
        pattern.case_span = type_name.span;
        pattern.bindings = Optional<ast.Pattern[]>.Value([bound]);
        pattern.type_name = Optional<ast.TypeName>.Value(type_name);
        pattern.span = type_name.span;
        var make = ast.Expression.MemberAccess(ast.Expression.TypeLiteral(optional), "Value", keyword, span);
        var arm = ast.MatchValueArm();
        arm.value = ast.Expression.FunctionCall(make, [ast.Expression.SymbolRef(CAST_VALUE, type_name.span)], span);
        arm.patterns = [pattern];
        arm.span = span;
        var m = ast.MatchExpression(value);
        m.arms = [arm];
        m.else_value = Optional<ast.Expression>.Value(
            ast.Expression.MemberAccess(ast.Expression.TypeLiteral(optional), "Empty", keyword, span)
        );
        m.else_span = keyword;
        m.keyword_span = keyword;
        m.span = span;
        return match_expression(m);
    }

    ## `e is P` anywhere but the whole condition of an `if` or `while`: a
    ## single test over `e`, which may bind nothing.
    is_expression(value: ast.Expression, pattern: ast.Pattern, keyword: ast.Span): Built<Expression> {
        var element_names = Array<ElementName>();
        for (var leaf in pattern_names(pattern, Expression.NoMatch)) {
            element_names.append(ElementName(name = leaf.name, loc = loc(leaf.span)));
        }
        var n = next_match();
        var at = loc(value.span());
        var site = MatchSite(id = n, keyword = loc(keyword), partial = true, no_bindings = true);
        var subject = Expression.Subject(SubjectExpression(id = n, ty = TypeName.auto(), loc = at));
        var case = case_pattern(pattern, subject)?;
        var test = MatchArmTest(subject.copy(), patterns = [case], site = site, element_names = element_names);
        var subject_value = expression(value)?;
        return Built<Expression>.Ok(
            Expression.WithSubject(WithSubject(subject_value, Expression.MatchArm(test), id = n, loc = at))
        );
    }

    ## The test of one arm, `MatchArm(subject is patterns)`, and with a guard
    ## `MatchArm(...) && guard`.
    arm_test(
        subject: Expression,
        patterns: CasePattern[],
        site: MatchSite,
        element_names: ElementName[],
        guard: ast.Expression?,
        bindings: _Binding[]
    ): Built<Expression> {
        var test = Expression.MatchArm(
            MatchArmTest(
                subject.copy(),
                patterns = patterns,
                site = site.copy(),
                element_names = element_names,
                guarded = guard.is_value()
            )
        );
        if (guard.is_empty()) {
            return Built<Expression>.Ok(test);
        }
        var at = loc(guard.value().span());
        var built = expression(guard.value())?;
        built = bind_in_expression(built, bindings);
        return Built<Expression>.Ok(_binary(BinaryOp.LogicalAnd, test, built, at));
    }

    ## A pattern of an arm over `subject`. A literal pattern carries the test
    ## `subject == literal`.
    case_pattern(p: ast.Pattern, subject: Expression): Built<CasePattern> {
        if (p.elements.is_value()) {
            var elements = Array<CasePattern>();
            ulong i = 0;
            for (var e in p.elements.value()) {
                var built = case_pattern(e, _element_path(subject, i, loc(e.span)))?;
                elements.append(built);
                i += 1;
            }
            return Built<CasePattern>.Ok(
                CasePattern(case = p.to_string(), loc = loc(p.span), elements = Optional<CasePattern[]>.Value(elements))
            );
        }
        var at = loc(p.case_span);
        var literal = Optional<Expression>.Empty;
        var values = Optional<(long, long)>.Empty;
        if (p.literal.is_value() and p.range_end.is_value()) {
            var start = p.literal.value();
            var end = p.range_end.value();
            var low_value = expression(start)?;
            var low = _binary(BinaryOp.GreaterEqual, subject.copy(), low_value, at);
            var high_value = expression(end)?;
            var high = _binary(p.range_inclusive ? BinaryOp.LessEqual : BinaryOp.Less, subject.copy(), high_value, at);
            literal = Optional<Expression>.Value(_binary(BinaryOp.LogicalAnd, low, high, at));
            var first = _constant_integer(start);
            var last = _constant_integer(end);
            if (first.is_value() and last.is_value()) {
                values = Optional<(long, long)>.Value(
                    (first.value(), p.range_inclusive ? last.value() : last.value() - 1)
                );
            }
        } else if (p.literal.is_value()) {
            var value = expression(p.literal.value())?;
            literal = Optional<Expression>.Value(_binary(BinaryOp.Equal, subject.copy(), value, at));
            var v = _constant_integer(p.literal.value());
            if (v.is_value()) {
                values = Optional<(long, long)>.Value((v.value(), v.value()));
            }
        } else if (p.constant.is_value()) {
            literal = Optional<Expression>.Value(
                _binary(BinaryOp.Equal, subject.copy(), _symbol(p.constant.value(), at), at)
            );
        }
        var qualifier = Optional<TypeName>.Empty;
        if (p.constant.is_empty() and p.qualifier.is_value()) {
            qualifier = Optional<TypeName>.Value(type_name_from(p.qualifier.value()));
        }
        var literal_or_constant = p.literal.is_value() or p.constant.is_value();
        var case = literal_or_constant ? p.to_string() : p.case_name;
        var pattern_loc = p.range_end.is_value() ? loc(p.span) : at;
        var bindings = Optional<CasePattern[]>.Empty;
        if (p.bindings.is_value()) {
            var subs = Array<CasePattern>();
            ulong i = 0;
            for (var sub in p.bindings.value()) {
                var built = case_pattern(sub, case_path(subject, p, i))?;
                subs.append(built);
                i += 1;
            }
            bindings = Optional<CasePattern[]>.Value(subs);
        }
        var ty = Optional<TypeName>.Empty;
        if (!literal_or_constant and p.type_name.is_value()) {
            ty = Optional<TypeName>.Value(type_name_from(p.type_name.value()));
        }
        return Built<CasePattern>.Ok(
            CasePattern(
                qualifier = qualifier,
                case = case,
                loc = pattern_loc,
                bindings = bindings,
                literal = literal,
                range = p.range_end.is_value(),
                constant = p.constant.is_value(),
                values = values,
                ty = ty
            )
        );
    }

    ## Value `index` of case pattern `p` over `subject`: a `CaseValue` with
    ## one choice.
    case_path(subject: Expression, p: ast.Pattern, index: ulong): Expression {
        var subs = p.bindings.is_value() ? p.bindings.value() : Array<ast.Pattern>();
        var at = index < subs.count ? loc(subs[index].span) : loc(p.case_span);
        var case_loc = loc(p.case_span);
        var ty = Optional<TypeName>.Empty;
        if (p.type_name.is_value()) {
            ty = Optional<TypeName>.Value(type_name_from(p.type_name.value()));
        }
        var binding_locs = Array<Loc>();
        for (var s in subs) {
            binding_locs.append(loc(s.span));
        }
        var choice = CaseChoice(
            case = p.case_name, case_loc = case_loc, ty = ty, index = index, bindings = binding_locs, loc = at
        );
        return Expression.CaseValue(CaseValue(subject.copy(), choices = [choice], loc = at));
    }

    ## Every name `p` may bind over `subject`, `_` left out, in order.
    pattern_names(p: ast.Pattern, subject: Expression): _Leaf[] {
        var out = Array<_Leaf>();
        _walk_names(p, subject.copy(), Array<String>(), false, out);
        return out;
    }

    _walk_names(p: ast.Pattern, path: Expression, key: String[], in_tuple: bool, out: _Leaf[]) {
        if (p.elements.is_value()) {
            ulong i = 0;
            for (var e in p.elements.value()) {
                _walk_names(e, _element_path(path, i, loc(e.span)), _key_with(key, $"{i}"), true, out);
                i += 1;
            }
            return;
        }
        if (in_tuple and p.is_bare_name() and p.case_name != "_") {
            out.append(_Leaf(p.case_name, p.case_span, false, path.copy(), key.copy(), Optional<ast.Pattern>.Empty, 0));
        }
        if (p.bindings.is_value()) {
            ulong index = 0;
            for (var sub in p.bindings.value()) {
                if (sub.is_bare_name()) {
                    if (sub.case_name != "_") {
                        out.append(
                            _Leaf(
                                sub.case_name,
                                sub.case_span,
                                true,
                                path.copy(),
                                key.copy(),
                                Optional<ast.Pattern>.Value(p),
                                index
                            )
                        );
                    }
                } else {
                    # A pattern the value must match: its own names bind inside it.
                    _walk_names(sub, case_path(path, p, index), _key_with(key, $"{p.case_name}.{index}"), true, out);
                }
                index += 1;
            }
        }
    }

    ## Replaces each name an arm binds with the value it reads, in a `match`
    ## expression's arm value or an arm's guard.
    bind_in_expression(value: Expression, bindings: _Binding[]): Expression {
        if (bindings.count == 0) {
            return value;
        }
        return _ArmBinder(bindings).rewrite(value);
    }

    ## The names an arm's patterns bind, each with the value it reads and
    ## where it is bound, and the arm's bare element names.
    match_bindings(patterns: ast.Pattern[], subject: Expression): Built<(_Binding[], ElementName[])> {
        var per = Array<_Leaf[]>();
        for (var p in patterns) {
            per.append(pattern_names(p, subject));
        }
        # A name twice in a case's values (`Pair(Line, Line)`) must be a case
        # there, like a bare name a tuple pattern repeats.
        for (var names in per) {
            var twice = Array<String>();
            ulong i = 0;
            while (i < names.count) {
                if (names[i].payload) {
                    ulong j = 0;
                    while (j < i) {
                        if (names[j].name == names[i].name and names[j].payload) {
                            twice.append(names[i].name);
                            break;
                        }
                        j += 1;
                    }
                }
                i += 1;
            }
            for (var leaf in names) {
                if (leaf.payload and twice.contains(leaf.name)) {
                    leaf.payload = false;
                }
            }
        }
        var order = Array<(String, ast.Span)>();
        for (var names in per) {
            for (var leaf in names) {
                var seen = false;
                for (var (n, _) in order) {
                    if (n == leaf.name) {
                        seen = true;
                    }
                }
                if (!seen) {
                    order.append((leaf.name, leaf.span));
                }
            }
        }
        var out = Array<_Binding>();
        var element_names = Array<ElementName>();
        for (var (name, span) in order) {
            var entries = Array<_Leaf[]>();
            var any_payload = false;
            for (var names in per) {
                var found = Array<_Leaf>();
                for (var leaf in names) {
                    if (leaf.name == name) {
                        found.append(leaf);
                        any_payload = any_payload or leaf.payload;
                    }
                }
                entries.append(found);
            }
            if (!any_payload) {
                var consistent = entries.count > 0 and entries[0].count > 0;
                if (consistent) {
                    var first = entries[0][0].key;
                    for (var e in entries) {
                        if (e.count != 1 or !_same_key(e[0].key, first)) {
                            consistent = false;
                        }
                    }
                }
                for (var e in entries) {
                    for (var leaf in e) {
                        element_names.append(ElementName(name = name, loc = loc(leaf.span), declared = consistent));
                    }
                }
                if (consistent) {
                    out.append(_Binding(name, entries[0][0].path.copy(), loc(span)));
                }
                continue;
            }
            # A pattern without the name binds nothing, and the name must be
            # a case wherever it appears (`Pair(Line, _), Line`).
            var lacking = Optional<ast.Pattern>.Empty;
            ulong k = 0;
            while (k < patterns.count and lacking.is_empty()) {
                var has = false;
                for (var leaf in entries[k]) {
                    has = has or leaf.payload;
                }
                if (!has) {
                    lacking = Optional<ast.Pattern>.Value(patterns[k]);
                }
                k += 1;
            }
            if (lacking.is_value()) {
                var p = lacking.value();
                var shown = p.case_name;
                if (p.literal.is_value()) {
                    shown = p.literal.value().to_string();
                } else if (p.elements.is_value()) {
                    shown = p.to_string();
                }
                for (var e in entries) {
                    for (var leaf in e) {
                        element_names.append(
                            ElementName(
                                name = name,
                                loc = loc(leaf.span),
                                missing = Optional<(String, Loc)>.Value((shown, loc(p.case_span)))
                            )
                        );
                    }
                }
                continue;
            }
            var choices = Array<CaseChoice>();
            var first = Optional<_Leaf>.Empty;
            for (var found in entries) {
                var payload = Optional<_Leaf>.Empty;
                for (var leaf in found) {
                    if (!leaf.payload) {
                        element_names.append(ElementName(name = name, loc = loc(leaf.span)));
                    } else if (payload.is_empty()) {
                        payload = Optional<_Leaf>.Value(leaf);
                    }
                }
                if (payload.is_empty()) {
                    continue;
                }
                var leaf = payload.value();
                if (first.is_empty()) {
                    first = payload;
                } else if (!_same_key(first.value().key, leaf.key)) {
                    var message = $"'{name}' is bound at a different element than in the arm's first pattern: bind it at the same element in each";
                    var error = _noted(
                        _error(message, loc(leaf.span)), $"'{name}' is bound here", loc(first.value().span)
                    );
                    return Built<(_Binding[], ElementName[])>.Err(error);
                }
                var pattern = leaf.pattern.value();
                var case_loc = loc(pattern.case_span);
                var ty = Optional<TypeName>.Empty;
                if (pattern.type_name.is_value()) {
                    ty = Optional<TypeName>.Value(type_name_from(pattern.type_name.value()));
                }
                var binding_locs = Array<Loc>();
                if (pattern.bindings.is_value()) {
                    for (var s in pattern.bindings.value()) {
                        binding_locs.append(loc(s.span));
                    }
                }
                choices.append(
                    CaseChoice(
                        case = pattern.case_name,
                        case_loc = case_loc,
                        ty = ty,
                        index = leaf.index,
                        bindings = binding_locs,
                        loc = loc(leaf.span)
                    )
                );
            }
            # A bare name in a case's values may turn out to be a case of the
            # value's enum, which only the value's type decides.
            for (var e in entries) {
                for (var leaf in e) {
                    if (leaf.payload) {
                        element_names.append(ElementName(name = name, loc = loc(leaf.span), declared = true));
                    }
                }
            }
            var path = first.is_value() ? first.value().path.copy() : subject.copy();
            out.append(
                _Binding(
                    name,
                    Expression.CaseValue(CaseValue(path, name = name, choices = choices, loc = loc(span))),
                    loc(span)
                )
            );
        }
        return Built<(_Binding[], ElementName[])>.Ok((out, element_names));
    }

    function_def(decl: ast.FunctionDecl, parent: String?): Built<FunctionDef> {
        # Only a trait method (a requirement), an `extern`, or a
        # `[__BuiltIn]` declaration may end with `;`.
        if (decl.body.is_empty() and !decl.external) {
            var name = decl.is_indexer ? "[]" : decl.name;
            var message = $"'{name}' has no body; only a trait method or a '[__BuiltIn]' declaration may end with ';'";
            return Built<FunctionDef>.Err(_error(message, loc(decl.name_span)));
        }
        return trait_method_def(decl, parent);
    }

    ## A trait's method, whose body is optional: one without is a requirement.
    trait_method_def(decl: ast.FunctionDecl, parent: String?): Built<FunctionDef> {
        reject_implicit(decl.attributes)?;
        return member_def(decl, parent);
    }

    ## An `[Implicit]` constructor must take exactly one argument, which must
    ## not already be the struct or one of its type parameters.
    check_implicit_constructor(decl: ast.StructDecl, constructor: ast.FunctionDecl): Built<bool> {
        var attribute = _implicit_attribute(constructor.attributes);
        if (attribute.is_empty()) {
            return Built<bool>.Ok(true);
        }
        var at = loc(attribute.value().span);
        var one_argument = constructor.parameters.count > 0;
        ulong i = 1;
        while (i < constructor.parameters.count) {
            if (constructor.parameters[i].default_value.is_empty()) {
                one_argument = false;
            }
            i += 1;
        }
        if (!one_argument) {
            return Built<bool>.Err(
                _error($"'{IMPLICIT_ATTRIBUTE}' constructor of '{decl.name}' must be callable with one argument", at)
            );
        }
        var first = constructor.parameters[0];
        var from = TypeName();
        # `this.field = default` takes the field's type.
        if (first.name.starts_with("this.")) {
            var field = first.name.substr_bytes(5, first.name.size - 5);
            var found = Optional<ast.VariableDecl>.Empty;
            for (var f in decl.fields) {
                if (f.name == field and found.is_empty()) {
                    found = Optional<ast.VariableDecl>.Value(f);
                }
            }
            if (found.is_empty()) {
                return Built<bool>.Ok(true);
            }
            from = type_name_from(found.value().type_name);
        } else {
            from = type_name_from(first.type_name);
        }
        if (from.sub_types.count == 0) {
            for (var g in decl.generic_params) {
                if (g.name == from.name) {
                    var message = $"'{IMPLICIT_ATTRIBUTE}' constructor of '{decl.name}' cannot convert from its type parameter '{from.name}'";
                    return Built<bool>.Err(_error(message, at));
                }
            }
        }
        if (from.name == decl.name) {
            return Built<bool>.Err(
                _error(
                    $"'{IMPLICIT_ATTRIBUTE}' constructor of '{decl.name}' cannot convert from '{from.display()}'", at
                )
            );
        }
        return Built<bool>.Ok(true);
    }

    ## A function or struct member, with no check on its attributes.
    member_def(decl: ast.FunctionDecl, parent: String?): Built<FunctionDef> {
        var saved = with_attributes(decl.attributes);
        var scope = in_generic_scope(decl.generic_params, Optional<ast.TypeName>.Empty);
        var built = member_in_scope(decl, parent);
        leave(scope);
        leave(saved);
        return built;
    }

    member_in_scope(decl: ast.FunctionDecl, parent: String?): Built<FunctionDef> {
        check_deprecation(decl.attributes)?;
        # A concrete override (`describe<Circle>`) passes its type arguments
        # to the generic it overrides, whose constraints they must meet.
        var overrides = false;
        for (var p in decl.generic_params) {
            overrides = overrides or p.is_argument;
        }
        if (parent.is_empty() and overrides) {
            var args = Array<TypeName>();
            var locs = Array<Loc>();
            for (var p in decl.generic_params) {
                args.append(TypeName.named(p.name));
                locs.append(loc(p.name_span));
            }
            push_type_use(TypeName.with_args(decl.name, args), locs);
        }
        # The signature before the body, so its type uses come first.
        var generic_params = Array<GenericParam>();
        for (var p in decl.generic_params) {
            generic_params.append(generic_param_from(p));
        }
        var ty = type_name_from(decl.return_type);
        var parameters = Array<VariableDef>();
        for (var p in decl.parameters) {
            var built = variable_def(p, Kind.Param)?;
            parameters.append(built);
        }
        var body = Optional<Block>.Empty;
        if (decl.body.is_value()) {
            var saved = return_type;
            return_type = Optional<ast.TypeName>.Value(decl.return_type);
            var built = block(decl.body.value())?;
            return_type = saved;
            body = Optional<Block>.Value(built);
        }
        # A comparison's result is a condition; codegen tests it as an i1.
        var declared = decl.return_type;
        var returns_other = declared.name != AUTO and declared.name != "bool";
        match (decl.name) {
            "==", "!=", "<", "<=", ">", ">=" => {
                if (returns_other) {
                    var message = $"comparison operator '{decl.name}' must return 'bool', not '{type_name_from(declared).to_string()}'";
                    return Built<FunctionDef>.Err(_error(message, loc(declared.span)));
                }
            }
            "!", "!!" => {
                # `!` and the truth test `!!` are conditions too.
                if (returns_other) {
                    var kind = decl.name == "!" ? "logical" : "truth-test";
                    var message = $"{kind} operator '{decl.name}' must return 'bool', not '{type_name_from(declared).to_string()}'";
                    return Built<FunctionDef>.Err(_error(message, loc(declared.span)));
                }
            }
            else => {}
        }
        # Unary-only operators take their operand as `this`.
        if ((decl.name == "!" or decl.name == "!!" or decl.name == "~")
            and !decl.is_static
            and decl.parameters.count > 0) {
            var message = $"unary operator '{decl.name}' takes no parameters, have {decl.parameters.count}";
            return Built<FunctionDef>.Err(_error(message, loc(decl.name_span)));
        }
        return Built<FunctionDef>.Ok(
            FunctionDef(
                name = decl.name,
                ty = ty,
                generic_params = generic_params,
                parameters = parameters,
                body = body,
                parent = parent,
                is_static = decl.is_static,
                is_indexer = decl.is_indexer,
                is_generic_func = decl.generic_params.count > 0,
                attributes = decl.attributes,
                loc = loc(decl.name_span),
                owner = Loc.none()
            )
        );
    }

    ## A declaration inside a block.
    declaration(decl: ast.Declaration): Built<Declaration> {
        match (decl) {
            Variable(v) => {
                var built = variable_def(v, Kind.Variable)?;
                return Built<Declaration>.Ok(Declaration.Variable(built));
            }
            Function(f) => {
                var built = function_def(f, Optional<String>.Empty)?;
                return Built<Declaration>.Ok(Declaration.Function(built));
            }
            Struct(s) => {
                if (s.enumeration.is_value()) {
                    return Built<Declaration>.Err(_error("enums are top-level declarations", loc(s.name_span)));
                }
                var built = struct_def(s)?;
                return Built<Declaration>.Ok(Declaration.Struct(built));
            }
            Trait(t) => {
                var built = trait_def(t)?;
                return Built<Declaration>.Ok(Declaration.Trait(built));
            }
            Extend(e) => {
                var built = extension_def(e)?;
                return Built<Declaration>.Ok(Declaration.Extension(built));
            }
            TypeAlias(t) => {
                return Built<Declaration>.Err(_error("type aliases are top-level declarations", loc(t.name_span)));
            }
            Static(s) => {
                return Built<Declaration>.Err(
                    _error("a module-scope 'static' block cannot be declared here", loc(s.keyword_span))
                );
            }
        }
        return Built<Declaration>.Err(_error("unsupported declaration", loc(decl.span())));
    }

    trait_def(t: ast.TraitDecl): Built<TraitDef> {
        check_deprecation(t.attributes)?;
        reject_implicit(t.attributes)?;
        var generic_params = Array<GenericParam>();
        for (var p in t.generic_params) {
            generic_params.append(generic_param_from(p));
        }
        var methods = Array<FunctionDef>();
        for (var m in t.methods) {
            var built = trait_method_def(m, Optional<String>.Empty)?;
            methods.append(built);
        }
        for (var property in t.properties) {
            var built = property_members(
                property, _PropertyOwner(_TRAIT_OWNER, t.name, Optional<ast.Attribute>.Empty)
            )?;
            methods.append_all(built.accessors);
        }
        return Built<TraitDef>.Ok(
            TraitDef(
                name = t.name,
                generic_params = generic_params,
                methods = methods,
                attributes = t.attributes,
                loc = loc(t.name_span)
            )
        );
    }

    extension_def(e: ast.ExtendDecl): Built<ExtensionDef> {
        reject_deprecation(e.attributes, "an extension; deprecate its methods instead")?;
        reject_implicit(e.attributes)?;
        var target = type_name_from(e.target);
        var traits = Array<TypeName>();
        var trait_locs = Array<Loc>();
        for (var t in e.traits) {
            traits.append(type_name_from(t));
            trait_locs.append(loc(t.span));
        }
        var restated = Array<(ulong, Bound)>();
        ulong i = 0;
        for (var bounds in e.target_bounds) {
            for (var b in bounds) {
                var ty = type_name_from(b);
                restated.append((i, Bound(ty = ty, loc = loc(b.span))));
            }
            i += 1;
        }
        var methods = Array<FunctionDef>();
        for (var m in e.methods) {
            var built = function_def(m, Optional<String>.Empty)?;
            methods.append(built);
        }
        var extended = type_name_from(e.target);
        for (var property in e.properties) {
            var built = property_members(
                property, _PropertyOwner(_EXTENSION_OWNER, extended.name, Optional<ast.Attribute>.Empty)
            )?;
            methods.append_all(built.accessors);
        }
        return Built<ExtensionDef>.Ok(
            ExtensionDef(
                target = target,
                traits = traits,
                trait_locs = trait_locs,
                restated = restated,
                methods = methods,
                attributes = e.attributes,
                loc = loc(e.target.span),
                is_exported = e.is_exported,
                is_private = e.is_private
            )
        );
    }

    ## Lowers `property` to its storage field and accessor methods, and
    ## records its `PropertyDef` for the properties pass.
    property_members(property: ast.PropertyDecl, owner: _PropertyOwner): Built<_PropertyMembers> {
        check_deprecation(property.attributes)?;
        reject_implicit(property.attributes)?;
        var name = property.name;
        if (property.getter.is_empty()) {
            var at = property.setter.is_value() ? property.setter.value().span : property.name_span;
            return Built<_PropertyMembers>.Err(
                _error($"property '{name}' has no 'get' accessor; a property must have one", loc(at))
            );
        }
        var get = property.getter.value();
        var parent = owner.kind == _STRUCT_OWNER ? Optional<String>.Value(owner.name) : Optional<String>.Empty;
        var getter = accessor(
            property,
            parent,
            getter_name(name),
            Array<ast.VariableDecl>(),
            property.type_name,
            get.function.body,
            property.name_span
        )?;
        var value = ast.VariableDecl();
        value.name = PROPERTY_VALUE;
        value.name_span = property.name_span;
        value.type_name = property.type_name;
        value.span = property.name_span;
        var void = ast.TypeName("void", property.name_span);
        var setter = Optional<FunctionDef>.Empty;
        if (property.setter.is_value()) {
            var set = property.setter.value();
            var built = accessor(property, parent, setter_name(name), [value], void, set.function.body, set.span)?;
            setter = Optional<FunctionDef>.Value(built);
        }
        var has_storage = get.function.body.is_empty()
            or (property.setter.is_value() and property.setter.value().function.body.is_empty())
            or _uses_field(getter)
            or (setter.is_value() and _uses_field(setter.value()));
        var storage = get.function.body.is_empty() ? name : storage_name(name);
        if (owner.kind == _TRAIT_OWNER) {
            for (var a in [property.getter, property.setter]) {
                if (a.is_value() and a.value().function.body.is_value()) {
                    var message = $"an accessor of trait property '{name}' cannot have a body";
                    return Built<_PropertyMembers>.Err(_error(message, loc(a.value().span)));
                }
            }
            if (property.default_value.is_value()) {
                var message = $"trait property '{name}' cannot have an initializer";
                return Built<_PropertyMembers>.Err(_error(message, loc(property.default_value.value().span())));
            }
        } else if (owner.kind == _EXTENSION_OWNER and has_storage) {
            var message = $"an extension cannot add storage: property '{name}' must be computed, with accessor bodies that do not use 'field'";
            return Built<_PropertyMembers>.Err(_error(message, loc(property.name_span)));
        } else if (owner.kind == _ENUM_OWNER) {
            var error = enum_property_error(owner.name, property, has_storage);
            if (error.is_value()) {
                return Built<_PropertyMembers>.Err(error.value());
            }
        } else if (owner.kind == _STRUCT_OWNER and owner.shared.is_value() and property.setter.is_value()) {
            var message = $"property '{name}' of a '[{SHARED_ATTRIBUTE}]' struct cannot have a 'set' accessor: its storage is 'const'";
            var error = _error(message, loc(property.setter.value().span));
            return Built<_PropertyMembers>.Err(
                _noted(error, $"'[{SHARED_ATTRIBUTE}]' declared here", loc(owner.shared.value().span))
            );
        }
        if (!has_storage and property.default_value.is_value()) {
            var message = $"property '{name}' has no storage to initialize: it is computed";
            return Built<_PropertyMembers>.Err(_error(message, loc(property.default_value.value().span())));
        }
        var in_trait = owner.kind == _TRAIT_OWNER;
        # Default bodies read and write the storage; `field` in a written body
        # is the storage.
        if (!in_trait) {
            var at = loc(property.name_span);
            if (getter.body.is_value()) {
                rewrite_block(getter.body.value(), _FieldReplacer(storage));
            } else {
                var read = Statement.Return(
                    ReturnStatement(
                        expr = Optional<Expression>.Value(_member(Expression.ThisRef, storage, at)), loc = at
                    )
                );
                getter.body = Optional<Block>.Value(_block_of([read]));
            }
            if (setter.is_value()) {
                var s = setter.value();
                if (s.body.is_value()) {
                    rewrite_block(s.body.value(), _FieldReplacer(storage));
                } else {
                    var assign = _binary(
                        BinaryOp.Assign, _member(Expression.ThisRef, storage, at), _symbol(PROPERTY_VALUE, at), at
                    );
                    s.body = Optional<Block>.Value(_block_of([Statement.Expression(assign)]));
                }
            }
        }
        var shared = owner.kind == _STRUCT_OWNER and owner.shared.is_value();
        var storage_def = Optional<VariableDef>.Empty;
        if (has_storage and !in_trait) {
            var field = ast.VariableDecl();
            field.attributes = property.attributes;
            field.name = storage;
            field.name_span = property.name_span;
            field.type_name = property.type_name;
            field.default_value = property.default_value;
            field.is_const = shared;
            field.span = property.span;
            var built = variable_def(field, Kind.Field)?;
            storage_def = Optional<VariableDef>.Value(built);
        }
        var set_kind = Optional<AccessorKind>.Empty;
        var set_loc = Loc.none();
        if (property.setter.is_value()) {
            var set = property.setter.value();
            set_kind = Optional<AccessorKind>.Value(
                set.function.body.is_value() ? AccessorKind.Body : AccessorKind.Default
            );
            set_loc = loc(set.span);
        }
        var stored = (has_storage and !in_trait) ? Optional<String>.Value(storage) : Optional<String>.Empty;
        properties.append(
            PropertyDef(
                name = name,
                owner = owner.name,
                in_trait = in_trait,
                loc = loc(property.name_span),
                get = get.function.body.is_value() ? AccessorKind.Body : AccessorKind.Default,
                set = set_kind,
                set_loc = set_loc,
                storage = stored,
                shared = shared
            )
        );
        var accessors = [getter];
        if (setter.is_value()) {
            accessors.append(setter.value());
        }
        return Built<_PropertyMembers>.Ok(_PropertyMembers(storage_def, accessors));
    }

    ## One accessor of `property` as a method `method`.
    accessor(
        property: ast.PropertyDecl,
        parent: String?,
        method: String,
        parameters: ast.VariableDecl[],
        return_type: ast.TypeName,
        body: ast.Block?,
        span: ast.Span
    ): Built<FunctionDef> {
        var decl = ast.FunctionDecl();
        decl.name = method;
        decl.name_span = span;
        decl.return_type = return_type;
        decl.parameters = parameters;
        decl.body = body;
        decl.span = span;
        decl.attributes = property.attributes;
        return member_def(decl, parent);
    }

    ## Why `property` of enum `enum_name` is an error, if it is: an enum value
    ## is immutable and has nowhere to keep anything.
    enum_property_error(enum_name: String, property: ast.PropertyDecl, has_storage: bool): Diagnostic? {
        if (property.setter.is_value()) {
            var message = $"property '{property.name}' of enum '{enum_name}' cannot have a 'set' accessor: enum values are immutable";
            return Optional<Diagnostic>.Value(_error(message, loc(property.setter.value().span)));
        }
        if (has_storage) {
            var message = $"property '{property.name}' of enum '{enum_name}' must be computed: give 'get' a body that does not use 'field'";
            return Optional<Diagnostic>.Value(_error(message, loc(property.name_span)));
        }
        return Optional<Diagnostic>.Empty;
    }

    ## A property of an enum may not share a name with one of its cases.
    check_enum_property_names(decl: ast.StructDecl): Built<bool> {
        var body = decl.enumeration.value();
        for (var property in decl.properties) {
            for (var case in body.cases) {
                if (case.name == property.name) {
                    var error = _error(
                        $"property '{property.name}' has the same name as a case of '{decl.name}'",
                        loc(property.name_span)
                    );
                    return Built<bool>.Err(_noted(error, "case declared here", loc(case.name_span)));
                }
            }
            if (is_enum_built_in_method(property.name) or property.name == "name") {
                var message = $"'{property.name}' is built into every enum and cannot be redeclared";
                return Built<bool>.Err(_error(message, loc(property.name_span)));
            }
        }
        return Built<bool>.Ok(true);
    }

    ## A `[Value]` struct has no object: `destruct` and `[Shared]` do not
    ## apply to it.
    check_value_attributes(decl: ast.StructDecl): Built<bool> {
        if (!has_bare_attribute(decl.attributes, VALUE_ATTRIBUTE)) {
            return Built<bool>.Ok(true);
        }
        if (decl.destruct_span.is_value()) {
            return Built<bool>.Err(
                _error($"value struct '{decl.name}' cannot have a destructor", loc(decl.destruct_span.value()))
            );
        }
        var shared = _bare_attribute(decl.attributes, SHARED_ATTRIBUTE);
        if (shared.is_value()) {
            var message = $"'[Shared]' does not apply to value struct '{decl.name}': it is thread-safe when its fields are";
            return Built<bool>.Err(_error(message, loc(shared.value().span)));
        }
        return Built<bool>.Ok(true);
    }

    ## A `StructDef` from a struct declaration, with constructor and
    ## destructor shells the passes fill in.
    struct_def(decl: ast.StructDecl): Built<StructDef> {
        check_deprecation(decl.attributes)?;
        reject_implicit(decl.attributes)?;
        if (decl.destructor.is_value()) {
            reject_deprecation(decl.destructor.value().attributes, "a destructor")?;
            reject_implicit(decl.destructor.value().attributes)?;
        }
        check_value_attributes(decl)?;
        var generic_params = Array<GenericParam>();
        for (var p in decl.generic_params) {
            generic_params.append(generic_param_from(p));
        }
        var base_name = decl.name;
        var ty = TypeName.named(base_name);
        if (generic_params.count > 0) {
            var args = Array<TypeName>();
            for (var p in generic_params) {
                args.append(TypeName.named(p.name));
            }
            ty = TypeName.with_args(base_name, args);
        }
        var field_members = Array<VariableDef>();
        for (var f in decl.fields) {
            var built = variable_def(f, Kind.Field)?;
            field_members.append(built);
        }
        var generic_methods = Array<FunctionDef>();
        var method_members = Array<FunctionDef>();
        for (var m in decl.methods) {
            var built = function_def(m, Optional<String>.Value(base_name))?;
            if (built.is_generic_func) {
                generic_methods.append(built);
            } else {
                method_members.append(built);
            }
        }
        var shared = _bare_attribute(decl.attributes, SHARED_ATTRIBUTE);
        for (var property in decl.properties) {
            var built = property_members(property, _PropertyOwner(_STRUCT_OWNER, base_name, shared))?;
            if (built.storage.is_value()) {
                field_members.append(built.storage.value());
            }
            method_members.append_all(built.accessors);
        }
        # Several constructors overload one another as the set `Point$1`,
        # `Point$2`, ... (declaration order); a single one is named after the
        # type.
        var constructors = Array<FunctionDef>();
        var implicit = Optional<ast.FunctionDecl>.Empty;
        ulong index = 0;
        for (var constructor in decl.constructors) {
            check_implicit_constructor(decl, constructor)?;
            var attribute = _implicit_attribute(constructor.attributes);
            if (attribute.is_value()) {
                if (implicit.is_value()) {
                    var error = _error(
                        $"only one constructor of '{decl.name}' may be '{IMPLICIT_ATTRIBUTE}'",
                        loc(attribute.value().span)
                    );
                    return Built<StructDef>.Err(
                        _noted(error, "previous implicit constructor is here", loc(implicit.value().name_span))
                    );
                }
                implicit = Optional<ast.FunctionDecl>.Value(constructor);
            }
            var f = member_def(constructor, Optional<String>.Value(base_name))?;
            f.name = decl.constructors.count == 1 ? ty.to_string() : $"{ty.to_string()}${index + 1}";
            f.ty = ty.copy();
            constructors.append(f);
            index += 1;
        }
        if (constructors.count == 0) {
            constructors.append(
                FunctionDef(
                    name = ty.to_string(),
                    ty = ty.copy(),
                    body = Optional<Block>.Value(Block()),
                    parent = Optional<String>.Value(base_name),
                    loc = loc(decl.name_span),
                    owner = Loc.none()
                )
            );
        }
        var destructor = FunctionDef(
            name = "__dtor",
            ty = TypeName.void(),
            body = Optional<Block>.Value(Block()),
            parent = Optional<String>.Value(base_name),
            loc = loc(decl.name_span),
            owner = Loc.none()
        );
        if (decl.destructor.is_value()) {
            var body = block(decl.destructor.value())?;
            destructor.body = Optional<Block>.Value(body);
            destructor.attributes = decl.destructor.value().attributes;
        }
        return Built<StructDef>.Ok(
            StructDef(
                name = base_name,
                ty = ty,
                generic_params = generic_params,
                field_members = field_members,
                method_members = method_members,
                generic_methods = generic_methods,
                constructors = constructors,
                destructor = destructor,
                acquire = _empty_method(base_name, "__acquire"),
                release = _empty_method(base_name, "__release"),
                attributes = decl.attributes,
                loc = loc(decl.name_span)
            )
        );
    }

    ## An `EnumDef` from an `enum` declaration: cases number from 0 in order;
    ## `= N` sets a case's value and the cases after it continue from N + 1.
    enum_def(decl: ast.StructDecl): Built<EnumDef> {
        check_deprecation(decl.attributes)?;
        reject_implicit(decl.attributes)?;
        var body = decl.enumeration.value();
        if (decl.generic_params.count > 0) {
            var message = $"enum '{decl.name}' cannot be generic: its cases carry no values";
            return Built<EnumDef>.Err(_error(message, loc(decl.generic_params[0].name_span)));
        }
        var representation = TypeName.named("int");
        if (body.representation.is_value()) {
            var t = body.representation.value();
            var ty = type_name_from(t);
            if (!ty.is_integral() or ty.name == "bool") {
                var message = $"'{t.to_string()}' is not an integer type; an enum is stored as one of 'byte', 'short', 'int', 'long' or their unsigned forms";
                return Built<EnumDef>.Err(_error(message, loc(t.span)));
            }
            representation = ty;
        }
        var (min, max) = integer_range(representation.name);
        var cases = Array<EnumCaseDef>();
        long next = 0;
        for (var case in body.cases) {
            check_deprecation(case.attributes)?;
            reject_implicit(case.attributes)?;
            if (case.payload.is_value()) {
                var message = $"cases that carry values are not supported yet ('{case.name}')";
                return Built<EnumDef>.Err(_error(message, loc(case.name_span)));
            }
            for (var previous in cases) {
                if (previous.name == case.name) {
                    var error = _error($"redefinition of case '{case.name}'", loc(case.name_span));
                    return Built<EnumDef>.Err(_noted(error, "previous definition is here", previous.loc));
                }
            }
            var value = next;
            if (case.value.is_value()) {
                var constant = _constant_integer(case.value.value());
                if (constant.is_empty()) {
                    var message = $"the value of case '{case.name}' must be an integer constant";
                    return Built<EnumDef>.Err(_error(message, loc(case.value.value().span())));
                }
                value = constant.value();
            }
            if (value < min or value > max) {
                var at = case.value.is_value() ? case.value.value().span() : case.name_span;
                var message = $"value {value} of case '{case.name}' does not fit in '{representation.name}'";
                return Built<EnumDef>.Err(_error(message, loc(at)));
            }
            for (var previous in cases) {
                if (previous.value == value) {
                    var error = _error(
                        $"case '{case.name}' has the same value as '{previous.name}' ({value})", loc(case.name_span)
                    );
                    return Built<EnumDef>.Err(_noted(error, $"'{previous.name}' declared here", previous.loc));
                }
            }
            cases.append(
                EnumCaseDef(name = case.name, value = value, attributes = case.attributes, loc = loc(case.name_span))
            );
            next = value + 1;
        }
        return Built<EnumDef>.Ok(
            EnumDef(
                name = decl.name,
                representation = representation,
                cases = cases,
                attributes = decl.attributes,
                loc = loc(decl.name_span)
            )
        );
    }

    ## A reference enum (one with a case that carries values) as the struct
    ## its values are objects of: the tag and each case's values as `const`
    ## fields, one constructor, each case as a static method, and `name()`.
    reference_enum_def(decl: ast.StructDecl): Built<StructDef> {
        var body = decl.enumeration.value();
        if (body.representation.is_value()) {
            var message = $"enum '{decl.name}' has cases that carry values, so it is not stored as an integer type";
            return Built<StructDef>.Err(_error(message, loc(body.representation.value().span)));
        }
        for (var m in decl.methods) {
            if (m.name == "name") {
                return Built<StructDef>.Err(
                    _error("'name' is built into every enum and cannot be redeclared", loc(m.name_span))
                );
            }
        }
        var cases = Array<EnumCaseDef>();
        var fields = Array<ast.VariableDecl>();
        long tag = 0;
        for (var case in body.cases) {
            check_deprecation(case.attributes)?;
            reject_implicit(case.attributes)?;
            if (case.value.is_value()) {
                var message = $"case '{case.name}' of '{decl.name}' cannot have a value: its cases carry values";
                return Built<StructDef>.Err(_error(message, loc(case.value.value().span())));
            }
            for (var previous in cases) {
                if (previous.name == case.name) {
                    var error = _error($"redefinition of case '{case.name}'", loc(case.name_span));
                    return Built<StructDef>.Err(_noted(error, "previous definition is here", previous.loc));
                }
            }
            for (var m in decl.methods) {
                if (m.name == case.name) {
                    var error = _error(
                        $"case '{case.name}' has the same name as a method of '{decl.name}'", loc(case.name_span)
                    );
                    return Built<StructDef>.Err(_noted(error, "method declared here", loc(m.name_span)));
                }
            }
            var payload = Array<(String, Loc)>();
            if (case.payload.is_value()) {
                for (var value in case.payload.value()) {
                    if (value.default_value.is_value()) {
                        var message = $"the values of case '{case.name}' cannot have defaults";
                        return Built<StructDef>.Err(_error(message, loc(value.default_value.value().span())));
                    }
                    for (var (n, previous) in payload) {
                        if (n == value.name) {
                            var error = _error(
                                $"redefinition of '{value.name}' in case '{case.name}'", loc(value.name_span)
                            );
                            return Built<StructDef>.Err(_noted(error, "previous definition is here", previous));
                        }
                    }
                    var field = _copy_variable(value);
                    field.name = payload_field(case.name, value.name);
                    field.is_const = true;
                    fields.append(field);
                    payload.append((value.name, loc(value.name_span)));
                }
            }
            cases.append(
                EnumCaseDef(
                    name = case.name,
                    value = tag,
                    payload = payload,
                    attributes = case.attributes,
                    loc = loc(case.name_span)
                )
            );
            tag += 1;
        }
        check_enum_property_names(decl)?;
        var lowered = _copy_struct(decl);
        lowered.enumeration = Optional<ast.EnumBody>.Empty;
        lowered.fields = fields;
        lowered.constructors = Array<ast.FunctionDecl>();
        lowered.destructor = Optional<ast.Block>.Empty;
        var st = struct_def(lowered)?;
        for (var property in decl.properties) {
            var stored = false;
            for (var f in st.field_members) {
                stored = stored or f.name == property.name or f.name == storage_name(property.name);
            }
            var error = enum_property_error(decl.name, property, stored);
            if (error.is_value()) {
                return Built<StructDef>.Err(error.value());
            }
        }
        var at = loc(decl.name_span);
        st.field_members.insert(
            0,
            VariableDef(
                name = TAG_FIELD,
                ty = TypeName.named("int"),
                kind = Kind.Field,
                loc = at,
                type_loc = Loc.none(),
                is_const = true
            )
        );
        # `construct(this.__tag, this.Text.text, ...)`: each parameter sets
        # its field.
        var parameters = Array<VariableDef>();
        for (var f in st.field_members) {
            parameters.append(
                VariableDef(
                    name = $"this.{f.name}",
                    ty = f.ty.copy(),
                    kind = Kind.Param,
                    loc = Loc.none(),
                    type_loc = Loc.none()
                )
            );
        }
        st.constructors[0].parameters = parameters;
        ulong c = 0;
        while (c < cases.count) {
            var case = cases[c];
            var ast_case = body.cases[c];
            var case_parameters = Array<VariableDef>();
            if (ast_case.payload.is_value()) {
                for (var p in ast_case.payload.value()) {
                    var built = variable_def(p, Kind.Param)?;
                    case_parameters.append(built);
                }
            }
            var args = [Expression.IntLiteral(case.value)];
            ulong i = 1;
            while (i < st.field_members.count) {
                var f = st.field_members[i];
                var own = Optional<String>.Empty;
                for (var (n, _) in case.payload) {
                    if (own.is_empty() and payload_field(case.name, n) == f.name) {
                        own = Optional<String>.Value(n);
                    }
                }
                if (own.is_value()) {
                    args.append(
                        Expression.SymbolRef(SymbolRefExpression(id = own.value(), ty = f.ty.copy(), loc = Loc.none()))
                    );
                } else {
                    args.append(Expression.Default(f.ty.copy()));
                }
                i += 1;
            }
            # Unlocated: only the enum's cases may construct it. A case that
            # carries nothing is one shared, immortal object, except in a
            # `[Value]` enum, where every case is a value.
            var make = _call(st.ty.to_string(), args, Loc.none());
            if (case.payload.count == 0 and !has_bare_attribute(decl.attributes, VALUE_ATTRIBUTE)) {
                make = Expression.StaticCase(StaticCaseExpression(ty = st.ty.copy(), tag = case.value));
            }
            st.method_members.append(
                _enum_struct_method(
                    decl.name,
                    case.name,
                    st.ty.copy(),
                    case_parameters,
                    [_returns(make)],
                    true,
                    case.attributes,
                    case.loc
                )
            );
            c += 1;
        }
        var items = Array<Statement>();
        for (var case in cases) {
            var tag_ref = _member(Expression.ThisRef, TAG_FIELD, Loc.none());
            var test = _binary(BinaryOp.Equal, tag_ref, Expression.IntLiteral(case.value), Loc.none());
            items.append(Statement.Branch(Branch(test, if_block = _block_of([_returns(_text(case.name))]))));
        }
        items.append(_returns(_text("")));
        st.method_members.append(
            _enum_struct_method(
                decl.name,
                "name",
                TypeName.named("String"),
                Array<VariableDef>(),
                items,
                false,
                Array<ast.Attribute>(),
                at
            )
        );
        st.enum_cases = Optional<EnumCaseDef[]>.Value(cases);
        return Built<StructDef>.Ok(st);
    }

    ## A method of an enum, as the free function `E::m`: an instance method
    ## takes the value as its first parameter, `this`.
    enum_method(decl: ast.StructDecl, m: ast.FunctionDecl): Built<FunctionDef> {
        var at = loc(m.name_span);
        if (is_enum_built_in_method(m.name)) {
            return Built<FunctionDef>.Err(_error($"'{m.name}' is built into every enum and cannot be redeclared", at));
        }
        var operator = m.is_indexer or !_starts_like_name(m.name);
        if (operator and m.is_static) {
            return Built<FunctionDef>.Err(_error($"an operator of enum '{decl.name}' cannot be static", at));
        }
        if (m.name == "==" or m.name == "!=") {
            var message = $"enum '{decl.name}' cannot declare '{m.name}': it compares its cases with '==' and '!=' already";
            return Built<FunctionDef>.Err(_error(message, at));
        }
        # A value is passed by value and never changes, so nothing can assign
        # through one.
        var compound = m.name.ends_with("=") and m.name != "<=" and m.name != ">=";
        if (compound or m.name == "__index_set" or m.name == "!!") {
            var shown = m.name == "__index_set" ? "[]" : m.name;
            var why = m.name == "!!" ? "an enum value is not a condition" : "its values never change";
            return Built<FunctionDef>.Err(_error($"enum '{decl.name}' cannot declare '{shown}': {why}", at));
        }
        var f = function_def(m, Optional<String>.Empty)?;
        f.name = enum_method_name(decl.name, m.name);
        if (!m.is_static) {
            f.parameters.insert(0, enum_this_parameter(decl.name));
        }
        return Built<FunctionDef>.Ok(f);
    }

    ## The model of the file's syntax tree.
    build_module(module: ast.Module): Built<Module> {
        var out = Module();
        out.imports = module.imports;
        # A `[__BuiltIn]` declaration documents a compiler built-in; the
        # compiler never reads it.
        for (var decl in module.declarations) {
            if (!ast.is_built_in(decl.attributes())) {
                var saved = with_attributes(decl.attributes());
                declare(decl, out)?;
                leave(saved);
            }
        }
        return Built<Module>.Ok(out);
    }

    ## Builds top-level declaration `decl` into `out`.
    declare(decl: ast.Declaration, out: Module): Built<bool> {
        match (decl) {
            Variable(v) => {
                # An addressable global, initialized by codegen.
                var built = variable_def(v, Kind.Variable)?;
                out.globals.append(built);
            }
            Static(s) => {
                var built = module_static_block(s)?;
                out.static_blocks.append(built);
            }
            Function(f) => {
                if (f.external) {
                    check_deprecation(f.attributes)?;
                    reject_implicit(f.attributes)?;
                    var ty = type_name_from(f.return_type);
                    var parameters = Array<VariableDef>();
                    for (var p in f.parameters) {
                        var built = variable_def(p, Kind.Param)?;
                        parameters.append(built);
                    }
                    out.externs.append(
                        ExternDef(
                            name = f.name,
                            ty = ty,
                            parameters = parameters,
                            is_variadic = f.is_variadic,
                            attributes = f.attributes,
                            loc = loc(f.name_span)
                        )
                    );
                } else {
                    if (!f.is_exported) {
                        out.private_functions.insert(loc(f.name_span));
                    }
                    if (f.is_private) {
                        out.file_private_functions.insert(loc(f.name_span));
                    }
                    var built = function_def(f, Optional<String>.Empty)?;
                    out.functions.append(built);
                }
            }
            Struct(s) => {
                if (_is_reference_enum(s)) {
                    var scope = in_generic_scope(s.generic_params, Optional<ast.TypeName>.Empty);
                    var built = reference_enum_def(s)?;
                    leave(scope);
                    out.structs.append(built);
                } else if (s.enumeration.is_value()) {
                    var built = enum_def(s)?;
                    out.enums.append(built);
                    for (var m in s.methods) {
                        var method = enum_method(s, m)?;
                        out.functions.append(method);
                    }
                    check_enum_property_names(s)?;
                    for (var property in s.properties) {
                        var members = property_members(
                            property, _PropertyOwner(_ENUM_OWNER, s.name, Optional<ast.Attribute>.Empty)
                        )?;
                        for (var f in members.accessors) {
                            f.name = enum_method_name(s.name, f.name);
                            f.parameters.insert(0, enum_this_parameter(s.name));
                            out.functions.append(f);
                        }
                    }
                } else {
                    var scope = in_generic_scope(s.generic_params, Optional<ast.TypeName>.Empty);
                    var built = struct_def(s)?;
                    leave(scope);
                    out.structs.append(built);
                }
            }
            Trait(t) => {
                var scope = in_generic_scope(t.generic_params, Optional<ast.TypeName>.Empty);
                var built = trait_def(t)?;
                leave(scope);
                out.traits.append(built);
            }
            Extend(e) => {
                # A constrained extension's parameters carry the constraints
                # it adds (`extend Box<T: Named>`), beside the struct's own.
                var params = Array<ast.GenericParam>();
                ulong i = 0;
                while (i < e.target.generic_types.count and i < e.target_bounds.count) {
                    var argument = e.target.generic_types[i];
                    var bounds = e.target_bounds[i];
                    if (argument.generic_types.count == 0 and bounds.count > 0) {
                        var p = ast.GenericParam(argument.name, argument.span);
                        p.bounds = bounds;
                        params.append(p);
                    }
                    i += 1;
                }
                var scope = in_generic_scope(params, Optional<ast.TypeName>.Value(e.target));
                var built = extension_def(e)?;
                leave(scope);
                out.extensions.append(built);
            }
            TypeAlias(t) => {
                check_deprecation(t.attributes)?;
                reject_implicit(t.attributes)?;
                var scope = in_generic_scope(t.generic_params, Optional<ast.TypeName>.Empty);
                var generic_params = Array<GenericParam>();
                for (var p in t.generic_params) {
                    generic_params.append(generic_param_from(p));
                }
                var target = type_name_from(t.target);
                var alias = TypeAliasDef(
                    name = t.name,
                    generic_params = generic_params,
                    target = target,
                    attributes = t.attributes,
                    loc = loc(t.name_span)
                );
                leave(scope);
                out.type_aliases.append(alias);
            }
        }
        return Built<bool>.Ok(true);
    }

    ## The placeholder for `expr` when it is part of a statement a `static`
    ## block emits and uses only compile-time names; empty otherwise.
    static_placeholder(expr: ast.Expression): Built<Expression?> {
        if (compile_time.is_empty()) {
            return Built<Expression?>.Ok(Optional<Expression>.Empty);
        }
        var names = compile_time.value();
        if (expr is FunctionCall(function, arguments, _)) {
            if (function is MemberAccess(lhs, name, name_span, _)) {
                if (_is_emitting_method(name) and _is_compile_time(lhs, names)) {
                    var args = call_arguments(arguments)?;
                    var spans = Array<ast.Span>();
                    for (var a in arguments) {
                        spans.append(a.extent());
                    }
                    var member = StaticMember(
                        lhs,
                        method = name,
                        args = args,
                        loc = loc(name_span),
                        span = expr.extent(),
                        argument_spans = spans
                    );
                    return Built<Expression?>.Ok(Optional<Expression>.Value(Expression.StaticMember(member)));
                }
            }
        }
        if (_is_compile_time(expr, names)) {
            var value = StaticValue(expr, loc = loc(expr.span()));
            return Built<Expression?>.Ok(Optional<Expression>.Value(Expression.StaticValue(value)));
        }
        return Built<Expression?>.Ok(Optional<Expression>.Empty);
    }

    ## Builds `static (captures) { ... }`; at module scope, nothing is
    ## emitted.
    build_static_block(block: ast.StaticBlock, module_scope: bool): Built<StaticBlock> {
        if (compile_time.is_value()) {
            return Built<StaticBlock>.Err(
                _error("a 'static' block cannot be nested in another", loc(block.keyword_span))
            );
        }
        var names = _StaticNames(module_scope);
        ulong i = 0;
        while (i < block.captures.count) {
            var capture = block.captures[i];
            ulong first = 0;
            while (first < i) {
                if (block.captures[first].name == capture.name) {
                    var error = _error($"'{capture.name}' is captured twice", loc(capture.span));
                    return Built<StaticBlock>.Err(
                        _noted(error, "first captured here", loc(block.captures[first].span))
                    );
                }
                first += 1;
            }
            names.declare(capture.name, true);
            i += 1;
        }
        var items = static_items(block.block.statements, names)?;
        var captures = Array<String>();
        for (var capture in block.captures) {
            captures.append(capture.name);
        }
        return Built<StaticBlock>.Ok(
            StaticBlock(captures = captures, items = items, loc = loc(block.keyword_span), span = block.span)
        );
    }

    ## Builds a module-scope `static { ... }`, whose top-level `const`
    ## declarations the parser also declared as module-scope variables.
    module_static_block(block: ast.StaticBlock): Built<ModuleStaticBlock> {
        if (block.captures.count > 0) {
            var message = "a module-scope 'static' block has no runtime values to capture";
            return Built<ModuleStaticBlock>.Err(_error(message, loc(block.captures[0].span)));
        }
        var built = build_static_block(block, true)?;
        var constants = Array<(String, Loc)>();
        for (var statement in block.block.statements) {
            if (statement is Declaration(declaration)) {
                if (declaration is Variable(v)) {
                    if (v.is_const and v.default_value.is_value()) {
                        constants.append((v.name, loc(v.name_span)));
                    }
                }
            }
        }
        return Built<ModuleStaticBlock>.Ok(ModuleStaticBlock(block = built, constants = constants));
    }

    _scoped(block: ast.Block, names: _StaticNames): Built<StaticItem[]> {
        names.push();
        var built = static_items(block.statements, names);
        names.pop();
        return built;
    }

    ## The items of a `static` block: compile-time work kept as written, and
    ## the statements it emits.
    static_items(statements: ast.Statement[], names: _StaticNames): Built<StaticItem[]> {
        var out = Array<StaticItem>();
        for (var statement in statements) {
            var item = Optional<StaticItem>.Empty;
            match (statement) {
                Expression(e) => {
                    if (!names.mentions_runtime(e)) {
                        item = Optional<StaticItem>.Value(StaticItem.Evaluate(e));
                    }
                }
                Declaration(declaration) => {
                    if (declaration is Variable(v)) {
                        if (v.default_value.is_value() and !names.mentions_runtime(v.default_value.value())) {
                            names.declare(v.name, false);
                            item = Optional<StaticItem>.Value(
                                StaticItem.Var(
                                    VarStaticItem(v.default_value.value(), name = v.name, loc = loc(v.name_span))
                                )
                            );
                        } else {
                            var emitted = emit(statement, names)?;
                            item = Optional<StaticItem>.Value(StaticItem.Emit(emitted, _written(statement)));
                            names.declare(v.name, true);
                        }
                    } else {
                        var message = "only variables can be declared in a 'static' block";
                        return Built<StaticItem[]>.Err(_error(message, loc(declaration.span())));
                    }
                }
                Branch(condition, if_block, else_block, _) => {
                    if (!_contains_is(condition)) {
                        var runtime = names.mentions_runtime(condition);
                        var loops = names.loops;
                        var in_runtime_if = names.in_runtime_if;
                        if (runtime) {
                            names.loops = 0;
                            names.in_runtime_if = true;
                        }
                        var then_items = _scoped(if_block, names);
                        var else_items = Built<StaticItem[]>.Ok(Array<StaticItem>());
                        if (else_block.is_value()) {
                            else_items = _scoped(else_block.value(), names);
                        }
                        names.loops = loops;
                        names.in_runtime_if = in_runtime_if;
                        var then_built = then_items?;
                        var else_built = else_items?;
                        if (runtime) {
                            var c = emit_expression(condition, names)?;
                            item = Optional<StaticItem>.Value(
                                StaticItem.EmitIf(
                                    EmitIfStaticItem(
                                        c, then_items = then_built, else_items = else_built, span = condition.extent()
                                    )
                                )
                            );
                        } else {
                            item = Optional<StaticItem>.Value(
                                StaticItem.If(
                                    IfStaticItem(
                                        condition,
                                        then_items = then_built,
                                        else_items = else_built,
                                        loc = loc(condition.span())
                                    )
                                )
                            );
                        }
                    }
                }
                For(binding, pattern, iterable, body, _) => {
                    if (pattern.count == 0 and !names.mentions_runtime(iterable)) {
                        names.push();
                        names.declare(binding.name, false);
                        names.loops += 1;
                        var built = static_items(body.statements, names);
                        names.loops -= 1;
                        names.pop();
                        var items = built?;
                        item = Optional<StaticItem>.Value(
                            StaticItem.For(
                                ForStaticItem(iterable, name = binding.name, body = items, loc = loc(iterable.span()))
                            )
                        );
                    }
                }
                While(condition, body, span) => {
                    if (!names.mentions_runtime(condition)) {
                        names.loops += 1;
                        var built = _scoped(body, names);
                        names.loops -= 1;
                        var items = built?;
                        var at = loc(ast.Span(span.start, span.start + 5));
                        item = Optional<StaticItem>.Value(
                            StaticItem.While(WhileStaticItem(condition, body = items, loc = at))
                        );
                    }
                }
                Labeled(_, label_span, loop, _) => {
                    # A runtime loop is emitted, label and all; a compile-time
                    # one cannot be named yet.
                    bool compile_time = false;
                    if (loop is For(_, pattern, iterable, _, _)) {
                        compile_time = pattern.count == 0 and !names.mentions_runtime(iterable);
                    }
                    if (loop is While(condition, _, _)) {
                        compile_time = !names.mentions_runtime(condition);
                    }
                    if (compile_time) {
                        return Built<StaticItem[]>.Err(
                            _error("a compile-time loop cannot have a label yet", loc(label_span))
                        );
                    }
                }
                LoopBreak(is_continue, label, label_span, span) => {
                    var word = is_continue ? "continue" : "break";
                    if (!label.is_empty and names.loops > 0) {
                        return Built<StaticItem[]>.Err(
                            _error($"'{word}' in a compile-time loop cannot name a label yet", loc(label_span))
                        );
                    }
                    if (names.loops == 0) {
                        var message = names.in_runtime_if ?
                            $"'{word}' in a runtime 'if' cannot leave a compile-time loop; the condition is not known while compiling" :
                            $"'{word}' in a 'static' block must be in a compile-time 'for' or 'while'";
                        return Built<StaticItem[]>.Err(_error(message, loc(span)));
                    }
                    var kind = is_continue ? LoopBreakKind.Continue : LoopBreakKind.Break;
                    item = Optional<StaticItem>.Value(StaticItem.Jump(JumpStaticItem(kind, loc = loc(span))));
                }
                Block(inner) => {
                    var items = _scoped(inner, names)?;
                    item = Optional<StaticItem>.Value(StaticItem.Block(items));
                }
                Static(nested) => {
                    return Built<StaticItem[]>.Err(
                        _error("a 'static' block cannot be nested in another", loc(nested.keyword_span))
                    );
                }
                else => {}
            }
            if (item.is_empty()) {
                var emitted = emit(statement, names)?;
                item = Optional<StaticItem>.Value(StaticItem.Emit(emitted, _written(statement)));
            }
            out.append(item.value());
        }
        return Built<StaticItem[]>.Ok(out);
    }

    ## `statement` as a `static` block emits it, its compile-time parts
    ## placeholders.
    emit(statement: ast.Statement, names: _StaticNames): Built<Statement> {
        if (names.module_scope) {
            var message = "a module-scope 'static' block cannot emit code; declare a 'const' with what it computes";
            return Built<Statement>.Err(_error(message, loc(statement.span())));
        }
        var saved = compile_time;
        compile_time = Optional<HashSet<String>>.Value(names.compile_time_names());
        var built = this.statement(statement);
        compile_time = saved;
        return built;
    }

    ## `expr` as a `static` block emits it.
    emit_expression(expr: ast.Expression, names: _StaticNames): Built<Expression> {
        if (names.module_scope) {
            var message = "a module-scope 'static' block cannot emit code; declare a 'const' with what it computes";
            return Built<Expression>.Err(_error(message, loc(expr.span())));
        }
        var saved = compile_time;
        compile_time = Optional<HashSet<String>>.Value(names.compile_time_names());
        var built = expression(expr);
        compile_time = saved;
        return built;
    }

    ## The statements `s` lowers to when an expression it evaluates uses
    ## `?`: what runs before the rest of the statement, in evaluation order
    ## (each `?`'s hidden local and early return, each earlier operand a
    ## `?` must not overtake, held in a hidden local, and each `&&`, `||`,
    ## `?:` or `match` with a `?` that may not run, as an `if` or `match`
    ## statement), then the statement, each `?` reading its local.
    lift(s: ast.Statement): Built<Statement[]?> {
        if (s is While(condition, body, _)) {
            if (_has_try(condition)) {
                var lowered = while_with_try(condition, body)?;
                return Built<Statement[]?>.Ok(Optional<Statement[]>.Value(lowered));
            }
            return Built<Statement[]?>.Ok(Optional<Statement[]>.Empty);
        }
        var head = _head(s);
        if (head.is_empty() or !_has_try(head.value())) {
            return Built<Statement[]?>.Ok(Optional<Statement[]>.Empty);
        }
        if (s is Expression(_) and _branch_has_try(head.value())) {
            # Its value is unused: each branch is a statement of its own.
            var branched = lowered(branch_statement(head.value(), Optional<String>.Empty))?;
            return Built<Statement[]?>.Ok(Optional<Statement[]>.Value(branched));
        }
        var items = Array<Statement>();
        var lifted_head = lift_walk(head.value(), items)?;
        var lifted = _with_head(s, lifted_head);
        var declares = false;
        if (lifted is Destructure(bindings, value, is_const, _)) {
            declares = true;
            var built = destructure(bindings, value, is_const)?;
            items.append_all(built);
        } else {
            declares = lifted is Declaration(_);
            var built = statement(lifted)?;
            items.append(built);
        }
        if (declares) {
            return Built<Statement[]?>.Ok(Optional<Statement[]>.Value(items));
        }
        return Built<Statement[]?>.Ok(Optional<Statement[]>.Value([Statement.Block(_block_of(items))]));
    }

    ## The statements `s` lowers to.
    lowered(s: ast.Statement): Built<Statement[]> {
        var lifted = lift(s)?;
        if (lifted.is_value()) {
            return Built<Statement[]>.Ok(lifted.value());
        }
        var built = statement(s)?;
        return Built<Statement[]>.Ok([built]);
    }

    ## `while (c) { body }` with a `?` in `c`: `while (true) { if (c) { body }
    ## else { break; } }`.
    while_with_try(condition: ast.Expression, body: ast.Block): Built<Statement[]> {
        var label = _take_label();
        var span = condition.span();
        var stop = ast.Statement.LoopBreak(false, "", span, span);
        var otherwise = ast.Block();
        otherwise.statements = [stop];
        otherwise.span = span;
        var branch = ast.Statement.Branch(condition, body, Optional<ast.Block>.Value(otherwise), span);
        var wrapper = ast.Block();
        wrapper.statements = [branch];
        wrapper.span = body.span;
        var built = block(wrapper)?;
        return Built<Statement[]>.Ok(
            [Statement.While(While(Expression.BoolLiteral(true), block = built, label = label))]
        );
    }

    ## `e` with each `?` replaced by a read of its hidden local, and what
    ## runs before it appended to `items` in evaluation order.
    lift_walk(e: ast.Expression, items: Statement[]): Built<ast.Expression> {
        match (e) {
            Unary(op, prefix, operand, span) => {
                var lifted = lift_walk(operand, items)?;
                if (op == "?") {
                    var at = ast.Span(span.end - 1, span.end);
                    var name = $"{TRY_LOCAL}{tries}";
                    tries += 1;
                    var checked = try_check(name, lifted, at)?;
                    items.append_all(checked);
                    return Built<ast.Expression>.Ok(
                        _ast_method_call(ast.Expression.SymbolRef(name, at), "value", Array<ast.Expression>(), at)
                    );
                }
                return Built<ast.Expression>.Ok(ast.Expression.Unary(op, prefix, lifted, span));
            }
            Binary(lhs, op, rhs, span) => {
                if (_has_try(rhs) and (op == "&&" or op == "||" or op == "and" or op == "or")) {
                    return logical(lhs, op, rhs, span, items);
                }
                var left = lift_walk(lhs, items)?;
                if (_has_try(rhs)) {
                    left = settle(left, items)?;
                }
                var right = lift_walk(rhs, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Binary(left, op, right, span));
            }
            Ternary(condition, true_expr, false_expr, span) => {
                if (_branch_has_try(e)) {
                    return branches(e, items);
                }
                var c = lift_walk(condition, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Ternary(c, true_expr, false_expr, span));
            }
            Match(m) => {
                if (_branch_has_try(e)) {
                    return branches(e, items);
                }
                var value = lift_walk(m.value, items)?;
                var copy = ast.MatchExpression(value);
                copy.arms = m.arms;
                copy.else_value = m.else_value;
                copy.else_span = m.else_span;
                copy.keyword_span = m.keyword_span;
                copy.span = m.span;
                return Built<ast.Expression>.Ok(ast.Expression.Match(copy));
            }
            FunctionCall(function, arguments, span) => {
                var later = _any_has_try(arguments);
                var callee = function;
                if (function is MemberAccess(lhs, name, name_span, member_span)) {
                    var receiver = lift_walk(lhs, items)?;
                    if (later) {
                        receiver = settle(receiver, items)?;
                    }
                    callee = ast.Expression.MemberAccess(receiver, name, name_span, member_span);
                } else {
                    callee = lift_walk(function, items)?;
                    if (later) {
                        callee = settle(callee, items)?;
                    }
                }
                var args = lift_all(arguments, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.FunctionCall(callee, args, span));
            }
            Index(lhs, rhs, span) => {
                var left = lift_walk(lhs, items)?;
                if (_has_try(rhs)) {
                    left = settle(left, items)?;
                }
                var right = lift_walk(rhs, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Index(left, right, span));
            }
            MemberAccess(lhs, name, name_span, span) => {
                var left = lift_walk(lhs, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.MemberAccess(left, name, name_span, span));
            }
            Cast(inner, type_name, span, keyword_span, optional) => {
                var lifted = lift_walk(inner, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Cast(lifted, type_name, span, keyword_span, optional));
            }
            NamedArgument(name, name_span, value, span) => {
                var lifted = lift_walk(value, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.NamedArgument(name, name_span, lifted, span));
            }
            Is(value, pattern, keyword_span, span) => {
                var lifted = lift_walk(value, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Is(lifted, pattern, keyword_span, span));
            }
            Tuple(elements, labels, span) => {
                var lifted = lift_all(elements, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Tuple(lifted, labels, span));
            }
            ArrayLiteral(elements, span) => {
                var lifted = lift_all(elements, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.ArrayLiteral(lifted, span));
            }
            MapLiteral(entries, span) => {
                var flat = Array<ast.Expression>();
                for (var entry in entries) {
                    flat.append(entry.key);
                    flat.append(entry.value);
                }
                var lifted = lift_all(flat, items)?;
                var out = Array<ast.MapEntry>();
                for (var i in 0..entries.count) {
                    out.append(ast.MapEntry(lifted[2 * i], lifted[2 * i + 1]));
                }
                return Built<ast.Expression>.Ok(ast.Expression.MapLiteral(out, span));
            }
            else => {}
        }
        return Built<ast.Expression>.Ok(e);
    }

    ## `operands`, evaluated in order, each lifted by `lift_walk`; one that
    ## a later operand's `?` must not overtake is settled first.
    lift_all(operands: ast.Expression[], items: Statement[]): Built<ast.Expression[]> {
        # The operands before the last one that uses `?` are settled.
        ulong last = operands.count;
        while (last > 0 and !_has_try(operands[last - 1])) {
            last -= 1;
        }
        var out = Array<ast.Expression>();
        for (var i in 0..operands.count) {
            var lifted = lift_walk(operands[i], items)?;
            if (i + 1 < last) {
                lifted = settle(lifted, items)?;
            }
            out.append(lifted);
        }
        return Built<ast.Expression[]>.Ok(out);
    }

    ## `e`, an operand already lifted, evaluated now because a `?` after it
    ## would otherwise run first: each call (or `++`, `--`, assignment) it
    ## still makes runs into a hidden local, which `e` then reads. A place
    ## (`a.b`, `a[i]`) stays a place: only the values its receiver and
    ## index need are held.
    settle(e: ast.Expression, items: Statement[]): Built<ast.Expression> {
        if (!_has_effect(e)) {
            return Built<ast.Expression>.Ok(e);
        }
        match (e) {
            MemberAccess(lhs, name, name_span, span) => {
                var held = settle(lhs, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.MemberAccess(held, name, name_span, span));
            }
            Index(lhs, rhs, span) => {
                var held = settle(lhs, items)?;
                var index = settle(rhs, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.Index(held, index, span));
            }
            NamedArgument(name, name_span, value, span) => {
                var held = settle(value, items)?;
                return Built<ast.Expression>.Ok(ast.Expression.NamedArgument(name, name_span, held, span));
            }
            else => {}
        }
        var span = e.span();
        var name = $"{VALUE_LOCAL}{tries}";
        tries += 1;
        var value = expression(e)?;
        items.append(_declare(_hidden(name, value, loc(span))));
        return Built<ast.Expression>.Ok(ast.Expression.SymbolRef(name, span));
    }

    ## `lhs op rhs` (`&&`, `||`, `and`, `or`) whose `rhs` uses `?`, which
    ## runs only when `lhs` does not decide: a hidden `bool`, set by `if
    ## (lhs) { if (rhs) { b = true; } }` for `&&` and by `if (lhs) { b =
    ## true; } else { if (rhs) { b = true; } }` for `||`.
    logical(
        lhs: ast.Expression, op: String, rhs: ast.Expression, span: ast.Span, items: Statement[]
    ): Built<ast.Expression> {
        var name = $"{VALUE_LOCAL}{tries}";
        tries += 1;
        items.append(_declare(_hidden(name, Expression.BoolLiteral(false), loc(span))));
        var holds = _branch_block(
            Optional<String>.Value(name), ast.Expression.Literal(ast.Literal.Bool(true), rhs.span())
        );
        var nested = ast.Block();
        nested.statements = [ast.Statement.Branch(rhs, holds, Optional<ast.Block>.Empty, rhs.span())];
        nested.span = rhs.span();
        var outer = ast.Statement.Branch(lhs, holds, Optional<ast.Block>.Value(nested), span);
        if (op == "&&" or op == "and") {
            outer = ast.Statement.Branch(lhs, nested, Optional<ast.Block>.Empty, span);
        }
        var built = lowered(outer)?;
        items.append_all(built);
        return Built<ast.Expression>.Ok(ast.Expression.SymbolRef(name, span));
    }

    ## `e`, a `?:` or `match` with a `?` in a branch, which runs only when
    ## that branch is taken: a hidden local, set by an `if` or `match`
    ## statement with a block per branch. Its initializer, `e` with each `?`
    ## read as its operand's value, only gives it `e`'s type:
    ## `resolve_implicit_types` drops it.
    branches(e: ast.Expression, items: Statement[]): Built<ast.Expression> {
        var span = e.span();
        var name = $"{BRANCH_LOCAL}{tries}";
        tries += 1;
        var saved = typing_only;
        typing_only = true;
        var typed = expression(e);
        typing_only = saved;
        items.append(_declare(_hidden(name, typed?, loc(span))));
        var built = lowered(branch_statement(e, Optional<String>.Value(name)))?;
        items.append_all(built);
        return Built<ast.Expression>.Ok(ast.Expression.SymbolRef(name, span));
    }

    ## The `if` statement for `?:` `e`, or the `match` statement for `match`
    ## `e`, whose branches assign their values to `target`, or evaluate
    ## them when there is none.
    branch_statement(e: ast.Expression, target: String?): ast.Statement {
        if (e is Ternary(condition, true_expr, false_expr, span)) {
            var otherwise = Optional<ast.Block>.Value(_branch_block(target, false_expr));
            return ast.Statement.Branch(condition, _branch_block(target, true_expr), otherwise, span);
        }
        if (e is Match(m)) {
            var copy = ast.Match(m.value);
            for (var arm in m.arms) {
                var lowered_arm = ast.MatchArm();
                lowered_arm.patterns = arm.patterns;
                lowered_arm.guard = arm.guard;
                lowered_arm.body = _branch_block(target, arm.value);
                lowered_arm.span = arm.span;
                copy.arms.append(lowered_arm);
            }
            if (m.else_value.is_value()) {
                copy.else_block = Optional<ast.Block>.Value(_branch_block(target, m.else_value.value()));
            }
            copy.else_span = m.else_span;
            copy.keyword_span = m.keyword_span;
            copy.span = m.span;
            return ast.Statement.Match(copy);
        }
        return ast.Statement.Expression(e);
    }

    ## `var name = operand;` and `if (name._propagates()) { return
    ## R._from_residual(name._residual()); }` for the `?` at `at`.
    try_check(name: String, operand: ast.Expression, at: ast.Span): Built<Statement[]> {
        var returns = try_return_type(at)?;
        var owner_type = ast.TypeName(returns.name, at);
        owner_type.generic_types = returns.generic_types;
        owner_type.labels = returns.labels;
        var residual = _ast_method_call(
            ast.Expression.TypeLiteral(owner_type),
            "_from_residual",
            [_ast_method_call(ast.Expression.SymbolRef(name, at), "_residual", Array<ast.Expression>(), at)],
            at
        );
        var value = expression(operand)?;
        var hidden = VariableDef(
            name = name,
            ty = TypeName.auto(),
            default = Optional<Expression>.Value(value),
            hidden = true,
            loc = loc(at),
            type_loc = Loc.none()
        );
        var condition = expression(
            _ast_method_call(ast.Expression.SymbolRef(name, at), "_propagates", Array<ast.Expression>(), at)
        )?;
        var returned = expression(residual)?;
        var exit = Statement.Return(ReturnStatement(expr = Optional<Expression>.Value(returned), loc = loc(at)));
        var branch = Statement.Branch(Branch(condition, if_block = _block_of([exit])));
        return Built<Statement[]>.Ok([_declare(hidden), branch]);
    }

    ## The declared return type of the function a `?` at `at` returns from.
    try_return_type(at: ast.Span): Built<ast.TypeName> {
        if (return_type.is_empty()) {
            return Built<ast.TypeName>.Err(_error("'?' can be used only in a function body", loc(at)));
        }
        var returns = return_type.value();
        match (returns.name) {
            "", "auto", "__auto" => {
                var error = _error("'?' requires the enclosing function to declare its return type", loc(at));
                var note = "a Result or an Optional, as in 'f(): Result<int>' or, for a closure, '(x): Result<int> => ...'";
                return Built<ast.TypeName>.Err(_noted_nowhere(error, note));
            }
            "void" => {
                var message = "'?' requires the enclosing function to return a Result or an Optional";
                return Built<ast.TypeName>.Err(_error(message, loc(at)));
            }
            else => {}
        }
        return Built<ast.TypeName>.Ok(returns);
    }
}

## Whether accessor `f`'s body uses `field`.
_uses_field(f: FunctionDef): bool {
    if (f.body.is_empty()) {
        return false;
    }
    var finder = _FieldFinder();
    rewrite_block(f.body.value(), finder);
    return finder.found;
}

## Whether `name` starts like an identifier, not an operator.
_starts_like_name(name: String): bool {
    if (name.is_empty) {
        return false;
    }
    var first = name.bytes()[0];
    return (first >= 48 and first <= 57)
        or (first >= 65 and first <= 90)
        or (first >= 97 and first <= 122)
        or first == 95;
}

## Whether `decl` is an enum with a case that carries values.
_is_reference_enum(decl: ast.StructDecl): bool {
    if (decl.enumeration.is_empty()) {
        return false;
    }
    for (var case in decl.enumeration.value().cases) {
        if (case.payload.is_value()) {
            return true;
        }
    }
    return false;
}

## A shallow copy of `decl`.
_copy_struct(decl: ast.StructDecl): ast.StructDecl {
    var out = ast.StructDecl();
    out.name = decl.name;
    out.name_span = decl.name_span;
    out.generic_params = decl.generic_params;
    out.fields = decl.fields;
    out.properties = decl.properties;
    out.methods = decl.methods;
    out.constructors = decl.constructors;
    out.destructor = decl.destructor;
    out.destruct_span = decl.destruct_span;
    out.span = decl.span;
    out.attributes = decl.attributes;
    out.is_exported = decl.is_exported;
    out.is_private = decl.is_private;
    out.enumeration = decl.enumeration;
    return out;
}

## `return value;`, unlocated.
_returns(value: Expression): Statement {
    return Statement.Return(ReturnStatement(expr = Optional<Expression>.Value(value), loc = Loc.none()));
}

## The string literal `value`, unlocated.
_text(value: String): Expression {
    return Expression.StringLiteral(StringLiteralExpression(value = value, loc = Loc.none()));
}

## A method `name` of the struct a reference enum `enum_name` is built as.
_enum_struct_method(
    enum_name: String,
    name: String,
    ty: TypeName,
    parameters: VariableDef[],
    items: Statement[],
    is_static: bool,
    attributes: ast.Attribute[],
    at: Loc
): FunctionDef {
    return FunctionDef(
        name = name,
        ty = ty,
        parameters = parameters,
        body = Optional<Block>.Value(_block_of(items)),
        parent = Optional<String>.Value(enum_name),
        is_static = is_static,
        attributes = attributes,
        loc = at,
        owner = Loc.none()
    );
}

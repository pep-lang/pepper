//! Sema model: owned enum tree ported from `source/Sema/Model/*`. No
//! `Rc/RefCell` — passes walk `&mut Module` sequentially and replace nodes in
//! place, mirroring the C++ `NodeRef` assignment.

use crate::type_name::TypeName;
use pepper_parser::ast;
pub use pepper_parser::diagnostic::{Diagnostic, FileId, Loc};

// ── Binary operators (port of Model/BinaryOps.h) ─────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    Identical,
    NotIdentical,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    LShift,
    RShift,
    BitAnd,
    BitOr,
    BitXor,
    LogicalAnd,
    LogicalOr,
    Assign,
    AddAssign,
    SubAssign,
    MulAssign,
    DivAssign,
    ModAssign,
    LShiftAssign,
    RShiftAssign,
    BitAndAssign,
    BitOrAssign,
    BitXorAssign,
}

impl BinaryOp {
    /// Operator name for method overload lookup (`opName()`): `+` → `+`, `==` → `==`.
    pub fn op_name(&self) -> String {
        let base = match self {
            BinaryOp::Add => "+",
            BinaryOp::Sub => "-",
            BinaryOp::Mul => "*",
            BinaryOp::Div => "/",
            BinaryOp::Mod => "%",
            BinaryOp::Pow => "**",
            BinaryOp::Equal => "==",
            BinaryOp::NotEqual => "!=",
            BinaryOp::Less => "<",
            BinaryOp::LessEqual => "<=",
            BinaryOp::Greater => ">",
            BinaryOp::GreaterEqual => ">=",
            BinaryOp::LShift => "<<",
            BinaryOp::RShift => ">>",
            BinaryOp::BitAnd => "&",
            BinaryOp::BitOr => "|",
            BinaryOp::BitXor => "^",
            BinaryOp::LogicalAnd => "&&",
            BinaryOp::LogicalOr => "||",
            BinaryOp::Identical | BinaryOp::NotIdentical => "",
            BinaryOp::Assign => "",
            BinaryOp::AddAssign => "+=",
            BinaryOp::SubAssign => "-=",
            BinaryOp::MulAssign => "*=",
            BinaryOp::DivAssign => "/=",
            BinaryOp::ModAssign => "%=",
            BinaryOp::LShiftAssign => "<<=",
            BinaryOp::RShiftAssign => ">>=",
            BinaryOp::BitAndAssign => "&=",
            BinaryOp::BitOrAssign => "|=",
            BinaryOp::BitXorAssign => "^=",
        };
        base.to_string()
    }

    /// The assign component of a compound assignment (`+=` → `+`).
    pub fn base_assign_op(&self) -> Option<BinaryOp> {
        match self {
            BinaryOp::AddAssign => Some(BinaryOp::Add),
            BinaryOp::SubAssign => Some(BinaryOp::Sub),
            BinaryOp::MulAssign => Some(BinaryOp::Mul),
            BinaryOp::DivAssign => Some(BinaryOp::Div),
            BinaryOp::ModAssign => Some(BinaryOp::Mod),
            BinaryOp::LShiftAssign => Some(BinaryOp::LShift),
            BinaryOp::RShiftAssign => Some(BinaryOp::RShift),
            BinaryOp::BitAndAssign => Some(BinaryOp::BitAnd),
            BinaryOp::BitOrAssign => Some(BinaryOp::BitOr),
            BinaryOp::BitXorAssign => Some(BinaryOp::BitXor),
            _ => None,
        }
    }

    pub fn is_assignment(&self) -> bool {
        matches!(
            self,
            BinaryOp::Assign
                | BinaryOp::AddAssign
                | BinaryOp::SubAssign
                | BinaryOp::MulAssign
                | BinaryOp::DivAssign
                | BinaryOp::ModAssign
                | BinaryOp::LShiftAssign
                | BinaryOp::RShiftAssign
                | BinaryOp::BitAndAssign
                | BinaryOp::BitOrAssign
                | BinaryOp::BitXorAssign
        )
    }

    /// Comparison ops (`==`, `!=`, `<`, `<=`, `>`, `>=`, identical): their
    /// result type is `bool`.
    /// `===`/`!==` as the raw `==`/`!=` codegen performs for them: after
    /// sema no operator method stands behind either, so both compare the
    /// operands' own values (addresses for references). Other operators are
    /// returned unchanged.
    pub fn identity_as_equality(&self) -> BinaryOp {
        match self {
            BinaryOp::Identical => BinaryOp::Equal,
            BinaryOp::NotIdentical => BinaryOp::NotEqual,
            other => *other,
        }
    }

    pub fn is_comparison(&self) -> bool {
        matches!(
            self,
            BinaryOp::Identical | BinaryOp::NotIdentical | BinaryOp::Equal | BinaryOp::NotEqual | BinaryOp::Less | BinaryOp::LessEqual | BinaryOp::Greater | BinaryOp::GreaterEqual
        )
    }
}

// ── Unary operators (port of Model/UnaryOps via ModelBuilder tables) ─────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,
    Pos,
    PreInc,
    PostInc,
    PreDec,
    PostDec,
    LogicalNot,
    BitNot,
}

// ── Types ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Kind {
    #[default]
    Variable,
    Field,
    Param,
}

// ── Expressions ──────────────────────────────────────────────────────────────

/// The read-modify-write operation of an `AtomicFetch` intrinsic.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AtomicFetchOp {
    Add,
    Sub,
    And,
    Or,
    Xor,
}

#[derive(Debug, Clone)]
pub enum Expression {
    /// Reference to a symbol by identifier, with an (optional, resolved) type.
    SymbolRef {
        id: String,
        ty: TypeName,
        loc: Loc,
    },
    /// `this`
    ThisRef,
    /// Member access on an expression: `lhs.name`
    MemberRef {
        lhs: Box<Expression>,
        name: String,
        /// Location of the member name.
        loc: Loc,
    },
    BoolLiteral(bool),
    IntLiteral(i64),
    FloatLiteral(f64),
    /// (value, is_raw)
    StringLiteral {
        value: String,
        is_raw: bool,
        /// The literal in the source; `Loc::NONE` for synthesized ones.
        loc: Loc,
    },
    /// Null pointer literal
    PointerLiteral,
    Binary {
        op: BinaryOp,
        lhs: Box<Expression>,
        rhs: Box<Expression>,
        /// Location of the operator and right operand.
        loc: Loc,
    },
    Unary {
        op: UnaryOp,
        operand: Box<Expression>,
        loc: Loc,
    },
    /// `expr as Type` — static cast (docs/src/language/types-and-variables.md).
    Cast {
        expr: Box<Expression>,
        ty: TypeName,
        loc: Loc,
    },
    Ternary {
        condition: Box<Expression>,
        true_expr: Box<Expression>,
        false_expr: Box<Expression>,
    },
    /// `lhs[rhs]`
    Index {
        lhs: Box<Expression>,
        rhs: Box<Expression>,
        loc: Loc,
    },
    /// POD array indexing after operator resolution
    ArrayIndex {
        ty: TypeName,
        lhs: Box<Expression>,
        rhs: Box<Expression>,
        loc: Loc,
    },
    SizeOf(TypeName),
    IsPod(TypeName),
    Default(TypeName),
    /// A new object of struct `T` with every field zero (null for a
    /// reference) and both head counts 1, made without running `T`'s
    /// constructor. Like a constructor's result, it is an owned rvalue
    /// carrying one reference. Only in the `__copy` methods that
    /// `passes::copies` synthesizes.
    Allocate(TypeName),
    /// `__refcount<T>(t)`: the reference count of object `t` (0 for POD T).
    RefCount(TypeName, Box<Expression>),
    /// `__address<T>(v)`: the pointer address of object `v` (identity
    /// hashing for structs); POD T folds the value's bytes instead.
    Address(TypeName, Box<Expression>),
    /// `__atomic_load<T>(p)`: acquire-ordered atomic load of the T-sized
    /// value at pointer `p` (the `Atomic<T>` storage slot).
    AtomicLoad(TypeName, Box<Expression>),
    /// `__atomic_store<T>(p, v)`: release-ordered atomic store of `v` into
    /// the T-sized value at pointer `p`.
    AtomicStore(TypeName, Box<Expression>, Box<Expression>),
    /// `__atomic_cmpxchg<T>(p, expected, desired)`: acquire/release compare
    /// and exchange; true iff `*p == expected` (in which case `*p = desired`).
    AtomicCmpXchg(TypeName, Box<Expression>, Box<Expression>, Box<Expression>),
    /// `__atomic_fetch_{add,sub,and,or,xor}<T>(p, v)`: acquire/release
    /// atomic read-modify-write on the T-sized integer value at pointer `p`;
    /// returns the previous value (the old occupant of the slot).
    AtomicFetch(AtomicFetchOp, TypeName, Box<Expression>, Box<Expression>),
    /// Weak reference intrinsics over struct `T` (see `passes::weak_types`):
    /// `__weak_from<T>(t)` (a new `__weak<T>` to `t`'s object),
    /// `__weak_upgrade<T>(w)` (a new strong `T`, or null once destroyed) and
    /// `__weak_expired<T>(w)` (bool).
    Weak(WeakOp, TypeName, Box<Expression>),
    /// One step of a head count of the `this` object inside a synthesized
    /// `__acquire`/`__release` body: `field` (`__refcount` or `__weakcount`)
    /// goes up by one (`increment`) or down by one. Evaluates to the count
    /// after the step (`u32`). See `struct_body` for when it is atomic.
    CountStep {
        field: CountField,
        increment: bool,
        /// An atomic read-modify-write (a `[Shared]` struct, a function
        /// type, or a weak view of a shared struct), else a plain one.
        atomic: bool,
    },
    /// `__function_pointer(f)`: the raw, C-callable address of function `f`
    /// (a `void*`), for passing a Pepper function to C as a callback. `owner`
    /// is the struct whose static method `f` is, or `None` for a free
    /// function.
    FunctionPointer {
        owner: Option<TypeName>,
        function: String,
        /// Location of the intrinsic's name.
        loc: Loc,
    },
    /// Free function call by name (possibly specialized `name<args>`)
    FunctionCall {
        function: String,
        args: Vec<Expression>,
        /// Location of the called name.
        loc: Loc,
    },
    /// Method call on `this` expression
    MethodCall {
        this: Box<Expression>,
        method: String,
        args: Vec<Expression>,
        /// Location of the method name.
        loc: Loc,
    },
    /// A named free function used as a value (`var f = square;`): a
    /// reference to the function's static function object, of function type
    /// `ty` (`__function<R, P...>`).
    FunctionRef {
        function: String,
        ty: TypeName,
        /// Location of the function's name.
        loc: Loc,
    },
    /// Call through a function value: `f(x)`, `obj.callback(x)`,
    /// `make_adder(1)(2)`. `callee` evaluates to a function object.
    Invoke {
        callee: Box<Expression>,
        args: Vec<Expression>,
    },
    /// A closure literal as written, before `lift_closures` (the first
    /// step of `struct_body::apply`) turns it into a `MakeClosure`. Never
    /// reaches the transform passes.
    ClosureLiteral(Box<ClosureLiteral>),
    /// Create a closure: `value` constructs the closure's synthesized struct
    /// (`__closure_N`, holding the captured values), which is used as a
    /// value of function type `ty`. `closure` names that struct (with its
    /// generic arguments, `__closure_N<T>`).
    MakeClosure {
        value: Box<Expression>,
        closure: String,
        ty: TypeName,
        loc: Loc,
    },
    /// The entry point of method `method` of the struct whose constructor
    /// this appears in, as a `void*`. Only in synthesized closure structs:
    /// their `__invoke` and `__destroy` field defaults.
    MethodAddress(String),
    /// Call the `void` function at `pointer` with `args`. Only in
    /// synthesized function type structs: the destructor calls `__destroy`.
    CallPointer {
        pointer: Box<Expression>,
        args: Vec<Expression>,
    },
    /// The iterator a `for` loop drives, built from its source expression:
    /// `source.iterate()` when the source's type declares `iterate()`
    /// (Iterable<T>), else the source itself when it declares `next()` and
    /// `current()` (Iterator<T>). Chosen by type, like C++ range-for; the
    /// builder emits it only as the default of the loop's hidden iterator.
    ForIterator(Box<Expression>),
    /// The condition of a lowered `with` block, over its bound value (a
    /// `SymbolRef`): "the scope was entered". `lower_with_blocks` replaces it
    /// once types are known: a null test for a struct or pointer value, no
    /// branch at all otherwise. Never reaches codegen.
    WithEntered(Box<Expression>),
    /// The argument of `move(value)` (a `[MoveSource]` parameter; wrapped by
    /// `check_confinement::lower_moved_arguments`): the reference the place
    /// `value` holds (a local, or a raw slot `p[i]` in the runtime), which
    /// the place gives up: it is
    /// left null without a release, and the expression is an owned rvalue
    /// carrying that reference. `check_confinement` checks what may be
    /// moved and that a moved local is not used again.
    Move {
        value: Box<Expression>,
        loc: Loc,
    },
    /// The tuple a destructuring (`var (a, b) = value;`, `(a, b) = value;`)
    /// reads, with the number of places it names: the builder emits it only
    /// as the default of the hidden `__tuple_N` local.
    /// `tuples::lower_destructures` checks that `value` is a tuple of `count`
    /// elements and replaces the node with `value`. Never reaches codegen.
    Destructure {
        value: Box<Expression>,
        count: usize,
        loc: Loc,
    },
    /// One arm's test in a lowered `match`: `subject` (the hidden
    /// `__match_N` local) is one of `patterns`. The builder lowers `match`
    /// to an `if`/`else` chain of these; `enums::lower_matches` replaces
    /// each with `==` tests once the subject's type is known, and checks
    /// exhaustiveness across the arms that share `site`. Never reaches
    /// codegen.
    MatchArm(Box<MatchArmTest>),
    /// A value a `match` pattern binds (`text` in `Text(text) => ...`): the
    /// value at `index` of the matched case of `subject`, a reference enum.
    /// The builder makes it the default of the binding's local. Typed by
    /// `resolve_implicit_types`, which reports a case or position the enum
    /// lacks; `enums::lower_matches` replaces it with the payload field.
    /// Never reaches codegen.
    CaseValue(Box<CaseValue>),
    /// A reference enum's case that carries no values (`Doc.Line`), as the
    /// one object every use of it shares: an immortal global of struct
    /// `ty` whose tag is `tag` and whose count starts at `STATIC_REFCOUNT`,
    /// so it is never freed and needs no allocation. The case's static
    /// method returns it.
    StaticCase { ty: TypeName, tag: i64 },
    /// Evaluate `subject` once, then `body`, in which [`Expression::Subject`]
    /// with the same `id` reads the value. A `match` expression is one
    /// around an `?:` chain of [`Expression::MatchArm`] tests, an `is` test
    /// one around a single test. An owned subject is released at the end of
    /// the full expression, like any temporary.
    WithSubject(Box<WithSubject>),
    /// The value the enclosing [`Expression::WithSubject`] with this `id`
    /// evaluated. `ty` is filled in by `resolve_implicit_types`.
    Subject { id: usize, ty: TypeName, loc: Loc },
    /// The value of a `match` expression with no `else` arm when no arm
    /// matched: the last `?:` of its chain falls through to it.
    /// `enums::lower_matches` drops it once it has checked that every case
    /// is handled. Never reaches codegen.
    NoMatch,
    /// A struct reference converted to a trait-typed value (`Shape s =
    /// Square(2);`): the same object, seen through the vtable of `from`'s
    /// conformance to `to`. Inserted by `convert_to_traits` wherever a value
    /// of struct type `from` flows into a slot of trait type `to`; a null
    /// `value` (`__null`) makes a null trait value. Like a shared_ptr
    /// upcast, it does no refcount work of its own: the consuming slot
    /// acquires (or the owned rvalue moves) exactly as for `from`.
    ToTrait {
        value: Box<Expression>,
        from: TypeName,
        to: TypeName,
        loc: Loc,
    },
}

impl Expression {
    /// Where the expression came from in source; [`Loc::NONE`] for literals
    /// and nodes the compiler synthesized.
    pub fn loc(&self) -> Loc {
        match self {
            Expression::SymbolRef { loc, .. }
            | Expression::MemberRef { loc, .. }
            | Expression::Binary { loc, .. }
            | Expression::Unary { loc, .. }
            | Expression::Cast { loc, .. }
            | Expression::Index { loc, .. }
            | Expression::ArrayIndex { loc, .. }
            | Expression::FunctionCall { loc, .. }
            | Expression::FunctionPointer { loc, .. }
            | Expression::FunctionRef { loc, .. }
            | Expression::MethodCall { loc, .. }
            | Expression::MakeClosure { loc, .. }
            | Expression::ToTrait { loc, .. }
            | Expression::Destructure { loc, .. }
            | Expression::Move { loc, .. }
            | Expression::StringLiteral { loc, .. } => *loc,
            Expression::ClosureLiteral(c) => c.loc,
            _ => Loc::NONE,
        }
    }
}

/// See [`Expression::MatchArm`].
#[derive(Debug, Clone)]
pub struct MatchArmTest {
    pub subject: Expression,
    pub patterns: Vec<CasePattern>,
    /// The `match` this arm belongs to.
    pub site: MatchSite,
}

/// The `match` statement an arm belongs to: every arm of one `match`
/// carries the same one.
#[derive(Debug, Clone, PartialEq)]
pub struct MatchSite {
    /// Program-wide number of the `match` (`__match_N`).
    pub id: usize,
    /// The `match` keyword.
    pub keyword: Loc,
    /// The `else` keyword, when the `match` has an `else` arm.
    pub else_arm: Option<Loc>,
    /// An `is` test rather than a `match`: its one arm need not handle every
    /// case.
    pub partial: bool,
}

/// See [`Expression::WithSubject`].
#[derive(Debug, Clone)]
pub struct WithSubject {
    /// The `match`'s site id (see [`MatchSite`]).
    pub id: usize,
    pub subject: Expression,
    pub body: Expression,
    /// Set by `enums::lower_matches` for a reference enum subject: the
    /// panic message when the subject is null.
    pub null_message: Option<String>,
    pub loc: Loc,
}

/// See [`Expression::CaseValue`].
#[derive(Debug, Clone)]
pub struct CaseValue {
    /// The hidden `__match_N` local.
    pub subject: Expression,
    /// The name bound.
    pub name: String,
    /// Each pattern of the arm that binds the name: its case and the
    /// position of the name among its bindings. Several when alternatives
    /// (`Concat(parts), Indent(parts)`) bind one name.
    pub choices: Vec<CaseChoice>,
    /// Location of the binding.
    pub loc: Loc,
}

/// One pattern's part in a [`CaseValue`].
#[derive(Debug, Clone)]
pub struct CaseChoice {
    pub case: String,
    /// Location of the case name in the pattern.
    pub case_loc: Loc,
    /// Position of the binding among the pattern's bindings.
    pub index: usize,
    /// Every binding of the pattern, `_` included.
    pub bindings: Vec<Loc>,
    /// Location of the binding in this pattern.
    pub loc: Loc,
}

/// A pattern of a `match` arm: `Case`, `Enum.Case`, or `Case(x, _)`.
#[derive(Debug, Clone)]
pub struct CasePattern {
    /// The enum named before the case, if any.
    pub qualifier: Option<TypeName>,
    pub case: String,
    /// Location of the case name.
    pub loc: Loc,
    /// The names bound to the case's values; `None` without parentheses.
    pub bindings: Option<Vec<(String, Loc)>>,
    /// For a literal pattern (`1`, `"import"`): the test `subject ==
    /// literal`, built by the builder so the passes type and resolve it like
    /// any `==`. `case` then holds the literal as written.
    pub literal: Option<Expression>,
}

/// An `enum` declaration whose cases carry no values: an integer type. An
/// enum with a case that carries values is a struct instead, with
/// [`StructDef::enum_cases`].
#[derive(Debug, Clone)]
pub struct EnumDef {
    pub name: String,
    /// The integer type its values are stored as (`int` unless written).
    pub representation: TypeName,
    pub cases: Vec<EnumCaseDef>,
    pub attributes: Vec<ast::Attribute>,
    /// Location of the enum's name.
    pub loc: Loc,
}

impl EnumDef {
    /// The case named `name`.
    pub fn case(&self, name: &str) -> Option<&EnumCaseDef> {
        self.cases.iter().find(|c| c.name == name)
    }

    /// The value of a slot nothing was stored in yet: the case whose value
    /// is 0, else the first case (0 for an enum with no cases).
    pub fn default_value(&self) -> i64 {
        if self.cases.iter().any(|c| c.value == 0) {
            0
        } else {
            self.cases.first().map_or(0, |c| c.value)
        }
    }
}

/// One case of an [`EnumDef`].
#[derive(Debug, Clone)]
pub struct EnumCaseDef {
    pub name: String,
    /// The case's value; a reference enum's tag.
    pub value: i64,
    /// A reference enum's case: the names of the values it carries, each
    /// with its location. Each is the field [`payload_field`] names.
    pub payload: Vec<(String, Loc)>,
    pub attributes: Vec<ast::Attribute>,
    /// Location of the case's name.
    pub loc: Loc,
}

/// The field of a reference enum's object that holds `value` of case
/// `case`: `Text.text`. The dot keeps two cases' values apart and keeps
/// source code from naming the field.
pub fn payload_field(case: &str, value: &str) -> String {
    format!("{}.{}", case, value)
}

/// The field of a reference enum's object that says which case it is.
pub const TAG_FIELD: &str = "__tag";

/// A closure literal: `(x: int) => x * 2`. Parameters and the return type
/// written without a type are `auto`.
#[derive(Debug, Clone)]
pub struct ClosureLiteral {
    pub parameters: Vec<VariableDef>,
    /// The return type (`auto` when not written).
    pub ty: TypeName,
    pub body: Block,
    /// The body was an expression, lowered to `{ return expr; }`.
    pub expression_body: bool,
    /// Location of the whole literal.
    pub loc: Loc,
}

/// Which head count of an object an `Expression::CountStep` changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CountField {
    /// `__refcount`, the strong count (byte offset 0).
    Strong,
    /// `__weakcount`, the weak count (byte offset 4).
    Weak,
}

impl CountField {
    /// The byte offset of the count in every object head.
    pub fn offset(self) -> u64 {
        match self {
            CountField::Strong => 0,
            CountField::Weak => 4,
        }
    }
}

/// Which weak reference intrinsic an `Expression::Weak` is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WeakOp {
    From,
    Upgrade,
    Expired,
}

impl WeakOp {
    /// The intrinsic's source name.
    pub fn name(self) -> &'static str {
        match self {
            WeakOp::From => "__weak_from",
            WeakOp::Upgrade => "__weak_upgrade",
            WeakOp::Expired => "__weak_expired",
        }
    }

    /// The result type for target `T`.
    pub fn result(self, target: &TypeName) -> TypeName {
        match self {
            WeakOp::From => TypeName::with_args(crate::type_name::WEAK, vec![target.clone()]),
            WeakOp::Upgrade => target.clone(),
            WeakOp::Expired => TypeName::bool_(),
        }
    }
}

// ── Statements ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Block {
    pub name: String,
    pub items: Vec<Statement>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
}

#[derive(Debug, Clone)]
pub struct Branch {
    pub condition: Expression,
    pub if_block: Block,
    pub else_block: Option<Block>,
}

#[derive(Debug, Clone)]
pub struct While {
    pub condition: Expression,
    pub block: Block,
}

#[derive(Debug, Clone)]
pub struct ReturnStatement {
    pub expr: Option<Expression>,
    /// Location of the returned value ([`Loc::NONE`] when synthesized).
    pub loc: Loc,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopBreakKind { Break, Continue }

#[derive(Debug, Clone)]
pub struct LoopBreak {
    pub kind: LoopBreakKind,
}

#[derive(Debug, Clone)]
pub enum Statement {
    Expression(Expression),
    Block(Block),
    Declaration(Declaration),
    Branch(Branch),
    While(While),
    Return(ReturnStatement),
    LoopBreak(LoopBreak),
}

// ── Declarations ─────────────────────────────────────────────────────────────

/// Variable definition: local, field, or parameter.
#[derive(Debug, Clone)]
pub struct VariableDef {
    pub name: String,
    pub ty: TypeName,
    pub default: Option<Expression>,
    /// Hidden internal var (e.g. the ctor's `size`).
    pub hidden: bool,
    pub kind: Kind,
    /// Source attributes; only module-scope variables use them
    /// (`[Target(...)]` platform selection).
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
    /// Location of the written type; [`Loc::NONE`] when it is inferred.
    pub type_loc: Loc,
    /// Declared `const`: it may not be assigned after its initialization.
    pub is_const: bool,
}

#[derive(Debug, Clone)]
/// A generic type parameter, optionally with a default (`TError=Error` in
/// `Result<TValue, TError=Error>`).
pub struct GenericParam {
    pub name: String,
    /// Default type substituted when a use omits this argument.
    pub default: Option<TypeName>,
    /// A type argument, not a parameter: module linking decided the function
    /// is a concrete override (see `ast::GenericParam::is_argument`).
    pub is_argument: bool,
}

#[derive(Debug, Clone)]
pub struct FunctionDef {
    pub name: String,
    pub ty: TypeName,
    /// Generic parameters (`T` in `hash<T>`), in declaration order.
    pub generic_params: Vec<GenericParam>,
    pub parameters: Vec<VariableDef>,
    pub body: Option<Block>,
    /// Owning struct for methods.
    pub parent: Option<String>,
    pub is_static: bool,
    pub is_indexer: bool,
    pub is_generic_func: bool,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
    /// A trait's default method copied into a struct that conforms to the
    /// trait: the trait's method names. A bare call in its body binds only
    /// to those (on `this`), never to a method only the struct declares.
    pub trait_default: Option<Vec<String>>,
    /// Where the code is compiled when that is not `loc`'s file: a copied
    /// trait default belongs to the file that declares the conformance
    /// (`extend S with Trait`), not the trait's. [`Loc::NONE`] otherwise.
    pub owner: Loc,
}

#[derive(Debug, Clone)]
pub struct StructDef {
    /// Declared name of the struct (`Test`), or the specialization string
    /// (`Test<int>`) for specialized instances.
    pub name: String,
    /// Base generic type (`Test` for `Test<int>`; name without args for
    /// non-generic structs).
    pub ty: TypeName,
    pub generic_params: Vec<GenericParam>,
    pub field_members: Vec<VariableDef>,
    pub method_members: Vec<FunctionDef>,
    /// Methods with type parameters of their own (`map<U>(...)`), kept
    /// apart: only their specializations (`map<long>`, added to
    /// `method_members` by `generic_methods`) are compiled.
    pub generic_methods: Vec<FunctionDef>,
    /// The constructors, at least one (an empty one when the struct
    /// declares none). A single constructor is named after the type
    /// (`Point`, `Box<int>`); several are an overload set named `Point$1`,
    /// `Point$2`, … in declaration order (see `overloads::name_overloads`).
    pub constructors: Vec<FunctionDef>,
    pub destructor: FunctionDef,
    pub acquire: FunctionDef,
    pub release: FunctionDef,
    pub traits: Vec<TypeName>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
    /// A reference enum (an `enum` with a case that carries values): its
    /// cases, each tagged by its position. The object holds the tag in
    /// [`TAG_FIELD`] and every case's values in [`payload_field`]s; each
    /// case is a static method that makes one.
    pub enum_cases: Option<Vec<EnumCaseDef>>,
}

/// The attribute that makes a struct shareable between threads.
pub const SHARED_ATTRIBUTE: &str = "Shared";

/// A value converted by an `[Implicit]` constructor: `to(value)` where the
/// value was a `from`.
#[derive(Debug, Clone, PartialEq)]
pub struct Conversion {
    /// The converted value in the source.
    pub at: Loc,
    pub from: TypeName,
    pub to: TypeName,
    /// The `[Implicit]` constructor.
    pub constructor: Loc,
}

/// The attribute that lets a one-argument constructor convert implicitly:
/// a value of its parameter's type flowing into a slot of the struct's type
/// becomes a call to it (`passes::convert_to_traits`).
pub const IMPLICIT_ATTRIBUTE: &str = "Implicit";

/// Whether `attributes` include a bare `[name]`.
pub fn has_attribute(attributes: &[ast::Attribute], name: &str) -> bool {
    attributes.iter().any(|a| matches!(&a.body, ast::Expression::SymbolRef { id, .. } if id == name))
}

impl StructDef {
    /// Declared `[Shared]`: its objects may be referenced from several
    /// threads, so its reference counts are atomic.
    pub fn is_shared(&self) -> bool {
        has_attribute(&self.attributes, SHARED_ATTRIBUTE)
    }

    /// The type an `[Implicit]` constructor converts from: its first
    /// parameter's (the builder checked the rest have defaults).
    pub fn implicit_from(&self) -> Option<&TypeName> {
        self.implicit_constructor()?.parameters.first().map(|p| &p.ty)
    }

    /// The constructor marked `[Implicit]`, if any (the builder allows one).
    pub fn implicit_constructor(&self) -> Option<&FunctionDef> {
        self.constructors.iter().find(|c| has_attribute(&c.attributes, IMPLICIT_ATTRIBUTE))
    }

    /// The constructor a call names: `Point`, `Point$2` or `Box<int>$2`.
    pub fn constructor_named(&self, name: &str) -> Option<&FunctionDef> {
        self.constructors.iter().find(|c| c.name == name)
    }

    /// Whether `name` names one of the constructors, or their set.
    pub fn is_constructor_name(&self, name: &str) -> bool {
        name == self.ty.to_string() || self.constructors.iter().any(|c| c.name == name)
    }

    /// Whether acquire/release step the counts atomically: `[Shared]`
    /// structs, and thread-safe function types (`shared (P...) => R`, the
    /// values that carry work to another thread). A plain function type
    /// counts like any other struct.
    pub fn atomic_counts(&self) -> bool {
        self.is_shared() || self.ty.is_shared_function_type()
    }
}

#[derive(Debug, Clone)]
pub struct TraitDef {
    pub name: String,
    /// Generic parameters (`T` in `Iterator<T>`), in declaration order.
    pub generic_params: Vec<GenericParam>,
    pub methods: Vec<FunctionDef>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
}

/// A trait used as a type, with its type arguments substituted
/// (`Iterator<int>`): the methods a value of this type can call, in vtable
/// order. Static members and members whose signature names `this` as a type
/// cannot be called through a value, so they have no slot.
#[derive(Debug, Clone)]
pub struct TraitType {
    pub ty: TypeName,
    /// Dispatchable methods (signatures only), in trait declaration order.
    pub methods: Vec<FunctionDef>,
}

#[derive(Debug, Clone)]
pub struct ExtensionDef {
    /// Target struct, possibly specialized.
    pub target: TypeName,
    /// Resolved target struct name (set by ResolveResolvables).
    pub resolved: Option<String>,
    pub traits: Vec<TypeName>,
    pub methods: Vec<FunctionDef>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the extended type.
    pub loc: Loc,
    /// Marked `export`: files that import its file may use its methods.
    pub is_exported: bool,
}

/// Per file, the other files whose exported extensions it may use (from
/// `modules::FileScope::extensions`), plus the prelude files, whose
/// exported extensions every file may use. An extension is always visible
/// in its own file.
#[derive(Debug, Clone, Default)]
pub struct ExtensionScopes {
    pub prelude: std::collections::HashSet<u32>,
    /// Indexed by `FileId`; empty when the module was not linked.
    pub visible: Vec<std::collections::HashSet<u32>>,
}

impl ExtensionScopes {
    /// Whether code in file `from` may use the methods of an extension
    /// declared in file `file`.
    pub fn sees(&self, from: FileId, file: FileId, exported: bool) -> bool {
        let Some(visible) = self.visible.get(from.0 as usize) else { return true };
        file == from || (exported && (self.prelude.contains(&file.0) || visible.contains(&file.0)))
    }
}

#[derive(Debug, Clone)]
pub struct ExternDef {
    pub name: String,
    pub ty: TypeName,
    pub parameters: Vec<VariableDef>,
    /// The C prototype ends in `...`: calls may pass arguments beyond
    /// `parameters`, which get C's default argument promotions.
    pub is_variadic: bool,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
}

impl ExternDef {
    /// The C symbol this extern binds to: the argument of a
    /// `[LinkName("sym")]` attribute, else the declared name. Pepper code
    /// always calls the extern by its declared name.
    pub fn link_name(&self) -> Result<&str, String> {
        let mut found: Option<&str> = None;
        for attr in &self.attributes {
            let ast::Expression::FunctionCall { function, arguments, .. } = &attr.body else {
                if matches!(&attr.body, ast::Expression::SymbolRef { id, .. } if id == "LinkName") {
                    return Err(format!("LinkName on extern '{}' needs a symbol: [LinkName(\"sym\")]", self.name));
                }
                continue;
            };
            if !matches!(function.as_ref(), ast::Expression::SymbolRef { id, .. } if id == "LinkName") {
                continue;
            }
            let [ast::Expression::Literal { value: ast::Literal::String(sym), .. }] = arguments.as_slice() else {
                return Err(format!("LinkName on extern '{}' takes exactly one string: [LinkName(\"sym\")]", self.name));
            };
            if sym.is_empty() {
                return Err(format!("LinkName on extern '{}' must not be empty", self.name));
            }
            if found.is_some() {
                return Err(format!("extern '{}' has more than one LinkName", self.name));
            }
            found = Some(sym.as_str());
        }
        Ok(found.unwrap_or(&self.name))
    }
}

/// Type alias definition: `type Name<P1, P2=Default> = Target;`. The target
/// may reference the alias's parameters; uses are expanded at resolution.
#[derive(Debug, Clone)]
pub struct TypeAliasDef {
    pub name: String,
    pub generic_params: Vec<GenericParam>,
    pub target: TypeName,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
}

#[derive(Debug, Clone)]
pub enum Declaration {
    Variable(VariableDef),
    Function(FunctionDef),
    Struct(StructDef),
    Trait(TraitDef),
    Extension(ExtensionDef),
    Extern(ExternDef),
    TypeAlias(TypeAliasDef),
}

/// Generic instantiation request: struct or function, keyed by concrete `TypeName`.
#[derive(Debug, Clone)]
pub enum Spec {
    Struct(TypeName),
    Function(TypeName),
}

#[derive(Debug, Clone, Default)]
pub struct Module {
    pub imports: Vec<ast::Import>,
    pub structs: Vec<StructDef>,
    pub traits: Vec<TraitDef>,
    pub extensions: Vec<ExtensionDef>,
    pub functions: Vec<FunctionDef>,
    pub externs: Vec<ExternDef>,
    /// Module-scope variables (`var x = ...` at file scope): LLVM globals,
    /// initialized by a constant initializer or an init function.
    pub globals: Vec<VariableDef>,
    /// Enums whose cases carry no values (`enum Color { Red, Green }`):
    /// integer types, which keep their own name through sema so types are
    /// checked and `match` is checked for exhaustiveness (see `enums.rs`).
    pub enums: Vec<EnumDef>,
    pub struct_specs: Vec<TypeName>,
    pub func_specs: Vec<TypeName>,
    /// Type aliases (`type Name = Target;`), expanded away by
    /// `resolve_type_aliases` before any other pass.
    pub type_aliases: Vec<TypeAliasDef>,
    /// Every trait type the program uses as a value type, filled by
    /// `convert_to_traits`; codegen builds their vtables and dispatch.
    pub trait_types: Vec<TraitType>,
    /// Every implicit constructor conversion `convert_to_traits` inserted
    /// where the converted value has a source location, for the language
    /// server's hover and inlay hints.
    pub conversions: Vec<Conversion>,
    /// Overloaded free functions: each set's name, as calls spell it, and
    /// its members' names (`scale$1`, `scale$2`) in declaration order.
    /// Filled by `overloads::name_overloads`.
    pub overload_sets: std::collections::BTreeMap<String, Vec<String>>,
    /// Overloaded methods: struct name → set name (`get`, `+`) → its
    /// members' names (`get$1`, `get$2`). A specialization's methods keep
    /// their base's member names. Filled by `overloads::name_overloads`.
    pub method_overload_sets: std::collections::BTreeMap<String, std::collections::BTreeMap<String, Vec<String>>>,
    /// Which files' extensions each file sees, for choosing among the
    /// members of a method overload set an extension adds to. Empty (every
    /// extension visible) unless the module was linked from a program.
    pub extension_scopes: ExtensionScopes,
    /// Each call or function value that named an overload set: its callee's
    /// location and the member it resolved to, for the language server.
    pub call_targets: Vec<(Loc, String)>,
    /// The files locations point into, for rendering diagnostics. Filled by
    /// whoever loads the files (see `build_file`); `merge` leaves it alone.
    pub sources: pepper_parser::diagnostic::SourceMap,
    /// Each file's namespace, by `FileId`, filled with `sources`. Names sema
    /// synthesizes for a file's code (closure structs) take it, so they do
    /// not depend on the other files of the program. `merge` leaves it alone.
    pub namespaces: Vec<String>,
    /// Per file, by `FileId`: its unit's object comes from the build cache,
    /// so `strip_bodies` drops its non-generic bodies once closures are
    /// lifted. Empty when nothing is cached. `merge` leaves it alone.
    pub cached_files: Vec<bool>,
    /// The link summaries (`check_confinement`) the build cache recorded for
    /// the functions of cached units, by each function's location:
    /// `strip_bodies` drops only bodies recorded here, and the pass uses the
    /// summaries in their place. `merge` leaves it alone.
    pub recorded_summaries: std::collections::HashMap<Loc, String>,
    /// Have `check_confinement` summarize every function and fill
    /// `summaries_to_record`, for the build cache to store.
    pub record_summaries: bool,
    /// The summaries worth recording (see `record_summaries`), by location.
    pub summaries_to_record: Vec<(Loc, String)>,
    /// Warnings found while compiling: those the driver carried over from
    /// the loaded program (`Program::warnings`), then the uses of
    /// deprecated members `check_deprecated_members` found. `merge` leaves
    /// it alone.
    pub warnings: Vec<Diagnostic>,
    /// Built from files module linking processed, which decided which
    /// generic functions are concrete overrides and marked them
    /// (`GenericParam::is_argument`): sema follows those marks alone.
    pub linked: bool,
}

impl Module {
    /// The struct constructed by a call to `function` and the constructor
    /// it calls: `Point` (a single constructor) or `Point$2`, `Box<int>$2`.
    /// A call still naming an overloaded struct's set has none yet.
    pub fn constructor_of(&self, function: &str) -> Option<(&StructDef, &FunctionDef)> {
        let ty = crate::passes::overloads::set_name(function);
        let st = self.structs.iter().find(|s| s.name == ty || s.ty.to_string() == ty)?;
        let single = || (st.constructors.len() == 1).then(|| &st.constructors[0]);
        let ctor = st.constructor_named(function).or_else(single)?;
        Some((st, ctor))
    }

    /// [`Module::warnings`] in source order, rendered clang-style against
    /// [`Module::sources`]; empty when there are none.
    pub fn render_warnings(&self) -> String {
        let mut warnings: Vec<&Diagnostic> = self.warnings.iter().collect();
        warnings.sort_by_key(|w| w.loc.map(|l| (l.file.0, l.span.start)));
        warnings.iter().map(|w| self.sources.render(w)).collect::<Vec<_>>().join("\n")
    }

    pub fn merge(&mut self, other: Module) {
        self.imports.extend(other.imports);
        self.structs.extend(other.structs);
        self.enums.extend(other.enums);
        self.traits.extend(other.traits);
        self.extensions.extend(other.extensions);
        self.functions.extend(other.functions);
        self.externs.extend(other.externs);
        self.globals.extend(other.globals);
        self.struct_specs.extend(other.struct_specs);
        self.func_specs.extend(other.func_specs);
        self.type_aliases.extend(other.type_aliases);
        self.linked |= other.linked;
    }
}

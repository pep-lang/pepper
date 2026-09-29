//! Sema model: owned enum tree ported from `source/Sema/Model/*`. No
//! `Rc/RefCell` — passes walk `&mut Module` sequentially and replace nodes in
//! place, mirroring the C++ `NodeRef` assignment.

use crate::type_name::TypeName;
use pepper_parser::ast;
pub use pepper_parser::diagnostic::{Diagnostic, Loc};

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
            | Expression::MethodCall { loc, .. }
            | Expression::MakeClosure { loc, .. }
            | Expression::ToTrait { loc, .. } => *loc,
            Expression::ClosureLiteral(c) => c.loc,
            _ => Loc::NONE,
        }
    }
}

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
    pub constructor: FunctionDef,
    pub destructor: FunctionDef,
    pub acquire: FunctionDef,
    pub release: FunctionDef,
    pub traits: Vec<TypeName>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
    /// Location of the declared name.
    pub loc: Loc,
}

/// The attribute that makes a struct shareable between threads.
pub const SHARED_ATTRIBUTE: &str = "Shared";

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
        if !has_attribute(&self.constructor.attributes, IMPLICIT_ATTRIBUTE) {
            return None;
        }
        self.constructor.parameters.first().map(|p| &p.ty)
    }

    /// Whether acquire/release step the counts atomically: `[Shared]`
    /// structs, and function types (the values that carry work to another
    /// thread).
    pub fn atomic_counts(&self) -> bool {
        self.is_shared() || self.ty.is_function_type()
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
    pub struct_specs: Vec<TypeName>,
    pub func_specs: Vec<TypeName>,
    /// Type aliases (`type Name = Target;`), expanded away by
    /// `resolve_type_aliases` before any other pass.
    pub type_aliases: Vec<TypeAliasDef>,
    /// Every trait type the program uses as a value type, filled by
    /// `convert_to_traits`; codegen builds their vtables and dispatch.
    pub trait_types: Vec<TraitType>,
    /// The files locations point into, for rendering diagnostics. Filled by
    /// whoever loads the files (see `build_file`); `merge` leaves it alone.
    pub sources: pepper_parser::diagnostic::SourceMap,
}

impl Module {
    pub fn merge(&mut self, other: Module) {
        self.imports.extend(other.imports);
        self.structs.extend(other.structs);
        self.traits.extend(other.traits);
        self.extensions.extend(other.extensions);
        self.functions.extend(other.functions);
        self.externs.extend(other.externs);
        self.globals.extend(other.globals);
        self.struct_specs.extend(other.struct_specs);
        self.func_specs.extend(other.func_specs);
        self.type_aliases.extend(other.type_aliases);
    }
}

//! Sema model: owned enum tree ported from `source/Sema/Model/*`. No
//! `Rc/RefCell` — passes walk `&mut Module` sequentially and replace nodes in
//! place, mirroring the C++ `NodeRef` assignment.

use crate::type_name::TypeName;
use pepper_parser::ast;

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
            BinaryOp::Identical => "",
            BinaryOp::Assign => "",
            BinaryOp::AddAssign => "+=",
            BinaryOp::SubAssign => "-=",
            BinaryOp::MulAssign => "*=",
            BinaryOp::DivAssign => "/=",
            BinaryOp::ModAssign => "%=",
            BinaryOp::LShiftAssign => "<<=",
            BinaryOp::RShiftAssign => ">>=",
            BinaryOp::BitAndAssign => "&=",
            BinaryOp::BitOrAssign => "^=",
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
        )
    }

    /// Comparison ops (`==`, `!=`, `<`, `<=`, `>`, `>=`, identical): their
    /// result type is `bool`.
    pub fn is_comparison(&self) -> bool {
        matches!(
            self,
            BinaryOp::Identical | BinaryOp::Equal | BinaryOp::NotEqual | BinaryOp::Less | BinaryOp::LessEqual | BinaryOp::Greater | BinaryOp::GreaterEqual
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
    },
    /// `this`
    ThisRef,
    /// Member access on an expression: `lhs.name`
    MemberRef {
        lhs: Box<Expression>,
        name: String,
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
    },
    Unary {
        op: UnaryOp,
        operand: Box<Expression>,
    },
    /// `expr as Type` — static cast (spec docs/pepper.md).
    Cast {
        expr: Box<Expression>,
        ty: TypeName,
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
    },
    /// POD array indexing after operator resolution
    ArrayIndex {
        ty: TypeName,
        lhs: Box<Expression>,
        rhs: Box<Expression>,
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
    /// Free function call by name (possibly specialized `name<args>`)
    FunctionCall {
        function: String,
        args: Vec<Expression>,
    },
    /// Method call on `this` expression
    MethodCall {
        this: Box<Expression>,
        method: String,
        args: Vec<Expression>,
    },
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
    pub constructor: FunctionDef,
    pub destructor: FunctionDef,
    pub acquire: FunctionDef,
    pub release: FunctionDef,
    pub traits: Vec<TypeName>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
}

#[derive(Debug, Clone)]
pub struct TraitDef {
    pub name: String,
    pub methods: Vec<FunctionDef>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
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
}

#[derive(Debug, Clone)]
pub struct ExternDef {
    pub name: String,
    pub ty: TypeName,
    pub parameters: Vec<VariableDef>,
    /// Source attributes (`[Target(OS(Windows))]` etc.) carried from the AST.
    pub attributes: Vec<ast::Attribute>,
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

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

#[derive(Debug, Clone)]
pub enum Statement {
    Expression(Expression),
    Block(Block),
    Declaration(Declaration),
    Branch(Branch),
    While(While),
    Return(ReturnStatement),
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
}

#[derive(Debug, Clone)]
pub struct FunctionDef {
    pub name: String,
    pub ty: TypeName,
    pub parameters: Vec<VariableDef>,
    pub body: Option<Block>,
    /// Owning struct for methods.
    pub parent: Option<String>,
    pub is_static: bool,
    pub is_indexer: bool,
    pub is_generic_func: bool,
}

#[derive(Debug, Clone)]
pub struct StructDef {
    /// Declared name of the struct (`Test`), or the specialization string
    /// (`Test<int>`) for specialized instances.
    pub name: String,
    /// Base generic type (`Test` for `Test<int>`; name without args for
    /// non-generic structs).
    pub ty: TypeName,
    pub generic_params: Vec<TypeName>,
    pub field_members: Vec<VariableDef>,
    pub method_members: Vec<FunctionDef>,
    pub constructor: FunctionDef,
    pub destructor: FunctionDef,
    pub acquire: FunctionDef,
    pub release: FunctionDef,
    pub traits: Vec<TypeName>,
}

#[derive(Debug, Clone)]
pub struct TraitDef {
    pub name: String,
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
}

#[derive(Debug, Clone)]
pub struct ExternDef {
    pub name: String,
    pub ty: TypeName,
    pub parameters: Vec<VariableDef>,
}

#[derive(Debug, Clone)]
pub enum Declaration {
    Variable(VariableDef),
    Function(FunctionDef),
    Struct(StructDef),
    Trait(TraitDef),
    Extension(ExtensionDef),
    Extern(ExternDef),
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
    pub struct_specs: Vec<TypeName>,
    pub func_specs: Vec<TypeName>,
}

impl Module {
    pub fn merge(&mut self, other: Module) {
        self.imports.extend(other.imports);
        self.structs.extend(other.structs);
        self.traits.extend(other.traits);
        self.extensions.extend(other.extensions);
        self.functions.extend(other.functions);
        self.externs.extend(other.externs);
        self.struct_specs.extend(other.struct_specs);
        self.func_specs.extend(other.func_specs);
    }
}

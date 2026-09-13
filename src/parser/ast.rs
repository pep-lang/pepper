use std::fmt::{Display, Formatter};
use itertools::join;

// ── Literals ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Literal {
    String(String, bool), // (value, is_raw)
    Integer(i64),
    Float(f64),
    Bool(bool),
    Null,
}

// ── Type names ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub struct TypeName {
    pub name: String,
    pub generic_types: Vec<TypeName>,
}

impl TypeName {
    pub fn auto() -> Self {
        Self {
            name: "auto".to_string(),
            generic_types: vec![],
        }
    }
}

impl Display for TypeName {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if self.generic_types.is_empty() {
            write!(f, "{}", self.name)
        } else {
            write!(f, "{}<{}>", self.name, join(&self.generic_types, ", "))
        }
    }
}

// ── Expressions ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum Expression {
    Literal(Literal),
    SymbolRef(String),
    /// A generic type reference in expression position, e.g. the `array<int>` in `array<int>()`.
    TypeLiteral(TypeName),
    SizeOf(TypeName),
    /// `op operand`  (prefix)  or  `operand op`  (postfix)
    Unary {
        op: String,
        prefix: bool,
        operand: Box<Expression>,
    },
    Binary {
        lhs: Box<Expression>,
        op: String,
        rhs: Box<Expression>,
    },
    Ternary {
        condition: Box<Expression>,
        true_expr: Box<Expression>,
        false_expr: Box<Expression>,
    },
    Index {
        lhs: Box<Expression>,
        rhs: Box<Expression>,
    },
    MemberAccess {
        lhs: Box<Expression>,
        name: String,
    },
    FunctionCall {
        function: Box<Expression>,
        arguments: Vec<Expression>,
    },
}

impl From<String> for Literal {
    fn from(s: String) -> Self {
        Literal::String(s, false)
    }
}
impl From<&str> for Literal {
    fn from(s: &str) -> Self {
        Literal::String(s.to_string(), false)
    }
}
impl From<i64> for Literal {
    fn from(v: i64) -> Self {
        Literal::Integer(v)
    }
}
impl From<f64> for Literal {
    fn from(v: f64) -> Self {
        Literal::Float(v)
    }
}
impl From<bool> for Literal {
    fn from(v: bool) -> Self {
        Literal::Bool(v)
    }
}

// ── Declarations ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct VariableDecl {
    pub name: String,
    pub type_name: TypeName,
    pub default_value: Option<Expression>,
    pub is_const: bool,
}

#[derive(Debug, Clone)]
pub struct FunctionDecl {
    pub name: String,
    pub generic_params: Vec<TypeName>,
    pub return_type: TypeName,
    pub parameters: Vec<VariableDecl>,
    pub external: bool,
    pub body: Option<Block>,
    /// `static` method modifier
    pub is_static: bool,
    /// Indexer method: `T [](params) { ... }`
    pub is_indexer: bool,
}

#[derive(Debug, Clone)]
pub struct StructDecl {
    pub name: String,
    pub generic_params: Vec<TypeName>,
    pub fields: Vec<VariableDecl>,
    pub methods: Vec<FunctionDecl>,
    /// `new(...)` / `construct(...)` constructor
    pub constructor: Option<FunctionDecl>,
    /// `destruct { ... }` destructor body
    pub destructor: Option<Block>,
}

#[derive(Debug, Clone)]
pub struct TraitDecl {
    pub name: String,
    pub generic_params: Vec<TypeName>,
    pub methods: Vec<FunctionDecl>,
}

#[derive(Debug, Clone)]
pub struct ExtendDecl {
    /// The struct being extended, possibly specialized: `Test<int>`
    pub target: TypeName,
    /// Traits implemented by the extension (after `with`)
    pub traits: Vec<TypeName>,
    pub methods: Vec<FunctionDecl>,
}

#[derive(Debug, Clone)]
pub enum Declaration {
    Variable(VariableDecl),
    Function(FunctionDecl),
    Struct(StructDecl),
    Trait(TraitDecl),
    Extend(ExtendDecl),
}

// ── Blocks & statements ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Block {
    pub statements: Vec<Statement>,
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
    pub expr: Expression,
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

// ── Module ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Import {
    pub name: String,
    pub alias: Option<String>,
    pub is_local: bool,
}

#[derive(Debug, Clone)]
pub struct Module {
    pub imports: Vec<Import>,
    pub declarations: Vec<Declaration>,
}

// ── Display ───────────────────────────────────────────────────────────────────

impl Display for Literal {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Literal::String(s, raw) => write!(f, "{}\"{}\"", if *raw { "@" } else { "" }, s),
            Literal::Integer(v) => write!(f, "{}", v),
            Literal::Float(v) => write!(f, "{}", v),
            Literal::Bool(v) => write!(f, "{}", v),
            Literal::Null => write!(f, "__null"),
        }
    }
}

impl Display for Expression {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Expression::Literal(lit) => write!(f, "{}", lit),
            Expression::SymbolRef(name) => write!(f, "{}", name),
            Expression::TypeLiteral(ty) => write!(f, "{}", ty),
            Expression::SizeOf(ty) => write!(f, "sizeof<{}>()", ty),
            Expression::Unary { op, prefix, operand } => {
                if *prefix {
                    write!(f, "{}{}", op, operand)
                } else {
                    write!(f, "{}{}", operand, op)
                }
            }
            Expression::Binary { lhs, op, rhs } => write!(f, "({} {} {})", lhs, op, rhs),
            Expression::Ternary { condition, true_expr, false_expr } => {
                write!(f, "({} ? {} : {})", condition, true_expr, false_expr)
            }
            Expression::Index { lhs, rhs } => write!(f, "{}[{}]", lhs, rhs),
            Expression::MemberAccess { lhs, name } => write!(f, "{}.{}", lhs, name),
            Expression::FunctionCall { function, arguments } => {
                write!(f, "{}({})", function, join(arguments, ", "))
            }
        }
    }
}

impl Display for VariableDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        let spec = if self.is_const { "const " } else { "var " };
        write!(f, "{}{}: {}", spec, self.name, self.type_name)?;
        if let Some(v) = &self.default_value {
            write!(f, " = {}", v)?;
        }
        Ok(())
    }
}

impl Display for FunctionDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if self.external {
            write!(f, "extern {} {}({})", self.return_type, self.name, join(&self.parameters, ", "))?;
            return Ok(());
        }
        if self.is_static {
            write!(f, "static ")?;
        }
        if self.is_indexer {
            // `T [](params) { ... }`
            write!(f, "{} []", self.return_type)?;
        } else {
            write!(f, "{}", self.name)?;
            if !self.generic_params.is_empty() {
                write!(f, "<{}>", join(&self.generic_params, ", "))?;
            }
        }
        write!(f, "({})", join(&self.parameters, ", "))?;
        if !self.is_indexer && self.return_type.name != "auto" {
            write!(f, ": {}", self.return_type)?;
        }
        if let Some(body) = &self.body {
            write!(f, " {}", body)?;
        } else if !self.is_indexer {
            // declaration without a body (e.g. trait method)
            write!(f, ";")?;
        }
        Ok(())
    }
}

impl Display for StructDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "struct {}", self.name)?;
        if !self.generic_params.is_empty() {
            write!(f, "<{}>", join(&self.generic_params, ", "))?;
        }
        write!(f, " {{")?;
        for field in &self.fields {
            write!(f, "\n    {}", field)?;
        }
        if let Some(constructor) = &self.constructor {
            let body = constructor.body.as_ref().expect("constructor has a body");
            write!(f, "\n    new({}) {}", join(&constructor.parameters, ", "), body)?;
        }
        if let Some(destructor) = &self.destructor {
            write!(f, "\n    destruct {}", destructor)?;
        }
        for method in &self.methods {
            write!(f, "\n    {}", method)?;
        }
        let has_members = !self.fields.is_empty()
            || self.constructor.is_some()
            || self.destructor.is_some()
            || !self.methods.is_empty();
        if has_members {
            write!(f, "\n")?;
        }
        write!(f, "}}")?;
        Ok(())
    }
}

impl Display for TraitDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "trait {}", self.name)?;
        if !self.generic_params.is_empty() {
            write!(f, "<{}>", join(&self.generic_params, ", "))?;
        }
        write!(f, " {{")?;
        for method in &self.methods {
            write!(f, "\n    {}", method)?;
        }
        if !self.methods.is_empty() {
            write!(f, "\n")?;
        }
        write!(f, "}}")
    }
}

impl Display for ExtendDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "extend {}", self.target)?;
        if !self.traits.is_empty() {
            write!(f, " with {}", join(&self.traits, ", "))?;
        }
        write!(f, " {{")?;
        for method in &self.methods {
            write!(f, "\n    {}", method)?;
        }
        if !self.methods.is_empty() {
            write!(f, "\n")?;
        }
        write!(f, "}}")
    }
}

impl Display for Block {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{{")?;
        for stmt in &self.statements {
            write!(f, "\n    {}", stmt)?;
        }
        if !self.statements.is_empty() {
            write!(f, "\n")?;
        }
        write!(f, "}}")?;
        Ok(())
    }
}

impl Display for Branch {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "if {} {}", self.condition, self.if_block)?;
        if let Some(else_block) = &self.else_block {
            write!(f, " else {}", else_block)?;
        }
        Ok(())
    }
}

impl Display for While {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "while {} {}", self.condition, self.block)
    }
}

impl Display for ReturnStatement {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "return {}", self.expr)
    }
}

impl Display for Statement {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Statement::Expression(e) => write!(f, "{};", e),
            Statement::Block(b) => write!(f, "{}", b),
            Statement::Declaration(Declaration::Variable(v)) => write!(f, "{};", v),
            Statement::Declaration(Declaration::Function(fn_)) => write!(f, "{}", fn_),
            Statement::Declaration(Declaration::Struct(s)) => write!(f, "{}", s),
            Statement::Declaration(Declaration::Trait(t)) => write!(f, "{}", t),
            Statement::Declaration(Declaration::Extend(e)) => write!(f, "{}", e),
            Statement::Branch(b) => write!(f, "{}", b),
            Statement::While(w) => write!(f, "{}", w),
            Statement::Return(r) => write!(f, "{};", r),
        }
    }
}

impl Display for Import {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if self.is_local {
            write!(f, "import \"{}\"", self.name)?;
        } else {
            write!(f, "import {}", self.name)?;
        }
        if let Some(alias) = &self.alias {
            write!(f, " as {}", alias)?;
        }
        Ok(())
    }
}

impl Display for Module {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        for imp in &self.imports {
            writeln!(f, "{};", imp)?;
        }
        for decl in &self.declarations {
            match decl {
                Declaration::Variable(v) => writeln!(f, "{};", v)?,
                Declaration::Function(fn_) => writeln!(f, "{}", fn_)?,
                Declaration::Struct(s) => writeln!(f, "{}", s)?,
                Declaration::Trait(t) => writeln!(f, "{}", t)?,
                Declaration::Extend(e) => writeln!(f, "{}", e)?,
            }
        }
        Ok(())
    }
}

use std::fmt::{Display, Formatter};
use itertools::join;

// ── Source locations ──────────────────────────────────────────────────────────

/// A position in a source file, 0-based line and column (column is in
/// characters).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Position {
    pub line: usize,
    pub col: usize,
}

/// A byte-offset range within one source file. `start` is inclusive, `end`
/// exclusive. Offsets are valid for the source the node was parsed from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    /// Zero-length span at offset `pos`.
    pub fn point(pos: usize) -> Self {
        Self { start: pos, end: pos }
    }

    /// The empty span; used for nodes synthesized outside of parsing.
    pub fn none() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.start == self.end
    }

    /// Convert a byte offset in `source` to a (line, col) position.
    pub fn offset_to_position(source: &str, offset: usize) -> Position {
        let offset = offset.min(source.len());
        let before = &source[..offset];
        let line = before.bytes().filter(|&b| b == b'\n').count();
        let col_start = match before.rfind('\n') {
            Some(i) => i + 1,
            None => 0,
        };
        let col = before[col_start..].chars().count();
        Position { line, col }
    }

    pub fn start_position(&self, source: &str) -> Position {
        Self::offset_to_position(source, self.start)
    }

    /// The end position points just past the last byte of the span.
    pub fn end_position(&self, source: &str) -> Position {
        Self::offset_to_position(source, self.end)
    }
}

// ── Literals ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum Literal {
    String(String),
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
    /// Span of the whole type as written (`int[]`, `Array<int>`, ...).
    pub span: Span,
}

impl TypeName {
    pub fn auto() -> Self {
        Self {
            name: "__auto".to_string(),
            generic_types: vec![],
            span: Span::none(),
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

// ── Attributes ───────────────────────────────────────────────────────────────

/// A single attribute: `[expr]`, where `expr` is exactly one attribute — a
/// bare symbol (`[Export]`) or a call (`[Align(8)]`). Platform selection is
/// `Target(OS(...) && Arch(...))`; boolean logic lives only inside it.
#[derive(Debug, Clone)]
pub struct Attribute {
    pub body: Expression,
    /// Span covering the whole `[...]` bracket group.
    pub span: Span,
}

// ── Expressions ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum Expression {
    Literal { value: Literal, span: Span },
    SymbolRef { id: String, span: Span },
    /// A generic type reference in expression position, e.g. the `Array<int>` in `Array<int>()`.
    TypeLiteral(TypeName),
    SizeOf(TypeName),
    /// `op operand`  (prefix)  or  `operand op`  (postfix)
    Unary {
        op: String,
        prefix: bool,
        operand: Box<Expression>,
        span: Span,
    },
    /// `expr as Type` — a static cast (spec docs/pepper.md: "equivalent of
    /// static_cast; compile error if the cast cannot succeed").
    Cast {
        expr: Box<Expression>,
        ty: TypeName,
        span: Span,
    },
    Binary {
        lhs: Box<Expression>,
        op: String,
        rhs: Box<Expression>,
        span: Span,
    },
    Ternary {
        condition: Box<Expression>,
        true_expr: Box<Expression>,
        false_expr: Box<Expression>,
        span: Span,
    },
    Index {
        lhs: Box<Expression>,
        rhs: Box<Expression>,
        span: Span,
    },
    MemberAccess {
        lhs: Box<Expression>,
        name: String,
        /// Span of the member name after the `.`.
        name_span: Span,
        span: Span,
    },
    FunctionCall {
        function: Box<Expression>,
        arguments: Vec<Expression>,
        span: Span,
    },
}

impl Expression {
    pub fn span(&self) -> Span {
        match self {
            Expression::Literal { span, .. }
            | Expression::SymbolRef { span, .. }
            | Expression::Unary { span, .. }
            | Expression::Binary { span, .. }
            | Expression::Ternary { span, .. }
            | Expression::Index { span, .. }
            | Expression::MemberAccess { span, .. }
            | Expression::Cast { span, .. }
            | Expression::FunctionCall { span, .. } => *span,
            Expression::TypeLiteral(t) | Expression::SizeOf(t) => t.span,
        }
    }
}

impl From<String> for Literal {
    fn from(s: String) -> Self {
        Literal::String(s)
    }
}
impl From<&str> for Literal {
    fn from(s: &str) -> Self {
        Literal::String(s.to_string())
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
    /// Attributes preceding the declaration (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
    pub name: String,
    /// Span of the declared name token.
    pub name_span: Span,
    pub type_name: TypeName,
    pub default_value: Option<Expression>,
    pub is_const: bool,
    /// Span from the declaration's first token to its last.
    pub span: Span,
}

#[derive(Debug, Clone)]
pub struct FunctionDecl {
    pub name: String,
    /// Span of the function name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    pub return_type: TypeName,
    pub parameters: Vec<VariableDecl>,
    pub external: bool,
    pub body: Option<Block>,
    /// `static` method modifier
    pub is_static: bool,
    /// Indexer method: `T [](params) { ... }`
    pub is_indexer: bool,
    pub span: Span,
    /// Attributes preceding the function (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
}

/// A generic type parameter, optionally with a default (`TError=Error` in
/// `Result<TValue, TError=Error>`).
#[derive(Debug, Clone)]
pub struct GenericParam {
    pub name: String,
    /// Default type substituted when a use omits this argument.
    pub default: Option<TypeName>,
}

#[derive(Debug, Clone)]
pub struct StructDecl {
    pub name: String,
    /// Span of the struct name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    pub fields: Vec<VariableDecl>,
    pub methods: Vec<FunctionDecl>,
    /// `new(...)` / `construct(...)` constructor
    pub constructor: Option<FunctionDecl>,
    /// `destruct { ... }` destructor body
    pub destructor: Option<Block>,
    pub span: Span,
    /// Attributes preceding the struct (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
}

#[derive(Debug, Clone)]
pub struct TraitDecl {
    /// Attributes preceding the `trait` keyword.
    pub attributes: Vec<Attribute>,
    pub name: String,
    /// Span of the trait name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    pub methods: Vec<FunctionDecl>,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub struct ExtendDecl {
    /// Attributes preceding the `extend` keyword.
    pub attributes: Vec<Attribute>,
    /// The struct being extended, possibly specialized: `Test<int>`
    pub target: TypeName,
    /// Traits implemented by the extension (after `with`)
    pub traits: Vec<TypeName>,
    pub methods: Vec<FunctionDecl>,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub enum Declaration {
    Variable(VariableDecl),
    Function(FunctionDecl),
    Struct(StructDecl),
    Trait(TraitDecl),
    Extend(ExtendDecl),
}

impl Declaration {
    pub fn name(&self) -> &str {
        match self {
            Declaration::Variable(d) => &d.name,
            Declaration::Function(f) => &f.name,
            Declaration::Struct(s) => &s.name,
            Declaration::Trait(t) => &t.name,
            Declaration::Extend(e) => e.target.name.as_str(),
        }
    }

    /// Span of the declared name token (for the extend target: the target type).
    pub fn name_span(&self) -> Span {
        match self {
            Declaration::Variable(d) => d.name_span,
            Declaration::Function(f) => f.name_span,
            Declaration::Struct(s) => s.name_span,
            Declaration::Trait(t) => t.name_span,
            Declaration::Extend(e) => e.target.span,
        }
    }

    pub fn span(&self) -> Span {
        match self {
            Declaration::Variable(d) => d.span,
            Declaration::Function(f) => f.span,
            Declaration::Struct(s) => s.span,
            Declaration::Trait(t) => t.span,
            Declaration::Extend(e) => e.span,
        }
    }
}

// ── Blocks & statements ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Block {
    pub statements: Vec<Statement>,
    /// Span covering the braces, widened to the first attribute when present.
    pub span: Span,
    /// Attributes preceding the block (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
}

#[derive(Debug, Clone)]
pub struct Branch {
    pub condition: Expression,
    pub if_block: Block,
    pub else_block: Option<Block>,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub struct While {
    pub condition: Expression,
    pub block: Block,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub struct ReturnStatement {
    pub expr: Expression,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopBreakKind { Break, Continue }

#[derive(Debug, Clone)]
pub struct LoopBreak {
    pub kind: LoopBreakKind,
    pub span: Span,
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

impl Statement {
    pub fn span(&self) -> Span {
        match self {
            Statement::Expression(e) => e.span(),
            Statement::Block(b) => b.span,
            Statement::Declaration(d) => d.span(),
            Statement::Branch(b) => b.span,
            Statement::While(w) => w.span,
            Statement::Return(r) => r.span,
            Statement::LoopBreak(l) => l.span,
        }
    }
}

// ── Module ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Import {
    pub name: String,
    /// Span of the imported name (identifier or string literal).
    pub name_span: Span,
    pub alias: Option<String>,
    pub is_local: bool,
    pub span: Span,
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
            Literal::String(s) => write!(f, "\"{}\"", s),
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
            Expression::Literal { value, .. } => write!(f, "{}", value),
            Expression::SymbolRef { id, .. } => write!(f, "{}", id),
            Expression::TypeLiteral(ty) => write!(f, "{}", ty),
            Expression::SizeOf(ty) => write!(f, "sizeof<{}>()", ty),
            Expression::Unary { op, prefix, operand, .. } => {
                if *prefix {
                    write!(f, "{}{}", op, operand)
                } else {
                    write!(f, "{}{}", operand, op)
                }
            }
            Expression::Binary { lhs, op, rhs, .. } => write!(f, "({} {} {})", lhs, op, rhs),
            Expression::Cast { expr, ty, .. } => write!(f, "({} as {})", expr, ty),
            Expression::Ternary { condition, true_expr, false_expr, .. } => {
                write!(f, "({} ? {} : {})", condition, true_expr, false_expr)
            }
            Expression::Index { lhs, rhs, .. } => write!(f, "{}[{}]", lhs, rhs),
            Expression::MemberAccess { lhs, name, .. } => write!(f, "{}.{}", lhs, name),
            Expression::FunctionCall { function, arguments, .. } => {
                write!(f, "{}({})", function, join(arguments, ", "))
            }
        }
    }
}

impl Display for Attribute {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        // `Expression`'s Display parenthesizes every binary; a top-level
        // binary is already bracketed, and a single-argument call's binary
        // argument is wrapped by the call parens — print both bare so
        // diagnostics quote what the user typed.
        match &self.body {
            Expression::Binary { lhs, op, rhs, .. } => write!(f, "[{} {} {}]", lhs, op, rhs),
            Expression::FunctionCall { function, arguments, .. }
                if arguments.len() == 1
                    && matches!(function.as_ref(), Expression::SymbolRef { .. }) =>
            {
                match &arguments[0] {
                    Expression::Binary { lhs, op, rhs, .. } => {
                        write!(f, "[{}({} {} {})]", function, lhs, op, rhs)
                    }
                    arg => write!(f, "[{}({})]", function, arg),
                }
            }
            body => write!(f, "[{}]", body),
        }
    }
}

/// Render a leading attribute list (`[A(1)] [B] `), including the trailing
/// separator, if any.
fn write_attributes(f: &mut Formatter<'_>, attributes: &[Attribute]) -> std::fmt::Result {
    for attr in attributes {
        write!(f, "{} ", attr)?;
    }
    Ok(())
}

/// Render a block's braces and statements without its leading attributes, so
/// callers can place the attributes themselves (e.g. `destruct { ... }`).
fn write_block_body(f: &mut Formatter<'_>, block: &Block) -> std::fmt::Result {
    write!(f, "{{")?;
    for stmt in &block.statements {
        write!(f, "\n    {}", stmt)?;
    }
    if !block.statements.is_empty() {
        write!(f, "\n")?;
    }
    write!(f, "}}")
}

impl Display for VariableDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        let spec = if self.is_const { "const " } else { "var " };
        write_attributes(f, &self.attributes)?;
        write!(f, "{}{}: {}", spec, self.name, self.type_name)?;
        if let Some(v) = &self.default_value {
            write!(f, " = {}", v)?;
        }
        Ok(())
    }
}

impl Display for GenericParam {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name)?;
        if let Some(d) = &self.default {
            write!(f, "={}", d)?;
        }
        Ok(())
    }
}

impl Display for FunctionDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write_attributes(f, &self.attributes)?;
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
        write_attributes(f, &self.attributes)?;
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
            write!(f, "\n    ")?;
            write_attributes(f, &constructor.attributes)?;
            write!(f, "new({}) {}", join(&constructor.parameters, ", "), body)?;
        }
        if let Some(destructor) = &self.destructor {
            write!(f, "\n    ")?;
            write_attributes(f, &destructor.attributes)?;
            write!(f, "destruct ")?;
            write_block_body(f, destructor)?;
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
        write_attributes(f, &self.attributes)?;
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
        write_attributes(f, &self.attributes)?;
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
        write_attributes(f, &self.attributes)?;
        write_block_body(f, self)
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
            Statement::LoopBreak(l) => write!(f, "{};", if l.kind == LoopBreakKind::Break { "break" } else { "continue" }),
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

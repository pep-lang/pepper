use std::fmt::{Display, Formatter};
use itertools::join;

// ── Source locations ──────────────────────────────────────────────────────────

/// A position in a source file, 0-based line and column (column is in
/// characters).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub struct Position {
    pub line: usize,
    pub col: usize,
}

/// A byte-offset range within one source file. `start` is inclusive, `end`
/// exclusive. Offsets are valid for the source the node was parsed from.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Default, serde::Serialize, serde::Deserialize)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

thread_local! {
    static POSITIONS_HIDDEN: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// Run `f` with spans and locations printing as `_` in `{:?}`, so a
/// declaration's debug text does not depend on where it sits in its file
/// (the build cache's interface hashes, see `pepper_sema::interface`).
pub fn without_positions<R>(f: impl FnOnce() -> R) -> R {
    let previous = POSITIONS_HIDDEN.with(|p| p.replace(true));
    let result = f();
    POSITIONS_HIDDEN.with(|p| p.set(previous));
    result
}

/// Whether [`without_positions`] is running.
pub fn positions_hidden() -> bool {
    POSITIONS_HIDDEN.with(|p| p.get())
}

impl std::fmt::Debug for Span {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if positions_hidden() {
            return f.write_str("_");
        }
        f.debug_struct("Span").field("start", &self.start).field("end", &self.end).finish()
    }
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

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Literal {
    String(String),
    Integer(i64),
    Float(f64),
    Bool(bool),
    /// A character literal (`'a'`): the character's byte, of type `byte`.
    Char(u8),
    Null,
}

// ── Type names ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct TypeName {
    pub name: String,
    pub generic_types: Vec<TypeName>,
    /// Span of the whole type as written (`int[]`, `Array<int>`, ...).
    pub span: Span,
    /// A tuple type's element labels, `line` and `column` in
    /// `(line: int, column: int)`: one per element, empty for an unlabeled
    /// element. Empty when no element is labeled.
    pub labels: Vec<String>,
}

/// Internal name of a type sema infers (`var x = 1;`).
pub const AUTO_TYPE: &str = "__auto";

impl TypeName {
    pub fn auto() -> Self {
        Self {
            name: AUTO_TYPE.to_string(),
            generic_types: vec![],
            span: Span::none(),
            labels: vec![],
        }
    }
}

/// Internal name of a function type: `(P1, P2) => R` is
/// `__function<R, P1, P2>` (return type first, then the parameters).
pub const FUNCTION_TYPE: &str = "__function";

/// Internal name of a tuple type: `(A, B)` is `__tuple<A, B>`.
pub const TUPLE_TYPE: &str = "__tuple";

/// Internal name of a thread-safe function type: `shared (P1, P2) => R` is
/// `__shared_function<R, P1, P2>`.
pub const SHARED_FUNCTION_TYPE: &str = "__shared_function";

/// Internal name of a C function pointer type: `extern (P1, P2) => R` is
/// `__extern_function<R, P1, P2>`.
pub const EXTERN_FUNCTION_TYPE: &str = "__extern_function";

impl Display for TypeName {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if (self.name == FUNCTION_TYPE || self.name == SHARED_FUNCTION_TYPE || self.name == EXTERN_FUNCTION_TYPE)
            && !self.generic_types.is_empty()
        {
            let shared = match self.name.as_str() {
                SHARED_FUNCTION_TYPE => "shared ",
                EXTERN_FUNCTION_TYPE => "extern ",
                _ => "",
            };
            return write!(f, "{}({}) => {}", shared, join(&self.generic_types[1..], ", "), self.generic_types[0]);
        }
        if self.name == TUPLE_TYPE && !self.generic_types.is_empty() {
            let elements: Vec<String> = self
                .generic_types
                .iter()
                .enumerate()
                .map(|(i, t)| match self.labels.get(i).filter(|l| !l.is_empty()) {
                    Some(label) => format!("{}: {}", label, t),
                    None => t.to_string(),
                })
                .collect();
            return write!(f, "({})", elements.join(", "));
        }
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
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Attribute {
    pub body: Expression,
    /// Span covering the whole `[...]` bracket group.
    pub span: Span,
}

/// One argument of an attribute: `"m"` in `[Link("m")]` (no name) or
/// `name = "sym"` in `[Link(name = "sym")]`.
#[derive(Debug, Clone, Copy)]
pub struct AttributeArgument<'a> {
    /// The argument's name and its span, for a named argument.
    pub name: Option<(&'a str, Span)>,
    pub value: &'a Expression,
}

impl Attribute {
    /// The attribute's name: `Link` in `[Link("m")]` and in `[Link]`.
    pub fn name(&self) -> Option<&str> {
        match &self.body {
            Expression::SymbolRef { id, .. } => Some(id),
            Expression::FunctionCall { function, .. } => match function.as_ref() {
                Expression::SymbolRef { id, .. } => Some(id),
                _ => None,
            },
            _ => None,
        }
    }

    /// The attribute's arguments in the order written; none for a bare
    /// `[Name]`.
    pub fn arguments(&self) -> Vec<AttributeArgument<'_>> {
        let Expression::FunctionCall { arguments, .. } = &self.body else { return vec![] };
        arguments
            .iter()
            .map(|argument| match argument {
                Expression::NamedArgument { name, name_span, value, .. } => {
                    AttributeArgument { name: Some((name.as_str(), *name_span)), value }
                }
                value => AttributeArgument { name: None, value },
            })
            .collect()
    }
}

/// How likely the block that `attributes` mark is to run: `Some(true)` for
/// `[Likely]`, `Some(false)` for `[Unlikely]`, `None` for neither. The
/// builder checks that a branch carries at most one of them.
pub fn branch_hint(attributes: &[Attribute]) -> Option<bool> {
    attributes.iter().find_map(|a| match (a.name(), &a.body) {
        (Some("Likely"), Expression::SymbolRef { .. }) => Some(true),
        (Some("Unlikely"), Expression::SymbolRef { .. }) => Some(false),
        _ => None,
    })
}

// ── Expressions ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum Expression {
    Literal { value: Literal, span: Span },
    SymbolRef { id: String, span: Span },
    /// A generic type reference in expression position, e.g. the `Array<int>` in `Array<int>()`.
    TypeLiteral(TypeName),
    SizeOf(TypeName),
    /// `op operand`  (prefix)  or  `operand op`  (postfix: `++`, `--`, and
    /// `?`, which propagates a `Result`'s error or an empty `Optional`)
    Unary {
        op: String,
        prefix: bool,
        operand: Box<Expression>,
        span: Span,
    },
    /// `expr as Type` — a static cast (docs/src/language/types-and-variables.md: "equivalent of
    /// static_cast; compile error if the cast cannot succeed").
    Cast {
        expr: Box<Expression>,
        ty: TypeName,
        span: Span,
        /// The `as` keyword, where a cast error points.
        keyword_span: Span,
        /// `expr as? Type`: a conversion of a trait value that may fail,
        /// giving `Type?`.
        #[serde(default)]
        optional: bool,
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
    /// A named argument `name = value`. Appears only directly in a
    /// [`Expression::FunctionCall`]'s `arguments` (calls and attributes).
    NamedArgument {
        name: String,
        /// Span of the name.
        name_span: Span,
        value: Box<Expression>,
        span: Span,
    },
    /// A closure literal: `(x: int, y) => x + y` or `(x): int => { ... }`.
    Closure(Box<ClosureLiteral>),
    /// A tuple value `(a, b, ...)`: two or more elements. On the left of `=`
    /// it lists the places a destructuring assignment stores into.
    /// `labels` is empty, or names every element (`(line: 3, column: 7)`),
    /// each with the span of its label.
    Tuple { elements: Vec<Expression>, labels: Vec<(String, Span)>, span: Span },
    /// An array literal `[a, b, ...]`: an `Array<T>` of the elements, where
    /// `T` is the first element's type.
    ArrayLiteral { elements: Vec<Expression>, span: Span },
    /// A map literal `[k: v, ...]` (`[:]` when empty): a `HashMap<K, V>` of
    /// the entries, where `K` and `V` are the first entry's types.
    MapLiteral { entries: Vec<(Expression, Expression)>, span: Span },
    /// `match (value) { pattern, ... => value, ... else => value }`: a
    /// `match` that produces a value.
    Match(Box<MatchExpression>),
    /// `value is Pattern`: whether `value` matches the pattern.
    Is {
        value: Box<Expression>,
        pattern: Box<Pattern>,
        /// Span of the `is` keyword.
        keyword_span: Span,
        span: Span,
    },
}

/// A `match` in expression position: each arm is `patterns => value`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MatchExpression {
    pub value: Expression,
    pub arms: Vec<MatchValueArm>,
    /// The `else` arm: the span of the `else` keyword and its value.
    pub else_arm: Option<(Span, Expression)>,
    /// Span of the `match` keyword.
    pub keyword_span: Span,
    pub span: Span,
}

/// One arm of a `match` expression: its patterns and the value they select.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MatchValueArm {
    pub patterns: Vec<Pattern>,
    /// The arm's guard (`if r > 10`): the arm is taken only when a pattern
    /// matches and the guard holds.
    pub guard: Option<Expression>,
    pub value: Expression,
    pub span: Span,
}

/// A closure literal. Parameters and the return type written without a type
/// are `auto`; sema infers them from where the closure is used.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClosureLiteral {
    pub parameters: Vec<VariableDecl>,
    /// The type after the parameter list (`(x): int => ...`), else `auto`.
    pub return_type: TypeName,
    /// The body. An expression body (`=> x * 2`) is a block holding
    /// `return x * 2;`.
    pub body: Block,
    /// The body was written as an expression rather than a block.
    pub expression_body: bool,
    pub span: Span,
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
            | Expression::FunctionCall { span, .. }
            | Expression::NamedArgument { span, .. }
            | Expression::Tuple { span, .. }
            | Expression::ArrayLiteral { span, .. }
            | Expression::MapLiteral { span, .. }
            | Expression::Is { span, .. } => *span,
            Expression::TypeLiteral(t) | Expression::SizeOf(t) => t.span,
            Expression::Closure(c) => c.span,
            Expression::Match(m) => m.span,
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

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
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
    /// `export` modifier (module-scope variables only): visible outside the
    /// declaring file.
    pub is_exported: bool,
}

/// A property: a member read and written like a field whose `get` and `set`
/// accessors may run code (`var name: T { get; set { ... } } = init;`).
/// See `docs/src/language/properties.md`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PropertyDecl {
    /// Attributes preceding the declaration.
    pub attributes: Vec<Attribute>,
    pub name: String,
    /// Span of the declared name token.
    pub name_span: Span,
    pub type_name: TypeName,
    /// The initializer after the accessor block: it initializes the
    /// property's implied storage.
    pub default_value: Option<Expression>,
    /// The `get` accessor; `None` only for a set-only property, which is an
    /// error the builder reports.
    pub get: Option<Accessor>,
    /// The `set` accessor; `None` for a read-only property.
    pub set: Option<Accessor>,
    /// Span from the declaration's first token to its last.
    pub span: Span,
}

/// One accessor of a [`PropertyDecl`]: `get;` / `set;` (the default body) or
/// `get { ... }` / `set { ... }`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Accessor {
    /// Span of the `get` or `set` keyword.
    pub span: Span,
    /// The accessor as the method it compiles to: `__get_P(): T` or
    /// `__set_P(value: T)`, whose `body` is `None` for the default body.
    /// Tools that look at methods (the language server) see accessor bodies
    /// through it.
    pub function: FunctionDecl,
}

impl Accessor {
    /// The written body; `None` for `get;` / `set;`.
    pub fn body(&self) -> Option<&Block> {
        self.function.body.as_ref()
    }
}

impl PropertyDecl {
    /// The property's accessors as methods: `get`, then `set`.
    pub fn accessors(&self) -> impl Iterator<Item = &FunctionDecl> {
        self.get.iter().chain(&self.set).map(|a| &a.function)
    }
}

/// The name of the method a property's `get` accessor compiles to.
pub fn property_getter_name(name: &str) -> String {
    format!("__get_{}", name)
}

/// The name of the method a property's `set` accessor compiles to.
pub fn property_setter_name(name: &str) -> String {
    format!("__set_{}", name)
}

/// Inside a property accessor, the property's implied storage.
pub const PROPERTY_FIELD: &str = "field";
/// Inside a `set` accessor, the new value.
pub const PROPERTY_VALUE: &str = "value";

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
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
    /// Extern whose parameter list ends in C's `...` (`printf`, `open`).
    pub is_variadic: bool,
    pub span: Span,
    /// Attributes preceding the function (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
    /// `export` modifier: visible outside the declaring file. Top-level
    /// functions (and externs) are private to their file without it.
    pub is_exported: bool,
}

/// A generic type parameter, optionally with constraints and a default
/// (`TError=Error` in `Result<TValue, TError=Error>`, `T: Shape & Named =
/// Square`).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GenericParam {
    pub name: String,
    /// Span of the name token.
    pub name_span: Span,
    /// The traits an argument must conform to (`Shape`, `Named` in `T: Shape
    /// & Named`), in the order written.
    pub bounds: Vec<TypeName>,
    /// Default type substituted when a use omits this argument.
    pub default: Option<TypeName>,
    /// Set by module linking: the name is a type argument, not a parameter
    /// (`Point` in `describe<Point>`), so the function is a concrete
    /// override of the generic of its name.
    pub is_argument: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StructDecl {
    pub name: String,
    /// Span of the struct name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    pub fields: Vec<VariableDecl>,
    /// Properties (`var name: T { get; set; }`), in declaration order.
    #[serde(default)]
    pub properties: Vec<PropertyDecl>,
    pub methods: Vec<FunctionDecl>,
    /// `construct(...)` constructors, in declaration order; several
    /// overload one another
    pub constructors: Vec<FunctionDecl>,
    /// `destruct { ... }` destructor body
    pub destructor: Option<Block>,
    /// The `destruct` keyword, when there is a destructor.
    #[serde(default)]
    pub destruct_span: Option<Span>,
    pub span: Span,
    /// Attributes preceding the struct (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
    /// `export` modifier: visible outside the declaring file.
    pub is_exported: bool,
    /// `Some` when this was declared with `enum` rather than `struct`. An
    /// enum shares the struct's name, generics, methods and visibility, so
    /// linking, visibility and the language server treat it as one; the
    /// builder lowers it differently (see `docs/src/language/enums.md`).
    pub enumeration: Option<EnumBody>,
}

/// What an `enum` declaration adds to a [`StructDecl`]: its cases.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EnumBody {
    /// The integer type after `:` (`enum Kind: u8`); `None` for the default.
    pub representation: Option<TypeName>,
    /// The cases, in declaration order.
    pub cases: Vec<EnumCase>,
}

/// One case of an `enum`: `Name`, `Name = value`, or `Name(field: Type, ...)`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EnumCase {
    pub name: String,
    pub name_span: Span,
    /// The explicit value after `=`.
    pub value: Option<Expression>,
    /// The values the case carries; `None` when written without parentheses.
    pub payload: Option<Vec<VariableDecl>>,
    /// Attributes preceding the case (`[Deprecated(...)]`).
    pub attributes: Vec<Attribute>,
    /// The whole case, from its first attribute to its last token.
    pub span: Span,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TraitDecl {
    /// Attributes preceding the `trait` keyword.
    pub attributes: Vec<Attribute>,
    pub name: String,
    /// Span of the trait name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    pub methods: Vec<FunctionDecl>,
    /// Properties the trait requires (`var area: double { get; }`).
    #[serde(default)]
    pub properties: Vec<PropertyDecl>,
    pub span: Span,
    /// `export` modifier: visible outside the declaring file.
    pub is_exported: bool,
}

/// A type alias: `type Name<P1, P2=Default> = TargetType;`. The target may be
/// generic; the alias's own parameters are substituted into it at each use.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TypeAliasDecl {
    /// Attributes preceding the `type` keyword.
    pub attributes: Vec<Attribute>,
    pub name: String,
    /// Span of the alias name token.
    pub name_span: Span,
    pub generic_params: Vec<GenericParam>,
    /// The type being aliased (may reference the alias's parameters).
    pub target: TypeName,
    pub span: Span,
    /// `export` modifier: visible outside the declaring file.
    pub is_exported: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ExtendDecl {
    /// Attributes preceding the `extend` keyword.
    pub attributes: Vec<Attribute>,
    /// The struct being extended, possibly specialized: `Test<int>`
    pub target: TypeName,
    /// Constraints restated on the target's parameters (`Shape` in `extend
    /// Box<T: Shape>`), per argument; empty when none is. They document the
    /// struct's own constraints, which apply without them.
    pub target_bounds: Vec<Vec<TypeName>>,
    /// Traits implemented by the extension (after `with`)
    pub traits: Vec<TypeName>,
    pub methods: Vec<FunctionDecl>,
    /// Computed properties the extension adds.
    #[serde(default)]
    pub properties: Vec<PropertyDecl>,
    pub span: Span,
    /// `export` modifier: the extension's methods are usable outside the
    /// declaring file.
    pub is_exported: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum Declaration {
    Variable(VariableDecl),
    Function(FunctionDecl),
    Struct(StructDecl),
    Trait(TraitDecl),
    Extend(ExtendDecl),
    TypeAlias(TypeAliasDecl),
    /// A module-scope `static { ... }` block: compile-time work whose
    /// top-level `const` declarations become module-scope constants.
    Static(StaticBlock),
}

impl Declaration {
    /// The attributes written before the declaration.
    pub fn attributes(&self) -> &[Attribute] {
        match self {
            Declaration::Variable(v) => &v.attributes,
            Declaration::Function(f) => &f.attributes,
            Declaration::Struct(s) => &s.attributes,
            Declaration::Trait(t) => &t.attributes,
            Declaration::Extend(e) => &e.attributes,
            Declaration::TypeAlias(t) => &t.attributes,
            Declaration::Static(s) => &s.attributes,
        }
    }

    /// Marked `export`: usable from files that import this one.
    pub fn is_exported(&self) -> bool {
        match self {
            Declaration::Variable(v) => v.is_exported,
            Declaration::Function(f) => f.is_exported,
            Declaration::Struct(s) => s.is_exported,
            Declaration::Trait(t) => t.is_exported,
            Declaration::Extend(e) => e.is_exported,
            Declaration::TypeAlias(t) => t.is_exported,
            Declaration::Static(s) => s.is_exported,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Declaration::Variable(d) => &d.name,
            Declaration::Function(f) => &f.name,
            Declaration::Struct(s) => &s.name,
            Declaration::Trait(t) => &t.name,
            Declaration::Extend(e) => e.target.name.as_str(),
            Declaration::TypeAlias(t) => &t.name,
            Declaration::Static(_) => "",
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
            Declaration::TypeAlias(t) => t.name_span,
            Declaration::Static(s) => s.keyword_span,
        }
    }

    pub fn span(&self) -> Span {
        match self {
            Declaration::Variable(d) => d.span,
            Declaration::Function(f) => f.span,
            Declaration::Struct(s) => s.span,
            Declaration::Trait(t) => t.span,
            Declaration::Extend(e) => e.span,
            Declaration::TypeAlias(t) => t.span,
            Declaration::Static(s) => s.span,
        }
    }
}

// ── Blocks & statements ───────────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Block {
    pub statements: Vec<Statement>,
    /// Span covering the braces, widened to the first attribute when present.
    pub span: Span,
    /// Attributes preceding the block (`[Name(args)]`).
    pub attributes: Vec<Attribute>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Branch {
    pub condition: Expression,
    pub if_block: Block,
    pub else_block: Option<Block>,
    pub span: Span,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct While {
    pub condition: Expression,
    pub block: Block,
    pub span: Span,
}

/// `for (var x in expr) { ... }`: iterate `expr` via the iterator protocol
/// (`iterate()`, or `next()` + `current()`). The binding is a `var` or typed
/// declaration with no default value.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct For {
    /// The loop variable. With a `pattern` it has an empty name.
    pub binding: VariableDecl,
    /// `for (var (k, v) in pairs)`: the tuple pattern each element is
    /// destructured into. Empty for a plain binding.
    pub pattern: Vec<DestructureBinding>,
    pub iterable: Expression,
    pub block: Block,
    pub span: Span,
}

/// `with (var x = scope) { ... } else { ... }`: enter a `Scoped<T>` value.
/// `x` is bound to `scope.enter()`; a null struct result skips the body and
/// runs `else_block` instead. `binding` carries no default value: the scope
/// expression is `scope`. Without a binding the result is held unnamed.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct With {
    pub binding: Option<VariableDecl>,
    pub scope: Expression,
    pub block: Block,
    pub else_block: Option<Block>,
    pub span: Span,
}

/// `var (a, b) = e;` or `const (a, _: int) = e;`: declares one local per
/// element of the tuple `e`. A binding named `_` skips its element.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Destructure {
    /// One per element, in order: the name (`_` to skip), its span, and its
    /// type (`auto` when not written).
    pub bindings: Vec<DestructureBinding>,
    pub value: Expression,
    pub is_const: bool,
    pub span: Span,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DestructureBinding {
    pub name: String,
    pub name_span: Span,
    pub type_name: TypeName,
    /// A nested pattern, `(b, c)` in `var (a, (b, c)) = ...`: its bindings,
    /// with an empty `name`. Empty for a plain binding.
    pub nested: Vec<DestructureBinding>,
}

impl DestructureBinding {
    /// Every named binding in this one and its nested patterns, in order
    /// (`_` included).
    pub fn leaves(&self) -> Vec<&DestructureBinding> {
        if self.nested.is_empty() {
            vec![self]
        } else {
            self.nested.iter().flat_map(|b| b.leaves()).collect()
        }
    }
}

impl Display for DestructureBinding {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if !self.nested.is_empty() {
            let inner: Vec<String> = self.nested.iter().map(|b| b.to_string()).collect();
            return write!(f, "({})", inner.join(", "));
        }
        if self.type_name.name == AUTO_TYPE {
            write!(f, "{}", self.name)
        } else {
            write!(f, "{}: {}", self.name, self.type_name)
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ReturnStatement {
    /// None for a bare `return;`.
    pub expr: Option<Expression>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum LoopBreakKind { Break, Continue }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LoopBreak {
    pub kind: LoopBreakKind,
    pub span: Span,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum Statement {
    Expression(Expression),
    Block(Block),
    Declaration(Declaration),
    Branch(Branch),
    While(While),
    For(For),
    With(With),
    Return(ReturnStatement),
    LoopBreak(LoopBreak),
    Destructure(Destructure),
    Match(Match),
    Static(StaticBlock),
}

/// `static (captures) { ... }`: work done at compile time, such as
/// reflection (`docs/src/language/reflection.md`). A statement in the block
/// that uses a captured name, or a runtime local the block declares, is
/// emitted into the function; everything else runs in the compiler.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StaticBlock {
    /// The runtime values the block may emit code against, each with the
    /// span of its name.
    pub captures: Vec<(String, Span)>,
    pub block: Block,
    /// Span of the `static` keyword.
    pub keyword_span: Span,
    pub span: Span,
    /// At module scope: the attributes written before the block.
    pub attributes: Vec<Attribute>,
    /// At module scope: written `export static`, so the constants it
    /// declares are exported.
    pub is_exported: bool,
}

impl Display for StaticBlock {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if self.captures.is_empty() {
            return write!(f, "static {}", self.block);
        }
        let names: Vec<&str> = self.captures.iter().map(|(name, _)| name.as_str()).collect();
        write!(f, "static ({}) {}", names.join(", "), self.block)
    }
}

/// `match (value) { pattern, ... => { ... } ... else => { ... } }`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Match {
    pub value: Expression,
    pub arms: Vec<MatchArm>,
    /// The `else` arm: the span of the `else` keyword and its block.
    pub else_arm: Option<(Span, Block)>,
    /// Span of the `match` keyword.
    pub keyword_span: Span,
    pub span: Span,
}

/// One arm of a `match`: its patterns and the block they select.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MatchArm {
    pub patterns: Vec<Pattern>,
    /// The arm's guard (`if r > 10`): the arm is taken only when a pattern
    /// matches and the guard holds.
    pub guard: Option<Expression>,
    pub body: Block,
    pub span: Span,
}

/// A case pattern: `Case`, `Enum.Case`, or `Case(binding, _, ...)`; a
/// literal pattern (`1`, `'a'`, `"import"`, `true`), whose `case` is empty;
/// or a tuple pattern (`(Circle, _)`, `(0, y)`), whose `case` is empty.
///
/// Inside a tuple pattern, a bare name (`y`) is a case when the element is an
/// enum with a case of that name, and otherwise binds the element; `_`
/// matches anything.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Pattern {
    /// The literal of a literal pattern; `None` for a case pattern.
    pub literal: Option<Expression>,
    /// The element patterns of a tuple pattern; `None` otherwise.
    pub elements: Option<Vec<Pattern>>,
    /// The enum named before the case (`Color` in `Color.Red`).
    pub qualifier: Option<TypeName>,
    pub case: String,
    pub case_span: Span,
    /// The patterns of the case's values, in order; `None` without
    /// parentheses. Like a tuple pattern's elements, each is `_` (any
    /// value), a name that binds the value (unless it is a case of the
    /// value's enum or a constant), or a pattern the value must match
    /// (`Value(Text(t))`, `Text("")`, `Circle(0..10)`).
    pub bindings: Option<Vec<Pattern>>,
    /// A range pattern (`1..9`, `'a'..>'z'`): `literal` is its start and
    /// this its end.
    #[serde(default)]
    pub range: Option<PatternRange>,
    /// Set by module linking when this name (`MAX_SIZE`, or `limits.MAX`
    /// qualified by a module) names a module-scope constant: the constant's
    /// linked name. The pattern then compares with it, like a literal.
    #[serde(default)]
    pub constant: Option<String>,
    /// A case pattern's name read as a type (`Circle`, `shapes.Circle`,
    /// `Box<int>`), with any type arguments written after it: what the
    /// pattern tests for when the value matched is a trait value. Set by
    /// the parser for every case pattern and resolved by module linking
    /// like any type; ignored when the value is an enum.
    #[serde(default)]
    pub ty: Option<TypeName>,
    pub span: Span,
}

/// The end of a range pattern: `..end` or, `inclusive`, `..>end`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PatternRange {
    pub end: Expression,
    pub inclusive: bool,
}

impl Pattern {
    /// Whether this is a bare name inside a tuple pattern (`y` in `(0, y)`),
    /// which binds the element unless the element is an enum with a case of
    /// that name.
    pub fn is_bare_name(&self) -> bool {
        self.literal.is_none() && self.elements.is_none() && self.qualifier.is_none() && self.bindings.is_none() && self.constant.is_none()
    }

    /// This pattern and every pattern nested in it, outermost first.
    pub fn all(&self) -> Vec<&Pattern> {
        let mut out = vec![self];
        for e in self.elements.iter().flatten().chain(self.bindings.iter().flatten()) {
            out.extend(e.all());
        }
        out
    }

    /// The names the pattern may bind, `_` left out: each bare name inside a
    /// tuple pattern or a case's parentheses.
    pub fn bound_names(&self) -> Vec<(String, Span)> {
        let mut out = vec![];
        self.collect_names(false, &mut out);
        out
    }

    fn collect_names(&self, in_tuple: bool, out: &mut Vec<(String, Span)>) {
        if let Some(elements) = &self.elements {
            for e in elements {
                e.collect_names(true, out);
            }
            return;
        }
        if in_tuple && self.is_bare_name() && self.case != "_" {
            out.push((self.case.clone(), self.case_span));
        }
        for b in self.bindings.iter().flatten() {
            b.collect_names(true, out);
        }
    }
}

impl Statement {
    pub fn span(&self) -> Span {
        match self {
            Statement::Expression(e) => e.span(),
            Statement::Block(b) => b.span,
            Statement::Declaration(d) => d.span(),
            Statement::Branch(b) => b.span,
            Statement::While(w) => w.span,
            Statement::For(f) => f.span,
            Statement::With(w) => w.span,
            Statement::Return(r) => r.span,
            Statement::LoopBreak(l) => l.span,
            Statement::Destructure(d) => d.span,
            Statement::Match(m) => m.span,
            Statement::Static(s) => s.span,
        }
    }
}

// ── Module ────────────────────────────────────────────────────────────────────

/// One `symbol` or `symbol as name` entry of `import [...] from source`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ImportedSymbol {
    pub name: String,
    pub name_span: Span,
    /// The local name; `None` binds the symbol under its own name.
    pub alias: Option<String>,
    pub span: Span,
}

impl ImportedSymbol {
    /// The name this symbol is bound to in the importing file.
    pub fn local_name(&self) -> &str {
        self.alias.as_deref().unwrap_or(&self.name)
    }
}

/// An import. The source is a module (`import math`, a folder with a
/// `module.pep` on the search path) or a file of the same module
/// (`import "helpers"`, `helpers.pep` next to the importing file).
///
/// - `import math` / `import math as m`: the module's exports, qualified
///   (`math.sqrt`, `m.sqrt`).
/// - `import "helpers"`: the file's exports, unqualified. With `as h`, qualified.
/// - `import [sqrt, pow as power] from math`: the named exports, unqualified.
///
/// A re-export of a source (`export * from "shapes"`, `export [area as
/// surface_area] from geometry`) is an `Import` with `reexport` set: it is
/// resolved like an import, but binds no name in its own file; it publishes
/// the source's exports (all of them for `*`, else the listed ones) to the
/// file's importers.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Import {
    /// The module name, or the file path as written without `.pep`.
    pub name: String,
    /// Span of the imported name (identifier or string literal).
    pub name_span: Span,
    pub alias: Option<String>,
    /// Local (`"name"`): a file of this module, or a module folder, relative
    /// to the importing file; rather than a dependency (`name`) found on the
    /// search paths.
    pub is_local: bool,
    /// `import [...] from source`: the symbols named in the list.
    pub symbols: Option<Vec<ImportedSymbol>>,
    /// `export * from source` (`symbols` is `None`) or `export [...] from
    /// source`: a re-export that binds nothing here.
    pub reexport: bool,
    /// Attributes before `import`: `[Target(OS(Linux))] import linux;`.
    pub attributes: Vec<Attribute>,
    /// The whole import, from its first attribute when it has any.
    pub span: Span,
}

impl Import {
    /// The name without a trailing `.pep`: `import "util.pep"` and
    /// `import "util"` name the same thing. Resolution and diagnostics both
    /// use it.
    pub fn stem(&self) -> &str {
        self.name.strip_suffix(".pep").unwrap_or(&self.name)
    }

    /// How diagnostics name the import's source: `"util.pep"` (whether
    /// written `"util"` or `"util.pep"`), `module 'm'`.
    pub fn describe(&self) -> String {
        if self.is_local {
            format!("\"{}.pep\"", self.stem())
        } else {
            format!("module '{}'", self.name)
        }
    }

    /// Like [`Import::describe`], naming a local import that resolved to a
    /// module folder (`folder`) as the folder: `the module folder "vec"`.
    pub fn describe_as(&self, folder: bool) -> String {
        if self.is_local && folder {
            format!("the module folder \"{}\"", self.stem())
        } else {
            self.describe()
        }
    }

    /// The qualifier this import binds (`m` in `m.sqrt`), if any: the alias,
    /// or a bare module import's own name.
    pub fn qualifier(&self) -> Option<&str> {
        if self.symbols.is_some() || self.reexport {
            return None;
        }
        match &self.alias {
            Some(a) => Some(a),
            None if !self.is_local => Some(&self.name),
            None => None,
        }
    }
}

/// `export symbol as name;` — re-exports `symbol` (declared in this file, or
/// imported: `sym`, `m.sym`) to importers under `name`, or under its own
/// (last) name without `as`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ExportAlias {
    /// The exported symbol as written, possibly qualified (`m.sym`).
    pub symbol: String,
    pub symbol_span: Span,
    pub alias: Option<String>,
    /// Attributes before `export`: `[Target(OS(Linux))] export open as o;`.
    pub attributes: Vec<Attribute>,
    /// The whole re-export, from its first attribute when it has any.
    pub span: Span,
}

impl ExportAlias {
    /// The name importers see.
    pub fn exported_name(&self) -> &str {
        self.alias.as_deref().unwrap_or_else(|| self.symbol.rsplit('.').next().unwrap_or(&self.symbol))
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Module {
    pub imports: Vec<Import>,
    pub exports: Vec<ExportAlias>,
    pub declarations: Vec<Declaration>,
    /// Warnings the parser found, such as deprecated syntax. Their locations
    /// carry the default `FileId`; the loader remaps them to the file's.
    /// Not serialized: the build cache stores only trees without warnings.
    #[serde(skip)]
    pub warnings: Vec<crate::diagnostic::Diagnostic>,
}

// ── Display ───────────────────────────────────────────────────────────────────

impl Display for Literal {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Literal::String(s) => {
                write!(f, "\"")?;
                for c in s.chars() {
                    match c {
                        '\n' => write!(f, "\\n")?,
                        '\t' => write!(f, "\\t")?,
                        '\r' => write!(f, "\\r")?,
                        '\0' => write!(f, "\\0")?,
                        '\\' => write!(f, "\\\\")?,
                        '"' => write!(f, "\\\"")?,
                        c => write!(f, "{}", c)?,
                    }
                }
                write!(f, "\"")
            }
            Literal::Integer(v) => write!(f, "{}", v),
            Literal::Float(v) => write!(f, "{}", v),
            Literal::Bool(v) => write!(f, "{}", v),
            Literal::Char(b) => match b {
                b'\n' => write!(f, "'\\n'"),
                b'\t' => write!(f, "'\\t'"),
                b'\r' => write!(f, "'\\r'"),
                0 => write!(f, "'\\0'"),
                b'\\' => write!(f, "'\\\\'"),
                b'\'' => write!(f, "'\\''"),
                0x20..=0x7e => write!(f, "'{}'", *b as char),
                _ => write!(f, "'\\x{:02X}'", b),
            },
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
            Expression::Cast { expr, ty, optional, .. } => write!(f, "({} as{} {})", expr, if *optional { "?" } else { "" }, ty),
            Expression::Ternary { condition, true_expr, false_expr, .. } => {
                write!(f, "({} ? {} : {})", condition, true_expr, false_expr)
            }
            Expression::Index { lhs, rhs, .. } => write!(f, "{}[{}]", lhs, rhs),
            Expression::MemberAccess { lhs, name, .. } => write!(f, "{}.{}", lhs, name),
            Expression::FunctionCall { function, arguments, .. } => {
                write!(f, "{}({})", function, join(arguments, ", "))
            }
            Expression::Closure(c) => {
                let params: Vec<String> = c
                    .parameters
                    .iter()
                    .map(|p| if p.type_name.name == AUTO_TYPE { p.name.clone() } else { format!("{}: {}", p.name, p.type_name) })
                    .collect();
                write!(f, "({})", params.join(", "))?;
                if c.return_type.name != AUTO_TYPE {
                    write!(f, ": {}", c.return_type)?;
                }
                match c.body.statements.as_slice() {
                    [Statement::Return(ReturnStatement { expr: Some(e), .. })] if c.expression_body => write!(f, " => {}", e),
                    _ => {
                        write!(f, " => ")?;
                        write_block_body(f, &c.body)
                    }
                }
            }
            Expression::Tuple { elements, labels, .. } if !labels.is_empty() => {
                let parts: Vec<String> = elements.iter().zip(labels).map(|(e, (l, _))| format!("{}: {}", l, e)).collect();
                write!(f, "({})", parts.join(", "))
            }
            Expression::Tuple { elements, .. } => write!(f, "({})", join(elements, ", ")),
            Expression::ArrayLiteral { elements, .. } => write!(f, "[{}]", join(elements, ", ")),
            Expression::MapLiteral { entries, .. } if entries.is_empty() => write!(f, "[:]"),
            Expression::MapLiteral { entries, .. } => {
                let entries: Vec<String> = entries.iter().map(|(k, v)| format!("{}: {}", k, v)).collect();
                write!(f, "[{}]", entries.join(", "))
            }
            Expression::Match(m) => {
                write!(f, "match ({}) {{", m.value)?;
                for arm in &m.arms {
                    write!(f, " {}{} => {},", join(&arm.patterns, ", "), guard_text(&arm.guard), arm.value)?;
                }
                if let Some((_, value)) = &m.else_arm {
                    write!(f, " else => {},", value)?;
                }
                write!(f, " }}")
            }
            Expression::Is { value, pattern, .. } => write!(f, "({} is {})", value, pattern),
            Expression::NamedArgument { name, value, .. } => write!(f, "{} = {}", name, value),
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
        if self.is_exported {
            write!(f, "export ")?;
        }
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
        if !self.bounds.is_empty() {
            write!(f, ": {}", join(&self.bounds, " & "))?;
        }
        if let Some(d) = &self.default {
            write!(f, "={}", d)?;
        }
        Ok(())
    }
}

impl Display for FunctionDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write_attributes(f, &self.attributes)?;
        if self.is_exported {
            write!(f, "export ")?;
        }
        if self.external {
            write!(f, "extern {} {}({}", self.return_type, self.name, join(&self.parameters, ", "))?;
            if self.is_variadic {
                write!(f, ", ...")?;
            }
            write!(f, ")")?;
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
        if !self.is_indexer && self.return_type.name != AUTO_TYPE {
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
        if self.is_exported {
            write!(f, "export ")?;
        }
        let keyword = if self.enumeration.is_some() { "enum" } else { "struct" };
        write!(f, "{} {}", keyword, self.name)?;
        if !self.generic_params.is_empty() {
            write!(f, "<{}>", join(&self.generic_params, ", "))?;
        }
        if let Some(repr) = self.enumeration.as_ref().and_then(|e| e.representation.as_ref()) {
            write!(f, ": {}", repr)?;
        }
        write!(f, " {{")?;
        for case in self.enumeration.iter().flat_map(|e| &e.cases) {
            write!(f, "\n    ")?;
            write_attributes(f, &case.attributes)?;
            write!(f, "{}", case.name)?;
            if let Some(payload) = &case.payload {
                write!(f, "({})", join(payload, ", "))?;
            }
            if let Some(value) = &case.value {
                write!(f, " = {}", value)?;
            }
            write!(f, ",")?;
        }
        for field in &self.fields {
            write!(f, "\n    {}", field)?;
        }
        for property in &self.properties {
            write!(f, "\n    {}", property)?;
        }
        for constructor in &self.constructors {
            let body = constructor.body.as_ref().expect("constructor has a body");
            write!(f, "\n    ")?;
            write_attributes(f, &constructor.attributes)?;
            write!(f, "construct({}) {}", join(&constructor.parameters, ", "), body)?;
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
        let has_members = self.enumeration.as_ref().is_some_and(|e| !e.cases.is_empty())
            || !self.fields.is_empty()
            || !self.properties.is_empty()
            || !self.constructors.is_empty()
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
        if self.is_exported {
            write!(f, "export ")?;
        }
        write!(f, "trait {}", self.name)?;
        if !self.generic_params.is_empty() {
            write!(f, "<{}>", join(&self.generic_params, ", "))?;
        }
        write!(f, " {{")?;
        for property in &self.properties {
            write!(f, "\n    {}", property)?;
        }
        for method in &self.methods {
            write!(f, "\n    {}", method)?;
        }
        if !self.methods.is_empty() || !self.properties.is_empty() {
            write!(f, "\n")?;
        }
        write!(f, "}}")
    }
}

impl Display for PropertyDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write_attributes(f, &self.attributes)?;
        write!(f, "var {}: {} {{", self.name, self.type_name)?;
        for (keyword, accessor) in [("get", &self.get), ("set", &self.set)] {
            if let Some(accessor) = accessor {
                match &accessor.function.body {
                    Some(body) => write!(f, " {} {}", keyword, body)?,
                    None => write!(f, " {};", keyword)?,
                }
            }
        }
        write!(f, " }}")?;
        if let Some(v) = &self.default_value {
            write!(f, " = {};", v)?;
        }
        Ok(())
    }
}

impl Display for ExtendDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write_attributes(f, &self.attributes)?;
        if self.is_exported {
            write!(f, "export ")?;
        }
        if self.target_bounds.iter().all(|b| b.is_empty()) {
            write!(f, "extend {}", self.target)?;
        } else {
            let args: Vec<String> = self
                .target
                .generic_types
                .iter()
                .zip(&self.target_bounds)
                .map(|(a, b)| if b.is_empty() { a.to_string() } else { format!("{}: {}", a, join(b, " & ")) })
                .collect();
            write!(f, "extend {}<{}>", self.target.name, args.join(", "))?;
        }
        if !self.traits.is_empty() {
            write!(f, " with {}", join(&self.traits, ", "))?;
            if self.methods.is_empty() && self.properties.is_empty() {
                return write!(f, ";");
            }
        }
        write!(f, " {{")?;
        for property in &self.properties {
            write!(f, "\n    {}", property)?;
        }
        for method in &self.methods {
            write!(f, "\n    {}", method)?;
        }
        if !self.methods.is_empty() || !self.properties.is_empty() {
            write!(f, "\n")?;
        }
        write!(f, "}}")
    }
}

impl Display for TypeAliasDecl {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write_attributes(f, &self.attributes)?;
        if self.is_exported {
            write!(f, "export ")?;
        }
        write!(f, "type {}", self.name)?;
        if !self.generic_params.is_empty() {
            write!(f, "<{}>", join(&self.generic_params, ", "))?;
        }
        write!(f, " = {}", self.target)
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

impl Display for For {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if !self.pattern.is_empty() {
            let pattern: Vec<String> = self.pattern.iter().map(|b| b.to_string()).collect();
            return write!(f, "for (var ({}) in {}) {}", pattern.join(", "), self.iterable, self.block);
        }
        write!(f, "for ({} in {}) {}", self.binding, self.iterable, self.block)
    }
}

impl Display for With {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match &self.binding {
            Some(b) => write!(f, "with ({} = {}) {}", b, self.scope, self.block)?,
            None => write!(f, "with ({}) {}", self.scope, self.block)?,
        }
        if let Some(e) = &self.else_block {
            write!(f, " else {}", e)?;
        }
        Ok(())
    }
}

impl Display for ReturnStatement {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match &self.expr {
            Some(expr) => write!(f, "return {}", expr),
            None => write!(f, "return"),
        }
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
            Statement::Declaration(Declaration::TypeAlias(t)) => write!(f, "{};", t),
            Statement::Declaration(Declaration::Static(s)) => write!(f, "{}", s),
            Statement::Branch(b) => write!(f, "{}", b),
            Statement::While(w) => write!(f, "{}", w),
            Statement::For(fr) => write!(f, "{}", fr),
            Statement::With(w) => write!(f, "{}", w),
            Statement::Return(r) => write!(f, "{};", r),
            Statement::LoopBreak(l) => write!(f, "{};", if l.kind == LoopBreakKind::Break { "break" } else { "continue" }),
            Statement::Destructure(d) => {
                let bindings: Vec<String> = d.bindings.iter().map(|b| b.to_string()).collect();
                write!(f, "{} ({}) = {};", if d.is_const { "const" } else { "var" }, bindings.join(", "), d.value)
            }
            Statement::Match(m) => write!(f, "{}", m),
            Statement::Static(s) => write!(f, "{}", s),
        }
    }
}

impl Display for Match {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "match ({}) {{", self.value)?;
        for arm in &self.arms {
            write!(f, " {}{} => {}", join(&arm.patterns, ", "), guard_text(&arm.guard), arm.body)?;
        }
        if let Some((_, block)) = &self.else_arm {
            write!(f, " else => {}", block)?;
        }
        write!(f, " }}")
    }
}

/// An arm's guard as written, with the space before it: ` if r > 10`.
fn guard_text(guard: &Option<Expression>) -> String {
    guard.as_ref().map_or(String::new(), |g| format!(" if {}", g))
}

impl Display for Pattern {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        if let Some(literal) = &self.literal {
            return match &self.range {
                Some(r) => write!(f, "{}{}{}", literal, if r.inclusive { "..>" } else { ".." }, r.end),
                None => write!(f, "{}", literal),
            };
        }
        if let Some(elements) = &self.elements {
            let shown: Vec<String> = elements.iter().map(|e| e.to_string()).collect();
            return write!(f, "({})", shown.join(", "));
        }
        if let Some(q) = &self.qualifier {
            write!(f, "{}.", q)?;
        }
        write!(f, "{}", self.case)?;
        if let Some(ty) = self.ty.as_ref().filter(|t| !t.generic_types.is_empty()) {
            write!(f, "<{}>", ty.generic_types.iter().map(|t| t.to_string()).collect::<Vec<_>>().join(", "))?;
        }
        if let Some(bindings) = &self.bindings {
            let shown: Vec<String> = bindings.iter().map(|b| b.to_string()).collect();
            write!(f, "({})", shown.join(", "))?;
        }
        Ok(())
    }
}

impl Display for ImportedSymbol {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name)?;
        if let Some(alias) = &self.alias {
            write!(f, " as {}", alias)?;
        }
        Ok(())
    }
}

impl Display for Import {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        for a in &self.attributes {
            write!(f, "{} ", a)?;
        }
        write!(f, "{} ", if self.reexport { "export" } else { "import" })?;
        match &self.symbols {
            Some(symbols) => write!(f, "[{}] from ", join(symbols, ", "))?,
            None if self.reexport => write!(f, "* from ")?,
            None => {}
        }
        if self.is_local {
            write!(f, "\"{}\"", self.name)?;
        } else {
            write!(f, "{}", self.name)?;
        }
        if let Some(alias) = &self.alias {
            write!(f, " as {}", alias)?;
        }
        Ok(())
    }
}

impl Display for ExportAlias {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        for a in &self.attributes {
            write!(f, "{} ", a)?;
        }
        write!(f, "export {}", self.symbol)?;
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
        for exp in &self.exports {
            writeln!(f, "{};", exp)?;
        }
        for decl in &self.declarations {
            match decl {
                Declaration::Variable(v) => writeln!(f, "{};", v)?,
                Declaration::Function(fn_) => writeln!(f, "{}", fn_)?,
                Declaration::Struct(s) => writeln!(f, "{}", s)?,
                Declaration::Trait(t) => writeln!(f, "{}", t)?,
                Declaration::Extend(e) => writeln!(f, "{}", e)?,
                Declaration::TypeAlias(t) => writeln!(f, "{};", t)?,
                Declaration::Static(s) => writeln!(f, "{}", s)?,
            }
        }
        Ok(())
    }
}

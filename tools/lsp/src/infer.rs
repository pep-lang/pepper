//! Typing what the sema model leaves untyped, from the syntax alone: the
//! body of a generic that nothing instantiates (sema checks only
//! specializations), the names a `match` arm or an `is` test binds, and the
//! members such code reaches. Hover and go-to-definition ask this when the
//! model has no answer.
//!
//! A name's type comes from its declaration, else from sema's inferred type
//! for it, else from its initializer: a constructor or call's return type, a
//! field's type, a ternary's arm, an element of an array. A member is found
//! in the declarations of every program file (the struct or enum, its
//! extensions, the traits those add), with the owner's type arguments bound
//! to the declaration's generic parameters.
//!
//! Expressions nest as deep as the parser allows, so the walk over a body
//! ([`each`]) keeps an explicit stack, and typing gives up past
//! [`MAX_DEPTH`] steps.

use pepper_parser::ast::{self, Span};
use pepper_parser::diagnostic::FileId;
use pepper_parser::namespace::demangle_name;

use crate::{Program, SemaModule, Symbol, body_at, scope_locals};

/// How many steps typing one expression may take: names whose initializers
/// name others, and members of members.
const MAX_DEPTH: usize = 48;

// ── Types ─────────────────────────────────────────────────────────────────────

/// A type as the typer tracks it: a name as written (no namespace or module
/// qualifier) and its type arguments. `T[]` is `Array<T>` and `T?` is
/// `Optional<T>`.
#[derive(Clone, Debug, PartialEq)]
pub struct Ty {
    pub name: String,
    pub args: Vec<Ty>,
    /// A tuple's element labels (`(line: int, column: int)`), else empty.
    pub labels: Vec<String>,
}

impl Ty {
    pub fn named(name: &str) -> Ty {
        Ty { name: name.to_string(), args: vec![], labels: vec![] }
    }

    fn of(name: &str, args: Vec<Ty>) -> Ty {
        Ty { name: name.to_string(), args, labels: vec![] }
    }

    /// `ty` as the typer spells it.
    pub fn from_ast(ty: &ast::TypeName) -> Ty {
        let mut name = ty.name.as_str();
        let mut arrays = 0;
        while let Some(element) = name.strip_suffix("[]") {
            name = element;
            arrays += 1;
        }
        let args = ty.generic_types.iter().map(Ty::from_ast).collect();
        let mut out = Ty { name: plain(name), args, labels: ty.labels.clone() };
        for _ in 0..arrays {
            out = Ty::of("Array", vec![out]);
        }
        out
    }

    /// A type rendered as text (a symbol's type, or sema's): `Box<int>`,
    /// `u8[]`, `int?`, `(int, String)`, `(T) => bool`.
    pub fn parse(text: &str) -> Option<Ty> {
        let mut parser = TypeParser { text: text.as_bytes(), at: 0 };
        let ty = parser.ty(0)?;
        parser.space();
        (parser.at == parser.text.len()).then_some(ty)
    }

    fn is_auto(&self) -> bool {
        self.name == ast::AUTO_TYPE || self.name == "unknown" || self.name.is_empty()
    }

    /// `self` with each type parameter in `bindings` replaced by its argument.
    pub fn substitute(&self, bindings: &[(String, Ty)]) -> Ty {
        if self.args.is_empty()
            && let Some((_, bound)) = bindings.iter().find(|(name, _)| *name == self.name)
        {
            return bound.clone();
        }
        Ty { name: self.name.clone(), args: self.args.iter().map(|a| a.substitute(bindings)).collect(), labels: self.labels.clone() }
    }
}

impl std::fmt::Display for Ty {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let list = |args: &[Ty]| args.iter().map(|a| a.to_string()).collect::<Vec<_>>().join(", ");
        match (self.name.as_str(), self.args.as_slice()) {
            ("Array", [element]) => write!(f, "{}[]", element),
            (ast::TUPLE_TYPE, elements) if !self.labels.is_empty() => {
                let labeled: Vec<String> = elements
                    .iter()
                    .zip(&self.labels)
                    .map(|(e, l)| if l.is_empty() { e.to_string() } else { format!("{}: {}", l, e) })
                    .collect();
                write!(f, "({})", labeled.join(", "))
            }
            (ast::TUPLE_TYPE, elements) => write!(f, "({})", list(elements)),
            (ast::FUNCTION_TYPE | ast::SHARED_FUNCTION_TYPE, [result, parameters @ ..]) => {
                let shared = if self.name == ast::SHARED_FUNCTION_TYPE { "shared " } else { "" };
                write!(f, "{}({}) => {}", shared, list(parameters), result)
            }
            (name, []) => f.write_str(name),
            (name, args) => write!(f, "{}<{}>", name, list(args)),
        }
    }
}

/// A declared name as the source spells it: no namespace (`x@io/file`), no
/// overload number, no module qualifier (`io.IoResult`).
fn plain(name: &str) -> String {
    let name = demangle_name(name);
    name.rsplit('.').next().unwrap_or(name).to_string()
}

/// A parser for rendered types; nesting past [`MAX_DEPTH`] fails.
struct TypeParser<'t> {
    text: &'t [u8],
    at: usize,
}

impl TypeParser<'_> {
    fn space(&mut self) {
        while self.text.get(self.at).is_some_and(|c| c.is_ascii_whitespace()) {
            self.at += 1;
        }
    }

    fn eat(&mut self, token: &str) -> bool {
        self.space();
        if self.text[self.at..].starts_with(token.as_bytes()) {
            self.at += token.len();
            return true;
        }
        false
    }

    fn name(&mut self) -> Option<String> {
        self.space();
        let start = self.at;
        let part = |c: u8| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'.' | b'@' | b'/' | b'#' | b'$');
        while self.text.get(self.at).is_some_and(|&c| part(c)) {
            self.at += 1;
        }
        (self.at > start).then(|| String::from_utf8_lossy(&self.text[start..self.at]).into_owned())
    }

    /// Types separated by `,` up to `close`, and their labels (`line:`),
    /// empty when none has one.
    fn list(&mut self, close: &str, depth: usize) -> Option<(Vec<Ty>, Vec<String>)> {
        let mut out = vec![];
        let mut labels = vec![];
        if self.eat(close) {
            return Some((out, labels));
        }
        loop {
            let save = self.at;
            match self.name() {
                Some(label) if self.eat(":") => labels.push(label),
                _ => {
                    self.at = save;
                    labels.push(String::new());
                }
            }
            out.push(self.ty(depth + 1)?);
            if self.eat(close) {
                if labels.iter().all(|l| l.is_empty()) {
                    labels.clear();
                }
                return Some((out, labels));
            }
            if !self.eat(",") {
                return None;
            }
        }
    }

    fn ty(&mut self, depth: usize) -> Option<Ty> {
        if depth > MAX_DEPTH {
            return None;
        }
        let shared = self.eat("shared ");
        let mut ty = if self.eat("(") {
            let (elements, labels) = self.list(")", depth)?;
            if self.eat("=>") {
                let result = self.ty(depth + 1)?;
                let name = if shared { ast::SHARED_FUNCTION_TYPE } else { ast::FUNCTION_TYPE };
                Ty::of(name, std::iter::once(result).chain(elements).collect())
            } else {
                Ty { name: ast::TUPLE_TYPE.to_string(), args: elements, labels }
            }
        } else {
            let name = self.name()?;
            let args = if self.eat("<") { self.list(">", depth)?.0 } else { vec![] };
            Ty::of(&plain(&name), args)
        };
        loop {
            if self.eat("[]") {
                ty = Ty::of("Array", vec![ty]);
            } else if self.eat("?") {
                ty = Ty::of("Optional", vec![ty]);
            } else if self.eat("*") {
                ty = Ty::of("__ptr", vec![ty]);
            } else {
                return Some(ty);
            }
        }
    }
}

/// Generic parameters bound to type arguments, in order.
fn bind(params: &[ast::GenericParam], args: &[Ty]) -> Vec<(String, Ty)> {
    params.iter().zip(args).map(|(p, a)| (p.name.clone(), a.clone())).collect()
}

/// The base name and type arguments of a member as written: `copy<T>` is
/// `copy` with `T`.
pub fn split_generics(name: &str) -> (&str, Vec<Ty>) {
    match name.split_once('<') {
        Some((base, rest)) => (base, Ty::parse(&format!("_<{}", rest)).map(|t| t.args).unwrap_or_default()),
        None => (name, vec![]),
    }
}

/// Whether two type names are the same type: as written, or the same number
/// type under two names (`u8` and `byte`).
fn same_type(declared: &str, name: &str) -> bool {
    let declared = plain(declared);
    declared == name || {
        let key = pepper_sema::value_types::key(&declared);
        key.is_some() && key == pepper_sema::value_types::key(name)
    }
}

// ── Walking a module ──────────────────────────────────────────────────────────

/// What [`each`] visits.
pub enum Item<'a> {
    Statement(&'a ast::Statement),
    Expression(&'a ast::Expression),
    /// The patterns of one `match` arm or `is` test, and the value matched.
    Patterns(&'a [ast::Pattern], &'a ast::Expression),
    /// A declared variable: a local, a parameter (closures' included), a
    /// field, a module-scope variable, or a `for` or `with` binding.
    Variable(&'a ast::VariableDecl),
}

enum Node<'a> {
    Block(&'a ast::Block),
    Statement(&'a ast::Statement),
    Expression(&'a ast::Expression),
    Function(&'a ast::FunctionDecl),
    Variable(&'a ast::VariableDecl),
}

/// Visit every statement, expression, pattern and variable of `module`.
pub fn each<'a>(module: &'a ast::Module, visit: impl FnMut(Item<'a>)) {
    let mut roots = vec![];
    for d in &module.declarations {
        match d {
            ast::Declaration::Variable(v) => roots.push(Node::Variable(v)),
            ast::Declaration::Function(f) => roots.push(Node::Function(f)),
            ast::Declaration::Struct(s) => {
                roots.extend(s.fields.iter().map(Node::Variable));
                roots.extend(s.constructors.iter().chain(&s.methods).map(Node::Function));
                roots.extend(s.destructor.iter().map(Node::Block));
                for case in s.enumeration.iter().flat_map(|e| &e.cases) {
                    roots.extend(case.payload.iter().flatten().map(Node::Variable));
                    roots.extend(case.value.iter().map(Node::Expression));
                }
            }
            ast::Declaration::Trait(t) => roots.extend(t.methods.iter().map(Node::Function)),
            ast::Declaration::Extend(e) => roots.extend(e.methods.iter().map(Node::Function)),
            ast::Declaration::TypeAlias(_) => {}
        }
    }
    walk(roots, visit);
}

/// [`each`] over one block.
pub fn each_in_block<'a>(block: &'a ast::Block, visit: impl FnMut(Item<'a>)) {
    walk(vec![Node::Block(block)], visit);
}

fn walk<'a>(mut stack: Vec<Node<'a>>, mut visit: impl FnMut(Item<'a>)) {
    while let Some(node) = stack.pop() {
        match node {
            Node::Function(f) => {
                stack.extend(f.parameters.iter().map(Node::Variable));
                stack.extend(f.body.iter().map(Node::Block));
            }
            Node::Variable(v) => {
                visit(Item::Variable(v));
                stack.extend(v.default_value.iter().map(Node::Expression));
            }
            Node::Block(b) => stack.extend(b.statements.iter().map(Node::Statement)),
            Node::Statement(s) => {
                visit(Item::Statement(s));
                match s {
                    ast::Statement::Expression(e) => stack.push(Node::Expression(e)),
                    ast::Statement::Block(b) => stack.push(Node::Block(b)),
                    ast::Statement::Declaration(ast::Declaration::Variable(v)) => stack.push(Node::Variable(v)),
                    ast::Statement::Declaration(ast::Declaration::Function(f)) => stack.push(Node::Function(f)),
                    ast::Statement::Declaration(_) | ast::Statement::LoopBreak(_) => {}
                    ast::Statement::Branch(b) => {
                        stack.push(Node::Expression(&b.condition));
                        stack.push(Node::Block(&b.if_block));
                        stack.extend(b.else_block.iter().map(Node::Block));
                    }
                    ast::Statement::While(w) => {
                        stack.push(Node::Expression(&w.condition));
                        stack.push(Node::Block(&w.block));
                    }
                    ast::Statement::For(f) => {
                        stack.push(Node::Variable(&f.binding));
                        stack.push(Node::Expression(&f.iterable));
                        stack.push(Node::Block(&f.block));
                    }
                    ast::Statement::With(w) => {
                        stack.extend(w.binding.iter().map(Node::Variable));
                        stack.push(Node::Expression(&w.scope));
                        stack.push(Node::Block(&w.block));
                        stack.extend(w.else_block.iter().map(Node::Block));
                    }
                    ast::Statement::Return(r) => stack.extend(r.expr.iter().map(Node::Expression)),
                    ast::Statement::Destructure(d) => stack.push(Node::Expression(&d.value)),
                    ast::Statement::Match(m) => {
                        stack.push(Node::Expression(&m.value));
                        for arm in &m.arms {
                            visit(Item::Patterns(&arm.patterns, &m.value));
                            stack.push(Node::Block(&arm.body));
                        }
                        stack.extend(m.else_arm.iter().map(|(_, b)| Node::Block(b)));
                    }
                }
            }
            Node::Expression(e) => {
                visit(Item::Expression(e));
                match e {
                    ast::Expression::Unary { operand, .. } => stack.push(Node::Expression(operand)),
                    ast::Expression::Cast { expr, .. } => stack.push(Node::Expression(expr)),
                    ast::Expression::Binary { lhs, rhs, .. } | ast::Expression::Index { lhs, rhs, .. } => {
                        stack.push(Node::Expression(lhs));
                        stack.push(Node::Expression(rhs));
                    }
                    ast::Expression::Ternary { condition, true_expr, false_expr, .. } => {
                        stack.push(Node::Expression(condition));
                        stack.push(Node::Expression(true_expr));
                        stack.push(Node::Expression(false_expr));
                    }
                    ast::Expression::MemberAccess { lhs, .. } => stack.push(Node::Expression(lhs)),
                    ast::Expression::FunctionCall { function, arguments, .. } => {
                        stack.push(Node::Expression(function));
                        stack.extend(arguments.iter().map(Node::Expression));
                    }
                    ast::Expression::Closure(c) => {
                        stack.extend(c.parameters.iter().map(Node::Variable));
                        stack.push(Node::Block(&c.body));
                    }
                    ast::Expression::Tuple { elements, .. } | ast::Expression::ArrayLiteral { elements, .. } => {
                        stack.extend(elements.iter().map(Node::Expression));
                    }
                    ast::Expression::MapLiteral { entries, .. } => {
                        stack.extend(entries.iter().flat_map(|(k, v)| [Node::Expression(k), Node::Expression(v)]));
                    }
                    ast::Expression::Match(m) => {
                        stack.push(Node::Expression(&m.value));
                        for arm in &m.arms {
                            visit(Item::Patterns(&arm.patterns, &m.value));
                            stack.push(Node::Expression(&arm.value));
                        }
                        stack.extend(m.else_arm.iter().map(|(_, v)| Node::Expression(v)));
                    }
                    ast::Expression::Is { value, pattern, .. } => {
                        visit(Item::Patterns(std::slice::from_ref(&**pattern), value));
                        stack.push(Node::Expression(value));
                    }
                    ast::Expression::Literal { .. }
                    | ast::Expression::SymbolRef { .. }
                    | ast::Expression::TypeLiteral(_)
                    | ast::Expression::SizeOf(_) => {}
                }
            }
        }
    }
}

/// Each pattern in `patterns` and nested in them, with the type of the value
/// it matches when known: a tuple pattern's elements match the tuple's.
fn with_subjects<'p>(patterns: &'p [ast::Pattern], subject: Option<Ty>) -> Vec<(&'p ast::Pattern, Option<Ty>)> {
    let mut out = vec![];
    let mut stack: Vec<(&ast::Pattern, Option<Ty>)> = patterns.iter().map(|p| (p, subject.clone())).collect();
    while let Some((p, ty)) = stack.pop() {
        if let Some(elements) = &p.elements {
            for (i, e) in elements.iter().enumerate() {
                let element = ty.as_ref().filter(|t| t.name == ast::TUPLE_TYPE).and_then(|t| t.args.get(i).cloned());
                stack.push((e, element));
            }
        }
        out.push((p, ty));
    }
    out
}

fn contains(span: Span, offset: usize) -> bool {
    span.start <= offset && offset <= span.end
}

// ── Declarations ──────────────────────────────────────────────────────────────

/// A member of a type: what the declaration says, and where.
#[derive(Clone)]
pub enum Kind<'a> {
    Field(&'a ast::VariableDecl),
    Method(&'a ast::FunctionDecl),
    Case(&'a ast::EnumCase),
    /// A method every enum of plain values has (`name`, `from_value`): no
    /// file declares it, so it is placed at the enum's name.
    EnumMethod(&'a ast::StructDecl, &'static str),
    /// A labeled element of a tuple (`p.line`), with its type. The label has
    /// no declaration of its own.
    Element(String, Ty),
}

/// A member [`Typer::member`] found.
#[derive(Clone)]
pub struct Found<'a> {
    /// The program file declaring it (0 is the document).
    pub file: usize,
    pub kind: Kind<'a>,
    /// The name of the type it was found in, as written.
    pub owner: String,
    /// The declaring type's generic parameters, bound to the owner's type
    /// arguments.
    pub bindings: Vec<(String, Ty)>,
}

impl Found<'_> {
    /// The member's name where it is declared; none for a tuple's element.
    pub fn name_span(&self) -> Option<Span> {
        Some(match &self.kind {
            Kind::Field(v) => v.name_span,
            Kind::Method(f) => f.name_span,
            Kind::Case(c) => c.name_span,
            Kind::EnumMethod(s, _) => s.name_span,
            Kind::Element(..) => return None,
        })
    }

    /// What hover shows: a field's type, a method's signature, or a case as
    /// `Shape.Circle(radius: int)`, with the owner's type arguments filled in.
    pub fn describe(&self) -> String {
        match &self.kind {
            Kind::Field(v) => Ty::from_ast(&v.type_name).substitute(&self.bindings).to_string(),
            Kind::Method(f) => {
                let parameters: Vec<String> = f
                    .parameters
                    .iter()
                    .filter(|p| p.name != "this")
                    .map(|p| format!("{}: {}", p.name, Ty::from_ast(&p.type_name).substitute(&self.bindings)))
                    .collect();
                format!(
                    "{}{}{}({}): {}",
                    if f.is_static { "static " } else { "" },
                    demangle_name(&f.name),
                    crate::generics_string(&f.generic_params),
                    parameters.join(", "),
                    Ty::from_ast(&f.return_type).substitute(&self.bindings)
                )
            }
            Kind::Case(c) => match &c.payload {
                Some(values) => {
                    let values: Vec<String> = values
                        .iter()
                        .map(|v| format!("{}: {}", v.name, Ty::from_ast(&v.type_name).substitute(&self.bindings)))
                        .collect();
                    format!("{}.{}({})", self.owner, c.name, values.join(", "))
                }
                None => format!("{}.{}", self.owner, c.name),
            },
            Kind::Element(_, ty) => ty.to_string(),
            Kind::EnumMethod(s, "from_value") => {
                let representation = s.enumeration.as_ref().and_then(|e| e.representation.as_ref()).map_or("int".to_string(), |r| r.to_string());
                format!("static from_value(value: {}): Result<{}>", representation, self.owner)
            }
            Kind::EnumMethod(_, method) => format!("{}(): String", method),
        }
    }
}

/// What a pattern names at an offset.
pub enum PatternHit<'a> {
    /// The case a pattern names.
    Case(Found<'a>),
    /// A name the pattern binds, where it binds it, and its type when known.
    Binding { name: String, span: Span, ty: Option<Ty> },
}

/// Types names and finds members in the document `doc` (the fresh parse of
/// `program.files[0]`) and the program's other files.
pub struct Typer<'a> {
    doc: &'a ast::Module,
    program: Option<&'a Program>,
    sema: Option<&'a SemaModule>,
}

impl<'a> Typer<'a> {
    pub fn new(doc: &'a ast::Module, program: Option<&'a Program>, sema: Option<&'a SemaModule>) -> Self {
        Typer { doc, program, sema }
    }

    /// The document, then each other program file, with its index.
    fn modules(&self) -> impl Iterator<Item = (usize, &'a ast::Module)> + 'a {
        let others = self.program.into_iter().flat_map(|p| p.files.iter().enumerate().skip(1).map(|(i, f)| (i, &f.module)));
        std::iter::once((0, self.doc)).chain(others)
    }

    fn declarations(&self) -> impl Iterator<Item = (usize, &'a ast::Declaration)> + 'a {
        self.modules().flat_map(|(i, m)| m.declarations.iter().map(move |d| (i, d)))
    }

    /// Whether `name` names a type: a struct, enum, trait or alias some file
    /// declares, a number type, or a type parameter in scope at `at`.
    fn is_type(&self, name: &str, at: usize) -> bool {
        pepper_sema::type_name::INTEGRAL_TYPES.contains(name)
            || self.declarations().any(|(_, d)| {
                matches!(d, ast::Declaration::Struct(_) | ast::Declaration::Trait(_) | ast::Declaration::TypeAlias(_))
                    && plain(d.name()) == name
            })
            || crate::generic_param_at(self.doc, at, |p| p.name == name).is_some()
    }

    /// `ty` with type aliases expanded.
    fn resolve(&self, mut ty: Ty) -> Ty {
        for _ in 0..8 {
            let alias = self.declarations().find_map(|(_, d)| match d {
                ast::Declaration::TypeAlias(t) if plain(&t.name) == ty.name => Some(t),
                _ => None,
            });
            let Some(alias) = alias else { break };
            ty = Ty::from_ast(&alias.target).substitute(&bind(&alias.generic_params, &ty.args));
        }
        ty
    }

    /// The member `name` of a value (or, for a static call, the type) of
    /// type `owner`: a field, method or enum case its declaration, an
    /// extension of it, or a trait either adds declares. `at` is where the
    /// owner is used: a type parameter there reaches its bounds' members.
    pub fn member(&self, owner: &Ty, name: &str, at: usize) -> Option<Found<'a>> {
        let owner = self.resolve(owner.clone());
        let owner = match owner.name.as_str() {
            // A weak reference or a pointer reaches its target's members.
            "__weak" | "__ptr" if owner.args.len() == 1 => owner.args[0].clone(),
            _ => owner,
        };
        // A tuple's labeled element.
        if owner.name == ast::TUPLE_TYPE
            && let Some(index) = owner.labels.iter().position(|l| l == name)
        {
            let kind = Kind::Element(name.to_string(), owner.args.get(index)?.clone());
            return Some(Found { file: 0, kind, owner: owner.to_string(), bindings: vec![] });
        }
        if let Some(found) = self.declared_member(&owner, name, 0) {
            return Some(found);
        }
        // A type parameter: its bounds' members.
        let bounds = self.doc_generic_bounds(at, &owner.name);
        bounds.iter().find_map(|b| self.declared_member(&Ty::from_ast(b), name, 0))
    }

    /// The bounds of the type parameter `name` in scope at `at`.
    fn doc_generic_bounds(&self, at: usize, name: &str) -> Vec<ast::TypeName> {
        let mut out = vec![];
        let inside = |s: Span| s.start <= at && at < s.end;
        let mut scan = |params: &[ast::GenericParam]| {
            out.extend(params.iter().filter(|p| p.name == name).flat_map(|p| p.bounds.iter().cloned()));
        };
        for d in &self.doc.declarations {
            match d {
                ast::Declaration::Function(f) if inside(f.span) => scan(&f.generic_params),
                ast::Declaration::Struct(s) if inside(s.span) => {
                    scan(&s.generic_params);
                    s.methods.iter().filter(|m| inside(m.span)).for_each(|m| scan(&m.generic_params));
                }
                ast::Declaration::Trait(t) if inside(t.span) => {
                    scan(&t.generic_params);
                    t.methods.iter().filter(|m| inside(m.span)).for_each(|m| scan(&m.generic_params));
                }
                ast::Declaration::Extend(e) if inside(e.span) => {
                    e.methods.iter().filter(|m| inside(m.span)).for_each(|m| scan(&m.generic_params));
                    // `extend Box<T: Named>` bounds a parameter of the target.
                    for (param, bounds) in e.target.generic_types.iter().zip(&e.target_bounds) {
                        if param.name == name {
                            scan(&[ast::GenericParam {
                                name: param.name.clone(),
                                name_span: param.span,
                                bounds: bounds.clone(),
                                default: None,
                                is_argument: false,
                            }]);
                        }
                    }
                }
                _ => {}
            }
        }
        out
    }

    fn declared_member(&self, owner: &Ty, name: &str, depth: usize) -> Option<Found<'a>> {
        if depth > 4 {
            return None;
        }
        let found = |file, kind, owner_name: &str, bindings| Some(Found { file, kind, owner: plain(owner_name), bindings });
        let mut traits: Vec<Ty> = vec![];
        for (file, d) in self.declarations() {
            match d {
                ast::Declaration::Struct(s) if same_type(&s.name, &owner.name) => {
                    let bindings = bind(&s.generic_params, &owner.args);
                    if let Some(v) = s.fields.iter().find(|v| v.name == name) {
                        return found(file, Kind::Field(v), &s.name, bindings);
                    }
                    if let Some(c) = s.enumeration.iter().flat_map(|e| &e.cases).find(|c| c.name == name) {
                        return found(file, Kind::Case(c), &s.name, bindings);
                    }
                    if let Some(m) = s.methods.iter().find(|m| demangle_name(&m.name) == name) {
                        return found(file, Kind::Method(m), &s.name, bindings);
                    }
                    if let Some(e) = &s.enumeration
                        && e.cases.iter().all(|c| c.payload.is_none())
                        && let Some(method) = pepper_sema::enums::BUILT_IN_METHODS.iter().find(|m| **m == name)
                    {
                        return found(file, Kind::EnumMethod(s, method), &s.name, bindings);
                    }
                }
                ast::Declaration::Trait(t) if same_type(&t.name, &owner.name) => {
                    if let Some(m) = t.methods.iter().find(|m| demangle_name(&m.name) == name) {
                        return found(file, Kind::Method(m), &t.name, bind(&t.generic_params, &owner.args));
                    }
                }
                ast::Declaration::Extend(e) if same_type(&e.target.name, &owner.name) => {
                    // `extend Box<T>` names its parameters in the target.
                    let bindings: Vec<(String, Ty)> =
                        e.target.generic_types.iter().zip(&owner.args).map(|(p, a)| (p.name.clone(), a.clone())).collect();
                    if let Some(m) = e.methods.iter().find(|m| demangle_name(&m.name) == name) {
                        return found(file, Kind::Method(m), &e.target.name, bindings);
                    }
                    traits.extend(e.traits.iter().map(|t| Ty::from_ast(t).substitute(&bindings)));
                }
                _ => {}
            }
        }
        traits.iter().find_map(|t| self.declared_member(t, name, depth + 1))
    }

    /// The type of a member's value: a field's type, or an enum case's owner.
    fn member_value(found: &Found, owner: &Ty) -> Option<Ty> {
        match &found.kind {
            Kind::Field(v) => Some(Ty::from_ast(&v.type_name).substitute(&found.bindings)),
            Kind::Element(_, ty) => Some(ty.clone()),
            Kind::Case(_) => Some(owner.clone()),
            Kind::Method(_) | Kind::EnumMethod(..) => None,
        }
    }

    // ── Names ─────────────────────────────────────────────────────────────

    /// The type `this` has at `at`: the enclosing struct's, its generic
    /// parameters as arguments, or the type an extension extends.
    pub fn this_type(&self, at: usize) -> Option<Ty> {
        if let Some((_, Some(s))) = body_at(self.doc, at) {
            let args = s.generic_params.iter().map(|p| Ty::named(&p.name)).collect();
            return Some(Ty::of(&s.name, args));
        }
        self.doc.declarations.iter().find_map(|d| match d {
            ast::Declaration::Extend(e) if e.span.start <= at && at < e.span.end => Some(Ty::from_ast(&e.target)),
            // A trait's default method: the trait's own members.
            ast::Declaration::Trait(t) if t.span.start <= at && at < t.span.end => {
                Some(Ty::of(&t.name, t.generic_params.iter().map(|p| Ty::named(&p.name)).collect()))
            }
            _ => None,
        })
    }

    /// The type of the local or parameter `symbol` (from `scope_locals` or
    /// `declared_at`).
    pub fn local_type_of(&self, symbol: &Symbol) -> Option<Ty> {
        self.local_type(symbol, 0)
    }

    /// The type of the local or parameter `symbol`, from its declaration.
    fn local_type(&self, symbol: &Symbol, depth: usize) -> Option<Ty> {
        if let Some(ty) = Ty::parse(&symbol.ty).filter(|t| !t.is_auto()) {
            return Some(ty);
        }
        let inferred = self
            .sema
            .and_then(|m| pepper_sema::member_lookup::local_type(m, FileId(0), symbol.name_span.start))
            .and_then(|t| Ty::parse(&t.to_string()));
        match inferred {
            // Sema's tuple types drop their labels; the syntax keeps them.
            Some(t) if t.name == ast::TUPLE_TYPE => {
                Some(self.declared_type(symbol, depth).filter(|d| d.name == ast::TUPLE_TYPE && !d.labels.is_empty()).unwrap_or(t))
            }
            Some(t) => Some(t),
            None => self.declared_type(symbol, depth),
        }
    }

    /// The type of the local or parameter `symbol` from its declaration:
    /// its initializer, the value a pattern or destructuring takes apart, or
    /// what a `for` loop iterates.
    fn declared_type(&self, symbol: &Symbol, depth: usize) -> Option<Ty> {
        // A constructor's `this.run = ...` parameter stores to the field.
        if let Some(field) = symbol.name.strip_prefix("this.") {
            let this = self.this_type(symbol.name_span.start)?;
            return Self::member_value(&self.member(&this, field, symbol.name_span.start)?, &this);
        }
        enum Site<'s> {
            Variable(&'s ast::VariableDecl),
            For(&'s ast::For),
            Bound(&'s [ast::Pattern], &'s ast::Expression),
            Destructure(&'s ast::Destructure),
            ForPattern(&'s ast::For),
            /// A closure's parameter, by the function type the closure is
            /// given as: what the callee's parameter or the variable says.
            ClosureParameter(usize, Ty),
        }
        let span = symbol.name_span;
        let leaf = |bindings: &[ast::DestructureBinding]| bindings.iter().flat_map(|b| b.leaves()).any(|b| b.name_span == span);
        let mut site = None;
        each(self.doc, |item| {
            if site.is_some() {
                return;
            }
            match item {
                Item::Statement(ast::Statement::For(f)) if f.binding.name_span == span => site = Some(Site::For(f)),
                Item::Statement(ast::Statement::For(f)) if leaf(&f.pattern) => site = Some(Site::ForPattern(f)),
                Item::Statement(ast::Statement::Destructure(d)) if leaf(&d.bindings) => site = Some(Site::Destructure(d)),
                Item::Variable(v) if v.name_span == span && v.type_name.name == ast::AUTO_TYPE => {
                    site = self.closure_parameter(span, depth + 1).map(|(i, t)| Site::ClosureParameter(i, t)).or(Some(Site::Variable(v)));
                }
                Item::Variable(v) if v.name_span == span => site = Some(Site::Variable(v)),
                Item::Patterns(patterns, subject)
                    if patterns.iter().flat_map(|p| p.bound_names()).any(|(_, s)| s == span) =>
                {
                    site = Some(Site::Bound(patterns, subject))
                }
                _ => {}
            }
        });
        match site? {
            Site::Variable(v) if v.type_name.name == ast::AUTO_TYPE => {
                self.type_at(v.default_value.as_ref()?, v.name_span.start, depth + 1)
            }
            Site::Variable(v) => Some(Ty::from_ast(&v.type_name)),
            Site::For(f) => {
                let iterable = self.type_at(&f.iterable, f.span.start, depth + 1)?;
                self.element(&iterable, f.span.start)
            }
            Site::ClosureParameter(index, ty) => match ty.name.as_str() {
                ast::FUNCTION_TYPE | ast::SHARED_FUNCTION_TYPE | ast::EXTERN_FUNCTION_TYPE => ty.args.get(index + 1).cloned(),
                _ => None,
            },
            Site::Destructure(d) => {
                let value = self.type_at(&d.value, d.span.start, depth + 1);
                destructured(&d.bindings, value, span)
            }
            Site::ForPattern(f) => {
                let iterable = self.type_at(&f.iterable, f.span.start, depth + 1);
                destructured(&f.pattern, iterable.and_then(|t| self.element(&t, f.span.start)), span)
            }
            Site::Bound(patterns, subject) => {
                let subject_type = self.type_at(subject, expression_start(subject), depth + 1);
                with_subjects(patterns, subject_type).into_iter().find_map(|(p, ty)| self.bound_type(p, ty.as_ref(), span))
            }
        }
    }

    /// For the closure parameter named at `span`: its position, and the type
    /// the closure is given as, from the callee's parameter it is passed to
    /// or the variable it initializes.
    fn closure_parameter(&self, span: Span, depth: usize) -> Option<(usize, Ty)> {
        let is_ours = |e: &ast::Expression| match e {
            ast::Expression::Closure(c) => c.parameters.iter().position(|p| p.name_span == span),
            _ => None,
        };
        let mut found = None;
        each(self.doc, |item| {
            if found.is_some() {
                return;
            }
            match item {
                Item::Variable(v) if v.type_name.name != ast::AUTO_TYPE => {
                    if let Some(index) = v.default_value.as_ref().and_then(is_ours) {
                        found = Some((index, Ty::from_ast(&v.type_name)));
                    }
                }
                Item::Expression(ast::Expression::FunctionCall { function, arguments, .. }) => {
                    let Some((argument, index)) = arguments.iter().enumerate().find_map(|(k, a)| Some((k, is_ours(a)?))) else {
                        return;
                    };
                    let at = span.start;
                    let parameter = match &**function {
                        ast::Expression::SymbolRef { id, .. } => self.declarations().find_map(|(_, d)| match d {
                            ast::Declaration::Function(f) if plain(&f.name) == *id => {
                                f.parameters.get(argument).map(|p| Ty::from_ast(&p.type_name))
                            }
                            _ => None,
                        }),
                        ast::Expression::MemberAccess { lhs, name, .. } => self.member_access_at(lhs, name, at, depth).and_then(|m| {
                            let Kind::Method(f) = &m.kind else { return None };
                            let p = f.parameters.iter().filter(|p| p.name != "this").nth(argument)?;
                            Some(Ty::from_ast(&p.type_name).substitute(&m.bindings))
                        }),
                        _ => None,
                    };
                    found = parameter.map(|t| (index, t));
                }
                _ => {}
            }
        });
        found
    }

    /// The type of the name pattern `p` binds at `span`, matching a value of
    /// type `subject`.
    fn bound_type(&self, p: &ast::Pattern, subject: Option<&Ty>, span: Span) -> Option<Ty> {
        if p.is_bare_name() && p.case_span == span {
            return subject.cloned();
        }
        let index = p.bindings.as_ref()?.iter().position(|(_, s)| *s == span)?;
        let found = self.case_of(p, subject)?;
        let Kind::Case(case) = &found.kind else { return None };
        let value = case.payload.as_ref()?.get(index)?;
        Some(Ty::from_ast(&value.type_name).substitute(&found.bindings))
    }

    /// The case pattern `p` names, matching a value of type `subject`: of the
    /// enum it qualifies, else the value's, else the one enum declaring a
    /// case of that name that carries as many values.
    pub fn case_of(&self, p: &ast::Pattern, subject: Option<&Ty>) -> Option<Found<'a>> {
        if p.literal.is_some() || p.elements.is_some() {
            return None;
        }
        let owner = p.qualifier.as_ref().map(Ty::from_ast).or_else(|| subject.cloned());
        if let Some(owner) = owner
            && let Some(found) = self.declared_member(&self.resolve(owner), &p.case, 0)
        {
            return matches!(found.kind, Kind::Case(_)).then_some(found);
        }
        let arity = p.bindings.as_ref().map(|b| b.len());
        let mut candidates = self.declarations().filter_map(|(file, d)| match d {
            ast::Declaration::Struct(s) => {
                let case = s.enumeration.as_ref()?.cases.iter().find(|c| {
                    c.name == p.case && arity.is_none_or(|n| c.payload.as_ref().is_some_and(|v| v.len() == n))
                })?;
                Some(Found { file, kind: Kind::Case(case), owner: plain(&s.name), bindings: vec![] })
            }
            _ => None,
        });
        let first = candidates.next()?;
        // Two enums could be meant: the document's own wins, else neither.
        match candidates.next() {
            Some(_) if first.file != 0 => None,
            _ => Some(first),
        }
    }

    /// What the pattern under `offset` names: a case, or a name it binds.
    pub fn pattern_at(&self, offset: usize) -> Option<PatternHit<'a>> {
        let mut hit: Option<(&ast::Pattern, &ast::Expression, &[ast::Pattern])> = None;
        each(self.doc, |item| {
            if let Item::Patterns(patterns, subject) = item
                && hit.is_none()
            {
                // `String.format`'s lowering binds its arguments by hidden
                // names at the arguments' own spans.
                for p in patterns.iter().flat_map(|p| p.all()).filter(|p| !p.case.starts_with("_pep_")) {
                    let on_case = p.literal.is_none() && p.elements.is_none() && contains(p.case_span, offset);
                    let on_binding = p.bindings.iter().flatten().any(|(_, s)| contains(*s, offset));
                    if on_case || on_binding {
                        hit = Some((p, subject, patterns));
                        return;
                    }
                }
            }
        });
        let (p, subject, patterns) = hit?;
        let subject_type = self.type_at(subject, expression_start(subject), 0);
        let subject_type = with_subjects(patterns, subject_type).into_iter().find(|(q, _)| std::ptr::eq(*q, p))?.1;
        if let Some((name, span)) = p.bindings.iter().flatten().find(|(_, s)| contains(*s, offset)) {
            let ty = self.bound_type(p, subject_type.as_ref(), *span);
            return Some(PatternHit::Binding { name: name.clone(), span: *span, ty });
        }
        // A bare name in a tuple pattern binds the element unless it is a case.
        match self.case_of(p, subject_type.as_ref()) {
            Some(found) => Some(PatternHit::Case(found)),
            None if p.is_bare_name() && p.case != "_" => {
                Some(PatternHit::Binding { name: p.case.clone(), span: p.case_span, ty: subject_type })
            }
            None => None,
        }
    }

    /// The type of the name `id` at `at`.
    pub fn symbol_type(&self, id: &str, at: usize) -> Option<Ty> {
        self.name_type(id, at, 0)
    }

    fn name_type(&self, id: &str, at: usize, depth: usize) -> Option<Ty> {
        if depth > MAX_DEPTH {
            return None;
        }
        if id == "this" {
            return self.this_type(at);
        }
        if let Some(symbol) = scope_locals(self.doc, at).into_iter().rev().find(|s| s.name == id) {
            return self.local_type(&symbol, depth + 1);
        }
        // A member of `this`, named bare.
        if let Some(this) = self.this_type(at)
            && let Some(found) = self.member(&this, id, at)
        {
            return Self::member_value(&found, &this);
        }
        // A module-scope variable, as declared or initialized.
        let (file, v) = self.declarations().find_map(|(file, d)| match d {
            ast::Declaration::Variable(v) if plain(&v.name) == plain(id) => Some((file, v)),
            _ => None,
        })?;
        if v.type_name.name != ast::AUTO_TYPE {
            return Some(Ty::from_ast(&v.type_name));
        }
        // Another file's initializer names that file's declarations; only a
        // call of a type or function is typed from here.
        let at = if file == 0 { v.name_span.start } else { usize::MAX };
        self.type_at(v.default_value.as_ref()?, at, depth + 1)
    }

    /// The type a value of `owner` holds as elements: an array's element, or
    /// what its iterator's `next()` returns.
    fn element(&self, owner: &Ty, at: usize) -> Option<Ty> {
        let owner = self.resolve(owner.clone());
        if matches!(owner.name.as_str(), "Array" | "__ptr") {
            return owner.args.first().cloned();
        }
        // An iterator, or what `iterate()` returns.
        let iterator = self.method_result(&owner, "iterate", &[], at).unwrap_or(owner);
        let next = self.method_result(&iterator, "next", &[], at)?;
        // `next()` returns an `Optional<T>`, or a `bool` with `current()` the
        // element.
        match next.name.as_str() {
            "Optional" => next.args.first().cloned(),
            "bool" => self.method_result(&iterator, "current", &[], at),
            _ => Some(next),
        }
    }

    /// The type a call of `owner`'s method `name` returns.
    fn method_result(&self, owner: &Ty, name: &str, args: &[Ty], at: usize) -> Option<Ty> {
        let found = self.member(owner, name, at)?;
        let Kind::Method(f) = &found.kind else { return None };
        let mut bindings = found.bindings.clone();
        bindings.extend(bind(&f.generic_params, args));
        // A trait's `this` is the type it is called on.
        bindings.push(("this".to_string(), owner.clone()));
        Some(Ty::from_ast(&f.return_type).substitute(&bindings)).filter(|t| !t.is_auto())
    }

    /// The type `expr` names when it names a type rather than a value: the
    /// owner of a static call (`Box<int>.make()`, `int.parse(...)`).
    pub fn named_type(&self, expr: &ast::Expression, at: usize) -> Option<Ty> {
        match expr {
            ast::Expression::TypeLiteral(t) if self.is_type(&plain(&t.name), at) => Some(Ty::from_ast(t)),
            ast::Expression::SymbolRef { id, .. }
                if !scope_locals(self.doc, at).iter().any(|s| s.name == *id) && self.is_type(id, at) =>
            {
                Some(Ty::named(id))
            }
            _ => None,
        }
    }

    /// The type of `expr`, written at `at`.
    pub fn type_of(&self, expr: &ast::Expression, at: usize) -> Option<Ty> {
        self.type_at(expr, at, 0)
    }

    fn type_at(&self, expr: &ast::Expression, at: usize, depth: usize) -> Option<Ty> {
        if depth > MAX_DEPTH {
            return None;
        }
        let depth = depth + 1;
        let ty = match expr {
            ast::Expression::Literal { value, .. } => Some(Ty::named(match value {
                ast::Literal::String(_) => "String",
                ast::Literal::Integer(_) => "int",
                ast::Literal::Float(_) => "float",
                ast::Literal::Bool(_) => "bool",
                ast::Literal::Char(_) => "byte",
                ast::Literal::Null => "__null",
            })),
            ast::Expression::SymbolRef { id, .. } => self.name_type(id, at, depth),
            ast::Expression::TypeLiteral(_) | ast::Expression::Closure(_) => None,
            ast::Expression::SizeOf(_) => Some(Ty::named("ulong")),
            ast::Expression::Unary { op, operand, .. } => match op.as_str() {
                "!" => Some(Ty::named("bool")),
                _ => self.type_at(operand, at, depth),
            },
            ast::Expression::Cast { ty, .. } => Some(Ty::from_ast(ty)),
            ast::Expression::Binary { lhs, op, rhs, .. } => match op.as_str() {
                "==" | "!=" | "===" | "!==" | "<" | ">" | "<=" | ">=" | "&&" | "||" => Some(Ty::named("bool")),
                _ => self.type_at(lhs, at, depth).or_else(|| self.type_at(rhs, at, depth)),
            },
            ast::Expression::Ternary { true_expr, false_expr, .. } => {
                self.type_at(true_expr, at, depth).or_else(|| self.type_at(false_expr, at, depth))
            }
            ast::Expression::Index { lhs, .. } => {
                let owner = self.type_at(lhs, at, depth)?;
                self.element(&owner, at).or_else(|| {
                    // An indexer (`[](index): T`).
                    let found = self.declared_member(&owner, "__index_get", 0)?;
                    let Kind::Method(f) = &found.kind else { return None };
                    Some(Ty::from_ast(&f.return_type).substitute(&found.bindings))
                })
            }
            ast::Expression::MemberAccess { lhs, name, .. } => {
                let owner = self.named_type(lhs, at).or_else(|| self.type_at(lhs, at, depth))?;
                let found = self.member(&owner, split_generics(name).0, at)?;
                Self::member_value(&found, &owner)
            }
            ast::Expression::FunctionCall { function, .. } => self.call_type(function, at, depth),
            ast::Expression::Tuple { elements, labels, .. } => {
                let args = elements.iter().map(|e| self.type_at(e, at, depth)).collect::<Option<Vec<_>>>()?;
                Some(Ty { name: ast::TUPLE_TYPE.to_string(), args, labels: labels.iter().map(|(l, _)| l.clone()).collect() })
            }
            ast::Expression::ArrayLiteral { elements, .. } => {
                Some(Ty::of("Array", vec![self.type_at(elements.first()?, at, depth)?]))
            }
            ast::Expression::MapLiteral { entries, .. } => {
                let (k, v) = entries.first()?;
                Some(Ty::of("HashMap", vec![self.type_at(k, at, depth)?, self.type_at(v, at, depth)?]))
            }
            ast::Expression::Match(m) => {
                m.arms.iter().map(|a| &a.value).chain(m.else_arm.as_ref().map(|(_, v)| v)).find_map(|v| self.type_at(v, at, depth))
            }
            ast::Expression::Is { .. } => Some(Ty::named("bool")),
        };
        ty.filter(|t| !t.is_auto())
    }

    /// The type a call of `function` returns.
    fn call_type(&self, function: &ast::Expression, at: usize, depth: usize) -> Option<Ty> {
        let result = |t: Ty| match t.name.as_str() {
            ast::FUNCTION_TYPE | ast::SHARED_FUNCTION_TYPE => t.args.first().cloned(),
            _ => None,
        };
        match function {
            ast::Expression::SymbolRef { id, .. } => {
                if self.is_type(id, at) && !scope_locals(self.doc, at).iter().any(|s| s.name == *id) {
                    return Some(Ty::named(id));
                }
                // A local or field holding a function.
                if let Some(t) = self.name_type(id, at, depth) {
                    return result(t);
                }
                // A method of `this`, called bare.
                if let Some(this) = self.this_type(at)
                    && let Some(t) = self.method_result(&this, id, &[], at)
                {
                    return Some(t);
                }
                self.function_result(id, &[])
            }
            ast::Expression::TypeLiteral(t) => match t.name.as_str() {
                "__weak_upgrade" => t.generic_types.first().map(Ty::from_ast),
                "__weak_from" => Some(Ty::of("__weak", t.generic_types.iter().map(Ty::from_ast).collect())),
                name if self.is_type(&plain(name), at) => Some(Ty::from_ast(t)),
                name => self.function_result(name, &t.generic_types.iter().map(Ty::from_ast).collect::<Vec<_>>()),
            },
            ast::Expression::MemberAccess { lhs, name, .. } => {
                let owner = self.named_type(lhs, at).or_else(|| self.type_at(lhs, at, depth))?;
                let (base, args) = split_generics(name);
                let found = self.member(&owner, base, at)?;
                match &found.kind {
                    Kind::Method(_) => self.method_result(&owner, base, &args, at),
                    Kind::EnumMethod(s, "from_value") => Some(Ty::of("Result", vec![Ty::named(&plain(&s.name))])),
                    Kind::EnumMethod(..) => Some(Ty::named("String")),
                    Kind::Case(_) => Some(self.resolve(owner)),
                    Kind::Field(_) | Kind::Element(..) => result(Self::member_value(&found, &owner)?),
                }
            }
            _ => None,
        }
    }

    /// The type a call of the top-level function `name` returns.
    fn function_result(&self, name: &str, args: &[Ty]) -> Option<Ty> {
        // Another file's initializer spells its own private names mangled.
        let name = plain(name);
        let f = self.declarations().find_map(|(_, d)| match d {
            ast::Declaration::Function(f) if plain(&f.name) == name => Some(f),
            _ => None,
        })?;
        Some(Ty::from_ast(&f.return_type).substitute(&bind(&f.generic_params, args))).filter(|t| !t.is_auto())
    }

    /// The member a member access (`x.name`, `x.name(...)`, `T.name(...)`)
    /// at `at` reaches.
    pub fn member_access(&self, lhs: &ast::Expression, name: &str, at: usize) -> Option<Found<'a>> {
        self.member_access_at(lhs, name, at, 0)
    }

    fn member_access_at(&self, lhs: &ast::Expression, name: &str, at: usize, depth: usize) -> Option<Found<'a>> {
        let owner = self.named_type(lhs, at).or_else(|| self.type_at(lhs, at, depth))?;
        self.member(&owner, split_generics(name).0, at)
    }

    /// The type of the module-scope variable declared at `name_span` in
    /// program file `file`, from its initializer when it names no type.
    pub fn global_type(&self, file: usize, name_span: Span) -> Option<Ty> {
        let module = self.modules().find(|(i, _)| *i == file)?.1;
        let v = module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Variable(v) if v.name_span == name_span => Some(v),
            _ => None,
        })?;
        if v.type_name.name != ast::AUTO_TYPE {
            return Some(Ty::from_ast(&v.type_name));
        }
        // Another file's initializer has no locals here.
        let at = if file == 0 { v.name_span.start } else { usize::MAX };
        self.type_at(v.default_value.as_ref()?, at, 0)
    }

    /// The labels of the tuple a member access (`p.line`) reads.
    pub fn member_owner_labels(&self, access: &ast::Expression, at: usize) -> Option<Vec<String>> {
        let ast::Expression::MemberAccess { lhs, .. } = access else { return None };
        let owner = self.type_at(lhs, at, 0)?;
        (owner.name == ast::TUPLE_TYPE && !owner.labels.is_empty()).then_some(owner.labels)
    }

    /// The member of `this` the bare name `id` at `at` reaches.
    pub fn bare_member(&self, id: &str, at: usize) -> Option<Found<'a>> {
        self.member(&self.this_type(at)?, id, at)
    }
}

/// The type of the name destructuring binds at `span`, from a value of type
/// `value`: its own type when written, else its element of the tuple.
fn destructured(bindings: &[ast::DestructureBinding], value: Option<Ty>, span: Span) -> Option<Ty> {
    let mut stack = vec![(bindings, value)];
    while let Some((bindings, value)) = stack.pop() {
        for (i, b) in bindings.iter().enumerate() {
            let element = value.as_ref().filter(|t| t.name == ast::TUPLE_TYPE).and_then(|t| t.args.get(i).cloned());
            if b.nested.is_empty() && b.name_span == span {
                return if b.type_name.name == ast::AUTO_TYPE { element } else { Some(Ty::from_ast(&b.type_name)) };
            }
            if !b.nested.is_empty() {
                stack.push((&b.nested, element));
            }
        }
    }
    None
}

/// Where `expr`'s text starts (see `expr_start`).
fn expression_start(expr: &ast::Expression) -> usize {
    crate::expr_start(expr)
}

//! `static (captures) { ... }` blocks: compile-time work and reflection
//! (`docs/src/language/reflection.md`).
//!
//! The builder (`builder/static_items.rs`) keeps a block as a
//! [`StaticBlock`]: compile-time steps as written, and the statements to
//! emit with placeholders for the compile-time values in them. [`expand`]
//! replaces each block in concrete code with what it emits: it runs the
//! compile-time steps (unrolling a `for` over `reflect.properties<T>()`,
//! choosing a branch of a compile-time `if`), and fills in each emitted
//! statement's placeholders (`field.name` becomes a string literal,
//! `field.get(value)` becomes `value.x`). A block in a generic base waits
//! until a specialization clones it with its type arguments
//! ([`StaticBlock::substitute`]); the transform passes call [`expand`] again
//! after each round of specialization, like C++ templates and Zig.
//!
//! The compile-time language is small: literals, operators, `var`, `if`,
//! `for` over a list, interpolated strings, the `reflect` functions and the
//! members and methods of what they return. It cannot call other functions
//! yet.

use crate::builder::{INTERPOLATE, REFLECT};
use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc};
use pepper_parser::namespace::{demangle, demangle_name};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// The attributes the compiler gives a meaning to. Any other attribute
/// must name an `[Attribute]` struct.
pub const BUILT_IN_ATTRIBUTES: &[&str] = &[
    "Alias",
    "Attribute",
    "Deprecated",
    "Export",
    "Implicit",
    "Isolated",
    "Link",
    "LinkName",
    "Locked",
    "Move",
    "MoveSource",
    "NotCopyable",
    "Rename",
    "Sending",
    "Shared",
    "Target",
    "Value",
];

/// The attribute that makes a struct an attribute.
pub const ATTRIBUTE_ATTRIBUTE: &str = "Attribute";

/// How many times a compile-time `while` may run before it is taken to be
/// endless.
const MAX_ITERATIONS: usize = 100_000;

/// Whether `module` has a `static` block anywhere, so a pass that expands
/// them can return at once when it has not.
fn has_static(block: &Block) -> bool {
    block.items.iter().any(|stmt| match stmt {
        Statement::Static(_) => true,
        Statement::Block(inner) => has_static(inner),
        Statement::Branch(branch) => has_static(&branch.if_block) || branch.else_block.as_ref().is_some_and(has_static),
        Statement::While(wh) => has_static(&wh.block),
        _ => false,
    })
}

/// A generic struct as declared, not one of its specializations.
fn is_generic_base(st: &StructDef) -> bool {
    st.ty.is_generic() && st.name == st.ty.name
}

/// Where a body with a `static` block is.
enum Site {
    Function(usize),
    Method(usize, usize),
    Constructor(usize, usize),
    Destructor(usize),
}

/// Expands every `static` block in concrete code: free functions that are
/// not generic, and the methods, constructors and destructors of structs
/// that are not. `lowered` says the bodies have been through the passes
/// that lower string literals, so a string the block emits is lowered too.
/// Returns whether any block was expanded.
pub fn expand(module: &mut Module, lowered: bool) -> bool {
    let body_has_static = |f: &FunctionDef| f.body.as_ref().is_some_and(has_static);
    let mut sites = vec![];
    for (i, function) in module.functions.iter().enumerate() {
        if !function.is_generic_func && body_has_static(function) {
            sites.push(Site::Function(i));
        }
    }
    for (s, st) in module.structs.iter().enumerate() {
        if is_generic_base(st) {
            continue;
        }
        for (m, method) in st.method_members.iter().enumerate() {
            if body_has_static(method) {
                sites.push(Site::Method(s, m));
            }
        }
        for (c, constructor) in st.constructors.iter().enumerate() {
            if body_has_static(constructor) {
                sites.push(Site::Constructor(s, c));
            }
        }
        if body_has_static(&st.destructor) {
            sites.push(Site::Destructor(s));
        }
    }
    if sites.is_empty() {
        return false;
    }
    let mut notes = vec![];
    for site in sites {
        let function = match site {
            Site::Function(i) => &mut module.functions[i],
            Site::Method(s, m) => &mut module.structs[s].method_members[m],
            Site::Constructor(s, c) => &mut module.structs[s].constructors[c],
            Site::Destructor(s) => &mut module.structs[s].destructor,
        };
        let Some(mut body) = function.body.take() else { continue };
        let context = Context::of(function, &body);
        let mut expander = Expander { module, lowered, context, type_map: vec![], file: FileId::default(), scopes: vec![], passes: vec![], notes: vec![], jump: None };
        expander.expand_in(&mut body);
        notes.append(&mut expander.notes);
        let function = match site {
            Site::Function(i) => &mut module.functions[i],
            Site::Method(s, m) => &mut module.structs[s].method_members[m],
            Site::Constructor(s, c) => &mut module.structs[s].constructors[c],
            Site::Destructor(s) => &mut module.structs[s].destructor,
        };
        function.body = Some(body);
    }
    module.warnings.append(&mut notes);
    true
}

/// Runs the module-scope `static` blocks and gives each constant one
/// declares the value the block computed, in place of the initializer the
/// parser gave it (the constant's own name). Runs before any other pass.
pub fn expand_module_blocks(module: &mut Module) {
    let blocks = std::mem::take(&mut module.static_blocks);
    let mut values = vec![];
    let mut notes = vec![];
    for block in &blocks {
        let context = Context { name: String::new(), symbol: String::new(), loc: block.block.loc, runtime: HashSet::new() };
        let mut expander =
            Expander { module, lowered: false, context, type_map: vec![], file: FileId::default(), scopes: vec![], passes: vec![], notes: vec![], jump: None };
        if let Err(error) = expander.expand(&block.block) {
            crate::errors::report(error);
            continue;
        }
        notes.append(&mut expander.notes);
        for (name, loc) in &block.constants {
            let written = ast::Expression::SymbolRef { id: name.clone(), span: loc.span };
            let value = expander.scopes[0].get(name).cloned().map(|value| expander.emitted(value, &written, *loc));
            match value {
                Some(Ok(value)) => values.push((*loc, value)),
                Some(Err(error)) => crate::errors::report(error),
                None => {}
            }
        }
    }
    for (loc, value) in values {
        if let Some(global) = module.globals.iter_mut().find(|g| g.loc == loc) {
            global.default = Some(value);
        }
    }
    module.warnings.append(&mut notes);
}

/// Removes the `static` blocks left in generic bases once every
/// specialization has been made: each specialization expanded its own copy,
/// and what a base's blocks emit was never typed, so the passes that check
/// whole bodies must not see it.
pub fn remove_from_generic_code(module: &mut Module) {
    fn strip(block: &mut Block) {
        for stmt in &mut block.items {
            match stmt {
                Statement::Static(_) => *stmt = Statement::Block(block_of(vec![])),
                Statement::Block(inner) => strip(inner),
                Statement::Branch(branch) => {
                    strip(&mut branch.if_block);
                    if let Some(else_block) = &mut branch.else_block {
                        strip(else_block);
                    }
                }
                Statement::While(wh) => strip(&mut wh.block),
                _ => {}
            }
        }
    }
    let functions = module.functions.iter_mut().chain(module.structs.iter_mut().flat_map(|st| {
        st.method_members.iter_mut().chain(st.constructors.iter_mut()).chain(st.generic_methods.iter_mut()).chain(std::iter::once(&mut st.destructor))
    }));
    let functions = functions.chain(module.traits.iter_mut().flat_map(|t| t.methods.iter_mut()));
    let functions = functions.chain(module.extensions.iter_mut().flat_map(|e| e.methods.iter_mut()));
    for function in functions {
        if let Some(body) = &mut function.body
            && has_static(body)
        {
            strip(body);
        }
    }
}

/// The function a block is expanded in.
struct Context {
    /// Its name as the user wrote it (`to_json<Point>`).
    name: String,
    /// Its name in the model, which [`Module::spec_requests`] is keyed by.
    symbol: String,
    loc: Loc,
    /// Its parameters and locals: runtime values a block must capture.
    runtime: HashSet<String>,
}

impl Context {
    fn of(function: &FunctionDef, body: &Block) -> Context {
        let mut runtime: HashSet<String> = function.parameters.iter().map(|p| p.name.trim_start_matches("this.").to_string()).collect();
        runtime.insert("this".to_string());
        collect_locals(body, &mut runtime);
        Context { name: demangle(&function.name).into_owned(), symbol: function.name.clone(), loc: function.loc, runtime }
    }
}

fn collect_locals(block: &Block, out: &mut HashSet<String>) {
    for stmt in &block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                out.insert(var.name.clone());
            }
            Statement::Block(inner) => collect_locals(inner, out),
            Statement::Branch(branch) => {
                collect_locals(&branch.if_block, out);
                if let Some(else_block) = &branch.else_block {
                    collect_locals(else_block, out);
                }
            }
            Statement::While(wh) => collect_locals(&wh.block, out),
            _ => {}
        }
    }
}

// ── Compile-time values ─────────────────────────────────────────────────────

/// A value a `static` block computes.
#[derive(Clone, Debug)]
enum Value {
    Int(i64),
    Float(f64),
    Bool(bool),
    String(String),
    /// An enum case: from `reflect.cases<E>()`, or written as `E.Case`.
    Case(Rc<Case>),
    /// A field or property, from `reflect.properties<T>()` or `fields<T>()`.
    Member(Rc<Member>),
    /// A function, from `reflect.functions_with<A>()`.
    Function(Rc<Function>),
    List(Rc<Vec<Value>>),
    /// An attribute's values, from `attribute<A>()`.
    Attribute(Rc<Attribute>),
}

#[derive(Debug)]
struct Member {
    name: String,
    /// The field `get` reads, when it is not `name`: a case's value is
    /// stored in `Case.value` ([`payload_field`]).
    field: Option<String>,
    ty: TypeName,
    index: usize,
    count: usize,
    is_const: bool,
    is_property: bool,
    attributes: Vec<ast::Attribute>,
    /// The file the attributes are written in.
    file: FileId,
}

#[derive(Debug)]
struct Case {
    /// The enum's type.
    enumeration: TypeName,
    name: String,
    /// The case's value (a value enum), or its tag (a reference enum).
    value: i64,
    index: usize,
    count: usize,
    /// A case of an enum with no values, which emitted code can name.
    is_value: bool,
    /// The values the case carries, as members whose `get` reads them.
    values: Vec<Value>,
    attributes: Vec<ast::Attribute>,
    file: FileId,
}

#[derive(Debug)]
struct Function {
    /// The function's name in the model, which a call uses.
    symbol: String,
    attributes: Vec<ast::Attribute>,
    file: FileId,
}

#[derive(Debug)]
struct Attribute {
    /// The attribute struct's name.
    ty: String,
    fields: Vec<(String, Value)>,
}

impl Value {
    /// What the value is, for messages.
    fn kind(&self) -> &'static str {
        match self {
            Value::Int(_) => "integer",
            Value::Float(_) => "floating-point number",
            Value::Bool(_) => "bool",
            Value::String(_) => "string",
            Value::Case(_) => "enum case",
            Value::Member(_) => "member",
            Value::Function(_) => "function",
            Value::List(_) => "list",
            Value::Attribute(_) => "attribute",
        }
    }

    /// [`Value::kind`] with its article: "an enum case".
    fn kind_with_article(&self) -> String {
        let kind = self.kind();
        let article = if kind.starts_with(['a', 'e', 'i', 'o', 'u']) { "an" } else { "a" };
        format!("{} {}", article, kind)
    }

    /// The value as `reflect.print` and an interpolated string show it.
    fn display(&self) -> String {
        match self {
            Value::Int(v) => v.to_string(),
            Value::Float(v) => v.to_string(),
            Value::Bool(v) => v.to_string(),
            Value::String(v) => v.clone(),
            Value::Case(case) => format!("{}.{}", demangle(&case.enumeration.display()), case.name),
            Value::Member(member) => member.name.clone(),
            Value::Function(function) => demangle_name(&function.symbol).to_string(),
            Value::List(items) => format!("[{}]", items.iter().map(Value::display).collect::<Vec<_>>().join(", ")),
            Value::Attribute(attribute) => {
                let fields: Vec<String> = attribute.fields.iter().map(|(name, value)| format!("{} = {}", name, value.quoted())).collect();
                format!("{}({})", demangle_name(&attribute.ty), fields.join(", "))
            }
        }
    }

    /// [`Value::display`], with a string in quotes.
    fn quoted(&self) -> String {
        match self {
            Value::String(v) => format!("{:?}", v),
            other => other.display(),
        }
    }

    fn equals(&self, other: &Value) -> Option<bool> {
        Some(match (self, other) {
            (Value::Int(a), Value::Int(b)) => a == b,
            (Value::Float(a), Value::Float(b)) => a == b,
            (Value::Int(a), Value::Float(b)) | (Value::Float(b), Value::Int(a)) => (*a as f64) == *b,
            (Value::Bool(a), Value::Bool(b)) => a == b,
            (Value::String(a), Value::String(b)) => a == b,
            (Value::Case(a), Value::Case(b)) => a.enumeration.name == b.enumeration.name && a.value == b.value,
            _ => return None,
        })
    }

    fn attributes(&self) -> Option<(&[ast::Attribute], FileId)> {
        match self {
            Value::Member(member) => Some((&member.attributes, member.file)),
            Value::Case(case) => Some((&case.attributes, case.file)),
            Value::Function(function) => Some((&function.attributes, function.file)),
            _ => None,
        }
    }
}

// ── Expansion ───────────────────────────────────────────────────────────────

type Result<T> = std::result::Result<T, Diagnostic>;

struct Expander<'m> {
    module: &'m Module,
    lowered: bool,
    context: Context,
    /// The block's type arguments (`T` → `Point`).
    type_map: Vec<(String, TypeName)>,
    /// The file the block is written in.
    file: FileId,
    /// The compile-time variables, innermost scope last.
    scopes: Vec<HashMap<String, Value>>,
    /// The `for` passes being expanded, outermost first: the loop's
    /// location, the pass's index and count, and its element.
    passes: Vec<(Loc, usize, usize, String)>,
    /// What `reflect.print` wrote.
    notes: Vec<Diagnostic>,
    /// A compile-time `break` or `continue` that ran and has not yet reached
    /// its loop: the statements after it are skipped.
    jump: Option<ast::LoopBreakKind>,
}

impl Expander<'_> {
    /// Replaces each `static` block in `block` with what it emits. An error
    /// is reported, and the block emits nothing.
    fn expand_in(&mut self, block: &mut Block) {
        for stmt in &mut block.items {
            match stmt {
                Statement::Static(static_block) => {
                    let static_block = std::mem::replace(static_block, Box::new(empty_static()));
                    *stmt = match self.expand(&static_block) {
                        Ok(expanded) => Statement::Block(expanded),
                        Err(error) => {
                            crate::errors::report(error);
                            Statement::Block(block_of(vec![]))
                        }
                    };
                }
                Statement::Block(inner) => self.expand_in(inner),
                Statement::Branch(branch) => {
                    self.expand_in(&mut branch.if_block);
                    if let Some(else_block) = &mut branch.else_block {
                        self.expand_in(else_block);
                    }
                }
                Statement::While(wh) => self.expand_in(&mut wh.block),
                _ => {}
            }
        }
    }

    fn expand(&mut self, block: &StaticBlock) -> Result<Block> {
        self.type_map = block.type_map.clone();
        self.file = block.loc.file;
        self.scopes = vec![HashMap::new()];
        self.passes.clear();
        self.jump = None;
        let items = self.items(&block.items).map_err(|error| {
            let mut error = error;
            if !self.context.name.is_empty() {
                error = error.with_note(format!("in the static block of '{}'", self.context.name), Some(self.context.loc));
                error = self.with_requests(error);
            }
            error
        })?;
        Ok(block_of(items))
    }

    /// `error` with a note for each specialization that led to the one
    /// being expanded, back to the code that is not generic: where the user
    /// called `json.encode(job)`, for an error in `_to_json<Job>`.
    fn with_requests(&self, mut error: Diagnostic) -> Diagnostic {
        let mut name = crate::passes::gather_generics::parse_type_string(&self.context.symbol).to_string();
        let mut shown: Vec<String> = vec![];
        while let Some(request) = self.module.spec_requests.get(&name) {
            if shown.contains(&request.by) || shown.len() >= crate::passes::gather_generics::MAX_SPECIALIZATION_DEPTH {
                break;
            }
            shown.push(request.by.clone());
            error = error.with_note(format!("'{}' is used by '{}' here", demangle(&name), demangle(&request.by)), Some(request.loc));
            name = request.by.clone();
        }
        error
    }

    fn at(&self, span: ast::Span) -> Loc {
        Loc::new(self.file, span)
    }

    /// `error` at `span`, with a note for each `for` pass being expanded.
    fn error(&self, message: impl Into<String>, span: ast::Span) -> Diagnostic {
        self.with_passes(Diagnostic::error(message).at(self.at(span)))
    }

    fn with_passes(&self, mut diagnostic: Diagnostic) -> Diagnostic {
        for (loc, index, count, element) in self.passes.iter().rev() {
            let note = if element.is_empty() {
                format!("in iteration {} of the compile-time 'while'", index + 1)
            } else {
                format!("in pass {} of {} ({})", index + 1, count, element)
            };
            diagnostic = diagnostic.with_note(note, Some(*loc));
        }
        diagnostic
    }

    fn scoped<T>(&mut self, run: impl FnOnce(&mut Self) -> T) -> T {
        self.scopes.push(HashMap::new());
        let result = run(self);
        self.scopes.pop();
        result
    }

    fn items(&mut self, items: &[StaticItem]) -> Result<Vec<Statement>> {
        let mut out = vec![];
        for item in items {
            match item {
                StaticItem::For { name, iterable, body, loc } => {
                    let list = match self.evaluate(iterable)? {
                        Value::List(list) => list,
                        other => {
                            return Err(self.error(
                                format!("a 'for' in a 'static' block needs a compile-time list, such as 'reflect.properties<T>()'; this is a {}", other.kind()),
                                iterable.span(),
                            ))
                        }
                    };
                    for (index, element) in list.iter().enumerate() {
                        self.passes.push((*loc, index, list.len(), format!("{} '{}'", element.kind(), element.display())));
                        let pass = self.scoped(|this| {
                            this.scopes.last_mut().unwrap().insert(name.clone(), element.clone());
                            this.items(body)
                        });
                        self.passes.pop();
                        out.push(Statement::Block(block_of(pass?)));
                        if self.jump.take() == Some(ast::LoopBreakKind::Break) {
                            break;
                        }
                    }
                }
                StaticItem::While { condition, body, loc } => {
                    let mut iteration = 0;
                    loop {
                        let keep_going = match self.evaluate(condition)? {
                            Value::Bool(value) => value,
                            other => {
                                return Err(self.error(format!("a compile-time condition must be a 'bool', not a {}", other.kind()), condition.span()))
                            }
                        };
                        if !keep_going {
                            break;
                        }
                        if iteration == MAX_ITERATIONS {
                            let message = format!("a compile-time 'while' ran {} times; is its condition ever false?", MAX_ITERATIONS);
                            return Err(self.with_passes(Diagnostic::error(message).at(*loc)));
                        }
                        self.passes.push((*loc, iteration, 0, String::new()));
                        let pass = self.scoped(|this| this.items(body));
                        self.passes.pop();
                        let pass = pass?;
                        if !pass.is_empty() {
                            out.push(Statement::Block(block_of(pass)));
                        }
                        iteration += 1;
                        if self.jump.take() == Some(ast::LoopBreakKind::Break) {
                            break;
                        }
                    }
                }
                StaticItem::Jump { kind, .. } => {
                    self.jump = Some(*kind);
                    return Ok(out);
                }
                StaticItem::If { condition, then_items, else_items, .. } => {
                    let taken = match self.evaluate(condition)? {
                        Value::Bool(value) => value,
                        other => return Err(self.error(format!("a compile-time condition must be a 'bool', not a {}", other.kind()), condition.span())),
                    };
                    let branch = if taken { then_items } else { else_items };
                    let expanded = self.scoped(|this| this.items(branch))?;
                    out.push(Statement::Block(block_of(expanded)));
                }
                StaticItem::EmitIf { condition, then_items, else_items } => {
                    let mut condition = condition.clone();
                    self.fill_expression(&mut condition)?;
                    let if_block = block_of(self.scoped(|this| this.items(then_items))?);
                    let else_block = if else_items.is_empty() { None } else { Some(block_of(self.scoped(|this| this.items(else_items))?)) };
                    out.push(Statement::Branch(Branch { condition, if_block, else_block }));
                }
                StaticItem::Block(inner) => {
                    let expanded = self.scoped(|this| this.items(inner))?;
                    out.push(Statement::Block(block_of(expanded)));
                }
                StaticItem::Var { name, value, .. } => {
                    let value = self.evaluate(value)?;
                    self.scopes.last_mut().unwrap().insert(name.clone(), value);
                }
                StaticItem::Evaluate(expr) => {
                    self.evaluate(expr)?;
                }
                StaticItem::Emit(stmt) => {
                    let mut stmt = stmt.clone();
                    self.fill_statement(&mut stmt)?;
                    out.push(stmt);
                }
            }
            if self.jump.is_some() {
                break;
            }
        }
        Ok(out)
    }

    /// The `x.Type` types of the members in scope.
    fn member_types(&self) -> Vec<(String, TypeName)> {
        let mut types = vec![];
        for scope in &self.scopes {
            for (name, value) in scope {
                if let Value::Member(member) = value {
                    types.retain(|(spelled, _)| spelled != &format!("{}.Type", name));
                    types.push((format!("{}.Type", name), member.ty.clone()));
                }
            }
        }
        types
    }

    /// Fills in an emitted statement: the members' types, then the
    /// placeholders.
    fn fill_statement(&mut self, stmt: &mut Statement) -> Result<()> {
        let types = self.member_types();
        if !types.is_empty() {
            let mut holder = block_of(vec![std::mem::replace(stmt, Statement::Block(block_of(vec![])))]);
            crate::passes::specialize_functions::replace_body_types(&mut holder, &types);
            *stmt = holder.items.pop().unwrap();
        }
        let mut error = None;
        crate::passes::walk_statement(stmt, &mut |e| {
            if error.is_none()
                && let Err(failed) = self.fill(e)
            {
                error = Some(failed);
            }
        });
        error.map_or(Ok(()), Err)
    }

    fn fill_expression(&mut self, expr: &mut Expression) -> Result<()> {
        let mut holder = Statement::Expression(std::mem::replace(expr, Expression::NoMatch));
        let result = self.fill_statement(&mut holder);
        let Statement::Expression(filled) = holder else { unreachable!() };
        *expr = filled;
        result
    }

    /// Replaces a placeholder with what it stands for.
    fn fill(&mut self, expr: &mut Expression) -> Result<()> {
        match expr {
            Expression::StaticValue(placeholder) => {
                let value = self.evaluate(&placeholder.expr)?;
                *expr = self.emitted(value, &placeholder.expr, placeholder.loc)?;
            }
            Expression::StaticMember(placeholder) => {
                let receiver = self.evaluate(&placeholder.member)?;
                let StaticMember { method, args, loc, member } = &mut **placeholder;
                let loc = *loc;
                let mut args = std::mem::take(args);
                let span = loc.span;
                let arity = |this: &Self, want: usize| -> Result<()> {
                    if args.len() == want {
                        Ok(())
                    } else {
                        Err(this.error(format!("'{}' takes {} argument{}, have {}", method, want, if want == 1 { "" } else { "s" }, args.len()), span))
                    }
                };
                *expr = match (&receiver, method.as_str()) {
                    (Value::Member(m), "get") => {
                        arity(self, 1)?;
                        Expression::MemberRef { lhs: Box::new(args.remove(0)), name: m.field.clone().unwrap_or_else(|| m.name.clone()), loc }
                    }
                    (Value::Member(m), "set") if m.field.is_some() => {
                        return Err(self.error(format!("'set' cannot change value '{}': a case's values are fixed once made", m.name), span));
                    }
                    (Value::Member(m), "set") => {
                        arity(self, 2)?;
                        let value = args.remove(1);
                        let target = Expression::MemberRef { lhs: Box::new(args.remove(0)), name: m.name.clone(), loc };
                        Expression::Binary { op: BinaryOp::Assign, lhs: Box::new(target), rhs: Box::new(value), loc }
                    }
                    (Value::Function(f), "call") => Expression::FunctionCall { function: f.symbol.clone(), args, loc },
                    (Value::Case(case), "get") if case.is_value => {
                        arity(self, 0)?;
                        Expression::Cast { expr: Box::new(Expression::IntLiteral(case.value)), ty: case.enumeration.clone(), loc: Loc::NONE, kind: CastKind::Synthesized }
                    }
                    (Value::Case(case), "matches") => {
                        arity(self, 1)?;
                        let subject = args.remove(0);
                        let test = if case.is_value {
                            Expression::Cast { expr: Box::new(Expression::IntLiteral(case.value)), ty: case.enumeration.clone(), loc: Loc::NONE, kind: CastKind::Synthesized }
                        } else {
                            Expression::IntLiteral(case.value)
                        };
                        let lhs = if case.is_value { subject } else { Expression::MemberRef { lhs: Box::new(subject), name: TAG_FIELD.to_string(), loc } };
                        Expression::Binary { op: BinaryOp::Equal, lhs: Box::new(lhs), rhs: Box::new(test), loc }
                    }
                    // `Shape.Circle(r)`: the case's static method makes it.
                    (Value::Case(case), "get") => {
                        if args.len() != case.values.len() {
                            return Err(self.error(
                                format!("'get' of case '{}' takes {} value{}, have {}", case.name, case.values.len(), if case.values.len() == 1 { "" } else { "s" }, args.len()),
                                span,
                            ));
                        }
                        let this = Expression::SymbolRef { id: case.enumeration.to_string(), ty: case.enumeration.clone(), loc };
                        Expression::MethodCall { this: Box::new(this), method: case.name.clone(), args, loc }
                    }
                    _ => {
                        let _ = member;
                        return Err(self.error(format!("no method named '{}' on a compile-time {}", method, receiver.kind()), span));
                    }
                };
            }
            _ => {}
        }
        Ok(())
    }

    /// `value` as an expression in emitted code.
    fn emitted(&self, value: Value, written: &ast::Expression, loc: Loc) -> Result<Expression> {
        Ok(match value {
            Value::Int(v) => Expression::IntLiteral(v),
            Value::Float(v) => Expression::FloatLiteral(v),
            Value::Bool(v) => Expression::BoolLiteral(v),
            Value::String(v) => {
                let mut literal = Expression::StringLiteral { value: v, is_raw: false, loc };
                if self.lowered {
                    crate::passes::convert_string_literals::convert(&mut literal);
                }
                literal
            }
            Value::Case(case) if case.is_value => Expression::Cast { expr: Box::new(Expression::IntLiteral(case.value)), ty: case.enumeration.clone(), loc: Loc::NONE, kind: CastKind::Synthesized },
            other => {
                return Err(self.error(
                    format!(
                        "'{}' is a compile-time {}, which emitted code cannot use; emitted code can use numbers, 'bool', strings and enum cases",
                        written,
                        other.kind()
                    ),
                    written.span(),
                ))
            }
        })
    }

    // ── Evaluation ──────────────────────────────────────────────────────────

    fn lookup(&self, name: &str) -> Option<&Value> {
        self.scopes.iter().rev().find_map(|scope| scope.get(name))
    }

    fn evaluate(&mut self, expr: &ast::Expression) -> Result<Value> {
        use ast::Expression as E;
        match expr {
            E::Literal { value, span } => Ok(match value {
                ast::Literal::Integer(v) => Value::Int(*v),
                ast::Literal::Float(v) => Value::Float(*v),
                ast::Literal::Bool(v) => Value::Bool(*v),
                ast::Literal::String(v) => Value::String(v.clone()),
                ast::Literal::Char(v) => Value::Int(*v as i64),
                ast::Literal::Null => return Err(self.error("'__null' has no compile-time value", *span)),
            }),
            E::SymbolRef { id, span } => {
                if let Some(value) = self.lookup(id) {
                    return Ok(value.clone());
                }
                if id == REFLECT {
                    return Err(self.error("'reflect' is used through its functions, such as 'reflect.properties<T>()'", *span));
                }
                if self.context.runtime.contains(id) {
                    return Err(self.error(format!("'{}' is a runtime value; add it to the static block's capture list", id), *span));
                }
                Err(self.error(format!("'{}' has no compile-time value", demangle(id)), *span))
            }
            E::Unary { op, operand, span, .. } => {
                let value = self.evaluate(operand)?;
                match (op.as_str(), &value) {
                    ("!", Value::Bool(v)) => Ok(Value::Bool(!v)),
                    ("-", Value::Int(v)) => Ok(Value::Int(-v)),
                    ("-", Value::Float(v)) => Ok(Value::Float(-v)),
                    _ => Err(self.error(format!("operator '{}' cannot be applied to a compile-time {}", op, value.kind()), *span)),
                }
            }
            E::Binary { lhs, op, rhs, span } => self.binary(lhs, op, rhs, *span),
            E::Ternary { condition, true_expr, false_expr, span } => match self.evaluate(condition)? {
                Value::Bool(true) => self.evaluate(true_expr),
                Value::Bool(false) => self.evaluate(false_expr),
                other => Err(self.error(format!("a compile-time condition must be a 'bool', not a {}", other.kind()), *span)),
            },
            E::Index { lhs, rhs, span } => {
                let list = self.evaluate(lhs)?;
                let index = self.evaluate(rhs)?;
                match (&list, &index) {
                    (Value::List(items), Value::Int(i)) => {
                        let found = usize::try_from(*i).ok().and_then(|i| items.get(i));
                        found.cloned().ok_or_else(|| self.error(format!("index {} is out of range for a list of {}", i, items.len()), *span))
                    }
                    _ => Err(self.error(format!("a compile-time {} cannot be indexed by a {}", list.kind(), index.kind()), *span)),
                }
            }
            E::MemberAccess { lhs, name, name_span, .. } => {
                if let E::SymbolRef { id, .. } = lhs.as_ref()
                    && self.lookup(id).is_none()
                    && let Some(case) = self.enum_case(id, name)
                {
                    return Ok(case);
                }
                let value = self.evaluate(lhs)?;
                self.member(&value, name, *name_span)
            }
            E::FunctionCall { function, arguments, .. } => self.call(function, arguments),
            E::TypeLiteral(ty) => Err(self.error(format!("'{}' is missing '()'", ty), ty.span)),
            other => Err(self.error("this expression cannot be evaluated at compile time", other.span())),
        }
    }

    /// `E.Case` for a value enum `E`.
    fn enum_case(&self, enumeration: &str, name: &str) -> Option<Value> {
        let def = self.find_enum(enumeration)?;
        let index = def.cases.iter().position(|c| c.name == name)?;
        Some(Value::Case(Rc::new(case_of(def, index))))
    }

    fn find_enum(&self, name: &str) -> Option<&EnumDef> {
        self.module
            .enums
            .iter()
            .find(|e| e.name == name)
            .or_else(|| prefer_file(self.module.enums.iter().filter(|e| demangle_name(&e.name) == name), |e| e.loc.file, self.file))
    }

    fn binary(&mut self, lhs: &ast::Expression, op: &str, rhs: &ast::Expression, span: ast::Span) -> Result<Value> {
        if let Some(arithmetic) = op.strip_suffix('=').filter(|o| ["", "+", "-", "*", "/", "%"].contains(o)) {
            let ast::Expression::SymbolRef { id, span: name_span } = lhs else {
                return Err(self.error("only a compile-time variable can be assigned in a 'static' block", lhs.span()));
            };
            if self.lookup(id).is_none() {
                return self.evaluate(lhs);
            }
            let value = if arithmetic.is_empty() { self.evaluate(rhs)? } else { self.binary(lhs, arithmetic, rhs, span)? };
            let scope = self.scopes.iter_mut().rev().find(|scope| scope.contains_key(id)).unwrap();
            scope.insert(id.clone(), value.clone());
            let _ = name_span;
            return Ok(value);
        }
        if op == "&&" || op == "||" {
            let left = self.condition(lhs)?;
            if left == (op == "||") {
                return Ok(Value::Bool(left));
            }
            return Ok(Value::Bool(self.condition(rhs)?));
        }
        let left = self.evaluate(lhs)?;
        let right = self.evaluate(rhs)?;
        let mismatch = |this: &Self| {
            this.error(format!("operator '{}' cannot be applied to a compile-time {} and {}", op, left.kind(), right.kind()), span)
        };
        Ok(match op {
            "==" | "!=" => match left.equals(&right) {
                Some(same) => Value::Bool(same == (op == "==")),
                None => return Err(mismatch(self)),
            },
            "<" | "<=" | ">" | ">=" => {
                let ordering = match (&left, &right) {
                    (Value::Int(a), Value::Int(b)) => a.cmp(b),
                    (Value::String(a), Value::String(b)) => a.cmp(b),
                    (Value::Float(_) | Value::Int(_), Value::Float(_) | Value::Int(_)) => {
                        let (a, b) = (as_float(&left), as_float(&right));
                        a.partial_cmp(&b).unwrap_or(std::cmp::Ordering::Equal)
                    }
                    _ => return Err(mismatch(self)),
                };
                Value::Bool(match op {
                    "<" => ordering.is_lt(),
                    "<=" => ordering.is_le(),
                    ">" => ordering.is_gt(),
                    _ => ordering.is_ge(),
                })
            }
            "+" | "-" | "*" | "/" | "%" => match (&left, &right) {
                (Value::String(a), Value::String(b)) if op == "+" => Value::String(format!("{}{}", a, b)),
                (Value::Int(a), Value::Int(b)) => {
                    let result = match op {
                        "+" => a.checked_add(*b),
                        "-" => a.checked_sub(*b),
                        "*" => a.checked_mul(*b),
                        "/" => a.checked_div(*b),
                        _ => a.checked_rem(*b),
                    };
                    match result {
                        Some(v) => Value::Int(v),
                        None if *b == 0 && (op == "/" || op == "%") => return Err(self.error("division by zero in a 'static' block", span)),
                        None => return Err(self.error("integer overflow in a 'static' block", span)),
                    }
                }
                (Value::Float(_) | Value::Int(_), Value::Float(_) | Value::Int(_)) => {
                    let (a, b) = (as_float(&left), as_float(&right));
                    Value::Float(match op {
                        "+" => a + b,
                        "-" => a - b,
                        "*" => a * b,
                        "/" => a / b,
                        _ => a % b,
                    })
                }
                _ => return Err(mismatch(self)),
            },
            _ => return Err(self.error(format!("operator '{}' is not supported in a 'static' block", op), span)),
        })
    }

    fn condition(&mut self, expr: &ast::Expression) -> Result<bool> {
        match self.evaluate(expr)? {
            Value::Bool(value) => Ok(value),
            other => Err(self.error(format!("a compile-time condition must be a 'bool', not a {}", other.kind()), expr.span())),
        }
    }

    /// `value.name`.
    fn member(&self, value: &Value, name: &str, span: ast::Span) -> Result<Value> {
        let found = match (value, name) {
            (Value::Member(m), "name") => Some(Value::String(m.name.clone())),
            (Value::Member(m), "index") => Some(Value::Int(m.index as i64)),
            (Value::Member(m), "is_last") => Some(Value::Bool(m.index + 1 == m.count)),
            (Value::Member(m), "type_name") => Some(Value::String(demangle(&m.ty.display()).into_owned())),
            (Value::Member(m), "is_const") => Some(Value::Bool(m.is_const)),
            (Value::Member(m), "is_property") => Some(Value::Bool(m.is_property)),
            (Value::Case(c), "name") => Some(Value::String(c.name.clone())),
            (Value::Case(c), "value") => Some(Value::Int(c.value)),
            (Value::Case(c), "index") => Some(Value::Int(c.index as i64)),
            (Value::Case(c), "is_last") => Some(Value::Bool(c.index + 1 == c.count)),
            (Value::Case(c), "values") => Some(Value::List(Rc::new(c.values.clone()))),
            (Value::Function(f), "name") => Some(Value::String(demangle_name(&f.symbol).to_string())),
            (Value::List(items), "count") => Some(Value::Int(items.len() as i64)),
            (Value::List(items), "is_empty") => Some(Value::Bool(items.is_empty())),
            (Value::String(s), "length") => Some(Value::Int(s.chars().count() as i64)),
            (Value::String(s), "is_empty") => Some(Value::Bool(s.is_empty())),
            (Value::Attribute(a), field) => a.fields.iter().find(|(n, _)| n == field).map(|(_, v)| v.clone()),
            _ => None,
        };
        found.ok_or_else(|| {
            let what = match value {
                Value::Attribute(a) => format!("attribute '{}'", demangle_name(&a.ty)),
                other => format!("compile-time {}", other.kind()),
            };
            self.error(format!("no member named '{}' in {}", name, what), span)
        })
    }

    /// The type `ty` names in the block: its type arguments substituted,
    /// `field.Type` resolved, `T[]` spelled `Array<T>`.
    fn resolve_type(&self, ty: &TypeName) -> TypeName {
        if let Some(base) = ty.name.strip_suffix("[]") {
            let mut element = ty.clone();
            element.name = base.to_string();
            return TypeName::with_args("Array", vec![self.resolve_type(&element)]);
        }
        if let Some(variable) = ty.name.strip_suffix(".Type")
            && let Some(Value::Member(member)) = self.lookup(variable)
        {
            return member.ty.clone();
        }
        let mut resolved = ty.clone();
        resolved.sub_types = ty.sub_types.iter().map(|t| self.resolve_type(t)).collect();
        if resolved.sub_types.is_empty() {
            crate::type_name::replace_map(&mut resolved, &self.type_map);
        } else {
            for (param, arg) in &self.type_map {
                if &resolved.name == param {
                    let args = std::mem::take(&mut resolved.sub_types);
                    resolved = arg.clone();
                    resolved.sub_types.extend(args);
                }
            }
        }
        resolved
    }

    fn from_ast(&self, ty: &ast::TypeName) -> TypeName {
        let args: Vec<TypeName> = ty.generic_types.iter().map(|t| self.from_ast(t)).collect();
        self.resolve_type(&if args.is_empty() { TypeName::new(&ty.name) } else { TypeName::with_args(&ty.name, args) })
    }

    /// A call in a `static` block: a `reflect` function, a method of a
    /// compile-time value, or `$"..."`'s conversion.
    fn call(&mut self, function: &ast::Expression, arguments: &[ast::Expression]) -> Result<Value> {
        use ast::Expression as E;
        let reflect_in_scope = self.lookup(REFLECT).is_none();
        match function {
            E::SymbolRef { id, .. } if id == INTERPOLATE && arguments.len() == 1 => Ok(Value::String(self.evaluate(&arguments[0])?.display())),
            E::MemberAccess { lhs, name, name_span, .. } => {
                let spelled = crate::passes::gather_generics::parse_type_string(name);
                let type_args: Vec<TypeName> = spelled.sub_types.iter().map(|t| self.resolve_type(t)).collect();
                if matches!(lhs.as_ref(), E::SymbolRef { id, .. } if id == REFLECT) && reflect_in_scope {
                    return self.reflect(&spelled.name, &type_args, arguments, *name_span);
                }
                let receiver = self.evaluate(lhs)?;
                self.method(&receiver, &spelled.name, &type_args, arguments, *name_span)
            }
            E::TypeLiteral(ty) if ty.name.contains('.') => {
                let (root, name) = ty.name.split_once('.').unwrap();
                let type_args: Vec<TypeName> = ty.generic_types.iter().map(|t| self.from_ast(t)).collect();
                let name_span = ast::Span { start: ty.span.start + root.len() + 1, end: ty.span.start + root.len() + 1 + name.len() };
                if root == REFLECT && reflect_in_scope {
                    return self.reflect(name, &type_args, arguments, name_span);
                }
                let receiver = match self.lookup(root) {
                    Some(value) => value.clone(),
                    None => return Err(self.error(format!("'{}' has no compile-time value", root), ty.span)),
                };
                self.method(&receiver, name, &type_args, arguments, name_span)
            }
            other => {
                let name = match other {
                    E::SymbolRef { id, .. } => demangle(id).into_owned(),
                    E::TypeLiteral(ty) => ty.to_string(),
                    _ => other.to_string(),
                };
                Err(self
                    .error(format!("'{}' cannot be called at compile time", name), other.span())
                    .with_note("a 'static' block can call the 'reflect' functions and the methods of what they return; calling other functions at compile time is not supported yet", None))
            }
        }
    }

    fn expect_arguments(&self, name: &str, arguments: &[ast::Expression], want: usize, span: ast::Span) -> Result<()> {
        if arguments.len() != want {
            return Err(self.error(format!("'{}' takes {} argument{}, have {}", name, want, if want == 1 { "" } else { "s" }, arguments.len()), span));
        }
        Ok(())
    }

    fn expect_types<'t>(&self, name: &str, type_args: &'t [TypeName], want: usize, span: ast::Span) -> Result<&'t [TypeName]> {
        if type_args.len() != want {
            let names = ["T", "A"][..want.min(2)].join(", ");
            return Err(self.error(format!("'{}' takes {} type argument{}: 'reflect.{}<{}>()'", name, want, if want == 1 { "" } else { "s" }, name, names), span));
        }
        Ok(type_args)
    }

    /// `reflect.name<args>(arguments)`.
    fn reflect(&mut self, name: &str, type_args: &[TypeName], arguments: &[ast::Expression], span: ast::Span) -> Result<Value> {
        match name {
            "name" => {
                let [ty] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                Ok(Value::String(demangle(&ty.display()).into_owned()))
            }
            "properties" | "fields" => {
                let [ty] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                self.members(ty, name == "fields", span)
            }
            "cases" => {
                let [ty] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                self.cases(ty, span)
            }
            "functions_with" => {
                let [attribute] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                let attribute = self.attribute_struct_named(attribute, span)?;
                let mut functions: Vec<&FunctionDef> = self
                    .module
                    .functions
                    .iter()
                    .filter(|f| !f.is_generic_func)
                    .filter(|f| f.attributes.iter().any(|a| self.names_attribute(a, f.loc.file, &attribute)))
                    .collect();
                functions.sort_by_key(|f| (f.loc.file.0, f.loc.span.start));
                Ok(Value::List(Rc::new(
                    functions
                        .into_iter()
                        .map(|f| Value::Function(Rc::new(Function { symbol: f.name.clone(), attributes: f.attributes.clone(), file: f.loc.file })))
                        .collect(),
                )))
            }
            "is_struct" | "is_enum" | "is_trait" => {
                let [ty] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                let is_enum = self.find_enum(&ty.name).is_some() || self.find_struct(ty).is_some_and(|(st, _)| st.enum_cases.is_some());
                Ok(Value::Bool(match name {
                    "is_enum" => is_enum,
                    "is_struct" => !is_enum && self.find_struct(ty).is_some(),
                    _ => self.module.traits.iter().any(|t| t.name == ty.name),
                }))
            }
            "is_reference" => {
                let [ty] = self.expect_types(name, type_args, 1, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                Ok(Value::Bool(self.find_struct(ty).is_some_and(|(st, _)| !st.is_value())))
            }
            "is_same" => {
                let [a, b] = self.expect_types(name, type_args, 2, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                let canonical = crate::passes::check_function_types::canonical;
                Ok(Value::Bool(canonical(a) == canonical(b)))
            }
            "has_attribute" | "attribute" => {
                let [ty, attribute] = self.expect_types(name, type_args, 2, span)? else { unreachable!() };
                self.expect_arguments(name, arguments, 0, span)?;
                let (attributes, file) = if let Some((st, _)) = self.find_struct(ty) {
                    (&st.attributes, st.loc.file)
                } else if let Some(e) = self.find_enum(&ty.name) {
                    (&e.attributes, e.loc.file)
                } else {
                    return Err(self.error(format!("'{}' is not a struct or an enum", demangle(&ty.display())), span));
                };
                let attributes = attributes.clone();
                self.attribute_of(&attributes, file, attribute, name == "attribute", &format!("'{}'", demangle(&ty.display())), span)
            }
            "print" => {
                self.expect_arguments(name, arguments, 1, span)?;
                let value = self.evaluate(&arguments[0])?;
                let note = self.with_passes(Diagnostic::note(format!("static print: {}", value.quoted())).at(self.at(span)));
                self.notes.push(note);
                Ok(Value::Bool(true))
            }
            "error" => {
                self.expect_arguments(name, arguments, 1, span)?;
                let message = self.evaluate(&arguments[0])?.display();
                Err(self.error(message, span))
            }
            "assert" => {
                self.expect_arguments(name, arguments, 2, span)?;
                if self.condition(&arguments[0])? {
                    return Ok(Value::Bool(true));
                }
                let message = self.evaluate(&arguments[1])?.display();
                Err(self.error(message, arguments[0].span()))
            }
            _ => Err(self.error(format!("no function named '{}' in 'reflect'", name), span)),
        }
    }

    /// `value.name<type_args>(arguments)` on a compile-time value.
    fn method(&mut self, value: &Value, name: &str, type_args: &[TypeName], arguments: &[ast::Expression], span: ast::Span) -> Result<Value> {
        match name {
            "has_attribute" | "attribute" if value.attributes().is_some() => {
                let [attribute] = type_args else {
                    return Err(self.error(format!("'{}' takes one type argument: '{}<A>()'", name, name), span));
                };
                self.expect_arguments(name, arguments, 0, span)?;
                let (attributes, file) = value.attributes().unwrap();
                let attributes = attributes.to_vec();
                let what = format!("{} '{}'", value.kind(), value.display());
                self.attribute_of(&attributes, file, attribute, name == "attribute", &what, span)
            }
            "starts_with" | "ends_with" | "contains" if matches!(value, Value::String(_)) => {
                self.expect_arguments(name, arguments, 1, span)?;
                let Value::String(text) = value else { unreachable!() };
                let Value::String(part) = self.evaluate(&arguments[0])? else {
                    return Err(self.error(format!("'{}' takes a string", name), arguments[0].span()));
                };
                Ok(Value::Bool(match name {
                    "starts_with" => text.starts_with(&part),
                    "ends_with" => text.ends_with(&part),
                    _ => text.contains(&part),
                }))
            }
            // At module scope, where nothing is emitted, a case's `get()`
            // is the case itself.
            "get" if matches!(value, Value::Case(case) if case.is_value) && arguments.is_empty() => Ok(value.clone()),
            "get" | "set" | "call" if value.attributes().is_some() => Err(self.error(
                format!("'{}' emits code, so it can be used only in a statement that uses a captured value", name),
                span,
            )),
            _ => Err(self.error(format!("no method named '{}' on a compile-time {}", name, value.kind()), span)),
        }
    }

    // ── Reflection ──────────────────────────────────────────────────────────

    /// The struct `ty` names, with the type arguments to substitute in its
    /// fields when only its generic base exists yet.
    fn find_struct(&self, ty: &TypeName) -> Option<(&StructDef, Vec<(String, TypeName)>)> {
        let spelled = ty.to_string();
        if let Some(st) = self.module.structs.iter().find(|s| s.name == spelled) {
            return Some((st, vec![]));
        }
        let base = self.module.structs.iter().find(|s| s.name == ty.name && !s.generic_params.is_empty()).or_else(|| {
            if ty.sub_types.is_empty() {
                prefer_file(self.module.structs.iter().filter(|s| s.generic_params.is_empty() && demangle_name(&s.name) == ty.name), |s| s.loc.file, self.file)
            } else {
                None
            }
        })?;
        let map = base.generic_params.iter().map(|p| p.name.clone()).zip(ty.sub_types.iter().cloned()).collect();
        Some((base, map))
    }

    fn members(&self, ty: &TypeName, all: bool, span: ast::Span) -> Result<Value> {
        let shown = demangle(&ty.display()).into_owned();
        let Some((st, map)) = self.find_struct(ty) else {
            if self.find_enum(&ty.name).is_some() {
                return Err(self.error(format!("'{}' is an enum; use 'reflect.cases<{}>()'", shown, shown), span));
            }
            return Err(self.error(format!("'{}' is not a struct", shown), span));
        };
        if st.enum_cases.is_some() {
            return Err(self.error(format!("'{}' is an enum; use 'reflect.cases<{}>()'", shown, shown), span));
        }
        if all && st.loc.file != self.file {
            return Err(self
                .error(format!("'fields' of '{}' is only available in the file that declares '{}'; use 'properties'", shown, shown), span)
                .with_note(format!("'{}' declared here", shown), Some(st.loc)));
        }
        // (position, name, type, const, property, attributes)
        let mut found: Vec<(Loc, String, TypeName, bool, bool, Vec<ast::Attribute>)> = vec![];
        let owner = demangle_name(&st.ty.name);
        let properties: Vec<&PropertyDef> =
            self.module.properties.iter().filter(|p| !p.in_trait && (p.owner == st.ty.name || demangle_name(&p.owner) == owner) && p.loc.file == st.loc.file).collect();
        for field in &st.field_members {
            let synthesized = field.name.starts_with("__") && !(all && field.name.starts_with("__field_"));
            if field.hidden || synthesized || field.name.contains('.') || (!all && field.name.starts_with('_')) {
                continue;
            }
            let mut ty = field.ty.clone();
            crate::type_name::replace_map(&mut ty, &map);
            let is_property = properties.iter().any(|p| p.storage.as_deref() == Some(field.name.as_str()) && p.name == field.name);
            found.push((field.loc, field.name.clone(), ty, field.is_const, is_property, field.attributes.clone()));
        }
        if !all {
            for property in properties {
                if property.name.starts_with('_') || found.iter().any(|(_, name, ..)| name == &property.name) {
                    continue;
                }
                let getter = st.method_members.iter().find(|m| m.name == getter_name(&property.name));
                let mut ty = getter.map_or_else(TypeName::auto, |g| g.ty.clone());
                crate::type_name::replace_map(&mut ty, &map);
                let attributes = getter.map(|g| g.attributes.clone()).unwrap_or_default();
                found.push((property.loc, property.name.clone(), ty, property.set.is_none(), true, attributes));
            }
        }
        found.sort_by_key(|(loc, ..)| (loc.file.0, loc.span.start));
        let count = found.len();
        Ok(Value::List(Rc::new(
            found
                .into_iter()
                .enumerate()
                .map(|(index, (loc, name, ty, is_const, is_property, attributes))| {
                    Value::Member(Rc::new(Member { name, field: None, ty, index, count, is_const, is_property, attributes, file: loc.file }))
                })
                .collect(),
        )))
    }

    fn cases(&self, ty: &TypeName, span: ast::Span) -> Result<Value> {
        if let Some(def) = self.find_enum(&ty.name) {
            return Ok(Value::List(Rc::new((0..def.cases.len()).map(|i| Value::Case(Rc::new(case_of(def, i)))).collect())));
        }
        if let Some((st, map)) = self.find_struct(ty)
            && let Some(cases) = &st.enum_cases
        {
            let count = cases.len();
            let values = |case: &EnumCaseDef| -> Vec<Value> {
                let count = case.payload.len();
                case.payload
                    .iter()
                    .enumerate()
                    .map(|(index, (name, loc))| {
                        let field = payload_field(&case.name, name);
                        let mut ty = st.field_members.iter().find(|f| f.name == field).map_or_else(TypeName::auto, |f| f.ty.clone());
                        crate::type_name::replace_map(&mut ty, &map);
                        Value::Member(Rc::new(Member {
                            name: name.clone(),
                            field: Some(field),
                            ty,
                            index,
                            count,
                            is_const: true,
                            is_property: false,
                            attributes: vec![],
                            file: loc.file,
                        }))
                    })
                    .collect()
            };
            return Ok(Value::List(Rc::new(
                cases
                    .iter()
                    .enumerate()
                    .map(|(index, case)| {
                        Value::Case(Rc::new(Case {
                            enumeration: ty.clone(),
                            name: case.name.clone(),
                            value: case.value,
                            index,
                            count,
                            is_value: false,
                            values: values(case),
                            attributes: case.attributes.clone(),
                            file: case.loc.file,
                        }))
                    })
                    .collect(),
            )));
        }
        Err(self.error(format!("'{}' is not an enum", demangle(&ty.display())), span))
    }

    /// The `[Attribute]` struct `ty` names, or the name of a built-in
    /// attribute.
    fn attribute_struct_named(&self, ty: &TypeName, span: ast::Span) -> Result<AttributeName> {
        let found = find_attribute_struct(self.module, &ty.name, self.file);
        if let Some(st) = found
            && !is_built_in(st)
        {
            return Ok(AttributeName::Declared(st.name.clone()));
        }
        let base = ty.name.rsplit('.').next().unwrap_or(&ty.name);
        if BUILT_IN_ATTRIBUTES.contains(&base) {
            return Ok(AttributeName::BuiltIn(base.to_string(), found.is_some()));
        }
        Err(self.error(format!("'{}' is not an attribute; an attribute is a struct marked '[Attribute]'", demangle(&ty.display())), span))
    }

    /// Whether `attribute`, written in `file`, is an `A`.
    fn names_attribute(&self, attribute: &ast::Attribute, file: FileId, wanted: &AttributeName) -> bool {
        let Some(name) = attribute_name(attribute) else { return false };
        match wanted {
            AttributeName::BuiltIn(built_in, _) => &name == built_in && find_attribute_struct(self.module, &name, file).is_none_or(is_built_in),
            AttributeName::Declared(st) => find_attribute_struct(self.module, &name, file).is_some_and(|found| &found.name == st),
        }
    }

    /// `has_attribute<A>()` or `attribute<A>()` over `attributes`, written in
    /// `file`.
    fn attribute_of(&self, attributes: &[ast::Attribute], file: FileId, attribute: &TypeName, value: bool, what: &str, span: ast::Span) -> Result<Value> {
        let wanted = self.attribute_struct_named(attribute, span)?;
        let found = attributes.iter().find(|a| self.names_attribute(a, file, &wanted));
        if !value {
            return Ok(Value::Bool(found.is_some()));
        }
        let shown = demangle(&attribute.display()).into_owned();
        let Some(found) = found else {
            return Err(self.error(format!("{} has no attribute '{}'; test it with 'has_attribute<{}>()' first", what, shown, shown), span));
        };
        match wanted {
            AttributeName::Declared(_) => attribute_value(self.module, found, file).map_err(|error| self.with_passes(error)),
            AttributeName::BuiltIn(name, true) => built_in_value(self.module, &name, found, file).map_err(|error| self.with_passes(error)),
            AttributeName::BuiltIn(name, false) => {
                Err(self.error(format!("built-in attribute '{}' is not declared in the runtime, so it has no value", name), span))
            }
        }
    }
}

enum AttributeName {
    /// An `[Attribute]` struct, by its name in the model.
    Declared(String),
    /// A built-in attribute, and whether the runtime declares it
    /// (`runtime/attributes.pep`), which gives it a value.
    BuiltIn(String, bool),
}

/// `st` declares a built-in attribute: an `[Attribute]` struct named like
/// one, as `runtime/attributes.pep` declares them.
fn is_built_in(st: &StructDef) -> bool {
    BUILT_IN_ATTRIBUTES.contains(&demangle_name(&st.name))
}

/// The value of built-in attribute `name` as written (`attribute`, in
/// `file`), as the struct the runtime declares for it. `[Target(...)]`
/// holds its condition as written; the others take their arguments as an
/// `[Attribute]` struct of the user's does.
fn built_in_value(module: &Module, name: &str, attribute: &ast::Attribute, file: FileId) -> Result<Value> {
    if name != "Target" {
        return attribute_value(module, attribute, file);
    }
    let st = find_attribute_struct(module, name, file).expect("the runtime declares 'Target'");
    let condition = attribute.arguments().iter().map(|argument| argument.value.to_string()).collect::<Vec<_>>().join(", ");
    Ok(Value::Attribute(Rc::new(Attribute { ty: st.name.clone(), fields: vec![("condition".to_string(), Value::String(condition))] })))
}

fn as_float(value: &Value) -> f64 {
    match value {
        Value::Int(v) => *v as f64,
        Value::Float(v) => *v,
        _ => 0.0,
    }
}

fn case_of(def: &EnumDef, index: usize) -> Case {
    let case = &def.cases[index];
    Case {
        enumeration: TypeName::new(&def.name),
        name: case.name.clone(),
        value: case.value,
        index,
        count: def.cases.len(),
        is_value: true,
        values: vec![],
        attributes: case.attributes.clone(),
        file: case.loc.file,
    }
}

fn block_of(items: Vec<Statement>) -> Block {
    Block { name: String::new(), items, attributes: vec![] }
}

fn empty_static() -> StaticBlock {
    StaticBlock { captures: vec![], items: vec![], type_map: vec![], loc: Loc::NONE }
}

/// The candidate declared in `file`, else the only one.
fn prefer_file<'a, T>(candidates: impl Iterator<Item = &'a T>, file_of: impl Fn(&T) -> FileId, file: FileId) -> Option<&'a T> {
    let candidates: Vec<&T> = candidates.collect();
    candidates.iter().find(|c| file_of(c) == file).copied().or_else(|| if candidates.len() == 1 { Some(candidates[0]) } else { None })
}

// ── Attributes ──────────────────────────────────────────────────────────────

/// The name an attribute is written with: `Option` in `[Option("o")]`, and
/// `json.Name` in `[json.Name("id")]`.
pub fn attribute_name(attribute: &ast::Attribute) -> Option<String> {
    fn spelled(expr: &ast::Expression) -> Option<String> {
        match expr {
            ast::Expression::SymbolRef { id, .. } => Some(id.clone()),
            ast::Expression::MemberAccess { lhs, name, .. } => Some(format!("{}.{}", spelled(lhs)?, name)),
            ast::Expression::TypeLiteral(ty) => Some(ty.name.clone()),
            _ => None,
        }
    }
    match &attribute.body {
        ast::Expression::FunctionCall { function, .. } => spelled(function),
        body => spelled(body),
    }
}

/// The `[Attribute]` struct an attribute named `name`, written in `file`,
/// refers to.
fn find_attribute_struct<'m>(module: &'m Module, name: &str, file: FileId) -> Option<&'m StructDef> {
    let is_attribute = |st: &&StructDef| st.generic_params.is_empty() && has_attribute(&st.attributes, ATTRIBUTE_ATTRIBUTE);
    if let Some(st) = module.structs.iter().filter(is_attribute).find(|st| st.name == name) {
        return Some(st);
    }
    // `serialize.Name`: the module's export, whatever file of the module
    // declares it (`Name@serialize/module`).
    let (module_name, base) = name.rsplit_once('.').map_or((None, name), |(m, b)| (Some(m), b));
    let in_module = |st: &&StructDef| match module_name {
        None => true,
        Some(m) => st.name.split_once(pepper_parser::namespace::SEPARATOR).is_some_and(|(_, ns)| ns == m || ns.split('/').next() == Some(m)),
    };
    prefer_file(module.structs.iter().filter(is_attribute).filter(|st| demangle_name(&st.name) == base).filter(in_module), |st| st.loc.file, file)
}

/// The value of a literal in the model: a parameter's default or a field's
/// initializer.
fn model_constant(module: &Module, expr: &Expression) -> Option<Value> {
    Some(match expr {
        Expression::IntLiteral(v) => Value::Int(*v),
        Expression::FloatLiteral(v) => Value::Float(*v),
        Expression::BoolLiteral(v) => Value::Bool(*v),
        Expression::StringLiteral { value, .. } => Value::String(value.clone()),
        // A lowered string literal: `String(raw, size, length)`.
        Expression::FunctionCall { function, args, .. } if function == "String" && args.len() == 3 => model_constant(module, &args[0])?,
        Expression::Unary { op: UnaryOp::Neg, operand, .. } => match model_constant(module, operand)? {
            Value::Int(v) => Value::Int(-v),
            Value::Float(v) => Value::Float(-v),
            _ => return None,
        },
        Expression::Cast { expr, ty, .. } => {
            let Expression::IntLiteral(v) = expr.as_ref() else { return None };
            match module.enums.iter().find(|e| e.name == ty.name) {
                Some(def) => {
                    let index = def.cases.iter().position(|c| c.value == *v)?;
                    Value::Case(Rc::new(case_of(def, index)))
                }
                None => Value::Int(*v),
            }
        }
        Expression::MemberRef { lhs, name, .. } => {
            let Expression::SymbolRef { id, .. } = lhs.as_ref() else { return None };
            let def = module.enums.iter().find(|e| &e.name == id)?;
            let index = def.cases.iter().position(|c| &c.name == name)?;
            Value::Case(Rc::new(case_of(def, index)))
        }
        _ => return None,
    })
}

/// The value a field of type `ty` holds when nothing sets it.
fn zero(module: &Module, ty: &TypeName) -> Option<Value> {
    let name = ty.name.as_str();
    if name == "bool" {
        return Some(Value::Bool(false));
    }
    if name == "String" {
        return Some(Value::String(String::new()));
    }
    if matches!(name, "float" | "double" | "f32" | "f64") {
        return Some(Value::Float(0.0));
    }
    if let Some(def) = module.enums.iter().find(|e| e.name == name) {
        let default = def.default_value();
        let index = def.cases.iter().position(|c| c.value == default)?;
        return Some(Value::Case(Rc::new(case_of(def, index))));
    }
    if crate::type_name::is_integral_name(name) || matches!(name, "char" | "byte") {
        return Some(Value::Int(0));
    }
    None
}

/// Whether a field of type `ty` can be part of an attribute: a number,
/// `bool`, `char`, a `String`, or an enum whose cases carry no values.
fn is_attribute_field_type(module: &Module, ty: &TypeName) -> bool {
    zero(module, ty).is_some()
}

/// Evaluates an argument of an attribute: a literal, `-` a number, an enum
/// case, or a `+` of strings.
fn attribute_argument(module: &Module, expr: &ast::Expression, file: FileId) -> Result<Value> {
    let error = |message: &str| Diagnostic::error(message.to_string()).at(Loc::new(file, expr.span()));
    let not_constant = || error("an attribute argument must be a constant: a number, 'bool', character, string or enum case");
    match expr {
        ast::Expression::Literal { value, .. } => Ok(match value {
            ast::Literal::Integer(v) => Value::Int(*v),
            ast::Literal::Float(v) => Value::Float(*v),
            ast::Literal::Bool(v) => Value::Bool(*v),
            ast::Literal::String(v) => Value::String(v.clone()),
            ast::Literal::Char(v) => Value::Int(*v as i64),
            ast::Literal::Null => return Err(not_constant()),
        }),
        ast::Expression::Unary { op, operand, .. } if op == "-" => match attribute_argument(module, operand, file)? {
            Value::Int(v) => Ok(Value::Int(-v)),
            Value::Float(v) => Ok(Value::Float(-v)),
            _ => Err(not_constant()),
        },
        ast::Expression::Binary { lhs, op, rhs, .. } if op == "+" => {
            match (attribute_argument(module, lhs, file)?, attribute_argument(module, rhs, file)?) {
                (Value::String(a), Value::String(b)) => Ok(Value::String(a + &b)),
                _ => Err(not_constant()),
            }
        }
        ast::Expression::MemberAccess { lhs, name, .. } => {
            let ast::Expression::SymbolRef { id, .. } = lhs.as_ref() else { return Err(not_constant()) };
            let def = module
                .enums
                .iter()
                .find(|e| &e.name == id)
                .or_else(|| prefer_file(module.enums.iter().filter(|e| demangle_name(&e.name) == id), |e| e.loc.file, file))
                .ok_or_else(not_constant)?;
            let index = def.cases.iter().position(|c| &c.name == name).ok_or_else(|| error(&format!("no case named '{}' in '{}'", name, demangle(&def.name))))?;
            Ok(Value::Case(Rc::new(case_of(def, index))))
        }
        _ => Err(not_constant()),
    }
}

/// Whether `value` fits a field of type `ty`.
fn fits(module: &Module, value: &Value, ty: &TypeName) -> bool {
    match (zero(module, ty), value) {
        (Some(Value::Int(_)), Value::Int(_)) | (Some(Value::Bool(_)), Value::Bool(_)) | (Some(Value::String(_)), Value::String(_)) => true,
        (Some(Value::Float(_)), Value::Float(_) | Value::Int(_)) => true,
        (Some(Value::Case(a)), Value::Case(b)) => a.enumeration.name == b.enumeration.name,
        _ => false,
    }
}

/// One value an attribute takes: the field it sets, and its default.
struct Slot {
    name: String,
    field: String,
    default: Option<Value>,
}

/// What an attribute struct's arguments set. With a constructor that takes
/// parameters, each parameter is a slot: a `this.field` parameter, or one
/// the body assigns to a field (`this.name = name;`, the only statement it
/// may hold). Without one, each field is a slot, in order, and one with an
/// initializer may be left out.
fn slots(module: &Module, st: &StructDef) -> Result<Vec<Slot>> {
    let shown = demangle_name(&st.name);
    let Some(constructor) = st.constructors.iter().find(|c| c.parameters.iter().any(|p| !p.hidden)) else {
        return Ok(st
            .field_members
            .iter()
            .filter(|f| !f.hidden && !f.name.starts_with("__"))
            .map(|f| Slot { name: f.name.clone(), field: f.name.clone(), default: f.default.as_ref().and_then(|d| model_constant(module, d)) })
            .collect());
    };
    // `this.name = name;` in the body: parameter → field.
    let mut assigned: Vec<(String, String)> = vec![];
    for stmt in constructor.body.iter().flat_map(|b| &b.items) {
        let target = match stmt {
            Statement::Expression(Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. }) => match (lhs.as_ref(), rhs.as_ref()) {
                (Expression::MemberRef { lhs: this, name: field, .. }, Expression::SymbolRef { id, .. })
                    if matches!(this.as_ref(), Expression::ThisRef) || matches!(this.as_ref(), Expression::SymbolRef { id, .. } if id == "this") =>
                {
                    Some((id.clone(), field.clone()))
                }
                (Expression::SymbolRef { id: field, .. }, Expression::SymbolRef { id, .. }) => Some((id.clone(), field.clone())),
                _ => None,
            },
            _ => None,
        };
        // What `struct_body` synthesized (allocation, field initializers).
        let synthesized = match stmt {
            Statement::Declaration(Declaration::Variable(var)) => var.hidden || var.loc.is_none(),
            Statement::Expression(e) => e.loc().is_none(),
            Statement::Return(r) => r.loc.is_none(),
            _ => false,
        };
        match target {
            Some(pair) => assigned.push(pair),
            None if synthesized => {}
            None => {
                return Err(Diagnostic::error(format!("the constructor of attribute '{}' may only assign its parameters to fields", shown))
                    .at(constructor.loc));
            }
        }
    }
    let mut slots = vec![];
    for parameter in constructor.parameters.iter().filter(|p| !p.hidden) {
        let name = parameter.name.trim_start_matches("this.").to_string();
        let field = if parameter.name.starts_with("this.") {
            name.clone()
        } else {
            match assigned.iter().find(|(p, _)| p == &name) {
                Some((_, field)) => field.clone(),
                None => {
                    return Err(Diagnostic::error(format!("parameter '{}' of attribute '{}' must set a field", name, shown)).at(parameter.loc));
                }
            }
        };
        slots.push(Slot { name, field, default: parameter.default.as_ref().and_then(|d| model_constant(module, d)) });
    }
    Ok(slots)
}

/// The value of `attribute` (written in `file`), an `[Attribute]` struct:
/// its arguments bound to the struct's [`slots`], then the other fields'
/// initializers and zero values.
fn attribute_value(module: &Module, attribute: &ast::Attribute, file: FileId) -> Result<Value> {
    let name = attribute_name(attribute).unwrap_or_default();
    let at = |span: ast::Span| Loc::new(file, span);
    let Some(st) = find_attribute_struct(module, &name, file) else {
        let name_span = match &attribute.body {
            ast::Expression::FunctionCall { function, .. } => function.span(),
            body => body.span(),
        };
        return Err(Diagnostic::error(format!("unknown attribute '{}'", name)).at(at(name_span)));
    };
    let shown = demangle_name(&st.name).to_string();
    let slots = slots(module, st)?;
    let arguments = attribute.arguments();
    let mut values: Vec<(String, Value)> = vec![];
    let set = |field: &str, value: Value, span: ast::Span, values: &mut Vec<(String, Value)>| -> Result<()> {
        let Some(declared) = st.field_members.iter().find(|f| f.name == field) else {
            return Err(Diagnostic::error(format!("no field named '{}' in attribute '{}'", field, shown)).at(at(span)));
        };
        if !fits(module, &value, &declared.ty) {
            return Err(Diagnostic::error(format!(
                "cannot use {} for '{}' of attribute '{}', which is a '{}'",
                value.kind_with_article(),
                field,
                shown,
                demangle(&declared.ty.display())
            ))
            .at(at(span)));
        }
        values.retain(|(name, _)| name != field);
        values.push((field.to_string(), value));
        Ok(())
    };
    let mut bound = vec![false; slots.len()];
    let mut positional = 0;
    for argument in &arguments {
        let index = match argument.name {
            Some((label, span)) => slots
                .iter()
                .position(|slot| slot.name == label)
                .ok_or_else(|| Diagnostic::error(format!("no parameter named '{}' in attribute '{}'", label, shown)).at(at(span)))?,
            None => {
                positional += 1;
                if positional > slots.len() {
                    return Err(Diagnostic::error(format!("too many arguments to attribute '{}': expected {}, have {}", shown, slots.len(), arguments.len()))
                        .at(at(argument.value.span())));
                }
                positional - 1
            }
        };
        if bound[index] {
            return Err(Diagnostic::error(format!("'{}' of attribute '{}' is given twice", slots[index].name, shown)).at(at(argument.value.span())));
        }
        bound[index] = true;
        let value = attribute_argument(module, argument.value, file)?;
        set(&slots[index].field, value, argument.value.span(), &mut values)?;
    }
    for (index, slot) in slots.iter().enumerate() {
        if bound[index] {
            continue;
        }
        let Some(default) = slot.default.clone() else {
            return Err(Diagnostic::error(format!("too few arguments to attribute '{}': missing '{}'", shown, slot.name)).at(at(attribute.span)));
        };
        set(&slot.field, default, attribute.span, &mut values)?;
    }
    let mut fields = vec![];
    for field in &st.field_members {
        if field.hidden || field.name.starts_with("__") {
            continue;
        }
        let value = values
            .iter()
            .find(|(name, _)| name == &field.name)
            .map(|(_, v)| v.clone())
            .or_else(|| field.default.as_ref().and_then(|d| model_constant(module, d)))
            .or_else(|| zero(module, &field.ty))
            .unwrap_or(Value::Int(0));
        fields.push((field.name.clone(), value));
    }
    Ok(Value::Attribute(Rc::new(Attribute { ty: st.name.clone(), fields })))
}

// ── Checking attributes ─────────────────────────────────────────────────────

/// Reports an attribute that names neither a built-in attribute nor an
/// `[Attribute]` struct (`unknown attribute 'X'`), an argument an attribute
/// struct cannot take, and an `[Attribute]` struct that cannot be one.
pub fn check_attributes(module: &Module) {
    for st in &module.structs {
        if !has_attribute(&st.attributes, ATTRIBUTE_ATTRIBUTE) || !st.generic_params.is_empty() {
            continue;
        }
        for field in &st.field_members {
            if field.hidden || field.name.starts_with("__") {
                continue;
            }
            if !is_attribute_field_type(module, &field.ty) {
                crate::errors::report(
                    Diagnostic::error(format!(
                        "field '{}' of attribute '{}' must be a number, 'bool', 'char', 'String' or an enum, not '{}'",
                        field.name,
                        demangle_name(&st.name),
                        demangle(&field.ty.display())
                    ))
                    .at(if field.type_loc.is_none() { field.loc } else { field.type_loc }),
                );
                return;
            }
        }
    }
    let mut check = |attributes: &[ast::Attribute], file: FileId| {
        for attribute in attributes {
            let Some(name) = attribute_name(attribute) else { continue };
            // The compiler checks a built-in attribute's arguments itself.
            if find_attribute_struct(module, &name, file).is_none_or(is_built_in) && BUILT_IN_ATTRIBUTES.contains(&name.as_str()) {
                continue;
            }
            if let Err(error) = attribute_value(module, attribute, file) {
                crate::errors::report(error);
                return;
            }
        }
    };
    let function = |f: &FunctionDef, check: &mut dyn FnMut(&[ast::Attribute], FileId)| {
        check(&f.attributes, f.loc.file);
        for p in &f.parameters {
            check(&p.attributes, f.loc.file);
        }
    };
    for st in &module.structs {
        if st.name != st.ty.name && !st.generic_params.is_empty() {
            continue;
        }
        check(&st.attributes, st.loc.file);
        for field in &st.field_members {
            check(&field.attributes, st.loc.file);
        }
        for method in st.method_members.iter().chain(&st.constructors).chain(&st.generic_methods) {
            function(method, &mut check);
        }
        if let Some(cases) = &st.enum_cases {
            for case in cases {
                check(&case.attributes, case.loc.file);
            }
        }
    }
    for f in &module.functions {
        function(f, &mut check);
    }
    for e in &module.enums {
        check(&e.attributes, e.loc.file);
        for case in &e.cases {
            check(&case.attributes, case.loc.file);
        }
    }
    for g in &module.globals {
        check(&g.attributes, g.loc.file);
    }
    for t in &module.traits {
        check(&t.attributes, t.loc.file);
    }
}

//! Confinement: what a `with` block over an `[Isolated]` guard (a
//! `Mutex<T>`'s lock, a `ThreadLocal<T>`'s value) may do, and the checks
//! that make it sound.
//!
//! A value that is not thread-safe counts its references plainly, so while a
//! Mutex is unlocked no thread may hold a reference into its value. The
//! compiler keeps the locked value and the rest of the program apart by
//! **region**: inside the block, every value of a type that is not
//! thread-safe is part of the locked value (the lock's region), part of the
//! rest of the program (the outer region: parameters, `this`, and locals
//! declared outside the block), or new (a fresh region, which may join
//! either). A call links the regions of the operands its callee links, and
//! an assignment links its target and value; linking the lock's region with
//! the outer one (or with another lock's) is an error at the value that
//! would cross, as is returning part of the locked value from the block.
//!
//! **Link summaries.** Which operands a call links comes from its callee's
//! summary: the classes of its operands (`this`, then the parameters) and
//! its result that its body links, found with the same region walk over the
//! body, as a least fixed point over the call graph. A result is **fresh**
//! when no operand is in its class and it is not tainted: it shares nothing
//! with the inputs. Taint means "may also be referenced elsewhere": a
//! reference read through a pointer an `extern` returned (the operating
//! system's thread-local slots), a call through a function value, and a
//! value a closure captured. A call through a trait value joins the
//! summaries of every implementation. `extern` calls link nothing (C code
//! is its own promise), and `copy(x)` is fresh by definition. A reference
//! read through raw memory that a `[Shared]` struct's field holds is
//! tainted too: other threads may reach it. A runtime function that hands
//! out a value nothing else references through such memory says so with
//! `[ReturnsOwned]` (`Channel.receive`, `Mutex.replace`), an unchecked
//! promise only runtime files may make.
//!
//! The pass also checks, everywhere:
//!
//! - an `[Isolated]` guard is used only as the scope of a `with` header;
//! - an argument to a `[Sending]` parameter is **disconnected**: a value of
//!   a thread-safe type, or a call whose result is fresh or whose linked
//!   operands are all disconnected (a constructor call, a string literal,
//!   `copy(x)`); never a named variable;
//! - `ThreadLocal<T>.get()` for a `T` that is not thread-safe (reach the
//!   value with `with (var v = local.enter())`), and `Mutex<T>` of a number.

use crate::model::*;
use crate::passes::check_shared_types::{ThreadSafeStructs, unsafe_part_in, use_site};
use crate::passes::gather_generics::parse_type_string;
use crate::static_type::StructTable;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// A struct that can only be the scope of a `with` header.
pub const ISOLATED_ATTRIBUTE: &str = "Isolated";

/// A parameter whose argument must be disconnected.
pub const SENDING_ATTRIBUTE: &str = "Sending";

/// A runtime function whose results are fresh whatever its body shows: it
/// hands out a value nothing else references, through raw memory the
/// compiler cannot follow (`Channel.receive`, `Mutex.replace`). Only runtime
/// files may use it.
pub const RETURNS_OWNED_ATTRIBUTE: &str = "ReturnsOwned";

/// How many rounds the summaries may take to settle.
const MAX_ROUNDS: usize = 64;

// ── Summaries ────────────────────────────────────────────────────────────────

/// What a function's body links: for each operand slot (`this` first for a
/// method, then the parameters) and each result slot (one per element of a
/// tuple result, else one), the smallest slot of its class; and whether each
/// result is tainted.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Summary {
    class: Vec<usize>,
    /// One per result slot.
    tainted: Vec<bool>,
    /// The first `return` whose value shares an operand's class or is
    /// tainted, for notes. Not compared.
    blame: Option<Loc>,
}

impl Summary {
    /// Nothing linked, nothing tainted: every slot its own class.
    fn bottom(operands: usize, results: usize) -> Summary {
        Summary { class: (0..operands + results).collect(), tainted: vec![false; results], blame: None }
    }

    /// Everything linked and every result tainted: a callee nothing is
    /// known about.
    fn top(operands: usize, results: usize) -> Summary {
        Summary { class: vec![0; operands + results], tainted: vec![true; results], blame: None }
    }

    fn results(&self) -> usize {
        self.tainted.len()
    }

    fn operands(&self) -> usize {
        self.class.len() - self.results()
    }

    /// Result slot `n` shares nothing with the operands.
    fn fresh_at(&self, n: usize) -> bool {
        let result = self.class[self.operands() + n];
        !self.tainted[n] && (0..self.operands()).all(|slot| self.class[slot] != result)
    }

    /// Every result shares nothing with the operands.
    fn fresh(&self) -> bool {
        (0..self.results()).all(|n| self.fresh_at(n))
    }

    /// Both summaries' links (for a call through a trait value): the
    /// classes of either, joined. Summaries of different shapes join to the
    /// top.
    fn join(&self, other: &Summary) -> Summary {
        if self.class.len() != other.class.len() || self.results() != other.results() {
            return Summary::top(self.operands(), self.results());
        }
        let slots = self.class.len();
        let mut sets = Sets((0..slots).collect());
        for slot in 0..slots {
            for summary in [self, other] {
                sets.union(slot, summary.class[slot]);
            }
        }
        let class = (0..slots).map(|slot| (0..slots).find(|&s| sets.find(s) == sets.find(slot)).unwrap()).collect();
        let tainted = self.tainted.iter().zip(&other.tainted).map(|(a, b)| *a || *b).collect();
        Summary { class, tainted, blame: self.blame.or(other.blame) }
    }
}

/// The number of elements of a tuple type, or 1.
fn result_slots(ty: &TypeName) -> usize {
    if ty.name == crate::type_name::TUPLE && !ty.sub_types.is_empty() { ty.sub_types.len() } else { 1 }
}

/// A plain union-find over slots.
struct Sets(Vec<usize>);

impl Sets {
    fn find(&mut self, x: usize) -> usize {
        let mut root = x;
        while self.0[root] != root {
            root = self.0[root];
        }
        let mut at = x;
        while self.0[at] != root {
            let next = self.0[at];
            self.0[at] = root;
            at = next;
        }
        root
    }
    fn union(&mut self, a: usize, b: usize) {
        let (a, b) = (self.find(a), self.find(b));
        if a != b {
            self.0[b.max(a)] = a.min(b);
        }
    }
}

// ── Regions ──────────────────────────────────────────────────────────────────

/// What a region is part of.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Part {
    /// New: may join anything.
    Fresh,
    /// The rest of the program (in a function being checked).
    Outer,
    /// Operand slot `n` of the function being summarized.
    Operand(usize),
    /// The value locked by with block `n`.
    Locked(usize),
}

#[derive(Debug, Clone)]
struct Region {
    parent: usize,
    part: Part,
    /// May also be referenced from somewhere the walk cannot see.
    tainted: bool,
    /// A pointer the walk cannot follow back to its owner: one an `extern`
    /// returned, or one a thread-safe object's field holds. A reference read
    /// through it is tainted.
    untracked: bool,
    /// Operand slots in the region (summaries).
    operands: Vec<usize>,
    /// A tuple value: the region of each element (`None` for a
    /// thread-safe one). Never unioned: linking goes element by element.
    parts: Vec<Option<usize>>,
}

/// A `with` block over an `[Isolated]` guard.
#[derive(Debug, Clone)]
struct Lock {
    /// What was locked, as written (`names`).
    name: String,
    /// The locking call (`lock` in `names.lock()`).
    loc: Loc,
}

/// Why two regions cannot be linked, for the error.
struct Clash {
    into: Part,
    moving: Part,
}

// ── The walk ─────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    /// Summarize a function: operands have their own regions.
    Summarize,
    /// Check a function's `with` blocks: operands are outer.
    Check,
}

struct Program<'a> {
    module: &'a Module,
    table: StructTable,
    safe: ThreadSafeStructs,
    summaries: HashMap<String, Summary>,
    /// The functions with bodies: a callee not summarized yet starts at
    /// the bottom (it will be, and its callers again after it).
    bodies: std::collections::HashSet<String>,
    /// Structs by name.
    structs: HashMap<String, &'a StructDef>,
    /// Each constructor by the name a call gives it (`Point`, `Point$2`).
    constructors: HashMap<String, &'a FunctionDef>,
    /// The `[Isolated]` structs' names.
    isolated: std::collections::HashSet<String>,
    /// `has_region` by type, as computed.
    regions: std::cell::RefCell<HashMap<String, bool>>,
}

impl<'a> Program<'a> {
    fn new(module: &'a Module) -> Program<'a> {
        let bodies = bodies(module).into_iter().map(|(_, key, _)| key).collect();
        let structs = module.structs.iter().map(|st| (st.name.clone(), st)).collect();
        let constructors = module.structs.iter().flat_map(|st| st.constructors.iter()).map(|c| (c.name.clone(), c)).collect();
        let isolated = module.structs.iter().filter(|st| has_attribute(&st.attributes, ISOLATED_ATTRIBUTE)).map(|st| st.name.clone()).collect();
        Program {
            module,
            table: StructTable::build(module),
            safe: ThreadSafeStructs::of(module),
            summaries: HashMap::new(),
            bodies,
            structs,
            constructors,
            isolated,
            regions: std::cell::RefCell::new(HashMap::new()),
        }
    }

    fn is_isolated(&self, ty: &TypeName) -> bool {
        !self.isolated.is_empty() && self.isolated.contains(&ty.to_string())
    }

    /// Whether values of `ty` belong to regions: references to structs that
    /// are not thread-safe, plain function values, weak references to
    /// those, and raw pointers (which lead into the objects they came from).
    fn has_region(&self, ty: &TypeName) -> bool {
        let key = ty.to_string();
        if let Some(&known) = self.regions.borrow().get(&key) {
            return known;
        }
        let answer = if ty.is_empty() || ty.is_auto() || ty.name == "void" || self.is_isolated(ty) {
            false
        } else {
            ty.is_pointer() || unsafe_part_in(ty, &self.safe).is_some()
        };
        self.regions.borrow_mut().insert(key, answer);
        answer
    }

    fn struct_named(&self, name: &str) -> Option<&'a StructDef> {
        self.structs.get(name).copied()
    }

    fn is_trait(&self, ty: &TypeName) -> bool {
        self.module.traits.iter().any(|t| t.name == ty.name)
    }
}

/// The function a call resolves to.
enum Callee<'a> {
    /// A free function, method or constructor with a body: its summary key
    /// and definition.
    Known(String, &'a FunctionDef),
    /// A method called through a trait value: every implementation's key.
    Trait(Vec<String>),
    /// `copy(x)`: fresh, linking nothing.
    Copy,
    /// An `extern`: links nothing; a pointer result is marked.
    Extern,
    /// Anything else: links everything, result tainted.
    Unknown,
}

fn method_key(owner: &str, method: &str) -> String {
    format!("{owner}.{method}")
}

struct Walk<'p, 'a> {
    program: &'p Program<'a>,
    mode: Mode,
    regions: Vec<Region>,
    /// Scopes of locals: name, region (if any), type.
    scopes: Vec<Vec<(String, Option<usize>, TypeName)>>,
    locks: Vec<Lock>,
    /// The lock of each `with` block the walk is inside, innermost last.
    open: Vec<usize>,
    current: Option<TypeName>,
    /// Each `return`'s value region and location (summaries).
    returns: Vec<(Option<usize>, Loc)>,
    /// The region of each operand slot (summaries).
    operands: Vec<Option<usize>>,
    /// The summary keys of the functions the walk called.
    called: Vec<String>,
    error: Option<Diagnostic>,
}

impl<'p, 'a> Walk<'p, 'a> {
    fn new(program: &'p Program<'a>, mode: Mode, current: Option<TypeName>) -> Self {
        Walk { program, mode, regions: vec![], scopes: vec![vec![]], locks: vec![], open: vec![], current, returns: vec![], operands: vec![], called: vec![], error: None }
    }

    fn region(&mut self, part: Part) -> usize {
        let operands = match part {
            Part::Operand(n) => vec![n],
            _ => vec![],
        };
        self.regions.push(Region { parent: self.regions.len(), part, tainted: false, untracked: false, operands, parts: vec![] });
        self.regions.len() - 1
    }

    fn fresh(&mut self) -> usize {
        self.region(Part::Fresh)
    }

    /// A tuple value whose elements are in `parts`.
    fn tuple(&mut self, parts: Vec<Option<usize>>) -> usize {
        let region = self.fresh();
        self.regions[region].parts = parts;
        region
    }

    fn parts(&mut self, x: usize) -> Vec<Option<usize>> {
        let root = self.find(x);
        self.regions[root].parts.clone()
    }

    /// The regions a value is made of: its own, or its elements'.
    fn leaves(&mut self, x: usize) -> Vec<usize> {
        let parts = self.parts(x);
        if parts.is_empty() {
            return vec![x];
        }
        parts.into_iter().flatten().flat_map(|p| self.leaves(p)).collect()
    }

    fn find(&mut self, x: usize) -> usize {
        let mut root = x;
        while self.regions[root].parent != root {
            root = self.regions[root].parent;
        }
        let mut at = x;
        while self.regions[at].parent != root {
            let next = self.regions[at].parent;
            self.regions[at].parent = root;
            at = next;
        }
        root
    }

    fn part(&mut self, x: usize) -> Part {
        let root = self.find(x);
        self.regions[root].part
    }

    /// Link two regions; the clash when they are parts that must stay apart.
    fn union(&mut self, into: usize, moving: usize) -> Result<usize, Clash> {
        let (a, b) = (self.find(into), self.find(moving));
        if a == b {
            return Ok(a);
        }
        let (pa, pb) = (self.regions[a].part, self.regions[b].part);
        let part = match (pa, pb) {
            (Part::Fresh, p) | (p, Part::Fresh) => p,
            (Part::Operand(_), Part::Operand(_)) => pa,
            (x, y) if x == y => x,
            _ => return Err(Clash { into: pa, moving: pb }),
        };
        self.regions[b].parent = a;
        self.regions[a].part = part;
        self.regions[a].tainted |= self.regions[b].tainted;
        self.regions[a].untracked |= self.regions[b].untracked;
        let moved = std::mem::take(&mut self.regions[b].operands);
        self.regions[a].operands.extend(moved);
        Ok(a)
    }

    /// Link `moving` (the region of `expr`) into `into`, reporting a clash at
    /// `expr`.
    fn link(&mut self, into: Option<usize>, moving: Option<usize>, expr: &Expression) -> Option<usize> {
        if let (Some(a), Some(b)) = (into, moving) {
            // Tuples link element by element, or, against a single value,
            // every element with it.
            let (pa, pb) = (self.parts(a), self.parts(b));
            if !pa.is_empty() || !pb.is_empty() {
                if pa.len() == pb.len() {
                    for (x, y) in pa.into_iter().zip(pb) {
                        self.link(x, y, expr);
                    }
                } else if pa.is_empty() {
                    for y in pb {
                        self.link(Some(a), y, expr);
                    }
                } else {
                    for x in pa {
                        self.link(x, Some(b), expr);
                    }
                }
                return Some(a);
            }
        }
        match (into, moving) {
            (Some(a), Some(b)) => match self.union(a, b) {
                Ok(root) => Some(root),
                Err(clash) => {
                    self.clash(clash, expr);
                    Some(a)
                }
            },
            (a, b) => a.or(b),
        }
    }

    fn report(&mut self, diagnostic: Diagnostic) {
        if self.error.is_none() {
            self.error = Some(diagnostic);
        }
    }

    fn clash(&mut self, clash: Clash, expr: &Expression) {
        let what = describe(expr);
        let ty = self.ty(expr).map(|t| t.display()).unwrap_or_else(|| "value".to_string());
        let lock = |walk: &Walk, part: Part| match part {
            Part::Locked(n) => Some(walk.locks[n].clone()),
            _ => None,
        };
        let (message, lock_loc, advice) = match (lock(self, clash.into), lock(self, clash.moving)) {
            (Some(into), None) => (
                format!("'{what}' cannot move into the value locked by '{}'", into.name),
                into.loc,
                format!("'{ty}' is not thread-safe, so the locked value cannot share it with the rest of the program; pass 'copy({what})'"),
            ),
            (None, Some(from)) => (
                format!("'{what}' is part of the value locked by '{}' and cannot outlive the lock", from.name),
                from.loc,
                format!("'{ty}' is not thread-safe, so no part of the locked value may be kept outside the block; take 'copy({what})'"),
            ),
            (Some(into), Some(from)) => (
                format!("'{what}' is part of the value locked by '{}' and cannot move into the value locked by '{}'", from.name, into.name),
                from.loc,
                format!("'{ty}' is not thread-safe, so two locked values cannot share it; pass 'copy({what})'"),
            ),
            (None, None) => return,
        };
        let diagnostic = Diagnostic::error(message).at(expr.loc()).with_note("locked here", lock_loc.known()).with_note(advice, None);
        self.report(diagnostic);
    }

    // ── Types ──

    fn local(&self, name: &str) -> Option<&(String, Option<usize>, TypeName)> {
        self.scopes.iter().rev().flat_map(|s| s.iter().rev()).find(|(n, _, _)| n == name)
    }

    fn ty(&self, expr: &Expression) -> Option<TypeName> {
        if let Expression::SymbolRef { id, .. } = expr
            && let Some((_, _, ty)) = self.local(id)
        {
            return Some(ty.clone());
        }
        if let Expression::ThisRef = expr
            && let Some((_, _, ty)) = self.local("this")
        {
            return Some(ty.clone());
        }
        // A raw read (`_data[i]`) is typed only in codegen: its pointee.
        if let Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } = expr
            && let Some(pointer) = self.ty(lhs)
            && let Some(pointee) = pointer.to_string().strip_suffix('*')
        {
            return Some(parse_type_string(pointee));
        }
        crate::static_type::of(expr, &self.program.table, self.current.as_ref()).filter(|t| !t.is_auto())
    }

    fn has_region(&self, expr: &Expression) -> bool {
        self.ty(expr).is_some_and(|t| self.program.has_region(&t))
    }

    fn declare(&mut self, name: &str, region: Option<usize>, ty: TypeName) {
        self.scopes.last_mut().unwrap().push((name.to_string(), region, ty));
    }

    /// Where a local declared now belongs: new (and joined with its
    /// initializer), except outside every `with` block in a check, where
    /// it is part of the rest of the program.
    fn local_region(&mut self) -> usize {
        if self.mode == Mode::Check && self.open.is_empty() { self.region(Part::Outer) } else { self.fresh() }
    }

    /// A local's region, shaped like its initializer: a tuple of element
    /// regions for a tuple value.
    fn local_like(&mut self, value: usize) -> usize {
        let parts = self.parts(value);
        if parts.is_empty() {
            return self.local_region();
        }
        let parts = parts.into_iter().map(|p| p.map(|p| self.local_like(p))).collect();
        self.tuple(parts)
    }

    // ── Statements ──

    /// Walk `function`: its operands (`this` unless `is_static`, then the
    /// parameters) are outer in a check, and each its own in a summary.
    fn function(&mut self, function: &FunctionDef, is_static: bool) {
        let mut operands: Vec<(String, TypeName)> = vec![];
        if let Some(owner) = &self.current
            && !is_static
        {
            operands.push(("this".to_string(), owner.clone()));
        }
        operands.extend(function.parameters.iter().map(|p| (p.name.clone(), p.ty.clone())));
        for (slot, (name, ty)) in operands.into_iter().enumerate() {
            let region = if !self.program.has_region(&ty) {
                None
            } else if self.mode == Mode::Check {
                Some(self.region(Part::Outer))
            } else {
                Some(self.region(Part::Operand(slot)))
            };
            self.operands.push(region);
            self.declare(&name, region, ty);
        }
        if let Some(body) = &function.body {
            self.block(body);
        }
    }

    fn block(&mut self, block: &Block) {
        self.scopes.push(vec![]);
        // Only a check tags a locked value; a summary walks the block as
        // written.
        if self.mode == Mode::Check
            && let Some(lock) = self.isolated_with(block)
        {
            self.with_block(block, lock);
        } else {
            for statement in &block.items {
                self.statement(statement);
            }
        }
        self.scopes.pop();
    }

    /// The lock of a `with` block over an `[Isolated]` guard: the block the
    /// builder lowers `with` to (see `builder::with_block`) whose hidden
    /// scope local has an `[Isolated]` type.
    fn isolated_with(&mut self, block: &Block) -> Option<Lock> {
        let [Statement::Declaration(Declaration::Variable(scope)), Statement::Declaration(Declaration::Variable(_)), Statement::Branch(_)] =
            block.items.as_slice()
        else {
            return None;
        };
        if !scope.name.starts_with("__with_scope_") {
            return None;
        }
        let guard = scope.default.as_ref()?;
        let ty = if scope.ty.is_auto() { self.ty(guard)? } else { scope.ty.clone() };
        if !self.program.is_isolated(&ty) {
            return None;
        }
        Some(match guard {
            Expression::MethodCall { this, loc, .. } => Lock { name: describe(this), loc: *loc },
            other => Lock { name: describe(other), loc: scope.loc },
        })
    }

    fn with_block(&mut self, block: &Block, lock: Lock) {
        let [Statement::Declaration(Declaration::Variable(scope)), Statement::Declaration(Declaration::Variable(binding)), Statement::Branch(branch)] =
            block.items.as_slice()
        else {
            return;
        };
        // The guard expression itself (`names.lock()`) may use outer values.
        if let Some(guard) = &scope.default {
            self.eval(guard);
        }
        self.declare(&scope.name, None, scope.ty.clone());
        let index = self.locks.len();
        self.locks.push(lock);
        let region = if self.program.has_region(&binding.ty) || binding.ty.is_auto() { Some(self.region(Part::Locked(index))) } else { None };
        self.declare(&binding.name, region, binding.ty.clone());
        self.open.push(index);
        self.eval(&branch.condition);
        self.block(&branch.if_block);
        if let Some(other) = &branch.else_block {
            self.block(other);
        }
        self.open.pop();
    }

    fn statement(&mut self, statement: &Statement) {
        if self.error.is_some() {
            return;
        }
        match statement {
            Statement::Expression(expr) => {
                self.eval(expr);
            }
            Statement::Block(inner) => self.block(inner),
            Statement::Declaration(Declaration::Variable(var)) => {
                let value = var.default.as_ref().and_then(|d| self.eval(d));
                let ty = if var.ty.is_auto() { var.default.as_ref().and_then(|d| self.ty(d)).unwrap_or_else(TypeName::auto) } else { var.ty.clone() };
                if self.program.has_region(&ty) {
                    let region = match value {
                        Some(v) => self.local_like(v),
                        None => self.local_region(),
                    };
                    let joined = match (value, var.default.as_ref()) {
                        (Some(v), Some(d)) => self.link(Some(region), Some(v), d),
                        _ => Some(region),
                    };
                    self.declare(&var.name, joined, ty);
                } else {
                    self.declare(&var.name, None, ty);
                }
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => {
                self.eval(&branch.condition);
                self.block(&branch.if_block);
                if let Some(other) = &branch.else_block {
                    self.block(other);
                }
            }
            Statement::While(wh) => {
                self.eval(&wh.condition);
                self.block(&wh.block);
            }
            Statement::Return(ret) => {
                let value = ret.expr.as_ref().and_then(|e| self.eval(e));
                if let (Some(v), Some(expr)) = (value, ret.expr.as_ref()) {
                    let locked = self.leaves(v).into_iter().find_map(|leaf| match self.part(leaf) {
                        Part::Locked(n) => Some(n),
                        _ => None,
                    });
                    if let Some(n) = locked {
                        let lock = self.locks[n].clone();
                        let what = describe(expr);
                        self.report(
                            Diagnostic::error(format!("'{what}' is part of the value locked by '{}' and cannot be returned from the block", lock.name))
                                .at(expr.loc())
                                .with_note("locked here", lock.loc.known())
                                .with_note(format!("return 'copy({what})' instead"), None),
                        );
                    }
                }
                self.returns.push((value, ret.loc));
            }
            Statement::LoopBreak(_) => {}
        }
    }

    // ── Expressions ──

    fn eval(&mut self, expr: &Expression) -> Option<usize> {
        if self.error.is_some() {
            return None;
        }
        self.eval_inner(expr)
    }

    fn eval_inner(&mut self, expr: &Expression) -> Option<usize> {
        match expr {
            Expression::SymbolRef { id, .. } => self.local(id).and_then(|(_, r, _)| *r),
            Expression::ThisRef => self.local("this").and_then(|(_, r, _)| *r),
            Expression::MemberRef { lhs, name, .. } => {
                let owner = self.eval(lhs);
                // An element of a tuple value: its own region.
                if let Some(owner) = owner
                    && let Ok(index) = name.parse::<usize>()
                {
                    let parts = self.parts(owner);
                    if !parts.is_empty() {
                        return parts.get(index).copied().flatten();
                    }
                }
                if !self.has_region(expr) {
                    return None;
                }
                match owner {
                    Some(owner) => Some(owner),
                    None => {
                        // A field of a thread-safe object: raw memory that
                        // other threads may reach too. A reference read
                        // through it may be referenced elsewhere.
                        let region = self.fresh();
                        self.regions[region].untracked = true;
                        Some(region)
                    }
                }
            }
            Expression::BoolLiteral(_)
            | Expression::IntLiteral(_)
            | Expression::FloatLiteral(_)
            | Expression::SizeOf(_)
            | Expression::IsPod(_)
            | Expression::FunctionPointer { .. }
            | Expression::CountStep { .. }
            | Expression::MethodAddress(_)
            | Expression::FunctionRef { .. }
            | Expression::ClosureLiteral(_) => None,
            Expression::StringLiteral { .. } | Expression::PointerLiteral | Expression::Default(_) | Expression::Allocate(_) => {
                Some(self.fresh())
            }
            Expression::Binary { op, lhs, rhs, .. } if op.is_assignment() => {
                let value = self.eval(rhs);
                let target = self.place(lhs);
                self.link(target, value, rhs);
                None
            }
            Expression::Binary { lhs, rhs, .. } => {
                self.eval(lhs);
                self.eval(rhs);
                None
            }
            Expression::Unary { operand, .. } => {
                self.eval(operand);
                None
            }
            Expression::Cast { expr: inner, .. } => {
                let region = self.eval(inner);
                if self.has_region(expr) { Some(region.unwrap_or_else(|| self.fresh())) } else { None }
            }
            Expression::Ternary { condition, true_expr, false_expr } => {
                self.eval(condition);
                let a = self.eval(true_expr);
                let b = self.eval(false_expr);
                self.link(a, b, false_expr)
            }
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                self.eval(rhs);
                let pointer = self.eval(lhs);
                if !self.has_region(expr) {
                    return None;
                }
                let region = pointer.unwrap_or_else(|| self.fresh());
                // A reference read through a pointer an extern returned may
                // be referenced from wherever C keeps it.
                let root = self.find(region);
                if self.regions[root].untracked && !self.ty(expr).is_some_and(|t| t.is_pointer()) {
                    self.regions[root].tainted = true;
                }
                Some(region)
            }
            Expression::RefCount(_, arg) | Expression::Address(_, arg) => {
                self.eval(arg);
                None
            }
            Expression::Weak(op, _, arg) => {
                let region = self.eval(arg);
                if *op == WeakOp::Expired { None } else { region }
            }
            Expression::AtomicLoad(_, a) => {
                self.eval(a);
                None
            }
            Expression::AtomicStore(_, a, b) | Expression::AtomicFetch(_, _, a, b) => {
                self.eval(a);
                self.eval(b);
                None
            }
            Expression::AtomicCmpXchg(_, a, b, c) => {
                self.eval(a);
                self.eval(b);
                self.eval(c);
                None
            }
            Expression::FunctionCall { function, args, .. } => self.call_function(expr, function, args),
            Expression::MethodCall { this, method, args, .. } => self.call_method(expr, this, method, args),
            Expression::Invoke { callee, args } => {
                let mut acc = self.eval(callee);
                for arg in args {
                    let region = self.eval(arg);
                    acc = self.link(acc, region, arg);
                }
                if !self.has_region(expr) {
                    return None;
                }
                let region = acc.unwrap_or_else(|| self.region(if self.mode == Mode::Check { Part::Outer } else { Part::Fresh }));
                let root = self.find(region);
                self.regions[root].tainted = true;
                Some(region)
            }
            Expression::MakeClosure { value, .. } => {
                // The closure struct's constructor call, with the captures
                // as arguments.
                if let Expression::FunctionCall { args, .. } = value.as_ref() {
                    for arg in args {
                        if let Some(region) = self.eval(arg) {
                            let locked = self.leaves(region).into_iter().find_map(|leaf| match self.part(leaf) {
                                Part::Locked(n) => Some(n),
                                _ => None,
                            });
                            if let Some(n) = locked {
                                let lock = self.locks[n].clone();
                                let what = describe(arg);
                                self.report(
                                    Diagnostic::error(format!(
                                        "closure captures '{what}', which is part of the value locked by '{}'",
                                        lock.name
                                    ))
                                    .at(arg.loc())
                                    .with_note("locked here", lock.loc.known())
                                    .with_note(format!("a function value can carry what it captures out of the block; capture 'copy({what})'"), None),
                                );
                            }
                            // A captured value may be reached through the
                            // closure later: not fresh.
                            let root = self.find(region);
                            self.regions[root].tainted = true;
                        }
                    }
                }
                if self.has_region(expr) { Some(self.fresh()) } else { None }
            }
            Expression::CallPointer { pointer, args } => {
                self.eval(pointer);
                for arg in args {
                    self.eval(arg);
                }
                None
            }
            Expression::ForIterator(source) => self.eval(source),
            Expression::Destructure { value, .. } => self.eval(value),
            Expression::MatchArm(test) => {
                self.eval(&test.subject);
                None
            }
            Expression::WithEntered(value) => {
                self.eval(value);
                None
            }
            Expression::ToTrait { value, .. } => self.eval(value),
        }
    }

    /// The region an assignment to `target` stores into.
    fn place(&mut self, target: &Expression) -> Option<usize> {
        match target {
            Expression::SymbolRef { id, .. } => self.local(id).and_then(|(_, r, _)| *r),
            Expression::MemberRef { lhs, .. } => self.eval(lhs),
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                self.eval(rhs);
                self.eval(lhs)
            }
            other => self.eval(other),
        }
    }

    fn call_function(&mut self, expr: &Expression, function: &str, args: &[Expression]) -> Option<usize> {
        // A tuple literal keeps its elements apart.
        if function == crate::type_name::TUPLE || function.starts_with(&format!("{}<", crate::type_name::TUPLE)) {
            let parts = args.iter().map(|a| self.eval(a)).collect();
            return Some(self.tuple(parts));
        }
        let callee = self.resolve_function(function);
        let operands: Vec<(Option<usize>, &Expression)> = args.iter().map(|a| (self.eval(a), a)).collect();
        self.apply(expr, callee, operands)
    }

    fn call_method(&mut self, expr: &Expression, this: &Expression, method: &str, args: &[Expression]) -> Option<usize> {
        let (callee, is_static) = self.resolve_method(this, method);
        let mut operands: Vec<(Option<usize>, &Expression)> = vec![];
        if !is_static {
            operands.push((self.eval(this), this));
        }
        for arg in args {
            operands.push((self.eval(arg), arg));
        }
        self.apply(expr, callee, operands)
    }

    fn resolve_function(&self, function: &str) -> Callee<'a> {
        if function.starts_with("copy<") {
            return Callee::Copy;
        }
        let module = self.program.module;
        if module.externs.iter().any(|e| e.name == function) {
            return Callee::Extern;
        }
        if let Some(constructor) = self.program.constructors.get(function) {
            return Callee::Known(method_key(&constructor.name, "__ctor"), constructor);
        }
        if let Some(f) = module.functions.iter().find(|f| f.name == function && !f.is_generic_func) {
            return Callee::Known(function.to_string(), f);
        }
        Callee::Unknown
    }

    /// The method `this.method` calls, and whether it is static (the
    /// receiver names a type, not a value).
    fn resolve_method(&self, this: &Expression, method: &str) -> (Callee<'a>, bool) {
        let receiver_is_local = matches!(this, Expression::SymbolRef { id, .. } if self.local(id).is_some()) || matches!(this, Expression::ThisRef);
        if let Expression::SymbolRef { id, .. } = this
            && !receiver_is_local
            && let Some(st) = self.program.struct_named(id)
        {
            return match st.method_members.iter().find(|m| m.name == method) {
                Some(m) => (Callee::Known(method_key(&st.name, method), m), true),
                None => (Callee::Unknown, true),
            };
        }
        let Some(ty) = self.ty(this) else { return (Callee::Unknown, false) };
        let owner = ty.to_string().trim_end_matches('*').to_string();
        if let Some(st) = self.program.struct_named(&owner) {
            return match st.method_members.iter().find(|m| m.name == method) {
                Some(m) => (Callee::Known(method_key(&st.name, method), m), m.is_static),
                None => (Callee::Unknown, false),
            };
        }
        if self.program.is_trait(&ty) {
            let keys = self
                .program
                .module
                .structs
                .iter()
                .filter(|st| st.traits.iter().any(|t| t.name == ty.name))
                .filter(|st| st.method_members.iter().any(|m| m.name == method))
                .map(|st| method_key(&st.name, method))
                .collect();
            return (Callee::Trait(keys), false);
        }
        (Callee::Unknown, false)
    }

    /// The summary of a call, sized for its operands and results.
    fn summary_of(&self, callee: &Callee, operands: usize, results: usize) -> Option<Summary> {
        let known = |key: &String| match self.program.summaries.get(key) {
            Some(s) => s.clone(),
            None if self.program.bodies.contains(key) => Summary::bottom(operands, results),
            None => Summary::top(operands, results),
        };
        match callee {
            Callee::Known(key, _) => Some(known(key)),
            Callee::Trait(keys) => {
                let mut joined: Option<Summary> = None;
                for key in keys {
                    let s = known(key);
                    joined = Some(match joined {
                        Some(j) => j.join(&s),
                        None => s,
                    });
                }
                Some(joined.unwrap_or_else(|| Summary::top(operands, results)))
            }
            Callee::Unknown => Some(Summary::top(operands, results)),
            Callee::Copy | Callee::Extern => None,
        }
    }

    /// Link a call's operands as its callee does, and give its result a
    /// region.
    fn apply(&mut self, expr: &Expression, callee: Callee, operands: Vec<(Option<usize>, &Expression)>) -> Option<usize> {
        match &callee {
            Callee::Known(key, _) => self.called.push(key.clone()),
            Callee::Trait(keys) => self.called.extend(keys.iter().cloned()),
            _ => {}
        }
        let has_result = self.has_region(expr);
        let summary = match &callee {
            Callee::Copy => return if has_result { Some(self.fresh()) } else { None },
            Callee::Extern => {
                if !has_result && !self.ty(expr).is_some_and(|t| t.is_pointer()) {
                    return None;
                }
                let region = self.fresh();
                self.regions[region].untracked = true;
                return Some(region);
            }
            other => {
                let results = self.ty(expr).map(|t| result_slots(&t)).unwrap_or(1);
                self.summary_of(other, operands.len(), results)?
            }
        };
        let first_result = summary.operands();
        // Link the operands in each class, in operand order.
        let mut class_region: HashMap<usize, usize> = HashMap::new();
        for (slot, (region, operand)) in operands.iter().enumerate() {
            let Some(region) = *region else { continue };
            let class = summary.class.get(slot).copied().unwrap_or(slot);
            // A slot the summary does not know (a variadic or default
            // argument) stays unlinked.
            if slot >= first_result {
                continue;
            }
            match class_region.get(&class) {
                Some(&into) => {
                    let root = self.link(Some(into), Some(region), operand).unwrap();
                    class_region.insert(class, root);
                }
                None => {
                    class_region.insert(class, region);
                }
            }
        }
        if !has_result {
            return None;
        }
        // Each result slot: the region of the operands in its class, or a
        // new one (linked only to thread-safe operands, or to none).
        let mut results: Vec<Option<usize>> = vec![];
        for n in 0..summary.results() {
            let class = summary.class[first_result + n];
            let region = match class_region.get(&class) {
                Some(&linked) => linked,
                None => {
                    let region = self.fresh();
                    // Results in one class share their region.
                    class_region.insert(class, region);
                    region
                }
            };
            if summary.tainted[n] {
                let root = self.find(region);
                if self.regions[root].part == Part::Fresh && self.mode == Mode::Check {
                    self.regions[root].part = Part::Outer;
                }
                self.regions[root].tainted = true;
            }
            results.push(Some(region));
        }
        if results.len() == 1 {
            return results[0];
        }
        Some(self.tuple(results))
    }
}

// ── Describing expressions ───────────────────────────────────────────────────

/// An expression as the programmer wrote it, near enough for a message.
fn describe(expr: &Expression) -> String {
    match expr {
        Expression::SymbolRef { id, .. } => id.clone(),
        Expression::ThisRef => "this".to_string(),
        Expression::MemberRef { lhs, name, .. } => match lhs.as_ref() {
            Expression::ThisRef => name.clone(),
            lhs => format!("{}.{}", describe(lhs), name),
        },
        Expression::IntLiteral(v) => v.to_string(),
        Expression::StringLiteral { value, .. } => format!("\"{value}\""),
        Expression::MethodCall { this, method, args, .. } if method == "__index_get" => {
            format!("{}[{}]", describe(this), args.iter().map(describe).collect::<Vec<_>>().join(", "))
        }
        Expression::MethodCall { this, method, args, .. } => {
            let name = method.split('<').next().unwrap_or(method);
            format!("{}.{}({})", describe(this), name, args.iter().map(describe).collect::<Vec<_>>().join(", "))
        }
        Expression::FunctionCall { function, args, .. } => {
            // A string literal becomes `String(raw, size, length)`.
            if function == "String"
                && let Some(Expression::StringLiteral { value, .. }) = args.first()
            {
                return format!("\"{value}\"");
            }
            let name = function.split('<').next().unwrap_or(function);
            format!("{}({})", name, args.iter().map(describe).collect::<Vec<_>>().join(", "))
        }
        Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => format!("{}[{}]", describe(lhs), describe(rhs)),
        Expression::Cast { expr, .. } | Expression::ToTrait { value: expr, .. } => describe(expr),
        _ => "value".to_string(),
    }
}

// ── The pass ─────────────────────────────────────────────────────────────────

/// Every compiled function body, with the struct it belongs to and its
/// summary key.
fn bodies(module: &Module) -> Vec<(Option<TypeName>, String, &FunctionDef)> {
    let mut out = vec![];
    for f in module.functions.iter().filter(|f| !f.is_generic_func && f.body.is_some()) {
        out.push((None, f.name.clone(), f));
    }
    for st in module.structs.iter().filter(|st| !(st.name == st.ty.name && st.ty.is_generic())) {
        let owner = Some(TypeName::new(&st.name));
        for m in st.method_members.iter().filter(|m| !m.is_generic_func && m.body.is_some()) {
            out.push((owner.clone(), method_key(&st.name, &m.name), m));
        }
        for constructor in st.constructors.iter().filter(|c| c.body.is_some()) {
            out.push((owner.clone(), method_key(&constructor.name, "__ctor"), constructor));
        }
    }
    out
}

/// The number of operand slots of `function`: `this` (for a non-static
/// method) and its parameters.
fn slots(owner: &Option<TypeName>, key: &str, function: &FunctionDef) -> usize {
    let this = owner.is_some() && !function.is_static && !key.ends_with(".__ctor");
    function.parameters.len() + usize::from(this)
}

/// Summarize one function with the current summaries; also the keys of the
/// functions it calls.
fn summarize(program: &Program, owner: &Option<TypeName>, key: &str, function: &FunctionDef) -> (Summary, Vec<String>) {
    let n = slots(owner, key, function);
    let results = result_slots(&function.ty);
    let mut walk = Walk::new(program, Mode::Summarize, owner.clone());
    // A constructor's `this` is the object it builds: a local of its body.
    walk.function(function, function.is_static || key.ends_with(".__ctor"));
    let operand_regions = walk.operands.clone();
    // Every returned value, element by element for a tuple result.
    let mut result: Vec<Option<usize>> = vec![None; results];
    let mut blame = None;
    for (value, loc) in walk.returns.clone() {
        let Some(value) = value else { continue };
        let parts = walk.parts(value);
        let elements: Vec<Vec<usize>> = if results > 1 && parts.len() == results {
            parts.into_iter().map(|p| p.map(|p| walk.leaves(p)).unwrap_or_default()).collect()
        } else {
            vec![walk.leaves(value); results]
        };
        for (slot, leaves) in elements.into_iter().enumerate() {
            for leaf in leaves {
                let root = walk.find(leaf);
                if (walk.regions[root].tainted || !walk.regions[root].operands.is_empty()) && blame.is_none() {
                    blame = Some(loc);
                }
                result[slot] = Some(match result[slot] {
                    Some(r) => walk.union(r, leaf).unwrap_or(r),
                    None => leaf,
                });
            }
        }
    }
    let mut summary = Summary::bottom(n, results);
    let roots: Vec<Option<usize>> = operand_regions.iter().map(|r| r.map(|r| walk.find(r))).collect();
    for slot in 0..n {
        if let Some(root) = roots[slot] {
            summary.class[slot] = (0..n).find(|&s| roots[s] == Some(root)).unwrap_or(slot);
        }
    }
    let result_roots: Vec<Option<usize>> = result.iter().map(|r| r.map(|r| walk.find(r))).collect();
    for k in 0..results {
        let Some(root) = result_roots[k] else { continue };
        if let Some(slot) = (0..n).find(|&s| roots[s] == Some(root)) {
            summary.class[n + k] = summary.class[slot];
        } else if let Some(other) = (0..k).find(|&j| result_roots[j] == Some(root)) {
            summary.class[n + k] = summary.class[n + other];
        }
        summary.tainted[k] = walk.regions[root].tainted;
    }
    summary.blame = blame;
    if has_attribute(&function.attributes, RETURNS_OWNED_ATTRIBUTE) {
        for k in 0..results {
            summary.class[n + k] = n + k;
            summary.tainted[k] = false;
        }
        summary.blame = None;
    }
    (summary, walk.called)
}

/// The link summaries of the functions `roots` reach, as a least fixed
/// point: a worklist that summarizes each function once its callees'
/// summaries are known, and again when one of them changes.
fn summaries(program: &mut Program, roots: Vec<String>) {
    let all: HashMap<String, (Option<TypeName>, &FunctionDef)> =
        bodies(program.module).into_iter().map(|(owner, key, function)| (key, (owner, function))).collect();
    let mut callers: HashMap<String, Vec<String>> = HashMap::new();
    let mut queue: std::collections::VecDeque<String> = std::collections::VecDeque::new();
    let mut queued: std::collections::HashSet<String> = std::collections::HashSet::new();
    for key in roots {
        if let Some((owner, function)) = all.get(&key)
            && queued.insert(key.clone())
        {
            program.summaries.insert(key.clone(), Summary::bottom(slots(owner, &key, function), result_slots(&function.ty)));
            queue.push_back(key);
        }
    }
    let mut budget = MAX_ROUNDS * all.len().max(1);
    while let Some(key) = queue.pop_front() {
        queued.remove(&key);
        if budget == 0 {
            break;
        }
        budget -= 1;
        let (owner, function) = &all[&key];
        let (summary, called) = summarize(program, owner, &key, function);
        for callee in called {
            let Some((callee_owner, callee_function)) = all.get(&callee) else { continue };
            let list = callers.entry(callee.clone()).or_default();
            if !list.contains(&key) {
                list.push(key.clone());
            }
            if !program.summaries.contains_key(&callee) {
                program.summaries.insert(callee.clone(), Summary::bottom(slots(callee_owner, &callee, callee_function), result_slots(&callee_function.ty)));
                queued.insert(callee.clone());
                queue.push_back(callee);
            }
        }
        let changed = program.summaries.get(&key).map(|s| (&s.class, &s.tainted)) != Some((&summary.class, &summary.tainted));
        program.summaries.insert(key.clone(), summary);
        if changed {
            for caller in callers.get(&key).cloned().unwrap_or_default() {
                if queued.insert(caller.clone()) {
                    queue.push_back(caller);
                }
            }
        }
    }
}

/// The functions whose checks need summaries: those with a `with` block
/// (over an `[Isolated]` guard or not; the walk tells) or a call to a
/// function with a `[Sending]` parameter (by name, generously).
fn roots(module: &Module) -> Vec<String> {
    let mut sending: std::collections::HashSet<String> = std::collections::HashSet::new();
    for st in &module.structs {
        for constructor in &st.constructors {
            if constructor.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
                sending.insert(st.name.clone());
                sending.insert(constructor.name.clone());
            }
        }
        for m in &st.method_members {
            if m.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
                sending.insert(m.name.clone());
            }
        }
    }
    for f in &module.functions {
        if f.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
            sending.insert(f.name.clone());
        }
    }
    let mut out = vec![];
    for (_, key, function) in bodies(module) {
        let Some(body) = &function.body else { continue };
        let mut body = body.clone();
        let mut found = false;
        crate::passes::walk_block(&mut body, &mut |e: &mut Expression| match e {
            Expression::SymbolRef { id, .. } if id.starts_with("__with_scope_") => found = true,
            Expression::FunctionCall { function, .. } | Expression::MethodCall { method: function, .. } if sending.contains(function.as_str()) => {
                found = true
            }
            _ => {}
        });
        if found {
            out.push(key);
        }
    }
    out
}

pub fn check_confinement(module: &mut Module) {
    let module: &Module = module;
    let mut program = Program::new(module);
    if check_mutex_arguments(&program) || check_guard_fields(&program) || check_returns_owned(&program) {
        return;
    }
    let roots = roots(module);
    // Only a function with a `with` block needs the region walk.
    let with_blocks: std::collections::HashSet<String> = roots.iter().cloned().collect();
    if !roots.is_empty() {
        summaries(&mut program, roots);
    }
    let triggers = triggers(&program);
    for (owner, key, function) in bodies(module) {
        let regions = with_blocks.contains(&key);
        if !regions && !mentions(function, &triggers) {
            continue;
        }
        if let Some(error) = check_function(&program, &owner, function, regions) {
            crate::errors::report(error);
            return;
        }
    }
}

/// The names a function must mention for the expression checks to find
/// anything: methods that return a guard, guard types (constructed or
/// declared), `get` (on a `ThreadLocal`), and callees with a `[Sending]`
/// parameter.
fn triggers(program: &Program) -> std::collections::HashSet<String> {
    let mut names: std::collections::HashSet<String> = ["get".to_string()].into_iter().collect();
    for st in &program.module.structs {
        if program.isolated.contains(&st.name) {
            names.insert(st.name.clone());
        }
        for m in &st.method_members {
            if program.is_isolated(&m.ty) || m.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
                names.insert(m.name.clone());
            }
        }
        for constructor in &st.constructors {
            if constructor.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
                names.insert(st.name.clone());
                names.insert(constructor.name.clone());
            }
        }
    }
    for f in &program.module.functions {
        if program.is_isolated(&f.ty) || f.parameters.iter().any(|p| has_attribute(&p.attributes, SENDING_ATTRIBUTE)) {
            names.insert(f.name.clone());
        }
    }
    names
}

/// Whether `function` calls, constructs or declares anything in `names`.
fn mentions(function: &FunctionDef, names: &std::collections::HashSet<String>) -> bool {
    fn expression(e: &Expression, names: &std::collections::HashSet<String>) -> bool {
        let hit = match e {
            Expression::FunctionCall { function, .. } => names.contains(function),
            Expression::MethodCall { method, .. } => names.contains(method),
            _ => false,
        };
        hit || children(e).into_iter().any(|c| expression(c, names))
    }
    fn block(b: &Block, names: &std::collections::HashSet<String>) -> bool {
        b.items.iter().any(|statement| match statement {
            Statement::Expression(e) => expression(e, names),
            Statement::Block(inner) => block(inner, names),
            Statement::Declaration(Declaration::Variable(var)) => {
                names.contains(&var.ty.to_string()) || var.default.as_ref().is_some_and(|d| expression(d, names))
            }
            Statement::Declaration(_) => false,
            Statement::Branch(branch) => {
                expression(&branch.condition, names) || block(&branch.if_block, names) || branch.else_block.as_ref().is_some_and(|e| block(e, names))
            }
            Statement::While(wh) => expression(&wh.condition, names) || block(&wh.block, names),
            Statement::Return(ret) => ret.expr.as_ref().is_some_and(|e| expression(e, names)),
            Statement::LoopBreak(_) => false,
        })
    }
    function.parameters.iter().any(|p| names.contains(&p.ty.to_string())) || function.body.as_ref().is_some_and(|b| block(b, names))
}

/// Whether the function or method with summary key `key` (a function's
/// name, or `Struct.method`) returns a fresh value: one that shares nothing
/// with its inputs, so it may move into a locked value or be passed to a
/// `[Sending]` parameter. `None` when it has no body or returns a value of
/// a thread-safe type (which crosses freely anyway). For the language
/// server's hover.
pub fn returns_fresh(module: &Module, key: &str) -> Option<bool> {
    let mut program = Program::new(module);
    let function = bodies(module).into_iter().find(|(_, k, _)| k == key).map(|(_, _, f)| f)?;
    if !program.has_region(&function.ty) {
        return None;
    }
    summaries(&mut program, vec![key.to_string()]);
    program.summaries.get(key).map(Summary::fresh)
}

/// `[ReturnsOwned]` is an unchecked promise: only the runtime may make it.
fn check_returns_owned(program: &Program) -> bool {
    let mut runtime: Option<Option<std::path::PathBuf>> = None;
    for (_, _, function) in bodies(program.module) {
        let Some(attribute) = function.attributes.iter().find(|a| {
            matches!(&a.body, pepper_parser::ast::Expression::SymbolRef { id, .. } if id == RETURNS_OWNED_ATTRIBUTE)
        }) else {
            continue;
        };
        let file = function.loc.file;
        let directory = runtime.get_or_insert_with(|| {
            let (sources, _, _) = pepper_files::runtime::discover();
            sources.first().and_then(|s| s.parent()).and_then(|d| d.canonicalize().ok())
        });
        use pepper_parser::diagnostic::Sources;
        let in_runtime = match (directory, program.module.sources.get(file)) {
            (Some(directory), Some((name, _))) => {
                std::path::Path::new(name).canonicalize().is_ok_and(|path| path.starts_with(directory.as_path()))
            }
            // No runtime to compare with: nothing to protect.
            (None, _) => true,
            _ => false,
        };
        if !in_runtime {
            crate::errors::report(
                Diagnostic::error(format!("'[{}]' is only allowed in the runtime", RETURNS_OWNED_ATTRIBUTE))
                    .at(Loc::new(file, attribute.span))
                    .with_note("it promises the result shares nothing with any other value, which the compiler cannot check", None),
            );
            return true;
        }
    }
    false
}

/// A guard kept in a struct's field would hold its lock past any block.
fn check_guard_fields(program: &Program) -> bool {
    for st in &program.module.structs {
        if program.isolated.contains(&st.name) || (st.name == st.ty.name && st.ty.is_generic()) {
            continue;
        }
        let Some(field) = st.field_members.iter().find(|f| program.is_isolated(&f.ty)) else { continue };
        let at = [field.type_loc, field.loc].into_iter().find(|l| !l.is_none()).unwrap_or(st.loc);
        crate::errors::report(
            Diagnostic::error(format!("'{}' can only be the scope of a 'with' block", field.ty.display()))
                .at(at)
                .with_note("a guard kept in a field would hold its lock past the block; lock where the value is used", None),
        );
        return true;
    }
    false
}

/// `Mutex<T>` of a number: its `with` binding would be a copy the block
/// could never change back.
fn check_mutex_arguments(program: &Program) -> bool {
    for st in &program.module.structs {
        let Some(argument) = st.ty.sub_types.first() else { continue };
        let is_mutex = st.ty.name == "Mutex"
            && st.method_members.iter().any(|m| m.name == "lock" && program.is_isolated(&m.ty));
        if !is_mutex || st.name == st.ty.name || !(argument.is_integral() || argument.is_pointer()) {
            continue;
        }
        let at = use_site(program.module, &st.name).unwrap_or(st.loc);
        crate::errors::report(
            Diagnostic::error(format!("'{}' cannot protect a number: its 'with' binding is a copy that the block cannot store back", st.ty.display()))
                .at(at)
                .with_note(format!("use 'Atomic<{}>' for a number that threads share", argument.display()), None),
        );
        return true;
    }
    false
}

/// Every check on one function; the first error.
fn check_function(program: &Program, owner: &Option<TypeName>, function: &FunctionDef, regions: bool) -> Option<Diagnostic> {
    let exempt = owner.as_ref().is_some_and(|o| program.is_isolated(o)) || program.is_isolated(&function.ty);
    let is_static = function.is_static || function.name == owner.as_ref().map(|o| o.to_string()).unwrap_or_default();
    if regions {
        let mut walk = Walk::new(program, Mode::Check, owner.clone());
        walk.function(function, is_static);
        if let Some(error) = walk.error {
            return Some(error);
        }
    }
    let mut checks = Checks { program, walk: Walk::new(program, Mode::Check, owner.clone()), exempt, error: None };
    checks.walk.function(&FunctionDef { body: None, ..function.clone() }, is_static);
    if let Some(body) = &function.body {
        checks.block(body);
    }
    checks.error
}

/// The checks that look at single expressions: guard use, `[Sending]`
/// arguments and `ThreadLocal.get`.
struct Checks<'p, 'a> {
    program: &'p Program<'a>,
    /// For types and local lookups.
    walk: Walk<'p, 'a>,
    /// A function that makes guards (it returns one, or is the guard's own
    /// method).
    exempt: bool,
    error: Option<Diagnostic>,
}

impl Checks<'_, '_> {
    fn block(&mut self, block: &Block) {
        self.walk.scopes.push(vec![]);
        for statement in &block.items {
            if self.error.is_some() {
                break;
            }
            match statement {
                Statement::Expression(e) => self.expression(e, false),
                Statement::Block(inner) => self.block(inner),
                Statement::Declaration(Declaration::Variable(var)) => {
                    let scope = var.name.starts_with("__with_scope_");
                    if let Some(d) = &var.default {
                        self.expression(d, scope);
                    }
                    let ty = if var.ty.is_auto() { var.default.as_ref().and_then(|d| self.walk.ty(d)).unwrap_or_else(TypeName::auto) } else { var.ty.clone() };
                    if !scope && !var.hidden && !self.exempt && self.program.is_isolated(&ty) && !var.type_loc.is_none() {
                        self.guard_error(&ty, var.type_loc);
                    }
                    self.walk.declare(&var.name, None, ty);
                }
                Statement::Declaration(_) => {}
                Statement::Branch(b) => {
                    self.expression(&b.condition, false);
                    self.block(&b.if_block);
                    if let Some(e) = &b.else_block {
                        self.block(e);
                    }
                }
                Statement::While(w) => {
                    self.expression(&w.condition, false);
                    self.block(&w.block);
                }
                Statement::Return(r) => {
                    if let Some(e) = &r.expr {
                        self.expression(e, false);
                    }
                }
                Statement::LoopBreak(_) => {}
            }
        }
        self.walk.scopes.pop();
    }

    fn guard_error(&mut self, ty: &TypeName, at: Loc) {
        if self.error.is_none() {
            self.error = Some(
                Diagnostic::error(format!("'{}' can only be the scope of a 'with' block", ty.display()))
                    .at(at)
                    .with_note("a guard unlocks when its block ends; write 'with (var value = ...) { ... }'", None),
            );
        }
    }

    /// Check `expr` and everything in it. `scope`: it is a `with` header's
    /// scope, where a guard belongs.
    fn expression(&mut self, expr: &Expression, scope: bool) {
        if self.error.is_some() {
            return;
        }
        if !scope
            && !self.exempt
            && !matches!(expr, Expression::SymbolRef { id, .. } if id.starts_with("__with_scope_"))
            && self.walk.ty(expr).is_some_and(|t| self.program.is_isolated(&t))
        {
            let ty = self.walk.ty(expr).unwrap();
            self.guard_error(&ty, expr.loc());
            return;
        }
        match expr {
            Expression::MethodCall { this, method, args, loc } => {
                self.thread_local_get(this, method, *loc);
                let (callee, _) = self.walk.resolve_method(this, method);
                self.sending(&callee, args);
            }
            Expression::FunctionCall { function, args, .. } => {
                let callee = self.walk.resolve_function(function);
                self.sending(&callee, args);
            }
            _ => {}
        }
        for child in children(expr) {
            self.expression(child, false);
        }
    }

    /// `ThreadLocal<T>.get()` for a `T` that is not thread-safe.
    fn thread_local_get(&mut self, this: &Expression, method: &str, loc: Loc) {
        if method != "get" || self.error.is_some() {
            return;
        }
        let Some(ty) = self.walk.ty(this) else { return };
        let Some(value) = ty.sub_types.first() else { return };
        let is_thread_local = ty.name == "ThreadLocal"
            && self.program.struct_named(&ty.to_string()).is_some_and(|st| {
                st.method_members.iter().any(|m| m.name == "enter" && self.program.is_isolated(&m.ty))
            });
        if !is_thread_local || unsafe_part_in(value, &self.program.safe).is_none() {
            return;
        }
        self.error = Some(
            Diagnostic::error(format!(
                "'get' is not available on '{}', because '{}' is not thread-safe",
                ty.display(),
                value.display()
            ))
            .at(loc)
            .with_note(format!("reach this thread's value with 'with (var value = {}.enter())'", describe(this)), None),
        );
    }

    /// Each argument to a `[Sending]` parameter must be disconnected.
    fn sending(&mut self, callee: &Callee, args: &[Expression]) {
        let Callee::Known(_, function) = callee else { return };
        for (parameter, arg) in function.parameters.iter().zip(args) {
            if self.error.is_some() || !has_attribute(&parameter.attributes, SENDING_ATTRIBUTE) {
                continue;
            }
            if self.disconnected(arg) {
                continue;
            }
            let what = describe(arg);
            let mut diagnostic = Diagnostic::error(format!(
                "'{what}' is not a new value, but parameter '{}' takes a value that nothing else references",
                parameter.name
            ))
            .at(arg.loc())
            .with_note(format!("'{}' is declared [Sending] here", parameter.name), parameter.loc.known());
            if let Some(blame) = self.blame(arg) {
                diagnostic = diagnostic.with_note(format!("'{}' does not return a new value: this return shares its inputs", describe(arg)), blame.known());
            }
            self.error = Some(diagnostic.with_note(format!("pass a new value, such as 'copy({what})'"), None));
        }
    }

    /// The `return` that keeps a call's result from being fresh.
    fn blame(&self, arg: &Expression) -> Option<Loc> {
        let callee = match arg {
            Expression::FunctionCall { function, .. } => self.walk.resolve_function(function),
            Expression::MethodCall { this, method, .. } => self.walk.resolve_method(this, method).0,
            _ => return None,
        };
        let Callee::Known(key, _) = callee else { return None };
        self.program.summaries.get(&key).and_then(|s| s.blame)
    }

    /// A disconnected expression: nothing else references its value.
    fn disconnected(&self, expr: &Expression) -> bool {
        if !self.walk.has_region(expr) {
            return true;
        }
        match expr {
            Expression::StringLiteral { .. } | Expression::PointerLiteral | Expression::Default(_) | Expression::Allocate(_) => true,
            Expression::Cast { expr, .. } | Expression::ToTrait { value: expr, .. } => self.disconnected(expr),
            Expression::Ternary { true_expr, false_expr, .. } => self.disconnected(true_expr) && self.disconnected(false_expr),
            Expression::FunctionCall { function, args, .. } => {
                if function == crate::type_name::TUPLE || function.starts_with(&format!("{}<", crate::type_name::TUPLE)) {
                    return args.iter().all(|a| self.disconnected(a));
                }
                let callee = self.walk.resolve_function(function);
                self.call_disconnected(expr, &callee, args.iter().collect())
            }
            Expression::MethodCall { this, method, args, .. } => {
                let (callee, is_static) = self.walk.resolve_method(this, method);
                let mut operands: Vec<&Expression> = vec![];
                if !is_static {
                    operands.push(this);
                }
                operands.extend(args.iter());
                self.call_disconnected(expr, &callee, operands)
            }
            _ => false,
        }
    }

    /// A call's result is disconnected when the operands in its class are.
    fn call_disconnected(&self, call: &Expression, callee: &Callee, operands: Vec<&Expression>) -> bool {
        let results = self.walk.ty(call).map(|t| result_slots(&t)).unwrap_or(1);
        let summary = match callee {
            Callee::Copy => return true,
            Callee::Extern => return false,
            other => match self.walk.summary_of(other, operands.len(), results) {
                Some(s) => s,
                None => return false,
            },
        };
        let first_result = summary.operands();
        (0..summary.results()).all(|n| {
            let result = summary.class[first_result + n];
            !summary.tainted[n]
                && operands
                    .iter()
                    .enumerate()
                    .filter(|(slot, _)| *slot < first_result && summary.class[*slot] == result)
                    .all(|(_, operand)| self.disconnected(operand))
        })
    }
}

/// The direct sub-expressions of `expr` (like `passes::children_mut`).
fn children(expr: &Expression) -> Vec<&Expression> {
    match expr {
        Expression::SymbolRef { .. }
        | Expression::ThisRef
        | Expression::BoolLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral
        | Expression::SizeOf(_)
        | Expression::IsPod(_)
        | Expression::Default(_)
        | Expression::Allocate(_)
        | Expression::FunctionRef { .. }
        | Expression::MethodAddress(_)
        | Expression::CountStep { .. }
        | Expression::FunctionPointer { .. }
        | Expression::ClosureLiteral(_) => vec![],
        Expression::MemberRef { lhs, .. } => vec![lhs],
        Expression::Binary { lhs, rhs, .. } | Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => vec![lhs, rhs],
        Expression::Unary { operand, .. } => vec![operand],
        Expression::Cast { expr, .. } => vec![expr],
        Expression::Ternary { condition, true_expr, false_expr } => vec![condition, true_expr, false_expr],
        Expression::RefCount(_, arg)
        | Expression::Address(_, arg)
        | Expression::Weak(_, _, arg)
        | Expression::AtomicLoad(_, arg)
        | Expression::ForIterator(arg)
        | Expression::WithEntered(arg) => vec![arg],
        Expression::MatchArm(test) => vec![&test.subject],
        Expression::Destructure { value, .. } => vec![value],
        Expression::AtomicStore(_, a, b) | Expression::AtomicFetch(_, _, a, b) => vec![a, b],
        Expression::AtomicCmpXchg(_, a, b, c) => vec![a, b, c],
        Expression::FunctionCall { args, .. } => args.iter().collect(),
        Expression::MethodCall { this, args, .. } => std::iter::once(this.as_ref()).chain(args.iter()).collect(),
        Expression::Invoke { callee, args } => std::iter::once(callee.as_ref()).chain(args.iter()).collect(),
        Expression::CallPointer { pointer, args } => std::iter::once(pointer.as_ref()).chain(args.iter()).collect(),
        Expression::MakeClosure { value, .. } | Expression::ToTrait { value, .. } => vec![value],
    }
}

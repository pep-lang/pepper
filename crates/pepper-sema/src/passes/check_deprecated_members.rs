//! Uses of deprecated members: a field or method (an extension's included)
//! marked `[Deprecated(...)]`, reached as `x.name`, `x.name(...)`, a static
//! `S.name(...)`, or a bare `name` inside a method. Which struct a member
//! belongs to depends on the type of `x`, so this runs on the sema model
//! once every type is final; uses of top-level names are found on the AST
//! (see `crate::deprecation`). Each warning is added to `module.warnings`.
//!
//! A use is reported only where the source spells the member's name at the
//! use's location. That leaves out the calls sema synthesizes (a `for`
//! loop's `next()`, a `with` block's `enter()`, an operator overload), whose
//! locations point at the expression they stand for. Uses inside a
//! deprecated function, method, or struct are not reported, and each
//! location is reported once, however many specializations share it.

use crate::deprecation::{Deprecation, declared, warning};
use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;
use pepper_parser::diagnostic::{SourceMap, Sources};
use std::collections::{HashMap, HashSet};

/// Owner type (a struct or trait, by name or specialization) -> member name
/// -> its deprecation and where it is declared.
type Members = HashMap<String, HashMap<String, (Deprecation, Loc)>>;

/// The `Members` owner under which overloaded constructors are listed, by
/// function name.
const CONSTRUCTORS: &str = "";

pub fn check_deprecated_members(module: &mut Module) {
    let mut members: Members = HashMap::new();
    let mut add = |owner: &str, name: &str, attributes: &[pepper_parser::ast::Attribute], at: Loc| {
        if let Some(deprecation) = declared(attributes) {
            members.entry(owner.to_string()).or_default().insert(name.to_string(), (deprecation, at));
        }
    };
    for st in &module.structs {
        for f in &st.field_members {
            add(&st.name, &f.name, &f.attributes, f.loc);
        }
        for m in &st.method_members {
            add(&st.name, &m.name, &m.attributes, m.loc);
        }
        for m in &st.generic_methods {
            add(&st.name, &m.name, &m.attributes, m.loc);
        }
    }
    for t in &module.traits {
        for m in &t.methods {
            add(&t.name, &m.name, &m.attributes, m.loc);
        }
    }
    // An enum's methods are the functions `E::m`, which calls reach by that
    // name once `c.m()` is resolved.
    for f in &module.functions {
        if let Some((_, method)) = crate::enums::method_of(&f.name) {
            add(&f.name, method, &f.attributes, f.loc);
        }
    }
    // An overloaded constructor (`Point$2`, `Box<int>$2`) is deprecated on
    // its own; its calls are only known once overloads are resolved. A
    // single constructor is checked on the AST with the struct.
    for st in module.structs.iter().filter(|st| st.constructors.len() > 1) {
        for c in &st.constructors {
            add(CONSTRUCTORS, &c.name, &c.attributes, c.loc);
        }
    }
    if members.is_empty() {
        return;
    }
    let sources = std::mem::take(&mut module.sources);
    let mut checker = Checker {
        members,
        table: StructTable::build(module),
        sources: &sources,
        seen: HashSet::new(),
        warnings: vec![],
    };
    for function in &mut module.functions {
        if declared(&function.attributes).is_none() {
            checker.function(function, None);
        }
    }
    for st in &mut module.structs {
        if declared(&st.attributes).is_some() {
            continue;
        }
        let current = st.ty.clone();
        for constructor in &mut st.constructors {
            checker.function(constructor, Some(&current));
        }
        checker.function(&mut st.destructor, Some(&current));
        for method in &mut st.method_members {
            if declared(&method.attributes).is_none() {
                checker.function(method, Some(&current));
            }
        }
    }
    for var in &mut module.globals {
        if declared(&var.attributes).is_none() {
            super::walk_global(var, &mut |e| checker.expression(e, None));
        }
    }
    let warnings = checker.warnings;
    module.sources = sources;
    module.warnings.extend(warnings);
}

struct Checker<'a> {
    members: Members,
    table: StructTable,
    sources: &'a SourceMap,
    /// Locations already reported.
    seen: HashSet<(u32, usize)>,
    warnings: Vec<Diagnostic>,
}

impl Checker<'_> {
    fn function(&mut self, function: &mut FunctionDef, current: Option<&TypeName>) {
        super::walk_function(function, &mut |e| self.expression(e, current));
    }

    fn expression(&mut self, expr: &Expression, current: Option<&TypeName>) {
        match expr {
            Expression::MethodCall { this, method, loc, .. } => self.member(this, method, *loc, current),
            Expression::MemberRef { lhs, name, loc } => self.member(lhs, name, *loc, current),
            Expression::FunctionCall { function, loc, .. } => {
                self.constructor(function, *loc);
                if let Some((_, method)) = crate::enums::method_of(function) {
                    let owner = Expression::SymbolRef { id: function.clone(), ty: TypeName::auto(), loc: Loc::NONE };
                    self.member(&owner, method, *loc, current);
                }
            }
            _ => {}
        }
    }

    /// A call to overloaded constructor `function` (`Point$2`) at `used`,
    /// where the source spells the type (`Point`, `Box<int>` or `Box`).
    fn constructor(&mut self, function: &str, used: Loc) {
        let Some((deprecation, declared_at)) = self.members.get(CONSTRUCTORS).and_then(|m| m.get(function)).cloned()
        else {
            return;
        };
        let Some(used_at) = used.known() else { return };
        let ty = super::overloads::set_name(function);
        let base = ty.split('<').next().unwrap_or(ty);
        let spelled = self
            .sources
            .get(used_at.file)
            .and_then(|(_, text)| text.get(used_at.span.start..used_at.span.end))
            .unwrap_or("");
        if (spelled != ty && spelled != base) || !self.seen.insert((used_at.file.0, used_at.span.start)) {
            return;
        }
        self.warnings.push(warning(base, &deprecation, used_at, spelled, declared_at));
    }

    /// The use of member `name` of `owner` at `used`.
    fn member(&mut self, owner: &Expression, name: &str, used: Loc, current: Option<&TypeName>) {
        // A generic method's specialization (`pick<int>`) is a use of `pick`.
        let name = name.split('<').next().unwrap_or(name);
        let Some(used_at) = used.known() else { return };
        let Some((deprecation, declared_at)) = self.lookup(owner, name, current) else { return };
        if used_at == declared_at {
            return;
        }
        let spelled = self
            .sources
            .get(used_at.file)
            .and_then(|(_, text)| text.get(used_at.span.start..used_at.span.end))
            .unwrap_or("");
        if spelled != name || !self.seen.insert((used_at.file.0, used_at.span.start)) {
            return;
        }
        self.warnings.push(warning(name, &deprecation, used_at, spelled, declared_at));
    }

    /// The deprecation of member `name` of the type of `owner`, if it has one.
    fn lookup(&self, owner: &Expression, name: &str, current: Option<&TypeName>) -> Option<(Deprecation, Loc)> {
        let ty = static_type::of(owner, &self.table, current).or_else(|| match owner {
            // A static call names the struct itself: `S.make()`.
            Expression::SymbolRef { id, .. } => Some(TypeName::new(id)),
            _ => None,
        })?;
        let full = ty.to_string();
        let pointee = full.trim_end_matches('*');
        let base = pointee.split('<').next().unwrap_or(pointee);
        [pointee, base]
            .iter()
            .find_map(|owner| self.members.get(*owner).and_then(|m| m.get(name)))
            .cloned()
    }
}

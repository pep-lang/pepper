//! What a member access names, for the language server: the field or
//! method that `lhs.name` (or `lhs.name(...)`) reaches, found by the static
//! type of `lhs` in the checked model. Chains need nothing special:
//! `x.y.z` types `x.y` first, as codegen would.

use pepper_parser::diagnostic::{FileId, Loc, Sources};

use crate::model::{Block, Declaration, Expression, FunctionDef, Module, Statement, VariableDef};
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;

/// What a member access names.
pub enum Member<'m> {
    Field(&'m VariableDef),
    Method(&'m FunctionDef),
}

impl Member<'_> {
    /// Where the member is declared.
    pub fn loc(&self) -> Loc {
        match self {
            Member::Field(f) => f.loc,
            Member::Method(m) => m.loc,
        }
    }
}

/// The declaration of the member whose name, in file `file`, covers
/// `offset`: a field's or a method's location. `None` when no member access
/// is there, or its owner's type is not a struct the model knows.
pub fn member_declaration(module: &Module, file: FileId, offset: usize) -> Option<Loc> {
    Some(member_at(module, file, offset)?.loc())
}

/// The type of the field whose name, in file `file`, covers `offset` in a
/// member access (`core` in `worker.core`), as the owner's type has it.
pub fn field_type(module: &Module, file: FileId, offset: usize) -> Option<&TypeName> {
    match member_at(module, file, offset)? {
        Member::Field(f) => Some(&f.ty),
        Member::Method(_) => None,
    }
}

/// The member whose name, in file `file`, covers `offset` (see
/// [`member_declaration`]).
pub fn member_at(module: &Module, file: FileId, offset: usize) -> Option<Member<'_>> {
    // The innermost member name at `offset`, with the struct whose code it
    // is in (what `this` means there).
    let source = module.sources.get(file).map(|(_, text)| text);
    let mut found: Option<(&Expression, &str, Option<&TypeName>, Loc)> = None;
    let mut functions: Vec<(&FunctionDef, Option<&TypeName>)> = module.functions.iter().map(|f| (f, None)).collect();
    for st in &module.structs {
        for function in st.constructors.iter().chain([&st.destructor]).chain(&st.method_members) {
            functions.push((function, Some(&st.ty)));
        }
    }
    for (function, current) in functions {
        crate::passes::visit_function(function, &mut |e| {
            let (owner, name, loc) = match e {
                Expression::MemberRef { lhs, name, loc } => (&**lhs, name.as_str(), *loc),
                Expression::MethodCall { this, method, loc, .. } => (&**this, method.as_str(), *loc),
                _ => return,
            };
            let span = loc.span;
            if loc.file != file || offset < span.start || offset > span.end {
                return;
            }
            // Only a name the source spells there: sema's own calls (`xs[i]`
            // as `__index_get`, a `for` loop's `next()`, an operator method)
            // point at the code they stand for.
            let member = name.split('<').next().unwrap_or(name);
            let member = crate::passes::overloads::set_name(member);
            if source.and_then(|text| text.get(span.start..span.end)) != Some(member) {
                return;
            }
            let width = |l: Loc| l.span.end - l.span.start;
            if found.is_none_or(|(.., best)| width(loc) < width(best)) {
                found = Some((owner, name, current, loc));
            }
        });
    }
    let (owner, name, current, used) = found?;
    let table = StructTable::build(module);
    let ty = static_type::of(owner, &table, current).or_else(|| match owner {
        // A static call names the struct itself: `S.make()`.
        Expression::SymbolRef { id, .. } => Some(TypeName::new(id)),
        _ => None,
    })?;
    let full = ty.to_string();
    let pointee = full.trim_end_matches('*');
    let base = pointee.split('<').next().unwrap_or(pointee);
    // A generic method's specialization (`pick<int>`) is `pick`; an
    // overload member (`add$2`) belongs to its set.
    let name = name.split('<').next().unwrap_or(name);
    let st = module
        .structs
        .iter()
        .find(|s| s.ty.to_string() == pointee)
        .or_else(|| module.structs.iter().find(|s| s.name == base))?;
    let field = st.field_members.iter().find(|f| f.name == name).map(Member::Field);
    let method = || {
        st.method_members
            .iter()
            .chain(&st.generic_methods)
            .find(|m| m.name == name || crate::passes::overloads::set_name(&m.name) == name)
            .map(Member::Method)
    };
    // A captured local is a field of its closure's struct, declared where
    // it is used: not a member the source declares.
    field.or_else(method).filter(|m| !m.loc().is_none() && m.loc() != used && !st.name.starts_with("__closure"))
}

/// The type sema gave the local declared at `name` (the location of its
/// name) in file `file`: what `var worker = _async_worker()` infers. `None`
/// when no checked code declares a local there. In generic code, the first
/// specialization's type stands for all of them.
pub fn local_type(module: &Module, file: FileId, name: usize) -> Option<&TypeName> {
    fn find<'m>(block: &'m Block, file: FileId, name: usize) -> Option<&'m TypeName> {
        block.items.iter().find_map(|statement| match statement {
            Statement::Declaration(Declaration::Variable(v)) => {
                (v.loc.file == file && v.loc.span.start == name && !v.ty.is_auto() && !v.ty.is_empty()).then_some(&v.ty)
            }
            Statement::Block(b) => find(b, file, name),
            Statement::Branch(b) => find(&b.if_block, file, name).or_else(|| b.else_block.as_ref().and_then(|e| find(e, file, name))),
            Statement::While(w) => find(&w.block, file, name),
            _ => None,
        })
    }
    let structs = module.structs.iter().flat_map(|st| st.constructors.iter().chain([&st.destructor]).chain(&st.method_members));
    module.functions.iter().chain(structs).find_map(|f| f.body.as_ref().and_then(|b| find(b, file, name)))
}

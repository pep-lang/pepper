//! What a member access names, for the language server: the field or
//! method that `lhs.name` (or `lhs.name(...)`) reaches, found by the static
//! type of `lhs` in the checked model. Chains need nothing special:
//! `x.y.z` types `x.y` first, as codegen would.

use pepper_parser::diagnostic::{FileId, Loc, Sources};

use crate::model::{Expression, FunctionDef, Module};
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;

/// The declaration of the member whose name, in file `file`, covers
/// `offset`: a field's or a method's location. `None` when no member access
/// is there, or its owner's type is not a struct the model knows.
pub fn member_declaration(module: &Module, file: FileId, offset: usize) -> Option<Loc> {
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
    let field = st.field_members.iter().find(|f| f.name == name).map(|f| f.loc);
    let method = || {
        st.method_members
            .iter()
            .chain(&st.generic_methods)
            .find(|m| m.name == name || crate::passes::overloads::set_name(&m.name) == name)
            .map(|m| m.loc)
    };
    // A captured local is a field of its closure's struct, declared where
    // it is used: not a member the source declares.
    field.or_else(method).filter(|loc| !loc.is_none() && *loc != used && !st.name.starts_with("__closure"))
}

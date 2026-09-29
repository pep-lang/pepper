//! Port of `source/Sema/ReleaseFieldRefs.h`: struct-typed fields get
//! `__release` calls in reverse declaration order at the end of the dtor
//! (the object itself is freed by `__release`, not the dtor).

use crate::model::*;
use crate::symbols::SymbolTable;

pub fn release_field_refs(module: &mut Module) {
    let symbols = SymbolTable::build(module);
    for st_idx in 0..module.structs.len() {
        let struct_type_strings: Vec<String> = module
            .structs
            .iter()
            .flat_map(|st| [st.name.clone(), st.ty.to_string()])
            .collect();

        let st = &mut module.structs[st_idx];
        let field_names: Vec<String> = st
            .field_members
            .iter()
            .filter(|f| {
                f.ty.is_struct()
                    && (struct_type_strings.contains(&f.ty.to_string())
                        || symbols.structs.contains_key(&f.ty.to_string())
                        // A trait value releases through its vtable.
                        || crate::traits::is_trait_type(&module.traits, &f.ty))
            })
            .map(|f| f.name.clone())
            .collect();

        if field_names.is_empty() {
            continue;
        }
        // Codegen emits method bodies from `method_members`, where the
        // synthesized `__dtor` lives: struct_body::finish clones it out of
        // `destructor` before this pass runs, so patch that copy.
        let Some(dtor) = st.method_members.iter_mut().find(|m| m.name == "__dtor") else {
            continue;
        };
        let Some(body) = &mut dtor.body else {
            continue;
        };
        // Append the releases in reverse declaration order, after the user's
        // destructor body.
        let mut releases: Vec<Statement> = field_names
            .iter()
            .map(|name| {
                Statement::Expression(Expression::MethodCall {
                    this: Box::new(Expression::MemberRef {
                        lhs: Box::new(Expression::ThisRef),
                        name: name.clone(),
                        loc: crate::model::Loc::NONE,
                    }),
                    method: "__release".to_string(),
                    args: vec![],
                    loc: crate::model::Loc::NONE,
                })
            })
            .collect();
        releases.reverse();
        body.items.extend(releases);
    }
}

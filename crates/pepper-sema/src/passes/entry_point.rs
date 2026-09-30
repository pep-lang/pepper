//! The program's entry point, `main`, in either form:
//! - `main(): int` takes nothing;
//! - `main(args: String[]): int` takes the command-line arguments, the
//!   program name first, as `arguments()` returns them.
//!
//! The C `main` the compiler emits takes no `argc`/`argv`, so the second
//! form is renamed to [`MAIN_WITH_ARGUMENTS`] and a `main()` is synthesized
//! that calls it with the runtime's `_pep_arguments()`:
//!
//! ```text
//! main(): int { return main@#args(_pep_arguments()); }
//! ```
//!
//! A `void` main is called as a statement and the synthesized one returns 0.

use crate::model::*;
use crate::type_name::TypeName;

/// The model name of a `main` that takes arguments. `#` cannot start a
/// namespace, so no file's private `main` is spelled this way, and messages
/// demangle it to `main`.
pub const MAIN_WITH_ARGUMENTS: &str = "main@#args";

/// The runtime function (runtime/process.pep) that supplies the arguments.
const ARGUMENTS: &str = "_pep_arguments";

/// Whether `function` is the program's entry point, in either form: its
/// return type defaults to `int`.
pub fn is_entry_point(function: &FunctionDef) -> bool {
    function.parent.is_none() && (function.name == "main" || function.name == MAIN_WITH_ARGUMENTS)
}

/// Rewrite a `main(args: String[])` as described in the module comment,
/// reporting any other parameter list on `main`.
pub fn lower_main_arguments(module: &mut Module) {
    let mains: Vec<usize> = (0..module.functions.len())
        .filter(|&i| module.functions[i].name == "main" && module.functions[i].parent.is_none())
        .collect();
    if let [first, second, ..] = mains[..] {
        crate::errors::report(
            Diagnostic::error("redefinition of 'main'")
                .at(module.functions[second].loc)
                .with_note("previous definition is here", Some(module.functions[first].loc)),
        );
        return;
    }
    let Some(&index) = mains.first() else {
        return;
    };
    let main = &module.functions[index];
    match &main.parameters[..] {
        [] => return,
        [param] if is_string_array(&param.ty) && main.generic_params.is_empty() => {}
        [param, ..] => {
            let at = if main.parameters.len() > 1 { main.parameters[1].loc } else { param.type_loc };
            crate::errors::report(
                Diagnostic::error("'main' must take no parameters or one 'String[]'")
                    .at(if at.is_none() { param.loc } else { at }),
            );
            return;
        }
    }
    if main.body.is_none() {
        return;
    }
    if !module.functions.iter().any(|f| f.name == ARGUMENTS && f.parent.is_none()) {
        crate::errors::report(
            Diagnostic::error(format!("'main(args: String[])' needs '{}' from the runtime", ARGUMENTS))
                .at(main.parameters[0].loc),
        );
        return;
    }
    let loc = main.loc;
    let void = main.ty.name == "void" && main.ty.sub_types.is_empty();
    let ty = if void { TypeName::new("int") } else { main.ty.clone() };
    module.functions[index].name = MAIN_WITH_ARGUMENTS.to_string();
    let call = Expression::FunctionCall {
        function: MAIN_WITH_ARGUMENTS.to_string(),
        args: vec![Expression::FunctionCall { function: ARGUMENTS.to_string(), args: vec![], loc: Loc::NONE }],
        loc: Loc::NONE,
    };
    let items = if void {
        vec![
            Statement::Expression(call),
            Statement::Return(ReturnStatement { expr: Some(Expression::IntLiteral(0)), loc: Loc::NONE }),
        ]
    } else {
        vec![Statement::Return(ReturnStatement { expr: Some(call), loc: Loc::NONE })]
    };
    module.functions.push(FunctionDef {
        name: "main".to_string(),
        ty,
        generic_params: vec![],
        parameters: vec![],
        body: Some(Block { name: "main".to_string(), items, attributes: vec![] }),
        parent: None,
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        // The declaration's location, so the build cache gives it the same
        // owner (its file) as the `main` it calls.
        loc,
        trait_default: None,
        owner: Loc::NONE,
    });
}

/// `String[]`, as the builder spells it: `Array<String>`.
fn is_string_array(ty: &TypeName) -> bool {
    ty.name == "Array" && matches!(&ty.sub_types[..], [element] if element.name == "String" && element.sub_types.is_empty())
}

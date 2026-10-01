//! Port of `source/Sema/GatherGenerics.h`: record generic uses as specs.

use crate::model::{Block, Declaration, Diagnostic, Expression, Loc, Module, SpecRequest, Statement};
use crate::passes::walk_function;
use crate::symbols::SymbolTable;
use crate::type_name::TypeName;
use std::collections::BTreeMap;

/// How deep specialization may nest: a generic whose instance asks for a
/// larger instance of itself (`Foo<T>` holding a `Foo<Array<T>>`) never
/// reaches a fixpoint, so past this many links in its chain of requests it
/// is an error at the request.
pub const MAX_SPECIALIZATION_DEPTH: usize = 64;

/// The generic uses found so far, by name: who asked first, and where.
type Requests = BTreeMap<String, (String, Loc)>;

/// Where a variable's type is written, else its name.
fn written(var: &crate::model::VariableDef) -> Loc {
    if var.type_loc.is_none() { var.loc } else { var.type_loc }
}

fn request(requests: &mut Requests, name: &str, by: &str, loc: Loc) {
    requests.entry(name.to_string()).or_insert_with(|| (by.to_string(), loc));
}

pub fn gather_generics(module: &mut Module) {
    concrete_overrides(module);
    let symbols = SymbolTable::build(module);
    let mut functions: Requests = BTreeMap::new();
    let mut structs: Requests = BTreeMap::new();

    // Walk struct bodies for generic calls and TypeLiteral-based generics.
    for st in &mut module.structs {
        let params = param_names(&st.generic_params);
        let owner = st.name.clone();
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, loc, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    let ty = parse_type_string(function);
                    if !contains_param(&ty, &params) {
                        request(&mut functions, function, &owner, *loc);
                    }
                }
            }
        };
        for method in &mut st.method_members {
            walk_function(method, &mut gather);
        }
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            crate::passes::walk_block(body, &mut gather);
        }
        if let Some(body) = &mut st.destructor.body {
            crate::passes::walk_block(body, &mut gather);
        }
        // Struct field/method types carrying generics.
        for field in &st.field_members {
            if field.ty.is_generic()
                && !field.ty.name.starts_with("__")
                && !contains_param(&field.ty, &params)
            {
                request(&mut structs, &field.ty.to_string(), &owner, written(field));
            }
        }
        for method in &st.method_members {
            if method.ty.is_generic()
                && !method.ty.name.starts_with("__")
                && !contains_param(&method.ty, &params)
            {
                request(&mut structs, &method.ty.to_string(), &owner, method.loc);
            }
            for param in &method.parameters {
                if param.ty.is_generic()
                    && !param.ty.name.starts_with("__")
                    && !contains_param(&param.ty, &params)
                {
                    request(&mut structs, &param.ty.to_string(), &owner, written(param));
                }
            }
        }
    }

    for function in &mut module.functions {
        let params = param_names(&function.generic_params);
        let owner = function.name.clone();
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, loc, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    let ty = parse_type_string(function);
                    if !contains_param(&ty, &params) {
                        request(&mut functions, function, &owner, *loc);
                    }
                }
            }
        };
        walk_function(function, &mut gather);
        // A generic function's own parameters (`Array<U>` in `f<U>`) are
        // not a use; its specializations' concrete types are.
        if function.ty.is_generic() && !function.ty.name.starts_with("__") && !contains_param(&function.ty, &params) {
            request(&mut structs, &function.ty.to_string(), &owner, function.loc);
        }
        for param in &function.parameters {
            if param.ty.is_generic() && !param.ty.name.starts_with("__") && !contains_param(&param.ty, &params) {
                request(&mut structs, &param.ty.to_string(), &owner, written(param));
            }
        }
    }

    // Global initializers: `var x = Array<int>()` at file scope must register
    // the specialization too.
    for var in &mut module.globals {
        let owner = var.name.clone();
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, loc, .. } = expr {
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    request(&mut functions, function, &owner, *loc);
                }
            }
        };
        crate::passes::walk_global(var, &mut gather);
        if var.ty.is_generic() && !var.ty.name.starts_with("__") {
            request(&mut structs, &var.ty.to_string(), &owner, written(var));
        }
    }

    for ext in &mut module.extensions {
        // `extend Box<T>` extends the generic base: `Maybe<T>(...)` in its
        // methods is unbound here, like the same call in the struct's body.
        let params = extension_params(&module.structs, ext);
        let owner = ext.target.name.clone();
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, loc, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    let ty = parse_type_string(function);
                    if !contains_param(&ty, &params) {
                        request(&mut functions, function, &owner, *loc);
                    }
                }
            }
        };
        for method in &mut ext.methods {
            walk_function(method, &mut gather);
        }
    }

    // Local variable declarations (`Array<int> a;` with no ctor call) are the
    // only place generic types can appear that fields/params/calls miss.
    for st in &module.structs {
        let params = param_names(&st.generic_params);
        for method in &st.method_members {
            if let Some(body) = &method.body {
                gather_local_declarations(body, &mut structs, &params, &st.name);
            }
        }
        for body in st.constructors.iter().filter_map(|c| c.body.as_ref()) {
            gather_local_declarations(body, &mut structs, &params, &st.name);
        }
    }
    for function in &module.functions {
        let params = param_names(&function.generic_params);
        if let Some(body) = &function.body {
            gather_local_declarations(body, &mut structs, &params, &function.name);
        }
    }

    // Who asked for each, for the depth limit.
    for (name, (by, loc)) in structs.iter().chain(&functions) {
        let key = parse_type_string(name).to_string();
        module.spec_requests.entry(key).or_insert_with(|| SpecRequest { by: by.clone(), loc: *loc });
    }

    // Emit struct specs.
    let mut struct_specs: Vec<TypeName> = module.struct_specs.clone();
    for name in structs.keys() {
        let ty = parse_type_string(name);
        if struct_specs.iter().any(|s| s == &ty) {
            continue;
        }
        if let Some(st) = symbols.struct_by_name(module, &ty.name) {
            if st.ty == ty {
                continue;
            }
            struct_specs.push(ty);
        }
    }
    module.struct_specs = struct_specs;

    // Emit function specs (constructor calls become struct specs).
    let mut func_specs: Vec<TypeName> = module.func_specs.clone();
    for name in functions.keys() {
        let ty = parse_type_string(name);
        if func_specs.iter().any(|s| s == &ty) {
            continue;
        }
        if let Some(st) = symbols.struct_by_name(module, &ty.name) {
            if st.ty == ty || module.struct_specs.iter().any(|s| s == &ty) {
                continue;
            }
            module.struct_specs.push(ty.clone());
            continue;
        }
        if let Some(function) = symbols.function(module, &ty.name) {
            if function.ty == ty {
                continue;
            }
        }
        func_specs.push(ty);
    }
    module.func_specs = func_specs;
}

/// Concrete specializations written as definitions override generic bases:
/// `hash<String>(String value)` is a distinct function from `hash<T>(T)`.
/// The parser cannot tell them apart (both parse as name + generic params),
/// so this pass rewrites any free-function definition whose generic
/// parameters are ALL concrete types into its specialization form, in place:
/// the name becomes `name<args>` (the same string call sites use) and the
/// definition stops being a generic base. The generic base (`hash<T>`) is a
/// separate remaining entry that serves other call sites (`hash<int>`);
/// `specialize_functions` skips cloning a spec whose name already exists, so
/// the user's concrete body wins over the synthesized one. Idempotent —
/// rewritten functions have empty `generic_params` and are skipped on later
/// rounds.
pub(crate) fn concrete_overrides(module: &mut Module) {
    // A struct can be an override's argument too (`describe<Point>` of
    // `describe<T>`), but a struct's name is also a legal generic parameter
    // name: it overrides only when a generic base of the same name and
    // arity exists, one with a parameter that names no type.
    let linked = module.linked;
    let is_struct = |name: &str| module.structs.iter().any(|st| st.ty.name == name);
    let names_type = |p: &str| crate::type_name::is_concrete_override(std::iter::once(p)) || is_struct(p);
    let has_base = |function: &crate::model::FunctionDef| {
        module.functions.iter().any(|other| {
            other.name == function.name
                && other.generic_params.len() == function.generic_params.len()
                && other.generic_params.iter().any(|p| !p.bounds.is_empty() || !names_type(&p.name))
        })
    };
    let mut rewrites: Vec<(usize, String)> = vec![];
    for (idx, function) in module.functions.iter().enumerate() {
        // A constrained name (`describe<T: Shape>`) is always a parameter.
        if function.generic_params.is_empty() || function.generic_params.iter().any(|p| !p.bounds.is_empty()) {
            continue;
        }
        let params = || function.generic_params.iter().map(|p| p.name.as_str());
        // Module linking decides by what each file can see, and marks what
        // it decided; only an unlinked module falls back to program-wide
        // names.
        let all_concrete = crate::type_name::is_concrete_override(params())
            || function.generic_params.iter().any(|p| p.is_argument)
            || (!linked && params().all(names_type) && has_base(function));
        if !all_concrete {
            continue;
        }
        let args = function.generic_params.iter().map(|p| p.name.clone()).collect::<Vec<_>>().join(", ");
        rewrites.push((idx, format!("{}<{}>", function.name, args)));
    }
    for (idx, new_name) in rewrites {
        let mut concrete = module.functions[idx].clone();
        concrete.name = new_name;
        concrete.generic_params.clear();
        concrete.is_generic_func = false;
        // The original definition stays in place as the generic base.
        module.functions[idx] = concrete;
    }
}

/// A type that references one of the enclosing generic parameters is unbound
/// in this context; recording it as a spec would produce a specialization
/// with no concrete argument (e.g. `Array<V>` from HashMap's own field
/// list). Concrete uses are re-discovered from specialized bodies in the
/// second gather round.
fn contains_param(ty: &TypeName, params: &[TypeName]) -> bool {
    if params.iter().any(|p| p.name == ty.name) {
        return true;
    }
    ty.sub_types.iter().any(|s| contains_param(s, params))
}

/// Generic parameter names as bare TypeNames (for `contains_param`).
fn param_names(params: &[crate::model::GenericParam]) -> Vec<TypeName> {
    params.iter().map(|p| TypeName::new(&p.name)).collect()
}

/// The generic parameters an extension's methods can name: the target
/// struct's own, when the extension names the generic base (`extend Box` or
/// `extend Box<T>`, the rule `resolve_resolvables` uses). `extend Box<int>`
/// names one specialization and has none.
fn extension_params(structs: &[crate::model::StructDef], ext: &crate::model::ExtensionDef) -> Vec<TypeName> {
    let Some(base) = structs.iter().find(|st| st.name == ext.target.name) else { return vec![] };
    let extends_base = ext.target.sub_types.is_empty()
        || (base.generic_params.len() == ext.target.sub_types.len()
            && base.generic_params.iter().zip(&ext.target.sub_types).all(|(p, a)| a.sub_types.is_empty() && a.name == p.name));
    if extends_base { param_names(&base.generic_params) } else { vec![] }
}

/// Parse `Name<a, b>` back into a TypeName (specs are carried as TypeNames).
/// A call to an overloaded constructor (`Box<int>$2`) parses as the type
/// it constructs.
pub fn parse_type_string(s: &str) -> TypeName {
    let s = match crate::passes::overloads::set_name(s) {
        set if set.ends_with('>') => set,
        _ => s,
    };
    // A pointer type keeps its stars in the name (`Atomic<long>*`), with no
    // type arguments of its own.
    if s.ends_with('*') {
        return TypeName::new(s);
    }
    let Some(open) = s.find('<') else {
        return TypeName::new(s);
    };
    let name = &s[..open];
    let inner = &s[open + 1..s.len() - 1];
    let args: Vec<TypeName> = if inner.trim().is_empty() {
        vec![]
    } else {
        // Split on top-level commas only.
        let mut parts = vec![];
        let mut depth = 0usize;
        let mut current = String::new();
        for c in inner.chars() {
            match c {
                '<' => {
                    depth += 1;
                    current.push(c);
                }
                '>' => {
                    depth -= 1;
                    current.push(c);
                }
                ',' if depth == 0 => {
                    parts.push(current.trim().to_string());
                    current = String::new();
                }
                _ => current.push(c),
            }
        }
        if !current.trim().is_empty() {
            parts.push(current.trim().to_string());
        }
        parts.iter().map(|p| parse_type_string(p)).collect()
    };
    TypeName::with_args(name, args)
}

/// Collect generic types from local variable declarations, recursing into
/// nested blocks (branch/while bodies). Same predicate as the field and
/// parameter collection above.
fn gather_local_declarations(block: &Block, structs: &mut Requests, params: &[TypeName], owner: &str) {
    for stmt in &block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                if var.ty.is_generic()
                    && !var.ty.name.starts_with("__")
                    && !contains_param(&var.ty, params)
                {
                    request(structs, &var.ty.to_string(), owner, written(var));
                }
            }
            Statement::Block(inner) => gather_local_declarations(inner, structs, params, owner),
            Statement::Branch(branch) => {
                gather_local_declarations(&branch.if_block, structs, params, owner);
                if let Some(else_block) = &branch.else_block {
                    gather_local_declarations(else_block, structs, params, owner);
                }
            }
            Statement::While(wh) => gather_local_declarations(&wh.block, structs, params, owner),
            _ => {}
        }
    }
}

/// Whether making `spec` would nest specialization past
/// [`MAX_SPECIALIZATION_DEPTH`], following who asked for it
/// ([`Module::spec_requests`]): an instance asking for an instance asking
/// for ... If so, reports it at the request, with each place in the chain
/// as a note.
pub(crate) fn specialization_too_deep(module: &Module, spec: &TypeName) -> bool {
    let mut chain: Vec<&SpecRequest> = vec![];
    let mut name = spec.to_string();
    while let Some(request) = module.spec_requests.get(&name) {
        chain.push(request);
        if chain.len() > MAX_SPECIALIZATION_DEPTH {
            break;
        }
        name = request.by.clone();
    }
    if chain.len() <= MAX_SPECIALIZATION_DEPTH {
        return false;
    }
    let mut error = Diagnostic::error(format!(
        "'{}' is specialized {} levels deep, past the limit of {}; a generic whose instance asks for a larger instance of itself never ends",
        spec.name,
        chain.len(),
        MAX_SPECIALIZATION_DEPTH
    ))
    .at(chain[0].loc);
    // The chain usually repeats one place (a field asking for its own type
    // with a larger argument): each place once, innermost first.
    let mut shown: Vec<Loc> = vec![chain[0].loc];
    for request in &chain[1..] {
        if !shown.contains(&request.loc) {
            shown.push(request.loc);
            error = error.with_note(format!("asked for by '{}' here", request.by), Some(request.loc));
        }
    }
    crate::errors::report(error);
    true
}

//! Port of `source/Sema/ResolveOperators.h`: index operations become
//! `__index_get`/`__index_set` method calls or POD Array indexing; binary
//! operator overloads become method calls. Conversion is gated on the lhs's
//! static type naming a struct that declares the method, so plain field
//! compares (`Size == 0`) and POD indexing stay untouched.

use crate::model::*;
use crate::static_type::{self, StructInfo, StructTable};
use crate::type_name::TypeName;

pub fn resolve_operators(module: &mut Module) {
    // Struct table for overload gating. Built before any mutation so the
    // per-struct walks and the free-function walk share one immutable view.
    let table = StructTable::build(module);
    let overloads = crate::passes::overloads::Overloads::build(module);
    let mut targets: Vec<(Loc, String)> = vec![];

    for st_idx in 0..module.structs.len() {
        // Abstract generic bases (`Array<T>`) have no concrete bodies to
        // resolve; specializations (`Array<int>`) are concrete and must be.
        // Rewriting operator dispatch inside a base body would bake the
        // method into an unsubstituted receiver, and specialization clones
        // that MethodCall verbatim (SymbolRef `ty` annotations are not
        // substituted), so codegen would mangle against the parameter name.
        // Leave base bodies raw — the final pass resolves the specialized
        // clones, where the element type is concrete.
        if module.structs[st_idx].ty.is_generic() && module.structs[st_idx].name == module.structs[st_idx].ty.name {
            continue;
        }
        // The enclosing struct's type supplies `this`/bare-field types to the
        // walker (implicit-this fallback). Cloned so the mutable borrow of
        // the bodies below can coexist with it.
        let current = module.structs[st_idx].ty.clone();
        let st = &mut module.structs[st_idx];
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            targets.extend(resolve_body(body, &table, &overloads, Some(&current)));
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                targets.extend(resolve_body(body, &table, &overloads, Some(&current)));
            }
        }
    }

    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            targets.extend(resolve_body(body, &table, &overloads, None));
        }
    }

    // Global initializers: resolve operators in the default expression.
    // A compound-index assign in a global initializer would splice extra
    // statements (unsupported edge case) — only the first survives.
    for var in &mut module.globals {
        if let Some(default) = var.default.take() {
            let mut block = Block {
                name: String::new(),
                items: vec![Statement::Expression(default)],
                attributes: vec![],
            };
            targets.extend(resolve_body(&mut block, &table, &overloads, None));
            if !block.items.is_empty() {
                var.default = match block.items.remove(0) {
                    Statement::Expression(expr) => Some(expr),
                    other => {
                        panic!("global initializer became a non-expression statement: {:?}", std::mem::discriminant(&other));
                    }
                };
            }
        }
    }
    module.call_targets.extend(targets);
}

fn resolve_body(
    body: &mut Block,
    table: &StructTable,
    overloads: &crate::passes::overloads::Overloads,
    current: Option<&TypeName>,
) -> Vec<(Loc, String)> {
    // Temporaries are numbered within their function, after any an earlier
    // run declared there, so a function's code does not depend on which
    // functions were resolved before it.
    INDEX_TEMPORARIES.with(|c| c.set(next_index_temporary(body)));
    dispatch_operators(body, table, current);
    let mut targets = vec![];
    // The walk visits an index before its receiver, so `a[x][y]` lowers
    // only `a[x]`; once that call has a type (its overload picked), the
    // outer index can lower too. Repeat while an index lowers.
    loop {
        // An overloaded operator names its set (`+`); pick the member.
        // Nested calls type from the inside out, so repeat while that
        // settles more.
        if !overloads.is_empty() {
            for _ in 0..4 {
                let mut changed = false;
                crate::passes::walk_block(body, &mut |expr: &mut Expression| {
                    if let Expression::MethodCall { method, .. } = expr {
                        let before = method.clone();
                        targets.extend(crate::passes::overloads::resolve_method_call(expr, overloads, table, current));
                        changed |= matches!(expr, Expression::MethodCall { method, .. } if *method != before);
                    }
                });
                if !changed {
                    break;
                }
            }
        }
        let mut lowered = false;
        crate::passes::walk_block(body, &mut |expr: &mut Expression| lowered |= lower_index(expr, table, current));
        if !lowered {
            break;
        }
    }
    targets
}

/// Lower the index `expr` (`x[i]`) to its receiver's `__index_get` call, or
/// to raw `ArrayIndex` on a pointer; true when it changed. A receiver whose
/// type is not known yet is left for a later try.
fn lower_index(expr: &mut Expression, table: &StructTable, current: Option<&TypeName>) -> bool {
    let Expression::Index { lhs, rhs, loc } = expr else {
        return false;
    };
    // An enum's indexer: `light[i]` is `Light::__index_get(light, i)`.
    if let Some(ty) = static_type::of(lhs, table, current)
        && crate::enums::declares_operator(&ty, "__index_get")
    {
        *expr = crate::enums::operator_call(&ty, "__index_get", vec![(**lhs).clone(), (**rhs).clone()], *loc);
        return true;
    }
    let info = lhs_struct(lhs, table, current);
    if info.is_some_and(|i| i.methods.contains("__index_get")) && !is_raw_buffer_field(lhs, table, current) {
        // Replace the index op with a call to the index method.
        let lhs = (**lhs).clone();
        let rhs = (**rhs).clone();
        *expr = Expression::MethodCall {
            this: Box::new(lhs),
            method: "__index_get".to_string(),
            args: vec![rhs],
            loc: *loc,
        };
    } else if info.is_none() && static_type::of(lhs, table, current).is_some_and(|t| t.is_pointer()) {
        // A raw pointer receiver: Array indexing (element type
        // resolved at codegen). Any other receiver is left alone
        // for a later run: a `with` binding can still be typed as
        // its scope's generic parameter (`T`) here, and becomes the
        // struct whose indexer applies once specialization is done.
        // Codegen handles a remaining `Index` like `ArrayIndex`.
        let lhs = (**lhs).clone();
        let rhs = (**rhs).clone();
        *expr = Expression::ArrayIndex {
            ty: TypeName::auto(),
            lhs: Box::new(lhs),
            rhs: Box::new(rhs),
            loc: *loc,
        };
    }
    !matches!(expr, Expression::Index { .. })
}

fn dispatch_operators(body: &mut Block, table: &StructTable, current: Option<&TypeName>) {
    // Compound assign through an index (`x[y] += z`) expands to the C++
    // reference's tmp/get/set sequence before the walk: a bare `__index_set`
    // rewrite would drop the read-modify-write. The expansion splices one
    // extra statement after the decl, so it runs as a pre-pass over every
    // block (recursing into nested blocks) at statement level.
    expand_compound_index_assigns(body, table, current);
    // `-x`, `~x`, `!x` and truth tests (`if (x)`) on structs become method calls.
    crate::passes::unary_operators::dispatch(body, table, current);
    // Single traversal: walk_block visits every expression node once.
    crate::passes::walk_block(body, &mut |expr: &mut Expression| match expr {
        Expression::Binary { op, lhs, rhs, loc } if op.is_assignment() => {
            // `x[y] = z` → `x.__index_set(y, z)`, when the container is a
            // struct declaring the setter. Plain assign only — compound
            // assigns through an index expand in the pre-pass (statement
            // level) or use codegen's load-op-store path; a bare set here
            // would drop the read-modify-write.
            if *op == BinaryOp::Assign {
                if let Expression::Index { lhs: container, rhs: index, .. } = &**lhs {
                    if lhs_struct(container, table, current).is_some_and(|info| info.methods.contains("__index_set")) && !is_raw_buffer_field(container, table, current) {
                        let container = (**container).clone();
                        let index = (**index).clone();
                        let rhs_value = (**rhs).clone();
                        *expr = Expression::MethodCall {
                            this: Box::new(container),
                            method: "__index_set".to_string(),
                            args: vec![index, rhs_value],
                            loc: *loc,
                        };
                        return;
                    }
                }
            }
            // Compound assigns with an overload method (`str += x` →
            // `str.+=(x)`): only when the lhs's struct declares it.
            let op_name = op.op_name();
            if !op_name.is_empty() && lhs_struct(&**lhs, table, current).is_some_and(|info| info.methods.contains(&op_name)) {
                let lhs = (**lhs).clone();
                let rhs = (**rhs).clone();
                *expr = Expression::MethodCall {
                    this: Box::new(lhs),
                    method: op_name,
                    args: vec![rhs],
                    loc: *loc,
                };
            }
        }
        Expression::Index { .. } => {
            lower_index(expr, table, current);
        }
        Expression::Binary { op, lhs, rhs, loc } => {
            // Resolve overloads on lhs: x + y → x.operator+(y). Only when
            // the lhs's struct declares the method — plain field compares
            // (`Size == 0`) and POD elements must stay binary ops.
            let op_name = op.op_name();
            // An enum declaring the operator: `a < b` is `E::<(a, b)`.
            if !op_name.is_empty()
                && let Some(ty) = static_type::of(lhs, table, current)
                && crate::enums::declares_operator(&ty, &op_name)
            {
                *expr = crate::enums::operator_call(&ty, &op_name, vec![(**lhs).clone(), (**rhs).clone()], *loc);
                return;
            }
            if !op_name.is_empty() {
                // `Data[idx] == key` on a raw buffer field: dispatch on the
                // pointee (string content equality), which the receiver's
                // own static type does not describe. Struct receivers
                // (`Array<String>`) already type as their element, so
                // lhs_struct covers them.
                let lhs_structured = index_pointee_declares(lhs, table, current, &op_name)
                    || lhs_struct(&**lhs, table, current).is_some_and(|info| info.methods.contains(&op_name));
                if lhs_structured {
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *expr = Expression::MethodCall {
                        this: Box::new(lhs),
                        method: op_name,
                        args: vec![rhs],
                        loc: *loc,
                    };
                } else if *op == BinaryOp::NotEqual
                    && (index_pointee_declares(lhs, table, current, "==")
                        || lhs_struct(&**lhs, table, current).is_some_and(|info| info.methods.contains("==")))
                {
                    // Without its own `!=`, `a != b` is `!(a == b)`.
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *expr = Expression::Unary {
                        op: UnaryOp::LogicalNot,
                        operand: Box::new(Expression::MethodCall {
                            this: Box::new(lhs),
                            method: "==".to_string(),
                            args: vec![rhs],
                            loc: *loc,
                        }),
                        loc: *loc,
                    };
                }
            }
        }
        _ => {}
    });
}

/// Pre-pass for `x[y] op= z`: expands each compound index assign to the
/// tmp/get/set statement pair, recursing into nested blocks (the expansion
/// splices a statement, so it cannot run inside the expression walk).
/// NOTE: in loop bodies the synthesized tmp allocates per iteration
/// (`codegen_var_def` emits its alloca at the insertion point, not the entry
/// block), so a long loop with `a[i] += x` grows the stack — pre-existing
/// codegen behavior shared by any user-written local in a loop body.
fn expand_compound_index_assigns(body: &mut Block, table: &StructTable, current: Option<&TypeName>) {
    let mut i = 0usize;
    while i < body.items.len() {
        match &mut body.items[i] {
            Statement::Expression(expr) => {
                if let Some((decl, set)) = compound_index_assign(expr, table, current) {
                    // The statement becomes the tmp decl (C++ `binOp = tmp`);
                    // only the set call is spliced after it.
                    body.items[i] = Statement::Declaration(Declaration::Variable(decl));
                    body.items.splice((i + 1)..(i + 1), [Statement::Expression(set)]);
                    i += 2;
                    continue;
                }
            }
            Statement::Block(inner) => expand_compound_index_assigns(inner, table, current),
            Statement::Branch(branch) => {
                expand_compound_index_assigns(&mut branch.if_block, table, current);
                if let Some(else_block) = &mut branch.else_block {
                    expand_compound_index_assigns(else_block, table, current);
                }
            }
            Statement::While(w) => expand_compound_index_assigns(&mut w.block, table, current),
            _ => {}
        }
        i += 1;
    }
}

/// `x[y] op= z` as a whole expression → (tmp decl, set call) per the C++
/// reference. The statement becomes `var tmp = x.__index_get(y)`; the set
/// call carries `tmp op= z` so codegen's compound path performs the
/// read-modify-write on the loaded value.
fn compound_index_assign(
    expr: &Expression,
    table: &StructTable,
    current: Option<&TypeName>,
) -> Option<(VariableDef, Expression)> {
    let Expression::Binary { op, lhs, rhs, loc } = expr else {
        return None;
    };
    let loc = *loc;
    let Some(base_op) = op.base_assign_op() else {
        return None;
    };
    let Expression::Index { lhs: container, rhs: index, .. } = &**lhs else {
        return None;
    };
    if !lhs_struct(container, table, current).is_some_and(|info| info.methods.contains("__index_set"))
        || is_raw_buffer_field(container, table, current)
    {
        return None;
    }
    let get_call = Expression::MethodCall {
        this: Box::new((**container).clone()),
        method: "__index_get".to_string(),
        args: vec![(**index).clone()],
        loc,
    };
    let tmp_name = format!("_idx_tmp_{}", INDEX_TEMPORARIES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    }));
    let elem_ty = static_type::of(&get_call, table, current).unwrap_or_else(TypeName::auto);
    let tmp = VariableDef {
        ty: elem_ty,
        name: tmp_name.clone(),
        default: Some(get_call),
        hidden: false,
        kind: Kind::Variable,
        attributes: vec![],
        loc,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let set = Expression::MethodCall {
        this: Box::new((**container).clone()),
        method: "__index_set".to_string(),
        args: vec![
            (**index).clone(),
            Expression::Binary {
                op: base_op,
                lhs: Box::new(Expression::SymbolRef { id: tmp_name, ty: TypeName::auto(), loc }),
                rhs: Box::new((**rhs).clone()),
                loc,
            },
        ],
        loc,
    };
    Some((tmp, set))
}

/// The struct declaring the lhs's type, via its static type. Bare symbols resolve
/// against the enclosing struct's field table (implicit-this fields), since
/// implicit-type resolution does not annotate them.
fn lhs_struct<'a>(lhs: &Expression, table: &'a StructTable, current: Option<&TypeName>) -> Option<&'a StructInfo> {
    let ty = static_type::of(lhs, table, current).or_else(|| {
        if let Expression::SymbolRef { id, .. } = lhs {
            current.and_then(|c| {
                table.lookup(c)
                    .and_then(|info| info.fields.iter().find(|(f, _)| f == id).map(|(_, ty)| ty.clone()))
            })
        } else { None }
    })?;
    table.lookup(&ty)
}

/// True when a binary op on an index (`recv[i] == x`) should dispatch on the
/// index receiver's element: `static_type::of` types such a receiver as its
/// declared buffer type (`String*`, `Array<int>*`), so the pointee is what the
/// operator applies to. Non-buffer receivers (a nested index typed `Array<int>`)
/// carry no trailing `*` and are handled by lhs_struct instead.
fn index_pointee_declares(lhs: &Expression, table: &StructTable, current: Option<&TypeName>, method: &str) -> bool {
    let (Expression::Index { lhs: receiver, .. } | Expression::ArrayIndex { lhs: receiver, .. }) = lhs
    else {
        return false;
    };
    let Some(buffer_ty) = static_type::of(receiver, table, current) else {
        return false;
    };
    let binding = buffer_ty.to_string();
    let Some(pointee) = binding.strip_suffix('*') else {
        return false;
    };
    table.lookup(&TypeName::new(pointee)).is_some_and(|info| info.methods.contains(method))
}

/// True when the index receiver is a declared raw-buffer field (`Data` typed
/// `T*`). Such indexes stay RAW — codegen GEPs through the pointer directly.
/// Rewriting them to `__index_get` bakes the pointee's indexer into the
/// receiver, and an operator on the result then mangles against the pointee's
/// *pointee* (`Array<int>*` element `==` → `int.==`, which does not exist).
fn is_raw_buffer_field(expr: &Expression, table: &StructTable, current: Option<&TypeName>) -> bool {
    static_type::of(expr, table, current)
        .is_some_and(|ty| ty.to_string().ends_with('*'))
}

thread_local! {
    /// Numbers the temporaries of compound index assignments within the
    /// function being resolved (see `resolve_body`).
    static INDEX_TEMPORARIES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// One more than the highest `_idx_tmp_N` `block` declares, or 0.
fn next_index_temporary(block: &Block) -> usize {
    fn scan(block: &Block, next: &mut usize) {
        for stmt in &block.items {
            match stmt {
                Statement::Declaration(Declaration::Variable(var)) => {
                    if let Some(n) = var.name.strip_prefix("_idx_tmp_").and_then(|n| n.parse::<usize>().ok()) {
                        *next = (*next).max(n + 1);
                    }
                }
                Statement::Block(inner) => scan(inner, next),
                Statement::Branch(branch) => {
                    scan(&branch.if_block, next);
                    if let Some(else_block) = &branch.else_block {
                        scan(else_block, next);
                    }
                }
                Statement::While(wh) => scan(&wh.block, next),
                _ => {}
            }
        }
    }
    let mut next = 0;
    scan(block, &mut next);
    next
}

/// Restart temporary numbering (see `crate::reset_program_counters`).
pub(crate) fn reset_counter() {
    INDEX_TEMPORARIES.with(|c| c.set(0));
}

//! Generic constraints: `struct Gallery<T: Shape>`, `total_area<T: Shape &
//! Named>(...)`. A constraint names a trait, and every type argument of the
//! parameter must conform to it nominally: a struct through an `extend S with
//! Trait` (for a generic struct, `extend Box<T> with Trait` covers every
//! `Box<X>`; a generic trait must match exactly), a trait type when every
//! member of the trait can be called through a value, and a generic parameter
//! when it is constrained by that trait itself. Primitives, enums, pointers,
//! tuples and function types conform to none.
//!
//! [`check_constraints`] runs once, before anything is specialized: each
//! constraint must name a trait, each default must meet its parameter's
//! constraints, and each generic type written with arguments
//! ([`TypeUse`], recorded by the builder) and each concrete override must
//! pass arguments that conform, reported at the argument.
//! [`check_specializations`] runs after every `gather_generics`, before the
//! specializations it found are cloned: an inferred call (`total_area(circles)`
//! became `total_area<Circle>`) is reported at the call argument that fixed
//! the type. Overload resolution rejects a generic member whose inferred
//! arguments do not conform ([`Conformance::unmet`]), and `specialize_methods`
//! checks a generic method's own constraints at the call.
//!
//! The bodies of constrained generic code are not checked against their
//! constraints yet: they are still checked in each specialization.

use crate::model::*;
use crate::passes::check_function_types::canonical;
use crate::type_name::{replace_map, TypeName};
use pepper_parser::diagnostic::{Edit, Fix};
use std::collections::{HashMap, HashSet};

/// Whether any generic parameter in the module is constrained.
pub fn has_constraints(module: &Module) -> bool {
    let constrained = |params: &[GenericParam]| params.iter().any(|p| !p.bounds.is_empty());
    let function = |f: &FunctionDef| constrained(&f.generic_params);
    module.functions.iter().any(function)
        || module.structs.iter().any(|st| {
            constrained(&st.generic_params) || st.generic_methods.iter().any(function)
        })
        || module.traits.iter().any(|t| constrained(&t.generic_params) || t.methods.iter().any(function))
        || module.extensions.iter().any(|e| !e.restated.is_empty() || e.methods.iter().any(function))
        || !module.constrained_aliases.is_empty()
}

/// The generic parameters in scope at a use, by name.
type Scope = HashMap<String, InScope>;

/// A generic parameter in scope: its constraints, and where it and they are
/// declared, for the fix that adds one.
#[derive(Clone, Debug)]
struct InScope {
    bounds: Vec<TypeName>,
    /// The end of the name, or of its last constraint.
    end: Loc,
}

impl InScope {
    fn of(p: &GenericParam) -> Self {
        let end = p.bounds.last().map_or(p.loc, |b| b.loc);
        InScope { bounds: p.bounds.iter().map(|b| b.ty.clone()).collect(), end }
    }
}

/// `ty` as the programmer spells it: `int` rather than the `i32` a literal
/// is typed.
pub fn spelled(ty: &TypeName) -> String {
    let mut ty = ty.clone();
    fn rename(ty: &mut TypeName) {
        let name = match ty.name.as_str() {
            "i8" => "char",
            "u8" => "byte",
            "i16" => "short",
            "u16" => "ushort",
            "i32" => "int",
            "u32" => "uint",
            "i64" => "long",
            "u64" => "ulong",
            "f32" => "float",
            "f64" => "double",
            _ => "",
        };
        if !name.is_empty() {
            ty.name = name.to_string();
        }
        ty.sub_types.iter_mut().for_each(rename);
    }
    rename(&mut ty);
    ty.display()
}

#[derive(Clone, Debug)]
struct TraitFacts {
    /// Members a value of the trait type cannot call: the name and location.
    undispatchable: Vec<(String, Loc)>,
}

#[derive(Clone, Debug)]
struct StructFacts {
    params: Vec<String>,
    loc: Loc,
}

/// What deciding conformance needs from the module, owned, so overload
/// resolution can keep it.
#[derive(Clone, Debug, Default)]
pub struct Conformance {
    traits: HashMap<String, TraitFacts>,
    /// Structs by their declared name (generic bases and plain structs).
    structs: HashMap<String, StructFacts>,
    enums: HashMap<String, Loc>,
    /// Each extension's target, the traits it declares, and the constraints
    /// it adds to the struct's parameters (`extend Box<T: Shape> with
    /// Shape` conforms only when `T` does): the parameter's position, the
    /// trait, and where it is written.
    extensions: Vec<(TypeName, Vec<TypeName>, Vec<(usize, TypeName, Loc)>)>,
    /// The structs whose references are thread-safe (`[Shared]` structs and
    /// `shared` function types), by name, generic bases included: what the
    /// built-in constraint [`SHARED`] accepts.
    shared: HashSet<String>,
}

/// The built-in constraint `T: Shared`: `T` is thread-safe, as
/// `check_shared_types` decides for a field of a `[Shared]` struct. In a
/// constraint the name always means it, whatever the program declares.
pub const SHARED: &str = "Shared";

/// Whether constraint `ty` is the built-in [`SHARED`].
pub fn is_shared_bound(ty: &TypeName) -> bool {
    ty.name == SHARED && ty.sub_types.is_empty()
}

/// A constraint an argument does not meet.
#[derive(Clone, Debug)]
pub struct Unmet {
    /// The position of the parameter.
    pub index: usize,
    pub param: String,
    pub arg: TypeName,
    pub required: TypeName,
    /// Where the constraint is written.
    pub bound: Loc,
}

impl Conformance {
    pub fn of(module: &Module) -> Self {
        let traits = module
            .traits
            .iter()
            .map(|t| {
                let undispatchable = t
                    .methods
                    .iter()
                    .filter(|m| !crate::traits::is_dispatchable(m))
                    .map(|m| (crate::passes::overloads::set_name(&m.name).to_string(), m.loc))
                    .collect();
                (t.name.clone(), TraitFacts { undispatchable })
            })
            .collect();
        let structs = module
            .structs
            .iter()
            .filter(|st| !st.name.contains('<'))
            .map(|st| {
                let params = st.generic_params.iter().map(|p| p.name.clone()).collect();
                (st.name.clone(), StructFacts { params, loc: st.loc })
            })
            .collect();
        let shared = module
            .structs
            .iter()
            .filter(|st| st.is_shared() || st.ty.is_shared_function_type())
            .map(|st| st.name.clone())
            .collect();
        Conformance {
            shared,
            traits,
            structs,
            enums: module.enums.iter().map(|e| (e.name.clone(), e.loc)).collect(),
            extensions: module
                .extensions
                .iter()
                .map(|e| {
                    let added = added_constraints(module, e).into_iter().map(|(i, b)| (i, b.ty.clone(), b.loc)).collect();
                    (e.target.clone(), e.traits.clone(), added)
                })
                .collect(),
        }
    }

    fn is_trait(&self, ty: &TypeName) -> bool {
        ty.is_scalar() && !ty.is_pointer() && self.traits.contains_key(&ty.name)
    }

    /// The first part of `ty` that is not thread-safe, if any: what makes it
    /// miss the constraint `Shared`. A type parameter is thread-safe when it
    /// is constrained `Shared` itself.
    fn unshared_part(&self, ty: &TypeName, scope: &Scope) -> Option<TypeName> {
        if ty.sub_types.is_empty()
            && let Some(param) = scope.get(&ty.name)
        {
            return (!param.bounds.iter().any(is_shared_bound)).then(|| ty.clone());
        }
        let name = ty.to_string();
        if name == "void"
            || crate::type_name::is_integral_name(&name)
            || ty.is_shared_function_type()
            || ty.is_extern_function_type()
        {
            return None;
        }
        if ty.is_function_type() {
            return Some(ty.clone());
        }
        if let Some(pointee) = name.strip_suffix('*') {
            return self.unshared_part(&crate::passes::gather_generics::parse_type_string(pointee), scope);
        }
        if ty.name == "__ptr" && ty.sub_types.len() == 1 {
            return self.unshared_part(&ty.sub_types[0], scope);
        }
        if let Some(target) = ty.weak_target() {
            return self.unshared_part(target, scope);
        }
        if ty.is_tuple() {
            return ty.tuple_elements().iter().find_map(|e| self.unshared_part(e, scope));
        }
        // A `[Shared]` generic struct's own constraints say which arguments
        // it takes (`Atomic<T: Shared>`).
        if self.shared.contains(&ty.name) || self.shared.contains(&name) {
            return None;
        }
        Some(ty.clone())
    }

    /// Whether `arg` conforms to the trait type `required`.
    fn conforms(&self, arg: &TypeName, required: &TypeName, scope: &Scope) -> bool {
        if is_shared_bound(required) {
            return self.unshared_part(arg, scope).is_none();
        }
        let want = canonical(required);
        if arg.sub_types.is_empty()
            && let Some(param) = scope.get(&arg.name)
        {
            return param.bounds.iter().any(|b| canonical(b) == want);
        }
        if self.is_trait(arg) {
            return canonical(arg) == want && self.traits[&arg.name].undispatchable.is_empty();
        }
        if arg.is_pointer() {
            return false;
        }
        // A number, `bool` or enum conforms through `extend int with Tr`.
        if let Some(key) = arg.sub_types.is_empty().then(|| crate::value_types::key(&arg.name)).flatten() {
            return self.value_conformances(&key).any(|t| canonical(t) == want);
        }
        self.declaring(arg, required).any(|(map, conditions)| {
            conditions.iter().all(|(i, bound, _)| {
                let mut bound = bound.clone();
                replace_map(&mut bound, &map);
                arg.sub_types.get(*i).is_some_and(|a| self.conforms(a, &bound, scope))
            })
        })
    }

    /// The traits value type `key` (see `value_types::key`) declares.
    fn value_conformances<'s>(&'s self, key: &'s str) -> impl Iterator<Item = &'s TypeName> + 's {
        self.extensions
            .iter()
            .filter(move |(target, _, _)| target.sub_types.is_empty() && crate::value_types::key(&target.name).as_deref() == Some(key))
            .flat_map(|(_, traits, _)| traits)
    }

    /// The extensions that declare `required` for `arg`, a struct: each with
    /// its parameters' arguments and the conditions it adds.
    #[allow(clippy::type_complexity)]
    fn declaring<'s>(
        &'s self,
        arg: &'s TypeName,
        required: &TypeName,
    ) -> impl Iterator<Item = (Vec<(String, TypeName)>, &'s [(usize, TypeName, Loc)])> + 's {
        let want = canonical(required);
        let st = self.structs.get(&arg.name).filter(|_| !arg.is_pointer());
        self.extensions.iter().filter_map(move |(target, traits, conditions)| {
            let st = st?;
            if target.name != arg.name {
                return None;
            }
            // `extend Box<T>` (the struct's own parameters) covers every
            // `Box<X>`; `extend Box<int>` only itself.
            let generic = target.sub_types.is_empty()
                || (target.sub_types.len() == st.params.len()
                    && target.sub_types.iter().zip(&st.params).all(|(t, p)| t.sub_types.is_empty() && t.name == *p));
            let map: Vec<(String, TypeName)> = if generic {
                st.params.iter().cloned().zip(arg.sub_types.iter().cloned()).collect()
            } else if canonical(target) == canonical(arg) {
                vec![]
            } else {
                return None;
            };
            let declares = traits.iter().any(|t| {
                let mut t = t.clone();
                replace_map(&mut t, &map);
                canonical(&t) == want
            });
            declares.then_some((map, conditions.as_slice()))
        })
    }

    /// The note that says why `arg` does not conform to `required` although
    /// an extension declares it: the condition it does not meet, at the
    /// extension's constraint.
    pub fn condition_note(&self, arg: &TypeName, required: &TypeName) -> Option<(String, Loc)> {
        // Another extension declaring it may be met.
        if self.conforms(arg, required, &Scope::new()) {
            return None;
        }
        self.declaring(arg, required).find_map(|(map, conditions)| {
            conditions.iter().find_map(|(i, bound, loc)| {
                let mut bound = bound.clone();
                replace_map(&mut bound, &map);
                let a = arg.sub_types.get(*i)?;
                (!self.conforms(a, &bound, &Scope::new())).then(|| {
                    (
                        format!(
                            "'{}' conforms to '{}' only when '{}' conforms to '{}'",
                            spelled(arg),
                            spelled(required),
                            spelled(a),
                            spelled(&bound)
                        ),
                        *loc,
                    )
                })
            })
        })
    }

    /// The error for `bound`, a constraint that names no trait: what it
    /// names instead (a struct, an enum, a type parameter among `params`,
    /// with a note at its declaration), or nothing.
    fn not_a_trait<'p>(&self, bound: &Bound, mut params: impl Iterator<Item = &'p GenericParam>) -> Diagnostic {
        let name = spelled(&bound.ty);
        let param = if bound.ty.sub_types.is_empty() { params.find(|p| p.name == bound.ty.name) } else { None };
        let declared = self
            .structs
            .get(&bound.ty.name)
            .map(|st| st.loc)
            .or_else(|| self.enums.get(&bound.ty.name).copied())
            .or_else(|| param.map(|p| p.loc))
            .filter(|l| !l.is_none());
        let known = declared.is_some()
            || param.is_some()
            || crate::type_name::is_integral_name(&bound.ty.name)
            || bound.ty.is_pointer()
            || bound.ty.name.starts_with("__");
        if !known {
            return Diagnostic::error(format!("unknown type name '{}'", name)).at(bound.loc);
        }
        let error = Diagnostic::error(format!("'{}' is not a trait; a constraint must name a trait", name)).at(bound.loc);
        match declared {
            Some(at) => error.with_note(format!("'{}' declared here", name), Some(at)),
            None => error,
        }
    }

    /// Whether `arg` meets constraint `bound` (concrete types).
    pub fn meets(&self, arg: &TypeName, bound: &TypeName) -> bool {
        self.conforms(arg, bound, &Scope::new())
    }

    /// The first constraint of `params` that `args` (a use's arguments,
    /// defaults filling the rest) do not meet. A constraint may name the
    /// parameters of its own list (`I: Iterator<T>`), which take the
    /// arguments.
    fn unmet_in(&self, params: &[GenericParam], args: &[TypeName], scope: &Scope) -> Option<Unmet> {
        let mut map: Vec<(String, TypeName)> = vec![];
        for (i, p) in params.iter().enumerate() {
            match args.get(i).or(p.default.as_ref()) {
                Some(arg) => map.push((p.name.clone(), arg.clone())),
                None => return None,
            }
        }
        for (index, (p, (_, arg))) in params.iter().zip(&map).enumerate() {
            if arg.is_auto() || arg.contains_auto() {
                continue;
            }
            for bound in &p.bounds {
                let mut required = bound.ty.clone();
                replace_map(&mut required, &map);
                if !self.conforms(arg, &required, scope) {
                    return Some(Unmet { index, param: p.name.clone(), arg: arg.clone(), required, bound: bound.loc });
                }
            }
        }
        None
    }

    /// [`Conformance::unmet_in`] for concrete arguments.
    pub fn unmet(&self, params: &[GenericParam], args: &[TypeName]) -> Option<Unmet> {
        self.unmet_in(params, args, &Scope::new())
    }

    /// The error for a call of `base`, a generic method, as `spec`
    /// (`map<Circle>`) at `call`, whose arguments are at `args`, when its
    /// type arguments do not meet its constraints.
    pub fn check_call(&self, module: &Module, base: &FunctionDef, spec: &TypeName, call: Loc, args: &[Loc]) -> Option<Diagnostic> {
        let unmet = self.unmet(&base.generic_params, &spec.sub_types)?;
        let literal = |i: usize| module.literal_args.iter().find(|(c, j, _)| *c == call && *j == i).map(|(_, _, at)| *at);
        let at = base
            .parameters
            .iter()
            .zip(args)
            .enumerate()
            .find(|(_, (p, _))| mentions(&p.ty, &unmet.param))
            .map_or(call, |(i, (_, a))| if a.is_none() { literal(i).unwrap_or(call) } else { *a });
        let generic = crate::passes::overloads::set_name(&base.name);
        Some(self.error(&unmet, generic, at, module, &Scope::new()))
    }

    /// The error for `unmet`, a constraint of `generic`, at `at`.
    fn error(&self, unmet: &Unmet, generic: &str, at: Loc, module: &Module, scope: &Scope) -> Diagnostic {
        let (arg, required) = (spelled(&unmet.arg), spelled(&unmet.required));
        let shared = is_shared_bound(&unmet.required);
        let mut error = Diagnostic::error(format!(
            "'{}' does not conform to {}'{}', required by '{}' in '{}'",
            arg,
            if shared { "" } else { "trait " },
            required,
            unmet.param,
            generic
        ))
        .at(at)
        .with_note("constraint declared here", Some(unmet.bound));
        if unmet.arg.sub_types.is_empty()
            && let Some(param) = scope.get(&unmet.arg.name)
        {
            let (separator, what) = if param.bounds.is_empty() { (": ", "a constraint") } else { (" & ", "the constraint") };
            let declared = (!param.end.is_none()).then_some(param.end);
            error = error.with_note(format!("add {} to '{}': '{}{}{}'", what, arg, arg, separator, required), declared);
            if let Some(end) = declared.filter(|d| error.loc.is_some_and(|l| l.file == d.file)) {
                let insert = Loc::new(end.file, pepper_parser::ast::Span { start: end.span.end, end: end.span.end });
                let written = pepper_parser::namespace::demangle(&required).to_string();
                error = error.with_fix(Fix {
                    message: format!("Constrain '{}' to '{}'", arg, written),
                    edits: vec![Edit { loc: insert, replacement: format!("{}{}", separator, written) }],
                });
            }
            return error;
        }
        if shared {
            // Why it is not thread-safe, as for a `[Shared]` struct's field.
            return match self.unshared_part(&unmet.arg, scope) {
                Some(part) if self.is_trait(&part) => error.with_note(
                    format!("a value of trait type '{}' may refer to any struct, which need not be thread-safe", spelled(&part)),
                    None,
                ),
                Some(part) => crate::passes::check_shared_types::not_shared_note(error, &part, module),
                None => error,
            };
        }
        if self.is_trait(&unmet.arg) {
            let facts = &self.traits[&unmet.arg.name];
            if canonical(&unmet.arg) == canonical(&unmet.required)
                && let Some((name, loc)) = facts.undispatchable.first()
            {
                return error.with_note(
                    format!("'{}' cannot be called through a value of type '{}'", name, arg),
                    Some(*loc),
                );
            }
            return error;
        }
        if let Some((note, at)) = self.condition_note(&unmet.arg, &unmet.required) {
            return error.with_note(note, Some(at));
        }
        // A number, `bool` or enum conforms by an extension too.
        if crate::value_types::is_value_type(&unmet.arg) {
            let declared = self.enums.get(&unmet.arg.name).copied();
            return error.with_note(format!("declare it with 'extend {} with {}'", arg, required), declared);
        }
        if let Some(st) = self.structs.get(&unmet.arg.name).filter(|_| !unmet.arg.is_pointer()) {
            let written = pepper_parser::namespace::demangle(&arg).to_string();
            let required_written = pepper_parser::namespace::demangle(&required).to_string();
            error = error.with_note(format!("declare it with 'extend {} with {}'", arg, required), Some(st.loc));
            // The editor applies a fix to the file it shows.
            if error.loc.is_some_and(|l| l.file == st.loc.file)
                && let Some(end) = crate::passes::copies::struct_end(module, st.loc)
            {
                let insert = Loc::new(st.loc.file, pepper_parser::ast::Span { start: end, end });
                error = error.with_fix(Fix {
                    message: format!("Declare 'extend {} with {}'", written, required_written),
                    edits: vec![Edit {
                        loc: insert,
                        replacement: format!("\n\nextend {} with {} {{\n}}", written, required_written),
                    }],
                });
            }
        }
        error
    }
}

/// The constraints extension `ext` adds to its struct's parameters, beyond
/// the struct's own: the parameter's position and the constraint.
pub fn added_constraints<'m>(module: &'m Module, ext: &'m ExtensionDef) -> Vec<(usize, &'m Bound)> {
    if ext.restated.is_empty() {
        return vec![];
    }
    let Some(st) = module.structs.iter().find(|st| st.name == ext.target.name && !st.generic_params.is_empty()) else {
        return vec![];
    };
    ext.restated
        .iter()
        .filter(|(i, bound)| {
            st.generic_params
                .get(*i)
                .is_some_and(|p| !p.bounds.iter().any(|b| canonical(&b.ty) == canonical(&bound.ty)))
        })
        .map(|(i, bound)| (*i, bound))
        .collect()
}

/// Removes from `specialized`, a specialization of `base`, the members and
/// conformances of each constrained extension whose added constraints its
/// type arguments do not meet, and returns what it removed.
pub fn withhold(module: &Module, conformance: &Conformance, base: &StructDef, specialized: &mut StructDef) -> Vec<Withheld> {
    let mut withheld = vec![];
    let args = &specialized.ty.sub_types;
    let map: Vec<(String, TypeName)> = base.generic_params.iter().map(|p| p.name.clone()).zip(args.iter().cloned()).collect();
    for ext in module.extensions.iter().filter(|e| e.target.name == base.name) {
        let unmet = added_constraints(module, ext).into_iter().find_map(|(i, bound)| {
            let mut required = bound.ty.clone();
            replace_map(&mut required, &map);
            let arg = args.get(i)?;
            (!conformance.meets(arg, &required)).then(|| (arg.clone(), required, bound.loc))
        });
        let Some((arg, bound, at)) = unmet else { continue };
        let traits: Vec<TypeName> = ext
            .traits
            .iter()
            .map(|t| {
                let mut t = t.clone();
                replace_map(&mut t, &map);
                canonical(&t)
            })
            .collect();
        // A conformance another extension declares and the arguments meet
        // stays, with the trait defaults it copied in.
        let kept: Vec<TypeName> = traits.iter().filter(|t| conformance.meets(&specialized.ty, t)).cloned().collect();
        let own: HashSet<Loc> = ext.methods.iter().map(|m| m.loc).collect();
        // Its methods, and the trait defaults its conformances copied in.
        let from_extension =
            |m: &FunctionDef| own.contains(&m.loc) || (m.trait_default.is_some() && m.owner == ext.loc && kept.is_empty());
        for m in specialized.method_members.iter().chain(&specialized.generic_methods).filter(|m| from_extension(m)) {
            withheld.push(Withheld {
                owner: specialized.name.clone(),
                member: crate::passes::overloads::set_name(&m.name).to_string(),
                name: m.name.clone(),
                params: m.parameters.len(),
                arg: arg.clone(),
                bound: bound.clone(),
                at,
            });
        }
        specialized.method_members.retain(|m| !from_extension(m));
        specialized.generic_methods.retain(|m| !from_extension(m));
        specialized.traits.retain(|t| {
            let t = canonical(t);
            !traits.contains(&t) || kept.contains(&t)
        });
    }
    withheld
}

/// Reports a call of a member a specialization did not get from a
/// constrained extension (`b.label()` on a `Box<Circle>`, where `label` needs
/// `T: Named`), with the constraint it misses. Runs once specializations
/// and their calls are typed.
pub fn check_withheld(module: &Module) {
    if module.withheld.is_empty() {
        return;
    }
    let names: HashSet<&str> = module.withheld.iter().map(|w| w.member.as_str()).collect();
    let free: HashSet<&str> = module.functions.iter().map(|f| crate::passes::overloads::set_name(&f.name)).collect();
    let table = std::cell::OnceCell::new();
    let mut found: Option<Diagnostic> = None;
    let mut visit = |expr: &Expression, current: Option<&TypeName>| {
        if found.is_some() {
            return;
        }
        // A method call, or a bare call of a method of the enclosing struct.
        let (receiver, method, count, loc) = match expr {
            Expression::MethodCall { this, method, args, loc } => {
                if !names.contains(crate::passes::overloads::set_name(method)) {
                    return;
                }
                let table = table.get_or_init(|| crate::static_type::StructTable::build(module));
                let Some(receiver) = crate::static_type::of(this, table, current) else { return };
                (receiver, method, args.len(), *loc)
            }
            Expression::FunctionCall { function, args, loc } => {
                let set = crate::passes::overloads::set_name(function);
                let Some(current) = current.filter(|_| names.contains(set) && !free.contains(set)) else { return };
                (current.clone(), function, args.len(), *loc)
            }
            _ => return,
        };
        let owner = receiver.to_string();
        let owner = owner.trim_end_matches('*');
        let member = crate::passes::overloads::set_name(method);
        // A member the specialization kept that takes this many arguments.
        let fits = |m: &FunctionDef| {
            let required = m.parameters.iter().filter(|p| p.default.is_none()).count();
            count >= required && count <= m.parameters.len()
        };
        let has = module.structs.iter().find(|st| st.name == owner).is_some_and(|st| {
            st.method_members
                .iter()
                .chain(&st.generic_methods)
                .any(|m| crate::passes::overloads::set_name(&m.name) == member && (fits(m) || m.name == *method))
        });
        if has {
            return;
        }
        let candidates = module.withheld.iter().filter(|w| w.owner == owner && w.member == member);
        let mut candidates: Vec<&Withheld> = candidates.collect();
        // Of several withheld overloads, the one this call's arguments fit.
        candidates.sort_by_key(|w| w.params != count);
        if let Some(w) = candidates.first() {
            found = Some(
                Diagnostic::error(format!("no member named '{}' in '{}'", member, owner)).at(loc).with_note(
                    format!("'{}' requires '{}' to conform to '{}'", member, spelled(&w.arg), spelled(&w.bound)),
                    Some(w.at),
                ),
            );
        }
    };
    let mut function = |def: &FunctionDef, current: Option<&TypeName>| {
        if let Some(body) = &def.body {
            visit_block(body, &mut |e| visit(e, current));
        }
    };
    for def in module.functions.iter().filter(|f| !f.is_generic_func) {
        function(def, None);
    }
    for st in module.structs.iter().filter(|st| st.generic_params.is_empty()) {
        for def in st.method_members.iter().chain(&st.constructors).chain([&st.destructor]) {
            function(def, Some(&st.ty));
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            visit_expression(default, &mut |e| visit(e, None));
        }
    }
    if let Some(error) = found {
        crate::errors::report(error);
    }
}

/// An extension that adds constraints to its struct's parameters, and the
/// constraints it adds.
pub struct ConstrainedExtension<'m> {
    pub ext: &'m ExtensionDef,
    pub added: Vec<(usize, &'m Bound)>,
}

/// Every constrained extension of struct `name`.
pub fn constrained_extensions<'m>(module: &'m Module, name: &str) -> Vec<ConstrainedExtension<'m>> {
    module
        .extensions
        .iter()
        .filter(|e| e.target.name == name)
        .map(|ext| ConstrainedExtension { ext, added: added_constraints(module, ext) })
        .filter(|c| !c.added.is_empty())
        .collect()
}

/// The generics a use can name (generic structs, traits, generic functions
/// and aliases) that constrain a parameter, by name: their parameters.
fn constrained_generics(module: &Module) -> HashMap<&str, &[GenericParam]> {
    let mut out: HashMap<&str, &[GenericParam]> = HashMap::new();
    let lists = module
        .structs
        .iter()
        .filter(|st| !st.generic_params.is_empty())
        .map(|st| (st.name.as_str(), &st.generic_params))
        .chain(module.traits.iter().map(|t| (t.name.as_str(), &t.generic_params)))
        .chain(module.functions.iter().filter(|f| f.is_generic_func).map(|f| (f.name.as_str(), &f.generic_params)))
        .chain(module.constrained_aliases.iter().map(|a| (a.name.as_str(), &a.generic_params)));
    for (name, params) in lists {
        // The first declaration of a name is the one a use means.
        let entry = out.entry(name).or_insert(params);
        if !entry.iter().any(|p| !p.bounds.is_empty()) {
            *entry = &[];
        }
    }
    out.retain(|_, params| !params.is_empty());
    out
}

/// The scope of a use: its parameters, and inside `extend Box<T>` the
/// parameters of `Box`, which carry its constraints.
fn scope_of(module: &Module, context: &UseContext) -> Scope {
    let mut scope = Scope::new();
    if let Some(target) = &context.extension
        && let Some(st) = module.structs.iter().find(|st| st.name == target.name && !st.generic_params.is_empty())
    {
        for p in &st.generic_params {
            scope.insert(p.name.clone(), InScope::of(p));
        }
    }
    for p in &context.scope {
        let own = InScope::of(p);
        match scope.get_mut(&p.name) {
            // An extension's parameter keeps its struct's constraints.
            Some(outer) if context.extension.is_some() => outer.bounds.extend(own.bounds),
            _ => {
                scope.insert(p.name.clone(), own);
            }
        }
    }
    scope
}

/// A declared list of generic parameters: the name of what declares it,
/// the list, and the parameters of what encloses it (a method's struct,
/// trait, or extended struct), which its constraints may also name.
type Declared<'m> = (String, &'m [GenericParam], &'m [GenericParam]);

/// Every declared list of generic parameters, in declaration order.
fn declarations(module: &Module) -> Vec<Declared<'_>> {
    let mut out: Vec<Declared> = vec![];
    fn function<'m>(f: &'m FunctionDef, outer: &'m [GenericParam]) -> Declared<'m> {
        (crate::passes::overloads::set_name(&f.name).to_string(), &f.generic_params, outer)
    }
    for st in module.structs.iter().filter(|st| !st.name.contains('<')) {
        out.push((st.name.clone(), &st.generic_params, &[]));
        out.extend(st.generic_methods.iter().map(|m| function(m, &st.generic_params)));
    }
    for t in &module.traits {
        out.push((t.name.clone(), &t.generic_params, &[]));
        out.extend(t.methods.iter().map(|m| function(m, &t.generic_params)));
    }
    for e in &module.extensions {
        let outer: &[GenericParam] = module
            .structs
            .iter()
            .find(|st| st.name == e.target.name && !st.generic_params.is_empty())
            .map_or(&[], |st| &st.generic_params);
        out.extend(e.methods.iter().map(|m| function(m, outer)));
    }
    out.extend(module.functions.iter().filter(|f| f.is_generic_func).map(|f| function(f, &[])));
    for a in &module.constrained_aliases {
        out.push((a.name.clone(), &a.generic_params, &[]));
    }
    out
}

/// Checks the constraints themselves, the uses written in the source, and
/// the concrete overrides, then the specializations gathered so far (see
/// the module docs).
pub fn check_constraints(module: &Module) {
    // `Shared` in a constraint is always the built-in, so a trait cannot
    // take the name.
    if let Some(t) = module.traits.iter().find(|t| pepper_parser::namespace::demangle_name(&t.name) == SHARED) {
        crate::errors::report(
            Diagnostic::error(format!("trait '{}' takes the name of the built-in constraint 'Shared'; rename it", SHARED))
                .at(t.loc),
        );
        return;
    }
    if !has_constraints(module) {
        return;
    }
    let conformance = Conformance::of(module);
    // Specializations copy their base's parameters: check each once.
    let mut seen: HashSet<Loc> = HashSet::new();
    for (_, params, outer) in declarations(module) {
        for bound in params.iter().flat_map(|p| &p.bounds) {
            if !seen.insert(bound.loc) {
                continue;
            }
            if conformance.is_trait(&bound.ty) || is_shared_bound(&bound.ty) {
                continue;
            }
            crate::errors::report(conformance.not_a_trait(bound, params.iter().chain(outer)));
            return;
        }
    }
    // A constraint on an extension's parameter: the struct's own, restated,
    // or one it adds (a constrained extension).
    for ext in &module.extensions {
        for (i, bound) in &ext.restated {
            let base = module.structs.iter().find(|st| st.name == ext.target.name && !st.generic_params.is_empty());
            let param = base.and_then(|st| st.generic_params.get(*i));
            let arg = ext.target.sub_types.get(*i);
            let error = match (base, param, arg) {
                (Some(_), Some(p), Some(a)) if a.sub_types.is_empty() && a.name == p.name => {
                    // A constraint the struct lacks makes a constrained
                    // extension; either way it must name a trait.
                    if conformance.is_trait(&bound.ty) || is_shared_bound(&bound.ty) {
                        continue;
                    }
                    conformance.not_a_trait(bound, base.iter().flat_map(|st| &st.generic_params))
                }
                _ => Diagnostic::error(format!(
                    "only the parameters of '{}' can restate its constraints",
                    ext.target.name
                ))
                .at(bound.loc),
            };
            crate::errors::report(error);
            return;
        }
    }
    // A conformance needs its members wherever it holds: one a constrained
    // extension provides (`extend Box<T: Named> { name() }`) does not serve
    // `extend Box<T> with Named`, which holds for every `Box<X>`.
    for ext in module.extensions.iter().filter(|e| !e.traits.is_empty()) {
        let Some(st) = module.structs.iter().find(|st| st.name == ext.target.name && !st.generic_params.is_empty()) else {
            continue;
        };
        let own: Vec<(usize, TypeName)> = added_constraints(module, ext).into_iter().map(|(i, b)| (i, canonical(&b.ty))).collect();
        let others = constrained_extensions(module, &st.name);
        for trait_name in &ext.traits {
            let Some(def) = module.traits.iter().find(|t| t.name == trait_name.name) else { continue };
            for required in &def.methods {
                let set = crate::passes::overloads::set_name(&required.name);
                let implementers: Vec<&FunctionDef> = st
                    .method_members
                    .iter()
                    .chain(&st.generic_methods)
                    .filter(|m| m.trait_default.is_none() && crate::passes::overloads::set_name(&m.name) == set)
                    .collect();
                // The constraint each implementer needs beyond this
                // conformance's own, if any.
                let needs = |m: &FunctionDef| {
                    others.iter().filter(|c| c.ext.methods.iter().any(|x| x.loc == m.loc)).find_map(|c| {
                        c.added.iter().find(|(i, b)| !own.iter().any(|(j, t)| j == i && *t == canonical(&b.ty))).copied()
                    })
                };
                let needed: Vec<Option<(usize, &Bound)>> = implementers.iter().map(|m| needs(m)).collect();
                let Some(Some((i, bound))) = needed.first().copied() else { continue };
                if needed.iter().any(|n| n.is_none()) {
                    continue;
                }
                let param = st.generic_params.get(i).map(|p| p.name.clone()).unwrap_or_default();
                crate::errors::report(
                    Diagnostic::error(format!(
                        "'{}' conforms to '{}' for every '{}', but its '{}' exists only when '{}' conforms to '{}'",
                        st.name,
                        spelled(trait_name),
                        param,
                        set,
                        param,
                        spelled(&bound.ty)
                    ))
                    .at(ext.loc)
                    .with_note("constraint declared here", Some(bound.loc))
                    .with_note(
                        format!(
                            "make the conformance conditional: 'extend {}<{}: {}> with {}'",
                            st.name,
                            param,
                            spelled(&bound.ty),
                            spelled(trait_name)
                        ),
                        None,
                    ),
                );
                return;
            }
        }
    }
    // Each default meets its parameter's constraints.
    let mut seen: HashSet<Loc> = HashSet::new();
    for (name, params, _) in declarations(module) {
        let scope: Scope = params.iter().map(|p| (p.name.clone(), InScope::of(p))).collect();
        for (i, p) in params.iter().enumerate() {
            let (Some(default), Some(first)) = (&p.default, p.bounds.first()) else { continue };
            if !seen.insert(first.loc) {
                continue;
            }
            // The default stands for this parameter; earlier ones stay themselves.
            let mut args: Vec<TypeName> = params[..i].iter().map(|q| TypeName::new(&q.name)).collect();
            args.push(default.clone());
            if let Some(unmet) = conformance.unmet_in(&params[..=i], &args, &scope)
                && unmet.index == i
            {
                let at = if p.default_loc.is_none() { first.loc } else { p.default_loc };
                crate::errors::report(conformance.error(&unmet, &name, at, module, &scope));
                return;
            }
        }
    }
    // Each generic type written with arguments.
    let generics = constrained_generics(module);
    let mut seen: HashSet<Loc> = HashSet::new();
    for type_use in &module.type_uses {
        let Some(params) = generics.get(type_use.ty.name.as_str()) else { continue };
        if type_use.args.first().is_some_and(|a| !seen.insert(*a)) {
            continue;
        }
        let Some(context) = compiled(module, type_use) else { continue };
        let scope = scope_of(module, context);
        if let Some(unmet) = conformance.unmet_in(params, &type_use.ty.sub_types, &scope) {
            let at = type_use.args.get(unmet.index).copied().unwrap_or(Loc::NONE);
            crate::errors::report(conformance.error(&unmet, &type_use.ty.name, at, module, &scope));
            return;
        }
    }
    check_specializations(module);
}

/// Checks the struct and function specializations `gather_generics`
/// recorded, before they are cloned. One that fails comes from an inferred
/// call (a written one was checked where it is written), so it is reported
/// at the call's argument that fixed the failing type argument.
pub fn check_specializations(module: &Module) {
    if !has_constraints(module) {
        return;
    }
    let generics = constrained_generics(module);
    let mut specs = module.struct_specs.iter().chain(&module.func_specs).filter(|s| generics.contains_key(s.name.as_str())).peekable();
    if specs.peek().is_none() {
        return;
    }
    let conformance = Conformance::of(module);
    for spec in specs {
        if let Some(unmet) = conformance.unmet(generics[spec.name.as_str()], &spec.sub_types) {
            let at = spec_site(module, spec, &unmet);
            crate::errors::report(conformance.error(&unmet, &spec.name, at, module, &Scope::new()));
            return;
        }
    }
}

/// The context of `type_use`, when this platform compiles the code it is in
/// (no `[Target(...)]` around it removes it).
fn compiled<'m>(module: &'m Module, type_use: &TypeUse) -> Option<&'m UseContext> {
    let context = module.use_contexts.get(type_use.context)?;
    crate::passes::platform::keep(&context.conditions).unwrap_or(true).then_some(context)
}

/// Where the specialization `spec` is asked for: a use that spells it, or
/// the argument of a call to it whose parameter's type mentions the failing
/// type parameter (the one inference took it from), else the call.
fn spec_site(module: &Module, spec: &TypeName, unmet: &Unmet) -> Loc {
    if let Some(type_use) =
        module.type_uses.iter().find(|u| canonical(&u.ty) == canonical(spec) && compiled(module, u).is_some())
        && let Some(at) = type_use.args.get(unmet.index)
    {
        return *at;
    }
    let name = spec.to_string();
    let base = module.functions.iter().find(|f| f.is_generic_func && f.name == spec.name);
    let mut found: Option<Loc> = None;
    let mut visit = |expr: &Expression| {
        if found.is_some() {
            return;
        }
        if let Expression::FunctionCall { function, args, loc } = expr
            && *function == name
        {
            found = Some(argument_site(module, base, &unmet.param, args, *loc));
        }
    };
    for_each_expression(module, &mut visit);
    found
        .or_else(|| base.map(|f| f.loc))
        .or_else(|| module.structs.iter().find(|st| st.name == spec.name).map(|st| st.loc))
        .unwrap_or(Loc::NONE)
}

/// The argument of a call to `base` (or of a generic method) that fixes
/// `param`: the first whose parameter's declared type mentions it.
pub fn argument_site(module: &Module, base: Option<&FunctionDef>, param: &str, args: &[Expression], call: Loc) -> Loc {
    let Some(base) = base else { return call };
    base.parameters
        .iter()
        .zip(args)
        .enumerate()
        .find(|(_, (p, _))| mentions(&p.ty, param))
        .map_or(call, |(i, (_, a))| module.argument_loc(call, i, a))
}

fn mentions(ty: &TypeName, name: &str) -> bool {
    ty.name == name || ty.sub_types.iter().any(|t| mentions(t, name))
}

/// Calls `f` on every expression of the module's code, in declaration order.
fn for_each_expression(module: &Module, f: &mut impl FnMut(&Expression)) {
    let function = |def: &FunctionDef, f: &mut dyn FnMut(&Expression)| {
        if let Some(body) = &def.body {
            visit_block(body, f);
        }
    };
    for def in &module.functions {
        function(def, f);
    }
    for st in &module.structs {
        for def in st.method_members.iter().chain(&st.constructors) {
            function(def, f);
        }
    }
    for ext in &module.extensions {
        for def in &ext.methods {
            function(def, f);
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            visit_expression(default, f);
        }
    }
}

fn visit_block(block: &Block, f: &mut dyn FnMut(&Expression)) {
    for stmt in &block.items {
        match stmt {
            Statement::Expression(e) => visit_expression(e, f),
            Statement::Block(b) => visit_block(b, f),
            Statement::Declaration(Declaration::Variable(var)) => {
                if let Some(default) = &var.default {
                    visit_expression(default, f);
                }
            }
            Statement::Declaration(_) | Statement::LoopBreak(_) | Statement::Static(_) | Statement::StaticPass(_) => {}
            Statement::Branch(branch) => {
                visit_expression(&branch.condition, f);
                visit_block(&branch.if_block, f);
                if let Some(else_block) = &branch.else_block {
                    visit_block(else_block, f);
                }
            }
            Statement::While(wh) => {
                visit_expression(&wh.condition, f);
                visit_block(&wh.block, f);
            }
            Statement::Return(ret) => {
                if let Some(e) = &ret.expr {
                    visit_expression(e, f);
                }
            }
        }
    }
}

fn visit_expression(expr: &Expression, f: &mut dyn FnMut(&Expression)) {
    f(expr);
    for child in crate::passes::children(expr) {
        visit_expression(child, f);
    }
}

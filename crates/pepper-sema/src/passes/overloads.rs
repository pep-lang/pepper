//! Overloaded free functions: several functions of one file sharing a name,
//! told apart by their parameter lists (`scale(int)`, `scale(double)`).
//!
//! Every pass after this one looks functions up by name, so overloading is
//! settled by renaming:
//!
//! - [`name_overloads`] (first sema step that sees functions) checks each
//!   file's same-name free functions against one another, renames the
//!   members of each set of two or more `name$1`, `name$2`, … in declaration
//!   order, and records the set in `Module::overload_sets`. A set of one
//!   keeps its name, so a program without overloads is unchanged.
//!   Constructors are named by the builder (`Point$1`, `Point$2`, see
//!   `StructDef::constructors`); this pass checks them for redefinition,
//!   and their set is the type (`Point`, `Box<int>`), resolved like a
//!   function's.
//! - `resolve_implicit_types` resolves each call that names a set, as soon
//!   as its argument types are known, with [`Overloads::select`], and
//!   rewrites the call to the chosen member (a generic member becomes its
//!   specialization, `name$2<int>`). [`bind_function_values`] does the same
//!   for a set named as a value, by the function type of the slot it flows
//!   into.
//! - [`check_overloads`] reports what is still unresolved once types are
//!   final: no viable member, an ambiguous call, an overloaded name with no
//!   function type to pick a member by.
//!
//! Ranking follows C++: each argument ranks against its parameter (0 exact,
//! 1 promotion, 2 numeric conversion, 3 an `[Implicit]` constructor; among
//! integer widenings, the narrower target ranks better), and the
//! winner is no worse than every other viable member in every argument and
//! better in at least one; between otherwise equal members, a non-generic one
//! beats a generic one. Anything else is ambiguous.

use crate::model::*;
use crate::passes::check_function_types::canonical;
use crate::passes::type_arguments::GenericSignature;
use crate::type_name::TypeName;
use pepper_parser::namespace::{OVERLOAD_SEPARATOR as MEMBER_SEPARATOR, demangle_name};
use std::collections::{BTreeMap, HashMap, HashSet};

/// The set a member name belongs to: `scale$2` is `scale`. Other names are
/// returned unchanged.
pub fn set_name(member: &str) -> &str {
    match member.rsplit_once(MEMBER_SEPARATOR) {
        Some((set, ordinal)) if !ordinal.is_empty() && ordinal.bytes().all(|b| b.is_ascii_digit()) => set,
        _ => member,
    }
}

/// Whether `function` is a concrete override (`hash<Point>`), which
/// customizes a generic rather than overloading it.
fn is_override(function: &FunctionDef) -> bool {
    function.name.contains('<')
        || function.generic_params.iter().any(|p| p.is_argument)
        || crate::type_name::is_override(function.generic_params.iter().map(|p| p.name.as_str()))
}

/// What makes two members the same overload: their parameter types, with
/// generic parameters named by position (`f<T>(T)` and `f<U>(U)` clash).
fn parameter_key(function: &FunctionDef) -> Vec<String> {
    let positional: Vec<(String, TypeName)> = function
        .generic_params
        .iter()
        .enumerate()
        .map(|(i, p)| (p.name.clone(), TypeName::new(&format!("${}", i))))
        .collect();
    let mut key = vec![function.generic_params.len().to_string()];
    for param in &function.parameters {
        let mut ty = param.ty.clone();
        crate::type_name::replace_map(&mut ty, &positional);
        key.push(canonical(&ty).to_string());
    }
    key
}

fn return_key(function: &FunctionDef) -> String {
    canonical(&function.ty).to_string()
}

/// Check each file's same-name free functions and rename the members of
/// every overload set (see the module docs).
pub fn name_overloads(module: &mut Module) {
    // Concrete overrides are renamed to what they override (`hash<Point>`)
    // first, so they never join a set.
    crate::passes::gather_generics::concrete_overrides(module);
    let shared = replace_prelude_members(module);

    let mut groups: BTreeMap<(u32, String), Vec<usize>> = BTreeMap::new();
    for (i, function) in module.functions.iter().enumerate() {
        if is_override(function) {
            continue;
        }
        let file = shared.get(&function.name).copied().unwrap_or(function.loc.file.0);
        groups.entry((file, function.name.clone())).or_default().push(i);
    }

    for ((file, name), members) in &groups {
        // An extern names one C symbol, so it cannot share its name with
        // another function of the file; redeclaring the same prototype is
        // allowed.
        let externs: Vec<&ExternDef> = module.externs.iter().filter(|e| e.loc.file.0 == *file && &e.name == name).collect();
        if let Some(first) = members.first().filter(|_| !externs.is_empty()) {
            let function = &module.functions[*first];
            let (later, earlier) = if function.loc.span.start > externs[0].loc.span.start {
                (function.loc, externs[0].loc)
            } else {
                (externs[0].loc, function.loc)
            };
            crate::errors::report(
                Diagnostic::error(format!("extern '{}' cannot be overloaded", demangle_name(name)))
                    .at(later)
                    .with_note("previous declaration is here", Some(earlier)),
            );
            return;
        }
        if members.len() < 2 {
            continue;
        }
        for (j, &later) in members.iter().enumerate() {
            let function = &module.functions[later];
            let key = parameter_key(function);
            let Some(&earlier) = members[..j].iter().find(|&&i| parameter_key(&module.functions[i]) == key) else {
                continue;
            };
            let previous = &module.functions[earlier];
            let diagnostic = if return_key(previous) == return_key(function) {
                Diagnostic::error(format!("redefinition of '{}'", demangle_name(name)))
                    .at(function.loc)
                    .with_note("previous definition is here", Some(previous.loc))
            } else {
                Diagnostic::error("functions that differ only in their return type cannot be overloaded")
                    .at(function.loc)
                    .with_note("previous declaration is here", Some(previous.loc))
            };
            crate::errors::report(diagnostic);
            return;
        }
    }
    for externs in module.externs.iter().enumerate().fold(BTreeMap::<(u32, &str), Vec<usize>>::new(), |mut map, (i, e)| {
        map.entry((e.loc.file.0, e.name.as_str())).or_default().push(i);
        map
    }).values() {
        let first = &module.externs[externs[0]];
        let prototype = |e: &ExternDef| {
            let params: Vec<String> = e.parameters.iter().map(|p| canonical(&p.ty).to_string()).collect();
            (params, canonical(&e.ty).to_string(), e.is_variadic)
        };
        if let Some(&other) = externs[1..].iter().find(|&&i| prototype(&module.externs[i]) != prototype(first)) {
            crate::errors::report(
                Diagnostic::error(format!("extern '{}' cannot be overloaded", first.name))
                    .at(module.externs[other].loc)
                    .with_note("previous declaration is here", Some(first.loc)),
            );
            return;
        }
    }

    if !check_constructors(module) || !name_method_overloads(module) {
        return;
    }
    for ((_, name), members) in groups {
        if members.len() < 2 {
            continue;
        }
        let mut names = vec![];
        for (ordinal, i) in members.into_iter().enumerate() {
            let member = format!("{}{}{}", name, MEMBER_SEPARATOR, ordinal + 1);
            module.functions[i].name = member.clone();
            names.push(member);
        }
        module.overload_sets.insert(name, names);
    }
    attach_overrides(module);
}

/// Only prelude files (a forced import, then the runtime) may export the
/// same name, and the first definition wins: a forced import's
/// `assert(bool, __ptr<char>)` replaces the runtime's member with those
/// parameters and joins the rest of its set. Removes each replaced member
/// and returns the names so shared, each with the first file declaring it,
/// under which its one set is grouped.
fn replace_prelude_members(module: &mut Module) -> HashMap<String, u32> {
    let mut files: HashMap<&str, BTreeMap<u32, Vec<usize>>> = HashMap::new();
    for (i, function) in module.functions.iter().enumerate() {
        if is_override(function) || function.name.contains(pepper_parser::namespace::SEPARATOR) {
            continue;
        }
        files.entry(function.name.as_str()).or_default().entry(function.loc.file.0).or_default().push(i);
    }
    let mut shared = HashMap::new();
    let mut replaced = HashSet::new();
    for (name, by_file) in files.iter().filter(|(_, by_file)| by_file.len() > 1) {
        let mut seen: HashSet<Vec<String>> = HashSet::new();
        for members in by_file.values() {
            let keys: Vec<Vec<String>> = members.iter().map(|&i| parameter_key(&module.functions[i])).collect();
            for (&i, key) in members.iter().zip(&keys) {
                if seen.contains(key) {
                    replaced.insert(i);
                }
            }
            seen.extend(keys);
        }
        shared.insert(name.to_string(), *by_file.keys().next().unwrap());
    }
    let mut index = 0;
    module.functions.retain(|_| {
        index += 1;
        !replaced.contains(&(index - 1))
    });
    shared
}

/// Check that no two constructors of a struct take the same parameters.
/// Returns false after reporting an error.
fn check_constructors(module: &Module) -> bool {
    for st in module.structs.iter().filter(|st| st.constructors.len() > 1) {
        for (j, later) in st.constructors.iter().enumerate() {
            let key = parameter_key(later);
            if let Some(earlier) = st.constructors[..j].iter().find(|c| parameter_key(c) == key) {
                crate::errors::report(
                    Diagnostic::error(format!("constructor of '{}' cannot be redeclared", demangle_name(&st.name)))
                        .at(later.loc)
                        .with_note("previous declaration is here", Some(earlier.loc)),
                );
                return false;
            }
        }
    }
    true
}

/// Whether the module has anything to resolve: an overloaded free
/// function, method or constructor.
pub fn has_overloads(module: &Module) -> bool {
    !module.overload_sets.is_empty()
        || !module.method_overload_sets.is_empty()
        || module.structs.iter().any(|st| st.constructors.len() > 1)
}

/// Check each struct's same-name methods and rename the members of every
/// method overload set (`get$1`, `get$2`), recording them in
/// `module.method_overload_sets`. Returns false after reporting an error.
fn name_method_overloads(module: &mut Module) -> bool {
    for st in &mut module.structs {
        let Some(sets) = group_methods(&mut st.method_members, &st.name) else { return false };
        if !sets.is_empty() {
            module.method_overload_sets.insert(st.name.clone(), sets);
        }
    }
    // A trait's overloads: each member is its own vtable slot.
    for tr in &mut module.traits {
        let Some(sets) = group_methods(&mut tr.methods, &tr.name) else { return false };
        if !sets.is_empty() {
            module.method_overload_sets.insert(tr.name.clone(), sets);
        }
    }
    true
}

/// Group the methods of struct or trait `owner` into overload sets by set
/// name, checking each set,
/// and name the members of every set of two or more: a member already
/// named (`get$1`) keeps its name and a new one (an extension's `get`)
/// takes the next ordinal, so running it again after `apply_extensions` adds
/// to the sets without renaming what earlier passes named. Returns the
/// sets, or `None` after reporting an error.
pub(crate) fn group_methods(methods: &mut [FunctionDef], owner: &str) -> Option<BTreeMap<String, Vec<String>>> {
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    for (i, method) in methods.iter().enumerate() {
        groups.entry(set_name(&method.name).to_string()).or_default().push(i);
    }
    let mut sets = BTreeMap::new();
    for (name, members) in groups {
        if members.len() < 2 {
            continue;
        }
        let first = &methods[members[0]];
        // Inside a method a bare `open(p)` could mean either kind.
        if let Some(&other) = members.iter().find(|&&i| methods[i].is_static != first.is_static) {
            let (static_one, instance) = if first.is_static { (first, &methods[other]) } else { (&methods[other], first) };
            let later = if static_one.loc.span.start > instance.loc.span.start { static_one } else { instance };
            let earlier = if std::ptr::eq(later, static_one) { instance } else { static_one };
            crate::errors::report(
                Diagnostic::error(format!(
                    "static method '{}' cannot share its name with an instance method of '{}'",
                    name,
                    demangle_name(owner)
                ))
                .at(later.loc)
                .with_note("previous declaration is here", Some(earlier.loc)),
            );
            return None;
        }
        for (j, &later) in members.iter().enumerate() {
            let method = &methods[later];
            let key = parameter_key(method);
            let Some(&earlier) = members[..j].iter().find(|&&i| parameter_key(&methods[i]) == key) else {
                continue;
            };
            let previous = &methods[earlier];
            let diagnostic = if return_key(previous) == return_key(method) {
                Diagnostic::error(format!("redefinition of '{}'", name))
                    .at(method.loc)
                    .with_note("previous definition is here", Some(previous.loc))
            } else {
                Diagnostic::error("functions that differ only in their return type cannot be overloaded")
                    .at(method.loc)
                    .with_note("previous declaration is here", Some(previous.loc))
            };
            crate::errors::report(diagnostic);
            return None;
        }
        let ordinal = |member: &str| member.rsplit_once(MEMBER_SEPARATOR).and_then(|(_, n)| n.parse::<usize>().ok());
        let mut next = members.iter().filter_map(|&i| ordinal(&methods[i].name)).max().unwrap_or(0);
        let mut names = vec![];
        for i in members {
            if methods[i].name == name {
                next += 1;
                methods[i].name = format!("{}{}{}", name, MEMBER_SEPARATOR, next);
            }
            names.push(methods[i].name.clone());
        }
        sets.insert(name, names);
    }
    Some(sets)
}

/// A concrete override of an overloaded generic (`hash<Point>` with two
/// generic `hash` members) overrides the member whose parameters, with the
/// override's type arguments substituted, are the override's.
fn attach_overrides(module: &mut Module) {
    if module.overload_sets.is_empty() {
        return;
    }
    for i in 0..module.functions.len() {
        let function = &module.functions[i];
        let Some((base, _)) = function.name.split_once('<') else { continue };
        let Some(members) = module.overload_sets.get(base) else { continue };
        let args = crate::passes::gather_generics::parse_type_string(&function.name).sub_types;
        let params: Vec<TypeName> = function.parameters.iter().map(|p| canonical(&p.ty)).collect();
        let matching: Vec<&String> = members
            .iter()
            .filter(|member| {
                let Some(m) = module.functions.iter().find(|f| &f.name == *member) else { return false };
                if m.generic_params.len() != args.len() || m.parameters.len() != params.len() {
                    return false;
                }
                let map: Vec<(String, TypeName)> = m.generic_params.iter().map(|p| p.name.clone()).zip(args.iter().cloned()).collect();
                m.parameters.iter().zip(&params).all(|(p, want)| {
                    let mut ty = p.ty.clone();
                    crate::type_name::replace_map(&mut ty, &map);
                    canonical(&ty) == *want
                })
            })
            .collect();
        match matching.as_slice() {
            [member] => {
                let renamed = crate::passes::type_arguments::specialization(member, args);
                module.functions[i].name = renamed;
            }
            _ => {
                let function = &module.functions[i];
                crate::errors::report(
                    Diagnostic::error(format!(
                        "override '{}' matches {} of the overloads of '{}'; it must match exactly one",
                        demangle_name(&function.name),
                        if matching.is_empty() { "none" } else { "several" },
                        demangle_name(base)
                    ))
                    .at(function.loc),
                );
                return;
            }
        }
    }
}

/// One member of an overload set, as resolution needs it.
#[derive(Clone, Debug)]
pub struct Member {
    pub name: String,
    pub loc: Loc,
    pub params: Vec<TypeName>,
    /// How many parameters (from the front) have no default.
    pub required: usize,
    pub ret: TypeName,
    /// Present for a generic member.
    pub generic: Option<GenericSignature>,
}

impl Member {
    fn of(function: &FunctionDef) -> Self {
        Member {
            name: function.name.clone(),
            loc: function.loc,
            params: function.parameters.iter().map(|p| p.ty.clone()).collect(),
            required: function.parameters.iter().filter(|p| p.default.is_none()).count(),
            ret: function.ty.clone(),
            generic: function.is_generic_func.then(|| GenericSignature::of(function)),
        }
    }

    /// The member's type as a value: `(params) => return`.
    fn signature(&self) -> TypeName {
        let ret = if self.ret.to_string() == crate::type_name::AUTO { TypeName::void() } else { self.ret.clone() };
        TypeName::function_type(ret, self.params.clone())
    }
}

/// What an argument tells resolution beyond its type.
#[derive(Clone, Debug)]
pub enum ArgKind {
    Plain,
    IntLiteral(i64),
    /// A string literal, which `convert_string_literals` made a `String`
    /// constructor call around its raw `char*` global.
    StringLiteral,
    /// `__null`.
    Null,
    /// A closure literal with parameter types still unknown: its arity.
    UntypedClosure(usize),
    /// Another overload set named as a value: its members' function types.
    Overloaded(Vec<TypeName>),
}

/// One argument of a call being resolved.
#[derive(Clone, Debug)]
pub struct ArgInfo {
    /// Its type, when known.
    pub ty: Option<TypeName>,
    pub kind: ArgKind,
}

impl ArgInfo {
    /// Whether nothing is known about the argument yet.
    fn unknown(&self) -> bool {
        self.ty.is_none() && matches!(self.kind, ArgKind::Plain)
    }
}

/// Whether `expr` is a string literal after `convert_string_literals`.
pub fn is_string_literal(expr: &Expression) -> bool {
    matches!(expr, Expression::FunctionCall { function, args, loc }
        if function == "String"
            && matches!(args.first(), Some(Expression::StringLiteral { is_raw: true, loc: literal, .. }) if literal == loc))
}

/// A resolved call.
#[derive(Clone, Debug)]
pub struct Choice {
    /// The name the call now spells: the member, or its specialization.
    pub callee: String,
    pub ret: TypeName,
    /// Arguments that are string literals passed to a `__ptr<char>`
    /// parameter: they pass their raw global, not a `String`.
    pub raw_literals: Vec<usize>,
}

/// Why a call could not be resolved.
#[derive(Clone, Debug)]
pub struct Failure {
    pub message: String,
    pub notes: Vec<(String, Loc)>,
}

pub enum Outcome {
    Chosen(Choice),
    /// Some argument's type is not known yet.
    Pending,
    Failed(Failure),
}

/// A viable member with its argument ranks.
struct Viable {
    member: usize,
    ranks: Vec<Rank>,
    generic: bool,
    params: Vec<TypeName>,
    callee: String,
    ret: TypeName,
}

/// The overload sets of a module and the conversions ranking needs.
#[derive(Default)]
pub struct Overloads {
    sets: HashMap<String, Vec<Member>>,
    /// The sets in `sets` that are a struct's constructors (`Point`,
    /// `Box<int>`).
    constructors: HashSet<String>,
    /// Method overload sets: struct type → set name → members.
    methods: HashMap<String, HashMap<String, Vec<Member>>>,
    /// Struct type → the parameter type of its `[Implicit]` constructor.
    implicit: HashMap<String, TypeName>,
    /// Struct name → the traits it declares.
    conforms: HashMap<String, Vec<TypeName>>,
    traits: HashSet<String>,
    /// Each extension method, by its location: whether its extension is
    /// exported.
    extension_methods: HashMap<Loc, bool>,
    scopes: ExtensionScopes,
}

fn ordinal(n: usize) -> String {
    let suffix = match (n % 10, n % 100) {
        (1, 11) | (2, 12) | (3, 13) => "th",
        (1, _) => "st",
        (2, _) => "nd",
        (3, _) => "rd",
        _ => "th",
    };
    format!("{}{}", n, suffix)
}

fn integer_range(ty: &str) -> Option<(i128, i128)> {
    let bits = |b: u32, signed: bool| {
        if signed {
            (-(1i128 << (b - 1)), (1i128 << (b - 1)) - 1)
        } else {
            (0, (1i128 << b) - 1)
        }
    };
    Some(match ty {
        "i8" => bits(8, true),
        "i16" => bits(16, true),
        "i32" => bits(32, true),
        "i64" => bits(64, true),
        "u8" => bits(8, false),
        "u16" => bits(16, false),
        "u32" => bits(32, false),
        "u64" => bits(64, false),
        _ => return None,
    })
}

/// Numbers, `bool` included, convert among themselves.
fn is_numeric(ty: &str) -> bool {
    crate::arithmetic::is_numeric_type(ty)
}

/// Whether every value of numeric type `from` is a value of `to`.
/// An argument's rank against a parameter: its class (0 exact, 1 promotion,
/// 2 conversion, 3 `[Implicit]` constructor), then, for an integer widening,
/// the target's width in bits, so `short` prefers `int` to `long`.
type Rank = (u8, u8);

/// The width in bits of integer type `ty`.
fn integer_bits(ty: &str) -> Option<u8> {
    let (min, max) = integer_range(ty)?;
    Some((128 - ((max - min) as u128).leading_zeros()) as u8)
}

fn promotes(from: &str, to: &str) -> bool {
    if from == "f32" && to == "f64" {
        return true;
    }
    match (integer_range(from), integer_range(to)) {
        (Some((from_min, from_max)), Some((to_min, to_max))) => from_min >= to_min && from_max <= to_max,
        _ => false,
    }
}

impl Overloads {
    pub fn build(module: &Module) -> Self {
        if !has_overloads(module) {
            return Overloads::default();
        }
        let mut methods: HashMap<String, HashMap<String, Vec<Member>>> = HashMap::new();
        for st in &module.structs {
            for method in &st.method_members {
                let set = set_name(&method.name);
                if set != method.name {
                    methods
                        .entry(canonical(&st.ty).to_string())
                        .or_default()
                        .entry(set.to_string())
                        .or_default()
                        .push(Member::of(method));
                }
            }
        }
        // A value of trait type calls the trait's members: every instance the
        // module uses (`Source<int>`), and each trait's base.
        let trait_types = crate::traits::used_trait_types(module)
            .into_iter()
            .chain(module.traits.iter().map(|t| TypeName::new(&t.name)));
        for ty in trait_types {
            let Some(def) = crate::traits::trait_def(&module.traits, &ty) else { continue };
            let key = canonical(&ty).to_string();
            if methods.contains_key(&key) {
                continue;
            }
            for method in crate::traits::instance(def, &ty).methods {
                let set = set_name(&method.name);
                if set != method.name {
                    methods.entry(key.clone()).or_default().entry(set.to_string()).or_default().push(Member::of(&method));
                }
            }
        }
        let functions: HashMap<&str, &FunctionDef> = module.functions.iter().map(|f| (f.name.as_str(), f)).collect();
        let mut sets: HashMap<String, Vec<Member>> = module
            .overload_sets
            .iter()
            .map(|(set, members)| {
                (set.clone(), members.iter().filter_map(|m| functions.get(m.as_str())).map(|f| Member::of(f)).collect())
            })
            .collect();
        let concrete = |st: &&StructDef| !(st.ty.is_generic() && st.name == st.ty.name);
        let mut constructors = HashSet::new();
        for st in module.structs.iter().filter(concrete).filter(|st| st.constructors.len() > 1) {
            let set = st.ty.to_string();
            sets.insert(set.clone(), st.constructors.iter().map(Member::of).collect());
            constructors.insert(set);
        }
        let implicit = module
            .structs
            .iter()
            .filter(concrete)
            .filter_map(|st| st.implicit_from().map(|from| (canonical(&st.ty).to_string(), from.clone())))
            .collect();
        let mut conforms: HashMap<String, Vec<TypeName>> = HashMap::new();
        for st in &module.structs {
            conforms.entry(st.ty.to_string()).or_default().extend(st.traits.iter().cloned());
        }
        for ext in &module.extensions {
            conforms.entry(ext.target.to_string()).or_default().extend(ext.traits.iter().cloned());
        }
        let traits = module.traits.iter().map(|t| t.name.clone()).collect();
        let extension_methods =
            module.extensions.iter().flat_map(|ext| ext.methods.iter().map(|m| (m.loc, ext.is_exported))).collect();
        let scopes = module.extension_scopes.clone();
        Overloads { sets, constructors, methods, implicit, conforms, traits, extension_methods, scopes }
    }

    /// Whether `name` names an overload set.
    pub fn is_set(&self, name: &str) -> bool {
        self.sets.contains_key(name)
    }

    /// The set a call to `function` names and the type arguments it
    /// spells: `f<int>` is set `f` with `[int]`, but `Box<int>` is the
    /// constructor set of `Box<int>`.
    pub fn call_set<'f>(&self, function: &'f str) -> (&'f str, Option<Vec<TypeName>>) {
        if self.constructors.contains(function) {
            return (function, None);
        }
        split_type_arguments(function)
    }

    pub fn is_empty(&self) -> bool {
        self.sets.is_empty() && self.methods.is_empty()
    }

    /// The function types of a set's non-generic members.
    pub fn member_types(&self, set: &str) -> Vec<TypeName> {
        self.sets.get(set).map(|ms| ms.iter().filter(|m| m.generic.is_none()).map(Member::signature).collect()).unwrap_or_default()
    }

    /// The member of `set` whose function type is exactly `expected`.
    pub fn member_for(&self, set: &str, expected: &TypeName) -> Option<(String, TypeName)> {
        let want = canonical(expected);
        let mut found = self
            .sets
            .get(set)?
            .iter()
            .filter(|m| m.generic.is_none())
            .filter(|m| canonical(&m.signature()) == want)
            .map(|m| (m.name.clone(), m.signature()));
        let first = found.next()?;
        found.next().is_none().then_some(first)
    }

    /// `candidate function` notes, one per member of `set`.
    pub fn candidate_notes(&self, set: &str) -> Vec<(String, Loc)> {
        let what = if self.constructors.contains(set) { "candidate constructor" } else { "candidate function" };
        self.sets.get(set).map(|ms| ms.iter().map(|m| (what.to_string(), m.loc)).collect()).unwrap_or_default()
    }

    /// How well `arg` converts to a parameter of type `param`, or `None`
    /// when it does not.
    fn rank(&self, arg: &ArgInfo, param: &TypeName, implicit: bool) -> Option<Rank> {
        self.rank_class(arg, param, implicit).map(|class| {
            // Among integer widenings, the narrowest target is closest.
            let width = match (&arg.kind, arg.ty.as_ref()) {
                (ArgKind::Plain, Some(actual)) if class == 1 => integer_bits(&canonical(actual).to_string())
                    .and(integer_bits(&canonical(param).to_string()))
                    .unwrap_or(0),
                _ => 0,
            };
            (class, width)
        })
    }

    /// The class of `arg`'s conversion to `param`: 0 exact, 1 promotion, 2
    /// conversion, 3 `[Implicit]` constructor.
    fn rank_class(&self, arg: &ArgInfo, param: &TypeName, implicit: bool) -> Option<u8> {
        let p = canonical(param);
        let p_name = p.to_string();
        match &arg.kind {
            ArgKind::Overloaded(types) => {
                return (p.is_function_type() && types.iter().any(|t| canonical(t) == p)).then_some(0);
            }
            ArgKind::UntypedClosure(arity) => {
                return (p.is_function_type() && p.function_params().len() == *arity).then_some(0);
            }
            // `__null` is exact for a raw pointer, like C++ `nullptr`.
            ArgKind::Null => return Some(if p_name.ends_with('*') { 0 } else if is_numeric(&p_name) { 2 } else { 1 }),
            // A literal is its `char*` global where a pointer is expected.
            ArgKind::StringLiteral if p_name == "i8*" => return Some(0),
            _ => {}
        }
        let actual = arg.ty.as_ref()?;
        let a = canonical(actual);
        let a_name = a.to_string();
        if a == p {
            // A string literal is typed `String` by promotion.
            return Some(if matches!(arg.kind, ArgKind::StringLiteral) { 1 } else { 0 });
        }
        if let ArgKind::IntLiteral(v) = arg.kind {
            if integer_range(&p_name).is_some_and(|(min, max)| (v as i128) >= min && (v as i128) <= max) {
                return Some(1);
            }
        }
        if is_numeric(&a_name) && is_numeric(&p_name) {
            return Some(if promotes(&a_name, &p_name) { 1 } else { 2 });
        }
        if self.traits.contains(&p.name) {
            let declared = self.conforms.get(&a_name).is_some_and(|ts| ts.iter().any(|t| canonical(t) == p));
            return declared.then_some(1);
        }
        // A plain function value passes where a `shared` one of the same
        // signature is expected, and the reverse (`shared_functions`).
        if a.is_function_type() && p.is_function_type() {
            return (a.sub_types == p.sub_types).then_some(1);
        }
        // Pointers convert among themselves and to and from numbers (C
        // interop), and any struct reference passes as `void*`.
        let pointer = |t: &str| t.ends_with('*');
        if (pointer(&a_name) || is_numeric(&a_name)) && (pointer(&p_name) || is_numeric(&p_name)) || p_name == "void*" {
            return Some(2);
        }
        if implicit {
            if let Some(from) = self.implicit.get(&p_name) {
                if self.rank_class(arg, from, false).is_some_and(|r| r <= 1) {
                    return Some(3);
                }
            }
        }
        None
    }

    /// Resolve a call to `set` with `args`; `explicit` holds type arguments
    /// the call spells (`f<int>(x)`).
    pub fn select(&self, set: &str, explicit: Option<&[TypeName]>, args: &[ArgInfo]) -> Outcome {
        match self.sets.get(set) {
            Some(members) if self.constructors.contains(set) => match self.select_in(members, demangle_name(set), explicit, args) {
                Outcome::Failed(failure) => Outcome::Failed(constructor_failure(failure, set)),
                outcome => outcome,
            },
            Some(members) => self.select_in(members, demangle_name(set), explicit, args),
            None => Outcome::Pending,
        }
    }

    /// Resolve a call of method `set` on a receiver of type `receiver`.
    /// Resolve a call from `at` of method set `set` of `receiver`'s struct.
    pub fn select_method(&self, receiver: &TypeName, set: &str, args: &[ArgInfo], at: Loc) -> Outcome {
        match self.method_set(receiver, set, at) {
            Some(members) => self.select_in(&members, set, None, args),
            None => Outcome::Pending,
        }
    }

    /// The members of method set `set` of `receiver`'s struct that code at
    /// `at` can see: every body method, and the methods of the extensions
    /// visible in its file.
    fn method_set(&self, receiver: &TypeName, set: &str, at: Loc) -> Option<Vec<Member>> {
        let members = self.methods.get(&canonical(receiver).to_string())?.get(set)?;
        let visible = |m: &&Member| match self.extension_methods.get(&m.loc) {
            Some(&exported) => self.scopes.sees(at.file, m.loc.file, exported),
            None => true,
        };
        Some(members.iter().filter(visible).cloned().collect())
    }

    /// Whether some struct has a method overload set named `set`.
    fn is_any_method_set(&self, set: &str) -> bool {
        self.methods.values().any(|sets| sets.contains_key(set))
    }

    /// Whether `set` names a method overload set of `receiver`'s struct.
    pub fn is_method_set(&self, receiver: &TypeName, set: &str) -> bool {
        self.methods.get(&canonical(receiver).to_string()).is_some_and(|sets| sets.contains_key(set))
    }

    /// The member of method set `set` of `receiver`'s struct, visible at
    /// `at`, whose function type (without `this`) is exactly `expected`.
    pub fn method_member_for(&self, receiver: &TypeName, set: &str, expected: &TypeName, at: Loc) -> Option<String> {
        let want = canonical(expected);
        let members = self.method_set(receiver, set, at)?;
        let mut found = members.iter().filter(|m| canonical(&m.signature()) == want);
        let first = found.next()?;
        found.next().is_none().then(|| first.name.clone())
    }

    /// `candidate function` notes, one per member of method set `set`
    /// visible at `at`.
    pub fn method_candidate_notes(&self, receiver: &TypeName, set: &str, at: Loc) -> Vec<(String, Loc)> {
        self.method_set(receiver, set, at).map(|ms| ms.iter().map(|m| ("candidate function".to_string(), m.loc)).collect()).unwrap_or_default()
    }

    fn select_in(&self, members: &[Member], name: &str, explicit: Option<&[TypeName]>, args: &[ArgInfo]) -> Outcome {
        let count = args.len();
        let arity_fits = |m: &Member| count >= m.required && count <= m.params.len();
        let pending = args.iter().any(ArgInfo::unknown);
        if pending {
            // Arity alone may decide.
            let mut fitting = members.iter().filter(|m| arity_fits(m) && explicit.is_none() == m.generic.is_none());
            if let (Some(only), None) = (fitting.next(), fitting.next()) {
                if only.generic.is_none() {
                    return Outcome::Chosen(Choice { callee: only.name.clone(), ret: only.ret.clone(), raw_literals: vec![] });
                }
            }
            return Outcome::Pending;
        }

        let mut notes = vec![];
        let mut viable: Vec<Viable> = vec![];
        for (index, member) in members.iter().enumerate() {
            let not_viable = |why: String| (format!("candidate function not viable: {}", why), member.loc);
            if !arity_fits(member) {
                let (min, max) = (member.required, member.params.len());
                let plural = |n: usize| if n == 1 { "argument" } else { "arguments" };
                let requires = if min == max {
                    format!("requires {} {}", max, plural(max))
                } else if count < min {
                    format!("requires at least {} {}", min, plural(min))
                } else {
                    format!("requires at most {} {}", max, plural(max))
                };
                notes.push(not_viable(format!("{}, but {} {} provided", requires, count, if count == 1 { "was" } else { "were" })));
                continue;
            }
            // The member's parameter types at this call, and its name there.
            let (params, callee, ret) = match (&member.generic, explicit) {
                (None, None) => (member.params.clone(), member.name.clone(), member.ret.clone()),
                // Written type arguments pick among the generic members.
                (None, Some(_)) => continue,
                (Some(signature), _) => {
                    let type_args = match explicit {
                        Some(written) => {
                            if written.len() > signature.params.len() {
                                continue;
                            }
                            let filled: Option<Vec<TypeName>> = signature
                                .params
                                .iter()
                                .enumerate()
                                .map(|(i, p)| written.get(i).cloned().or_else(|| p.default.clone()))
                                .collect();
                            let Some(filled) = filled else { continue };
                            filled
                        }
                        None => {
                            let types: Vec<Option<TypeName>> = args
                                .iter()
                                .map(|a| match &a.kind {
                                    ArgKind::Overloaded(_) => None,
                                    _ => a.ty.clone(),
                                })
                                .collect();
                            match signature.infer(&types) {
                                Some(inferred) => inferred,
                                None => {
                                    let bound = signature.bind(&types);
                                    let missing = signature
                                        .params
                                        .iter()
                                        .find(|p| !bound.contains_key(&p.name) && p.default.is_none())
                                        .map(|p| p.name.clone())
                                        .unwrap_or_default();
                                    notes.push(not_viable(format!("cannot infer type argument '{}'", missing)));
                                    continue;
                                }
                            }
                        }
                    };
                    let map: Vec<(String, TypeName)> =
                        signature.params.iter().map(|p| p.name.clone()).zip(type_args.iter().cloned()).collect();
                    let params = member
                        .params
                        .iter()
                        .map(|p| {
                            let mut ty = p.clone();
                            crate::type_name::replace_map(&mut ty, &map);
                            ty
                        })
                        .collect();
                    let mut ret = member.ret.clone();
                    crate::type_name::replace_map(&mut ret, &map);
                    (params, crate::passes::type_arguments::specialization(&member.name, type_args), ret)
                }
            };
            let mut ranks = vec![];
            let mut failed = None;
            for (i, (arg, param)) in args.iter().zip(&params).enumerate() {
                match self.rank(arg, param, true) {
                    Some(r) => ranks.push(r),
                    None => {
                        failed = Some((i, arg, param));
                        break;
                    }
                }
            }
            if let Some((i, arg, param)) = failed {
                let from = match &arg.kind {
                    ArgKind::Overloaded(_) => "overloaded function".to_string(),
                    ArgKind::UntypedClosure(n) => format!("a closure of {} parameter{}", n, if *n == 1 { "" } else { "s" }),
                    ArgKind::Null => "__null".to_string(),
                    _ => arg.ty.as_ref().map(|t| format!("'{}'", t.display())).unwrap_or_default(),
                };
                notes.push(not_viable(format!("no known conversion from {} to '{}' for {} argument", from, param.display(), ordinal(i + 1))));
                continue;
            }
            viable.push(Viable { member: index, ranks, generic: member.generic.is_some(), params, callee, ret });
        }

        let better = |a: &Viable, b: &Viable| {
            let no_worse = a.ranks.iter().zip(&b.ranks).all(|(x, y)| x <= y);
            let strictly = a.ranks.iter().zip(&b.ranks).any(|(x, y)| x < y);
            no_worse && (strictly || (!a.generic && b.generic))
        };
        if viable.is_empty() {
            return Outcome::Failed(Failure { message: format!("no matching function for call to '{}'", name), notes });
        }
        let winner = (0..viable.len()).find(|&i| (0..viable.len()).all(|j| i == j || better(&viable[i], &viable[j])));
        match winner {
            Some(i) => {
                let chosen = &viable[i];
                let raw_literals = args
                    .iter()
                    .zip(&chosen.params)
                    .enumerate()
                    .filter(|(_, (a, p))| matches!(a.kind, ArgKind::StringLiteral) && canonical(p).to_string() == "i8*")
                    .map(|(i, _)| i)
                    .collect();
                Outcome::Chosen(Choice { callee: chosen.callee.clone(), ret: chosen.ret.clone(), raw_literals })
            }
            None => {
                // The members no other viable member beats tie.
                let tied = (0..viable.len()).filter(|&i| !(0..viable.len()).any(|j| i != j && better(&viable[j], &viable[i])));
                let notes = tied.map(|i| ("candidate function".to_string(), members[viable[i].member].loc)).collect();
                Outcome::Failed(Failure { message: format!("call to '{}' is ambiguous", name), notes })
            }
        }
    }
}

/// A failed constructor call worded as clang words it: `no matching
/// constructor for initialization of 'Point'`, `candidate constructor`.
fn constructor_failure(failure: Failure, set: &str) -> Failure {
    let ty = demangle_name(set);
    let message = if failure.message.starts_with("no matching function") {
        format!("no matching constructor for initialization of '{}'", ty)
    } else {
        format!("call to constructor of '{}' is ambiguous", ty)
    };
    let notes = failure
        .notes
        .into_iter()
        .map(|(note, at)| (note.replacen("candidate function", "candidate constructor", 1), at))
        .collect();
    Failure { message, notes }
}

/// Rewrite a call resolved to `choice`: its callee, and each string literal
/// passed to a raw pointer parameter as that literal's global.
pub fn apply_choice(function: &mut String, args: &mut [Expression], choice: &Choice) {
    *function = choice.callee.clone();
    for &i in &choice.raw_literals {
        if let Expression::FunctionCall { args: inner, .. } = &mut args[i] {
            let raw = inner.remove(0);
            args[i] = raw;
        }
    }
}

/// How `module.call_targets` names method `member` of `receiver`'s struct:
/// `Point.move$2`.
pub fn method_target(receiver: &TypeName, member: &str) -> String {
    format!("{}.{}", receiver, member)
}

/// Rewrite `expr`, a call of an overloaded method (an operator that
/// `resolve_operators` just turned into a method call), to the member its
/// arguments select, typing them with `static_type`.
pub(crate) fn resolve_method_call(
    expr: &mut Expression,
    overloads: &Overloads,
    table: &crate::static_type::StructTable,
    current: Option<&TypeName>,
) -> Option<(Loc, String)> {
    let Expression::MethodCall { this, method, args, loc } = expr else { return None };
    let receiver = crate::static_type::of(this, table, current)?;
    if !overloads.is_method_set(&receiver, method) {
        return None;
    }
    let infos: Vec<ArgInfo> =
        args.iter().map(|arg| arg_info(arg, overloads, crate::static_type::of(arg, table, current))).collect();
    let Outcome::Chosen(choice) = overloads.select_method(&receiver, method, &infos, *loc) else { return None };
    apply_choice(method, args, &choice);
    Some((*loc, method_target(&receiver, &choice.callee)))
}

/// Bind each overloaded name used as a value to the member whose function
/// type is the type of the slot it flows into (`var f: (int) => int =
/// scale;`). Runs in `resolve_implicit_types`' loop; returns whether it
/// bound any.
pub fn bind_function_values(module: &mut Module) -> bool {
    if !has_overloads(module) {
        return false;
    }
    let overloads = Overloads::build(module);
    // Most runs find nothing to bind: look for a candidate before typing
    // every expression.
    let mut candidate = false;
    crate::passes::closures::for_each_expression_mut(module, &mut |e| {
        candidate |= match e {
            Expression::SymbolRef { id, ty, .. } => ty.contains_auto() && overloads.is_set(id),
            Expression::MemberRef { name, .. } => overloads.is_any_method_set(name),
            _ => false,
        };
    });
    if !candidate {
        return false;
    }
    let table = crate::static_type::StructTable::build(module);
    let mut bound: HashMap<(String, Loc), (String, TypeName)> = HashMap::new();
    // Methods (`p.get`, `S.make`) by name and location: the member's name.
    let mut methods: HashMap<(String, Loc), (TypeName, String)> = HashMap::new();
    crate::passes::closures::for_each_site(module, &mut |expr, expected, current| {
        let Some(expected) = expected.filter(|t| t.is_function_type() && !t.contains_auto()) else { return };
        match expr {
            Expression::SymbolRef { id, ty, loc } if ty.contains_auto() && overloads.is_set(id) => {
                if let Some(member) = overloads.member_for(id, expected) {
                    bound.insert((id.clone(), *loc), member);
                }
            }
            Expression::MemberRef { lhs, name, loc } => {
                let Some(receiver) = crate::static_type::of(lhs, &table, current) else { return };
                if let Some(member) = overloads.method_member_for(&receiver, name, expected, *loc) {
                    methods.insert((name.clone(), *loc), (receiver, member));
                }
            }
            _ => {}
        }
    });
    if bound.is_empty() && methods.is_empty() {
        return false;
    }
    let mut targets = vec![];
    crate::passes::closures::for_each_expression_mut(module, &mut |e| {
        if let Expression::MemberRef { name, loc, .. } = e {
            if let Some((receiver, member)) = methods.get(&(name.clone(), *loc)) {
                targets.push((*loc, method_target(receiver, member)));
                *name = member.clone();
            }
        }
        if let Expression::SymbolRef { id, loc, .. } = e {
            if let Some((member, ty)) = bound.get(&(id.clone(), *loc)) {
                targets.push((*loc, member.clone()));
                let loc = *loc;
                *e = Expression::FunctionRef { function: member.clone(), ty: ty.clone(), loc };
            }
        }
    });
    module.call_targets.extend(targets);
    true
}

/// Report calls and values still naming an overload set once every type is
/// final (see the module docs). Generic bases are skipped: their
/// specializations are checked.
pub fn check_overloads(module: &Module) {
    if !has_overloads(module) {
        return;
    }
    let overloads = Overloads::build(module);
    let table = crate::static_type::StructTable::build(module);
    // `var g = scale;`: no type to pick a member by.
    let untyped_vars = untyped_function_values(module, &overloads);
    let mut reported = false;
    let mut report = |diagnostic: Diagnostic| {
        if !reported {
            crate::errors::report(diagnostic);
            reported = true;
        }
    };
    let generic_bases: HashSet<String> = module
        .functions
        .iter()
        .filter(|f| f.is_generic_func)
        .map(|f| f.name.clone())
        .chain(module.structs.iter().filter(|s| !s.generic_params.is_empty() && s.name == s.ty.name).map(|s| s.name.clone()))
        .collect();
    // An extension's own copy of a method is never resolved; its copy in
    // the struct is.
    crate::passes::closures::for_each_applied_site_in(module, &mut |owner, expr, expected, current| {
        if owner.is_some_and(|o| generic_bases.contains(o)) {
            return;
        }
        match expr {
            Expression::FunctionCall { function, args, loc } => {
                let (base, explicit) = overloads.call_set(function);
                if !overloads.is_set(base) {
                    return;
                }
                let infos: Vec<ArgInfo> = args
                    .iter()
                    .map(|arg| arg_info(arg, &overloads, crate::static_type::of(arg, &table, current)))
                    .collect();
                let failure = match overloads.select(base, explicit.as_deref(), &infos) {
                    Outcome::Failed(failure) => failure,
                    Outcome::Pending | Outcome::Chosen(_) => {
                        let unknown = infos.iter().position(ArgInfo::unknown).unwrap_or(0);
                        Failure {
                            message: format!(
                                "cannot choose an overload of '{}': the type of its {} argument is unknown",
                                demangle_name(base),
                                ordinal(unknown + 1)
                            ),
                            notes: overloads.candidate_notes(base),
                        }
                    }
                };
                let mut diagnostic = Diagnostic::error(failure.message).at(*loc);
                for (note, at) in failure.notes {
                    diagnostic = diagnostic.with_note(note, Some(at));
                }
                report(diagnostic);
            }
            Expression::MethodCall { this, method, args, loc } => {
                let Some(receiver) = crate::static_type::of(this, &table, current) else { return };
                if !overloads.is_method_set(&receiver, method) {
                    return;
                }
                let infos: Vec<ArgInfo> = args
                    .iter()
                    .map(|arg| arg_info(arg, &overloads, crate::static_type::of(arg, &table, current)))
                    .collect();
                let failure = match overloads.select_method(&receiver, method, &infos, *loc) {
                    Outcome::Failed(failure) => failure,
                    Outcome::Pending | Outcome::Chosen(_) => {
                        let unknown = infos.iter().position(ArgInfo::unknown).unwrap_or(0);
                        Failure {
                            message: format!(
                                "cannot choose an overload of '{}': the type of its {} argument is unknown",
                                method,
                                ordinal(unknown + 1)
                            ),
                            notes: overloads.method_candidate_notes(&receiver, method, *loc),
                        }
                    }
                };
                let mut diagnostic = Diagnostic::error(failure.message).at(*loc);
                for (note, at) in failure.notes {
                    diagnostic = diagnostic.with_note(note, Some(at));
                }
                report(diagnostic);
            }
            Expression::MemberRef { lhs, name, loc } => {
                let Some(receiver) = crate::static_type::of(lhs, &table, current) else { return };
                if !overloads.is_method_set(&receiver, name) {
                    return;
                }
                let spelled = format!("{}.{}", receiver.display(), name);
                let mut diagnostic = if let Some(var) = untyped_vars.get(loc) {
                    Diagnostic::error(format!("cannot infer the type of '{}' from overloaded method '{}'", var, spelled))
                } else if let Some(expected) = expected.filter(|t| t.is_function_type()) {
                    Diagnostic::error(format!(
                        "address of overloaded method '{}' does not match required type '{}'",
                        spelled,
                        expected.display()
                    ))
                } else {
                    Diagnostic::error(format!("reference to overloaded method '{}' could not be resolved", spelled))
                }
                .at(*loc);
                for (note, at) in overloads.method_candidate_notes(&receiver, name, *loc) {
                    diagnostic = diagnostic.with_note(note, Some(at));
                }
                report(diagnostic);
            }
            Expression::SymbolRef { id, ty, loc } if ty.contains_auto() && overloads.is_set(id) => {
                let name = demangle_name(id);
                let mut diagnostic = if let Some(var) = untyped_vars.get(loc) {
                    Diagnostic::error(format!("cannot infer the type of '{}' from overloaded function '{}'", var, name))
                } else if let Some(expected) = expected.filter(|t| t.is_function_type()) {
                    Diagnostic::error(format!(
                        "address of overloaded function '{}' does not match required type '{}'",
                        name,
                        expected.display()
                    ))
                } else {
                    Diagnostic::error(format!("reference to overloaded function '{}' could not be resolved", name))
                }
                .at(*loc);
                for (note, at) in overloads.candidate_notes(id) {
                    diagnostic = diagnostic.with_note(note, Some(at));
                }
                if let Some(var) = untyped_vars.get(loc) {
                    let example = overloads.member_types(id).first().map(|t| t.display()).unwrap_or_else(|| "(...) => ...".to_string());
                    diagnostic = diagnostic
                        .with_note(format!("declare the type, for example 'var {}: {} = {};'", var, example, name), Some(*loc));
                }
                report(diagnostic);
            }
            _ => {}
        }
    });
}

/// `name<args>` split into `name` and the written type arguments. A
/// resolved member (`Box<int>$2`) is returned whole.
pub fn split_type_arguments(function: &str) -> (&str, Option<Vec<TypeName>>) {
    if set_name(function) != function {
        return (function, None);
    }
    match function.split_once('<') {
        Some((base, _)) => (base, Some(crate::passes::gather_generics::parse_type_string(function).sub_types)),
        None => (function, None),
    }
}

/// What resolution needs to know about `arg`, whose type is `ty` if known.
pub fn arg_info(arg: &Expression, overloads: &Overloads, ty: Option<TypeName>) -> ArgInfo {
    let known = |t: Option<TypeName>| t.filter(|t| !t.is_empty() && !t.contains_auto());
    let kind = match arg {
        Expression::IntLiteral(v) => ArgKind::IntLiteral(*v),
        e if is_string_literal(e) => ArgKind::StringLiteral,
        Expression::PointerLiteral => ArgKind::Null,
        Expression::MakeClosure { ty, .. } if ty.contains_auto() => ArgKind::UntypedClosure(ty.function_params().len()),
        Expression::SymbolRef { id, ty, .. } if ty.contains_auto() && overloads.is_set(id) => {
            ArgKind::Overloaded(overloads.member_types(id))
        }
        _ => ArgKind::Plain,
    };
    let ty = match (&kind, arg) {
        (ArgKind::IntLiteral(v), _) => Some(TypeName::new(crate::type_name::int_literal_type(*v))),
        (ArgKind::StringLiteral, _) => Some(TypeName::new("String")),
        (ArgKind::UntypedClosure(_) | ArgKind::Overloaded(_) | ArgKind::Null, _) => None,
        _ => known(ty),
    };
    ArgInfo { ty, kind }
}

/// Locals and globals declared without a type and initialized with an
/// overloaded name, by the name's location.
fn untyped_function_values(module: &Module, overloads: &Overloads) -> HashMap<Loc, String> {
    let mut found = HashMap::new();
    let mut visit = |var: &VariableDef| {
        match &var.default {
            Some(Expression::SymbolRef { id, loc, .. }) if var.ty.contains_auto() && overloads.is_set(id) => {
                found.insert(*loc, var.name.clone());
            }
            // A method set is checked where the value is reported.
            Some(Expression::MemberRef { loc, .. }) if var.ty.contains_auto() => {
                found.insert(*loc, var.name.clone());
            }
            _ => {}
        }
    };
    fn walk(block: &Block, visit: &mut impl FnMut(&VariableDef)) {
        for stmt in &block.items {
            match stmt {
                Statement::Declaration(Declaration::Variable(var)) => visit(var),
                Statement::Block(b) => walk(b, visit),
                Statement::Branch(b) => {
                    walk(&b.if_block, visit);
                    if let Some(e) = &b.else_block {
                        walk(e, visit);
                    }
                }
                Statement::While(w) => walk(&w.block, visit),
                _ => {}
            }
        }
    }
    for var in &module.globals {
        visit(var);
    }
    let bodies = module
        .functions
        .iter()
        .chain(module.structs.iter().flat_map(|s| s.method_members.iter().chain(s.constructors.iter())))
        .filter_map(|f| f.body.as_ref());
    for body in bodies {
        walk(body, &mut visit);
    }
    found
}

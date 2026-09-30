//! Model tests: parse + build + transform the `unittests/Structs.cpp` shapes
//! and assert the resolved model.

use crate::builder::build;
use crate::passes::transform_pass;
use crate::struct_body;
use crate::type_name::TypeName;
use pepper_parser::parser::parse_source;

fn compile(source: &str) -> crate::model::Module {
    let ast = parse_source("test.pep", source).expect("parse error");
    let mut module = build(&ast).expect("build");
    crate::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");
    module
}

#[test]
fn reserved_member_access_is_rejected() {
    let ast = parse_source(
        "test.pep",
        r#"
struct Test {
    var x = 0
}
test(): int {
    var t = Test()
    return t.__refcount
}
"#,
    )
    .expect("parse error");
    let err = build(&ast).expect_err("reserved member access must be rejected");
    assert!(
        err.message.contains("reserved"),
        "expected a reserved-member diagnostic, got: {}",
        err
    );
}

const BASIC_STRUCT: &str = r#"
struct Test {
    var x = 0
}
test(): int {
    var t = Test()
    return t.x
}
"#;

#[test]
fn basic_struct_builds_refcount_first() {
    let module = compile(BASIC_STRUCT);
    assert_eq!(module.structs.len(), 1);
    let st = &module.structs[0];
    assert_eq!(st.name, "Test");
    // __refcount head field.
    assert_eq!(st.field_members[0].name, "__refcount");
    assert_eq!(st.field_members[0].ty.to_string(), "u32");
    // __weakcount head field.
    assert_eq!(st.field_members[1].name, "__weakcount");
    assert_eq!(st.field_members[1].ty.to_string(), "u32");
    // User field follows.
    assert_eq!(st.field_members[2].name, "x");
    // Synthesized methods appended: release, acquire, dtor.
    let names: Vec<&str> = st.method_members.iter().map(|m| m.name.as_str()).collect();
    assert!(names.contains(&"__release"));
    assert!(names.contains(&"__acquire"));
    assert!(names.contains(&"__dtor"));
}

#[test]
fn ctor_body_contains_malloc_and_this() {
    let module = compile(BASIC_STRUCT);
    let st = &module.structs[0];
    let ctor = &st.constructors[0];
    assert_eq!(ctor.name, "Test");
    let body = ctor.body.as_ref().expect("ctor body");
    let dumped = format!("{:?}", body);
    assert!(dumped.contains("_pep_malloc"), "ctor should allocate: {}", dumped);
    assert!(dumped.contains("ThisRef"), "ctor should define this: {}", dumped);
    assert!(dumped.contains("__alloc_size"), "ctor should have an __alloc_size var: {}", dumped);
    // Ends with `return this`.
    let last = body.items.last().expect("ctor statements");
    assert!(matches!(last, crate::model::Statement::Return(_)));
}

#[test]
fn release_body_checks_null_then_decrements() {
    let module = compile(BASIC_STRUCT);
    let st = &module.structs[0];
    let release = &st.release;
    let body = release.body.as_ref().expect("release body");
    let dumped = format!("{:?}", body);
    // Null check first (this === null → return).
    assert!(dumped.contains("Identical"), "release null check: {}", dumped);
    assert!(dumped.contains("PointerLiteral"), "null literal: {}", dumped);
    // Refcount decrement and dtor call at zero.
    assert!(dumped.contains("__dtor"), "release calls dtor: {}", dumped);
}

#[test]
fn test_function_returns_field_ref() {
    let module = compile(BASIC_STRUCT);
    assert_eq!(module.functions.len(), 1);
    let function = &module.functions[0];
    assert_eq!(function.name, "test");
    assert_eq!(function.ty.to_string(), "int");
    let body = function.body.as_ref().expect("test body");
    let dumped = format!("{:?}", body);
    // `Test()` constructor call, resolved through ConvertMemberRefs to a
    // `this.x` member ref on the local.
    assert!(dumped.contains("\"Test\""), "ctor call: {}", dumped);
    assert!(dumped.contains("MemberRef"), "member access t.x: {}", dumped);
}

#[test]
fn auto_var_resolves_from_default() {
    let module = compile(BASIC_STRUCT);
    // `var x = 0` in the struct resolves to i32 via ResolveImplicitTypes.
    let st = &module.structs[0];
    let x = st.field_members.iter().find(|f| f.name == "x").expect("x field");
    assert_eq!(x.ty.to_string(), "i32");
    // `var t = Test()` resolves to Test.
    let function = &module.functions[0];
    let body = function.body.as_ref().expect("body");
    if let crate::model::Statement::Declaration(crate::model::Declaration::Variable(t)) = &body.items[0] {
        assert_eq!(t.name, "t");
        assert_eq!(t.ty.to_string(), "Test");
    } else {
        panic!("first statement should be the var decl: {:?}", body.items[0]);
    }
}

#[test]
fn type_name_to_string_generics() {
    assert_eq!(TypeName::new("int").to_string(), "int");
    let generic = TypeName::with_args("Array", vec![TypeName::new("int")]);
    assert_eq!(generic.to_string(), "Array<int>");
    assert!(generic.is_generic());
    assert!(!TypeName::new("int").is_generic());
    let ptr = TypeName::new("char*");
    assert!(ptr.is_pointer());
}

#[test]
fn bracket_type_lowers_to_array() {
    // `int[]` is the spelling of `Array<int>`; nested brackets nest.
    let module = compile(
        "test(): int {
            int[] xs = Array<int>();
            int[][] ys = Array<Array<int>>();
            return 0
        }",
    );
    let body = module.functions[0].body.as_ref().expect("body");
    let mut types: Vec<String> = vec![];
    for stmt in &body.items {
        if let crate::model::Statement::Declaration(crate::model::Declaration::Variable(v)) = stmt {
            types.push(v.ty.to_string());
        }
    }
    assert_eq!(types, vec!["Array<int>".to_string(), "Array<Array<int>>".to_string()]);
}

#[test]
fn widest_promotes() {
    use crate::type_name::widest;
    assert_eq!(widest(&TypeName::new("i32"), &TypeName::new("i64")).to_string(), "i64");
    assert_eq!(widest(&TypeName::new("u8"), &TypeName::new("u32")).to_string(), "u32");
    assert_eq!(widest(&TypeName::new("int"), &TypeName::new("float")).to_string(), "f32");
    assert_eq!(widest(&TypeName::new("f32"), &TypeName::new("f64")).to_string(), "f64");
    assert_eq!(widest(&TypeName::new("u8"), &TypeName::new("i32")).to_string(), "i32");
}

#[test]
fn negated_literal_folds() {
    let module = compile("test(): int { return -5 }");
    let body = module.functions[0].body.as_ref().expect("body");
    let dumped = format!("{:?}", body);
    // ResolveLiterals folds `-5` into IntLiteral(-5); no Unary(Neg) remains.
    assert!(!dumped.contains("Neg"), "no negation remains: {}", dumped);
    assert!(dumped.contains("-5"), "folded literal: {}", dumped);
}

#[test]
fn as_cast_survives_to_model() {
    let module = compile("test(): int {\n    var e = 1.5e2 as int;\n    return e\n}");
    let body = module.functions[0].body.as_ref().expect("body");
    // The declaration's default must be a Cast node (not folded away).
    let mut found = false;
    for stmt in &body.items {
        if let crate::model::Statement::Declaration(crate::model::Declaration::Variable(v)) = stmt {
            match &v.default {
                Some(crate::model::Expression::Cast { ty, .. }) => {
                    assert_eq!(ty.to_string(), "int");
                    found = true;
                }
                other => panic!("expected Cast default, got {:?}", other),
            }
        }
    }
    assert!(found, "no variable declaration found: {:?}", body);
}

#[test]
fn cast_inferred_var_takes_cast_type() {
    let module = compile("test(): int {\n    var e = 1.5e2 as int;\n    return e\n}");
    let body = module.functions[0].body.as_ref().expect("body");
    for stmt in &body.items {
        if let crate::model::Statement::Declaration(crate::model::Declaration::Variable(v)) = stmt {
            assert_eq!(v.ty.to_string(), "int", "var must infer the cast target type");
        }
    }
}

#[test]
fn globals_land_in_module_globals() {
    let module = compile("const counter = 7;\ntest(): int {\n    return counter\n}");
    assert_eq!(module.globals.len(), 1);
    assert_eq!(module.globals[0].name, "counter");
    assert_eq!(module.globals[0].ty.to_string(), "i32");
}

#[test]
fn type_alias_expands_in_model() {
    let module = compile(
        r#"
type I = int;
type P = Result<int, Error>;
f(): P {
    var x: I = 0
    return x
}
"#,
    );
    assert!(module.type_aliases.is_empty(), "aliases must be expanded away");
    let f = module.functions.iter().find(|f| f.name == "f").expect("fn f");
    assert_eq!(f.ty.to_string(), "Result<int, Error>");
    match &f.body.as_ref().expect("body").items[0] {
        crate::model::Statement::Declaration(crate::model::Declaration::Variable(var)) => {
            assert_eq!(var.name, "x");
            assert_eq!(var.ty.to_string(), "int");
        }
        other => panic!("expected var decl, got {:?}", other),
    }
}

#[test]
fn generic_type_alias_substitutes_params_and_defaults() {
    let module = compile(
        r#"
type R<T, E=Error> = Result<T, E>;
f(): R<u32> { return 0 }
g(): R<i64, int> { return 0 }
h(): R<u8> { return 0 }
"#,
    );
    let ty_of = |name: &str| -> String {
        module
            .functions
            .iter()
            .find(|f| f.name == name)
            .unwrap()
            .ty
            .to_string()
    };
    assert_eq!(ty_of("f"), "Result<u32, Error>");
    assert_eq!(ty_of("g"), "Result<i64, int>");
    assert_eq!(ty_of("h"), "Result<u8, Error>");
}

#[test]
fn type_alias_chain_expands() {
    let module = compile(
        r#"
[Shared]
struct Box<T> {
    const value: T;
    construct(T value) { this.value = value; }
}
type A = B;
type B = Box<int>;
const g: A = Box<int>(0);
"#,
    );
    assert_eq!(module.globals.len(), 1);
    assert_eq!(module.globals[0].ty.to_string(), "Box<int>");
}

#[test]
fn type_alias_in_struct_fields_expands() {
    let module = compile(
        r#"
type I = int;
struct S { var x: I }
"#,
    );
    let st = module.structs.iter().find(|s| s.name == "S").expect("struct S");
    assert_eq!(st.field_members[0].ty.to_string(), "u32");
}

#[test]
fn type_alias_in_call_strings_expands() {
    let module = compile(
        r#"
type I = int;
type Pair = Result<int, Error>;
f(): int {
    var b = Pair.ok(7);
    var c = g<I>(5);
    return 0
}
"#,
    );
    let f = module.functions.iter().find(|f| f.name == "f").expect("fn f");
    let dumped = format!("{:?}", f.body.as_ref().expect("body"));
    assert!(
        dumped.contains("\"Result<int, Error>\""),
        "static call string must expand to the target: {}",
        dumped
    );
    assert!(dumped.contains("\"g<int>\""), "generic call args must expand: {}", dumped);
    assert!(!dumped.contains("Pair"), "alias name must not survive: {}", dumped);
}

#[test]
fn type_alias_value_shadow_not_rewritten() {
    // A value symbol (global) that shares an alias's name must keep its
    // meaning: `S.m()` on the variable S is not a static call through the
    // alias.
    let module = compile(
        r#"
[Shared]
struct A { construct() {} m(): int { return 1; } }
struct B { construct() {} m(): int { return 2; } }
type S = B;
const S: A = A();
main(): int { return S.m(); }
"#,
    );
    let main = module.functions.iter().find(|f| f.name == "main").expect("fn main");
    let dumped = format!("{:?}", main.body.as_ref().expect("body"));
    assert!(
        dumped.contains("SymbolRef { id: \"S\""),
        "value S must keep its receiver, not be rewritten to the alias target: {}",
        dumped
    );
}

#[test]
fn type_alias_free_function_not_rewritten() {
    // A free function sharing an alias's name must keep being called as a
    // function, not rewritten to the alias target's ctor form.
    let module = compile(
        r#"
struct B { construct() {} }
type S = B;
S(x: int): int { return x + 100; }
main(): int { return S(5); }
"#,
    );
    let main = module.functions.iter().find(|f| f.name == "main").expect("fn main");
    let dumped = format!("{:?}", main.body.as_ref().expect("body"));
    assert!(
        dumped.contains("\"S\""),
        "free function S must keep its call string, not be rewritten to the alias target: {}",
        dumped
    );
}

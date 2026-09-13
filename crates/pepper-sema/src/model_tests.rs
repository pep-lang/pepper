//! Model tests: parse + build + transform the `unittests/Structs.cpp` shapes
//! and assert the resolved model.

use crate::builder::build;
use crate::passes::transform_pass;
use crate::struct_body;
use crate::type_name::TypeName;
use pepper_parser::parser::parse_source;

fn compile(source: &str) -> crate::model::Module {
    let ast = parse_source("test.pep", source).expect("parse error");
    let mut module = build(&ast);
    struct_body::apply(&mut module);
    transform_pass(&mut module);
    module
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
    // User field follows.
    assert_eq!(st.field_members[1].name, "x");
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
    let ctor = &st.constructor;
    assert_eq!(ctor.name, "Test");
    let body = ctor.body.as_ref().expect("ctor body");
    let dumped = format!("{:?}", body);
    assert!(dumped.contains("_pep_malloc"), "ctor should allocate: {}", dumped);
    assert!(dumped.contains("ThisRef"), "ctor should define this: {}", dumped);
    assert!(dumped.contains("size"), "ctor should have a size var: {}", dumped);
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
    let generic = TypeName::with_args("array", vec![TypeName::new("int")]);
    assert_eq!(generic.to_string(), "array<int>");
    assert!(generic.is_generic());
    assert!(!TypeName::new("int").is_generic());
    let ptr = TypeName::new("char*");
    assert!(ptr.is_pointer());
    let arr = TypeName::make_array("array", TypeName::new("int"));
    assert_eq!(arr.to_string(), "array*");
    assert!(arr.is_array());
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

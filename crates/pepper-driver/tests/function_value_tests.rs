//! Function types and named function references: `(int) => int` values,
//! calls through them (locals, parameters, fields, array elements, call
//! results), refcount balance of the static function objects, and the
//! signature checks that keep a mismatched function out of a typed slot.

use pepper_codegen::CodeGenerator;
use pepper_sema::model::Module as SemaModule;

/// `_pep_live_allocs()` is a process-wide counter, so leak-census tests must
/// not run concurrently with each other; serialize on this lock.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn sema(source: &str) -> Result<SemaModule, String> {
    pepper_driver::compiler::compile_with_runtime("test.pep", source)
}

/// Compile + JIT `test()` and return (result, net live-allocation delta).
fn run(source: &str) -> (i32, i64) {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut module = sema(source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

fn compile_error(source: &str) -> String {
    match sema(source) {
        Ok(_) => panic!("expected a compile error for:\n{}", source),
        Err(e) => e,
    }
}

const FUNCTIONS: &str = r#"
square(x: int): int { return x * x; }
negate(x: int): int { return -x; }

struct Point {
    int x;
    construct(this.x = 0) {}
}

make_point(x: int): Point { return Point(x); }
point_x(p: Point): int { return p.x; }
"#;

#[test]
fn call_through_a_local() {
    let src = format!("{}{}", FUNCTIONS, r#"
test(): int {
    var f = square;
    var g: (int) => int = negate;
    return f(3) + g(1);
}
"#);
    assert_eq!(run(&src), (8, 0));
}

#[test]
fn reassign_a_function_value() {
    let src = format!("{}{}", FUNCTIONS, r#"
test(): int {
    var f = square;
    var a = f(4);
    f = negate;
    return a + f(6);
}
"#);
    assert_eq!(run(&src), (10, 0));
}

#[test]
fn pass_a_function_as_an_argument() {
    let src = format!("{}{}", FUNCTIONS, r#"
apply(f: (int) => int, x: int): int { return f(x); }
twice(f: (int) => int, x: int): int { return apply(f, apply(f, x)); }

test(): int {
    return twice(square, 3) + apply(negate, 1);
}
"#);
    assert_eq!(run(&src), (80, 0));
}

#[test]
fn call_through_a_field() {
    let src = format!("{}{}", FUNCTIONS, r#"
struct Transform {
    var op: (int) => int;
    construct(this.op = square) {}
    run(x: int): int { return op(x) + this.op(x); }
}

test(): int {
    var t = Transform();
    var direct = t.op(2);
    t.op = negate;
    var u = Transform(negate);
    return direct * 100 + t.run(5) + u.op(1);
}
"#);
    assert_eq!(run(&src), (389, 0));
}

#[test]
fn array_of_functions() {
    let src = format!("{}{}", FUNCTIONS, r#"
test(): int {
    var ops = Array<(int) => int>();
    ops.append(square);
    ops.append(negate);
    ops.append(square);
    var total = 0;
    var i = 0;
    while (i < ops.count()) {
        total = total + ops[i](i + 2);
        i = i + 1;
    }
    return total;
}
"#);
    // 2*2 - 3 + 4*4
    assert_eq!(run(&src), (17, 0));
}

#[test]
fn call_a_returned_function() {
    let src = format!("{}{}", FUNCTIONS, r#"
pick(squared: bool): (int) => int {
    if squared {
        return square;
    }
    return negate;
}

test(): int {
    var f = pick(false);
    return pick(true)(5) + f(5);
}
"#);
    assert_eq!(run(&src), (20, 0));
}

#[test]
fn struct_arguments_and_results_stay_balanced() {
    let src = format!("{}{}", FUNCTIONS, r#"
test(): int {
    var make = make_point;
    var read = point_x;
    var p = make(7);
    make(8);
    var sum = read(p) + read(make(9)) + point_x(make(1));
    return sum;
}
"#);
    assert_eq!(run(&src), (17, 0));
}

#[test]
fn module_scope_function_value() {
    let src = format!("{}{}", FUNCTIONS, r#"
var handler = square;

test(): int {
    var before = handler(3);
    handler = negate;
    return before + handler(3);
}
"#);
    assert_eq!(run(&src), (6, 0));
}

#[test]
fn function_type_alias() {
    let src = format!("{}{}", FUNCTIONS, r#"
type Op = (int) => int;
type Binary<T> = (T, T) => T;

add(a: int, b: int): int { return a + b; }
fold(values: int[], combine: Binary<int>, start: int): int {
    var total = start;
    var i = 0;
    while (i < values.count()) {
        total = combine(total, values[i]);
        i = i + 1;
    }
    return total;
}

test(): int {
    var op: Op = square;
    var values = Array<int>();
    values.append(1);
    values.append(2);
    values.append(3);
    return fold(values, add, op(2));
}
"#);
    assert_eq!(run(&src), (10, 0));
}

#[test]
fn generic_function_taking_a_function() {
    let src = format!("{}{}", FUNCTIONS, r#"
apply_twice<T>(f: (T) => T, x: T): T { return f(f(x)); }

test(): int {
    return apply_twice<int>(square, 3);
}
"#);
    assert_eq!(run(&src), (81, 0));
}

#[test]
fn void_function_values() {
    let src = r#"
var counter = 0;
bump(by: int) { counter = counter + by; }

test(): int {
    var f: (int) => void = bump;
    f(2);
    f(5);
    return counter;
}
"#;
    assert_eq!(run(src), (7, 0));
}

#[test]
fn local_shadows_a_function_name() {
    let src = format!("{}{}", FUNCTIONS, r#"
test(): int {
    var square = 3;
    return square;
}
"#);
    assert_eq!(run(&src), (3, 0));
}

#[test]
fn static_function_object_refcount_stays_balanced() {
    // Copies into locals, fields, arrays and parameters acquire, and every
    // one of them releases again: after the loop only `f` owns a reference
    // beyond the object's immortal base count.
    let src = format!("{}{}", FUNCTIONS, r#"
struct Holder {
    var op: (int) => int;
}

keep(f: (int) => int): int { return f(1); }

test(): int {
    var f = square;
    var base = __refcount<(int) => int>(f);
    var i = 0;
    while (i < 10) {
        var copy = f;
        var holder = Holder();
        holder.op = copy;
        var ops = Array<(int) => int>();
        ops.append(f);
        keep(copy);
        i = i + 1;
    }
    return (__refcount<(int) => int>(f) - base) as int;
}
"#);
    assert_eq!(run(&src), (0, 0));
}

#[test]
fn mismatched_initializer_is_an_error() {
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
test(): int {
    var f: (String) => int = square;
    return 0;
}
"#));
    assert!(err.contains("variable 'f' expects a function of type '(String) => int', but was given a function of type '(int) => int'"), "{}", err);
}

#[test]
fn mismatched_argument_is_an_error() {
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
apply(f: (int) => int, x: int): int { return f(x); }
test(): int {
    return apply(point_x, 1);
}
"#));
    assert!(err.contains("argument 1 of 'apply' expects a function of type '(int) => int', but was given a function of type '(Point) => int'"), "{}", err);
}

#[test]
fn mismatched_assignment_and_return_are_errors() {
    // The first error is the one reported, so each case compiles alone.
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
pick(): (int) => int { return make_point; }
test(): int { return 0; }
"#));
    assert!(err.contains("the return value of 'pick' expects a function of type '(int) => int', but was given a function of type '(int) => Point'"), "{}", err);
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
test(): int {
    var f = square;
    f = point_x;
    return 0;
}
"#));
    assert!(err.contains("assignment expects a function of type '(int) => int', but was given a function of type '(Point) => int'"), "{}", err);
}

#[test]
fn wrong_argument_count_is_an_error() {
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
test(): int {
    var f = square;
    return f(1, 2);
}
"#));
    assert!(err.contains("a function of type '(int) => int' takes 1 argument(s), but 2 were given"), "{}", err);
}

#[test]
fn non_function_argument_is_an_error() {
    let err = compile_error(&format!("{}{}", FUNCTIONS, r#"
apply(f: (int) => int, x: int): int { return f(x); }
test(): int {
    return apply(5, 1);
}
"#));
    assert!(err.contains("argument 1 of 'apply' expects a function of type '(int) => int'"), "{}", err);
}

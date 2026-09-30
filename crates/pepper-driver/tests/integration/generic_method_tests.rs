//! Generic calls without type arguments (`larger(3, 9)`), methods with
//! type parameters of their own (`map<U>`), and the iterator adapters built
//! on them (`Iterator.map`, `Iterator.filter`), with the leak census.

use pepper_codegen::CodeGenerator;
use pepper_sema::model::Module as SemaModule;

fn sema(source: &str) -> Result<SemaModule, String> {
    pepper_driver::compiler::compile_with_runtime("test.pep", source)
}

/// Compile + JIT `test()` and return (result, net live-allocation delta).
fn run(source: &str) -> (i32, i64) {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:\n{}", e));
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

#[test]
fn type_arguments_from_arguments() {
    let src = r#"
larger<T>(a: T, b: T): T { return a > b ? a : b; }
first<U>(items: Array<U>): U { return items[0]; }

test(): int {
    var words = Array<String>();
    words.append("hello");
    var word = first(words);
    return larger(3, 9) + (word.size() as int);
}
"#;
    assert_eq!(run(src), (14, 0));
}

#[test]
fn closure_arguments_take_and_give_type_arguments() {
    let src = r#"
apply<T>(f: (T) => T, x: T): T { return f(x); }

transform<T, U>(items: Array<T>, f: (T) => U): Array<U> {
    var out = Array<U>();
    for (var item in items) {
        out.append(f(item));
    }
    return out;
}

test(): int {
    var words = Array<String>();
    words.append("hi");
    words.append("there");
    var sizes = transform(words, (w) => w.size());
    return apply((x) => x + 1, 2) * 100 + (sizes[1] as int);
}
"#;
    assert_eq!(run(src), (305, 0));
}

#[test]
fn generic_methods() {
    let src = r#"
struct Box<T> {
    T value;
    construct(T v) { value = v; }
    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }
}

test(): int {
    var b = Box<int>(4);
    var explicit = b.map<long>((x: int): long => x + 1);
    var tens = b.map((x) => x * 10);
    var text = tens.map((x) => "abc");
    return (explicit.value as int) * 100 + (tens.value as int) + (text.value.size() as int);
}
"#;
    assert_eq!(run(src), (543, 0));
}

#[test]
fn iterator_adapters() {
    let src = r#"
struct Person {
    String name;
    int age;
    construct(this.name = "", this.age = 0) {}
}

test(): int {
    var people = Array<Person>();
    people.append(Person("Ada", 36));
    people.append(Person("Bo", 12));
    people.append(Person("Cyd", 40));
    var letters = 0;
    for (var name in people.iterate().filter((p) => p.age >= 18).map((p) => p.name)) {
        letters = letters + (name.size() as int);
    }
    var kept = 0;
    for (var c in "hello".iterate().filter((c) => c != "l")) {
        kept = kept + 1;
    }
    return letters * 10 + kept;
}
"#;
    assert_eq!(run(src), (63, 0));
}

#[test]
fn adapters_on_your_own_iterator() {
    let src = r#"
struct Countdown {
    int remaining;
    int now;
    construct(this.remaining = 0) {}
    bool next() {
        if (remaining == 0) { return false; }
        now = remaining;
        remaining = remaining - 1;
        return true;
    }
    int current() { return now; }
}

extend Countdown with Iterator<int> {}

test(): int {
    var total = 0;
    for (var n in Countdown(5).map((n) => n * n).filter((n) => n > 4)) {
        total = total + n;
    }
    return total;
}
"#;
    assert_eq!(run(src), (50, 0));
}

#[test]
fn uninferable_type_arguments_are_an_error() {
    let err = compile_error(
        r#"
make<T>(): T { return __default<T>(); }

test(): int {
    var x = make();
    return 0;
}
"#,
    );
    assert!(err.contains("cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)"), "{}", err);
    assert!(err.contains("test.pep:5:13"), "{}", err);
}

#[test]
fn inferred_calls_in_a_generic_structs_generic_method() {
    // `describe(this.v)` in `Box<T>` names `T` until `Box` is specialized:
    // it is inferred in `Box<int>.show<U>` (as `describe<int>`), not in the
    // generic base, where it would have become `describe<T>`.
    let src = r#"
describe<T>(v: T): int { return 7; }
wrap<X>(x: X): int { return describe(x) + 1; }
struct Box<T> {
    var v: T;
    construct(T v) { this.v = v; }
    show<U>(U u): int { return describe(this.v) + wrap(u); }
    plain(): int { return describe(this.v); }
}
test(): int { var b = Box<int>(1); return b.show(true) * 100 + b.plain(); }
"#;
    let (result, leaked) = run(src);
    assert_eq!(result, 1507);
    assert_eq!(leaked, 0);
}

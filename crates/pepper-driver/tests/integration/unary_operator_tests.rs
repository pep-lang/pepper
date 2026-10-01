//! Unary operator overloading on structs (`-()`, `~()`, `!()`) and the
//! truth-test operator `!!()`, which a struct value in a boolean context
//! calls: `if`/`while` conditions, the ternary condition, the operands of
//! `and`/`or`/`&&`/`||`, and the operand of `!`.

use crate::support::compile_jit_with_runtime;

/// Run a `test(): int` program whose checks `return <case index>` on failure.
fn assert_cases(source: &str) {
    assert_eq!(compile_jit_with_runtime(source), 0, "first failing case index");
}

fn compile_error(source: &str) -> String {
    match pepper_driver::compiler::compile_with_runtime("test.pep", source) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e,
    }
}

/// A counter whose truth test counts its calls, so a test can tell the
/// operator ran (rather than a null check).
const FLAG: &str = r#"
struct Flag {
    bool on;
    int tests;
    construct(this.on = false) {}
    !!(): bool {
        tests += 1;
        return on;
    }
}
"#;

#[test]
fn negate_and_complement_call_the_methods() {
    assert_cases(
        r#"struct V {
    int x;
    construct(this.x = 0) {}
    -(): V { return V(0 - x); }
    V ~() { return V(~x); }
}
test(): int {
    var a = V(5);
    var n = -a;
    if (n.x != -5) { return 1; }
    if ((~a).x != ~5) { return 2; }
    if ((-(-a)).x != 5) { return 3; }
    if ((-~a).x != 6) { return 4; }
    # Numbers are unchanged.
    var i = 3;
    if (-i != 0 - 3 or ~i != -4) { return 5; }
    return 0;
}"#,
    );
}

#[test]
fn logical_not_calls_the_method() {
    assert_cases(
        r#"struct Empty {
    int count;
    construct(this.count = 0) {}
    !(): bool { return count == 0; }
}
test(): int {
    var e = Empty();
    if (!(!e)) { return 1; }
    var f = Empty(2);
    if (!f) { return 2; }
    var b = !f;
    if (b) { return 3; }
    return 0;
}"#,
    );
}

#[test]
fn truth_test_in_every_boolean_context() {
    let source = format!(
        r#"{FLAG}
test(): int {{
    var on = Flag(true);
    var off = Flag();
    # if
    if (off) {{ return 1; }}
    if (off.tests != 1) {{ return 2; }}
    # while
    var n = 0;
    var countdown = Flag(true);
    while (countdown) {{
        n += 1;
        if (n == 3) {{ countdown.on = false; }}
    }}
    if (n != 3 or countdown.tests != 4) {{ return 3; }}
    # else if
    if (off) {{ return 4; }} else if (on) {{}} else {{ return 4; }}
    # ternary
    if ((on ? 1 : 2) != 1 or (off ? 1 : 2) != 2) {{ return 5; }}
    # and / or / && / ||
    if (on and off) {{ return 6; }}
    if (!(on or off)) {{ return 7; }}
    if (off && on) {{ return 8; }}
    if (!(off || on)) {{ return 9; }}
    if (!(on && true)) {{ return 10; }}
    # the operand of !
    if (!on) {{ return 11; }}
    if (!(!off)) {{ return 12; }}
    # !!x calls the truth test once
    var t = Flag(true);
    bool b = !!t;
    if (!b or t.tests != 1) {{ return 13; }}
    # a struct value from a call or a field
    var holder = Holder();
    if (!holder.flag) {{ return 14; }}
    if (!make(true) or make(false)) {{ return 15; }}
    # bool and int keep double negation
    if (!!0 or !(!!7) or !!false) {{ return 16; }}
    return 0;
}}

struct Holder {{
    Flag flag = Flag(true);
}}

make(on: bool): Flag {{
    return Flag(on);
}}
"#
    );
    assert_cases(&source);
}

#[test]
fn not_falls_back_to_the_truth_test() {
    let source = format!(
        r#"{FLAG}
test(): int {{
    var off = Flag();
    if (!off == false) {{ return 1; }}
    if (off.tests != 1) {{ return 2; }}
    var on = Flag(true);
    if (!on) {{ return 3; }}
    return 0;
}}
"#
    );
    assert_cases(&source);
}

#[test]
fn not_prefers_its_own_method() {
    assert_cases(
        r#"struct Both {
    int nots;
    int tests;
    !(): bool { nots += 1; return false; }
    !!(): bool { tests += 1; return true; }
}
test(): int {
    var b = Both();
    if (!b) { return 1; }
    if (b.nots != 1 or b.tests != 0) { return 2; }
    if (!!b == false) { return 3; }
    if (b.nots != 1 or b.tests != 1) { return 4; }
    if (b) {} else { return 5; }
    if (b.tests != 2) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn generic_structs_and_traits_declare_them_too() {
    assert_cases(
        r#"struct Box<T> {
    T value;
    bool full;
    !!(): bool { return full; }
    -(): Box<T> {
        var b = Box<T>();
        b.value = 0 - value;
        b.full = full;
        return b;
    }
}
trait Named {
    name(): int;
    !!(): bool;
}
struct Person {
    int id;
    name(): int { return id; }
    !!(): bool { return id != 0; }
}
extend Person with Named {}
test(): int {
    var b = Box<int>();
    if (b) { return 1; }
    b.value = 4;
    b.full = true;
    var n = -b;
    if (!n or n.value != -4) { return 2; }
    var p = Person();
    Named named = p;
    if (named) { return 3; }
    p.id = 7;
    if (!named) { return 4; }
    return 0;
}"#,
    );
}

// A unary and a binary `-` on one struct form a method overload set, resolved
// by arity (method overloading).
#[test]
fn unary_and_binary_minus_coexist() {
    assert_cases(
        r#"struct V {
    int x;
    construct(this.x = 0) {}
    -(): V { return V(0 - x); }
    -(other: V): V { return V(x - other.x); }
}
test(): int {
    var a = V(5);
    var b = V(2);
    if ((a - b).x != 3) { return 1; }
    if ((-a).x != -5) { return 2; }
    if ((-(a - b)).x != -3) { return 3; }
    if ((a - -b).x != 7) { return 4; }
    return 0;
}"#,
    );
}

#[test]
fn pointers_numbers_and_function_values_keep_their_truthiness() {
    assert_cases(
        r#"test(): int {
    var n = 0;
    if (n) { return 1; }
    var f = 0.5;
    if (!f) { return 2; }
    __ptr<int> p = __null;
    if (p) { return 3; }
    var g: (int) => int;
    if (g) { return 4; }
    g = (x: int) => x + 1;
    if (!g) { return 5; }
    var s = "text";
    if (s === __null) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn a_struct_without_a_truth_test_is_not_a_condition() {
    let cases = [
        "if (s) { return 1; }",
        "while (s) { return 1; }",
        "var x = s ? 1 : 2;",
        "var x = true && s;",
        "var x = s or false;",
        "if (!s) { return 1; }",
        "var x = !!s;",
    ];
    for case in cases {
        let source = format!("struct S {{\n    int x;\n}}\ntest(): int {{\n    var s = S();\n    {}\n    return 0;\n}}\n", case);
        let error = compile_error(&source);
        assert!(
            error.contains("error: 'S' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'"),
            "{}: {}",
            case,
            error
        );
        assert!(error.contains("note: 'S' declared here"), "{}: {}", case, error);
    }
    // A trait value without `!!` in its trait, too.
    let error = compile_error(
        "trait T {\n    f(): int;\n}\nstruct S {\n    f(): int { return 1; }\n}\nextend S with T {}\n\
         test(): int {\n    T t = S();\n    if (t) { return 1; }\n    return 0;\n}\n",
    );
    assert!(error.contains("error: 'T' cannot be used as a condition"), "{}", error);
}

#[test]
fn identity_comparisons_replace_null_checks() {
    assert_cases(
        r#"struct Item {
    int value;
}
struct Slot {
    Item item;
}
test(): int {
    var slot = Slot();
    if (slot.item !== __null) { return 1; }
    slot.item = Item();
    if (slot.item === __null) { return 2; }
    var empty: Item;
    if (empty !== __null) { return 3; }
    return 0;
}"#,
    );
}

#[test]
fn operator_return_and_parameter_errors() {
    let error = compile_error("struct S {\n    !!(): int { return 1; }\n}\ntest(): int { return 0; }\n");
    assert!(error.contains("error: truth-test operator '!!' must return 'bool', not 'int'"), "{}", error);
    let error = compile_error("struct S {\n    String !() { return \"\"; }\n}\ntest(): int { return 0; }\n");
    assert!(error.contains("error: logical operator '!' must return 'bool', not 'String'"), "{}", error);
    let error = compile_error("struct S {\n    ~(o: S): S { return o; }\n}\ntest(): int { return 0; }\n");
    assert!(error.contains("error: unary operator '~' takes no parameters, have 1"), "{}", error);
}

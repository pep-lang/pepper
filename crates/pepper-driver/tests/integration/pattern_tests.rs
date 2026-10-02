//! Patterns in `match` beyond a case and its bindings: guards
//! (docs/src/language/enums.md, "Guards").

use crate::support::{compile_error, jit_census, sema};

const SHAPE: &str = r#"
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Point,
}
"#;

#[test]
fn a_guard_picks_the_arm_only_when_it_holds() {
    let src = format!(
        "{}{}",
        SHAPE,
        r#"
size(s: Shape): int {
    match (s) {
        Circle(r) if r > 10 => { return 1; }
        Circle(r) => { return 2; }
        Rect(w, h) if w == h => { return 3; }
        Rect, Point => { return 4; }
    }
}

test(): int {
    return size(Shape.Circle(20)) + size(Shape.Circle(5)) * 10 + size(Shape.Rect(3, 3)) * 100
        + size(Shape.Rect(3, 4)) * 1000 + size(Shape.Point) * 10000;
}
"#
    );
    assert_eq!(jit_census(&src), (1 + 20 + 300 + 4000 + 40000, 0));
}

#[test]
fn guards_in_match_expressions_over_literals_and_tuples() {
    let src = r#"
sign(n: int, strict: bool): int {
    return match (n) {
        0 if strict => 100,
        0 => 0,
        else => n,
    };
}

pick(t: (int, bool)): int {
    return match (t) {
        (x, true) if x > 5 => 1,
        (x, b) if x < 0 && !b => 2,
        (_, true) => 3,
        (_, false) => 4,
    };
}

test(): int {
    return sign(0, true) + sign(0, false) + sign(7, true) * 1000
        + pick((9, true)) * 10000 + pick((-1, false)) * 100000 + pick((1, true)) * 1000000;
}
"#;
    assert_eq!(jit_census(src), (100 + 7000 + 10000 + 200000 + 3000000, 0));
}

#[test]
fn a_guard_reads_values_of_alternatives_and_strings() {
    let src = r#"
enum Token {
    Word(text: String),
    Quoted(text: String),
    End,
}

kind(t: Token): int {
    return match (t) {
        Word(s), Quoted(s) if s.length == 0 => 1,
        Word(s) if s == "if" => 2,
        Word, Quoted => 3,
        End => 4,
    };
}

test(): int {
    return kind(Token.Word("")) + kind(Token.Quoted("")) * 10 + kind(Token.Word("if")) * 100
        + kind(Token.Quoted("if")) * 1000 + kind(Token.End) * 10000;
}
"#;
    assert_eq!(jit_census(src), (1 + 10 + 200 + 3000 + 40000, 0));
}

#[test]
fn a_guarded_arm_does_not_cover_its_case() {
    let err = compile_error(&format!(
        "{}{}",
        SHAPE,
        "test(): int { return match (Shape.Point) { Circle(r) if r > 1 => 1, Rect, Point => 2 }; }"
    ));
    assert!(err.contains("match on 'Shape' does not handle 'Circle'"), "{err}");
    let err = compile_error("test(): int { return match ((1, true)) { (_, true) => 1, (_, false) if 1 > 0 => 2 }; }");
    assert!(err.contains("does not handle '(_, false)'"), "{err}");
    let err = compile_error("test(): int { var b = true; return match (b) { true => 1, false if b => 2 }; }");
    assert!(err.contains("match on 'bool' needs an 'else' arm"), "{err}");
}

#[test]
fn a_guarded_arm_after_its_case_is_handled_is_an_error() {
    let err = compile_error(&format!(
        "{}{}",
        SHAPE,
        "test(): int { return match (Shape.Point) { Point => 0, Circle(r) => 1, Rect => 2, Point if true => 3 }; }"
    ));
    assert!(err.contains("case 'Point' is already handled"), "{err}");
}

#[test]
fn else_after_a_guarded_arm_is_not_unreachable() {
    let src = format!("{}{}", SHAPE, "test(): int { return match (Shape.Point) { Circle(r) if r > 1 => 1, Rect, Point => 2, else => 3 }; }");
    let module = sema(&src).unwrap_or_else(|e| panic!("{e}"));
    assert!(module.warnings.is_empty(), "{:?}", module.warnings);
}

#[test]
fn a_closure_in_a_guard_cannot_use_a_binding() {
    let err = compile_error(&format!(
        "{}{}",
        SHAPE,
        "test(): int { return match (Shape.Point) { Circle(r) if (() => r)() > 1 => 1, else => 2 }; }"
    ));
    assert!(err.contains("a closure in a guard cannot use 'r', bound by the arm's patterns"), "{err}");
}

#[test]
fn a_bound_string_compares_by_value_in_a_match_expression() {
    // `==` on a binding resolves to `String`'s operator, as on any `String`.
    let src = r#"
enum Token {
    Word(text: String),
    End,
}

is_if(t: Token): bool {
    return match (t) {
        Word(s) => s == "if",
        End => false,
    };
}

test(): int {
    return (is_if(Token.Word("if")) ? 1 : 0) + (is_if(Token.Word("of")) ? 10 : 0);
}
"#;
    assert_eq!(jit_census(src), (1, 0));
}

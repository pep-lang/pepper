//! Patterns in `match` beyond a case and its bindings: guards, ranges and
//! constants (docs/src/language/enums.md).

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

#[test]
fn ranges_and_constants_match_integers_and_characters() {
    let src = r#"
const LIMIT = 10;

size(n: int): int {
    return match (n) {
        0 => 0,
        1..5 => 1,
        5..>9 => 2,
        LIMIT => 3,
        -9..0 => 4,
        else => 5,
    };
}

kind(c: char): int {
    return match (c) {
        'a'..>'z', 'A'..>'Z' => 1,
        '0'..>'9' => 2,
        else => 3,
    };
}

pair(t: (int, bool)): int {
    return match (t) {
        (0..LIMIT, true) => 1,
        (LIMIT, _) => 2,
        (x, _) => x,
    };
}

test(): int {
    var total = size(0) + size(4) * 10 + size(5) * 100 + size(9) * 1000 + size(10) * 10000;
    total += size(-1) * 100000 + size(11) * 1000000;
    total += kind('q') + kind('Q') * 10 + kind('5') * 100 + kind('!') * 1000;
    total += pair((3, true)) + pair((10, false)) * 10 + pair((42, true));
    return total;
}
"#;
    let expected = 10 + 200 + 2000 + 30000 + 400000 + 5000000 + 1 + 10 + 200 + 3000 + 1 + 20 + 42;
    assert_eq!(jit_census(src), (expected, 0));
}

#[test]
fn ranges_that_cover_every_value_need_no_else() {
    let src = r#"
half(b: u8): int {
    return match (b) {
        0..128 => 0,
        128..>255 => 1,
    };
}

test(): int {
    u8 high = 200;
    return half(3) + half(high) * 10;
}
"#;
    assert_eq!(jit_census(src), (10, 0));
    let src = "test(): int { u8 b = 1; return match (b) { 0..>255 => 1, else => 0 }; }";
    let module = sema(src).unwrap_or_else(|e| panic!("{e}"));
    assert!(module.warnings.iter().any(|w| w.message == "'else' is unreachable: every value of 'u8' is handled"), "{:?}", module.warnings);
    let err = compile_error("test(): int { u8 b = 1; return match (b) { 0..255 => 1 }; }");
    assert!(err.contains("match on 'u8' needs an 'else' arm"), "{err}");
}

#[test]
fn range_and_constant_pattern_errors() {
    let err = compile_error("test(): int { return match (3) { 1..9 => 1, 4 => 2, else => 0 }; }");
    assert!(err.contains("pattern '4' is already handled"), "{err}");
    let err = compile_error("test(): int { return match (3) { 1..9 => 1, 2..>5 => 2, else => 0 }; }");
    assert!(err.contains("pattern '2..>5' is already handled"), "{err}");
    let err = compile_error("test(): int { return match (3) { 9..1 => 1, else => 0 }; }");
    assert!(err.contains("range '9..1' matches no value"), "{err}");
    let err = compile_error("test(): int { return match (\"a\") { \"a\"..\"c\" => 1, else => 0 }; }");
    assert!(err.contains("a range cannot match a value of 'String'"), "{err}");
    let err = compile_error("enum Color { Red, Green }\nconst FAVORITE = Color.Red;\ntest(): int { return match (Color.Green) { FAVORITE => 1, else => 0 }; }");
    assert!(err.contains("a constant cannot match a value of 'Color': name its cases"), "{err}");
    // A name that is not a module-scope constant is not a pattern of an `int`.
    let err = compile_error("test(): int { var n = 3; return match (4) { n => 1, else => 0 }; }");
    assert!(err.contains("'n' is not a literal"), "{err}");
}

const DOC: &str = r#"
enum Doc {
    Text(text: String),
    Line,
    Pair(left: Doc, right: Doc),
}
"#;

#[test]
fn patterns_nest_inside_a_cases_values() {
    let src = format!(
        "{}{}",
        DOC,
        r#"
kind(o: Optional<Doc>): int {
    return match (o) {
        Empty => 0,
        Value(Text("")) => 1,
        Value(Text(t)) => (t.length as int) * 10,
        Value(Line) => 2,
        Value(Pair(Line, _)) => 3,
        Value(Pair(Text(a), Pair(_, Text(b)))) => 4,
        Value(Pair) => 5,
    };
}

count(n: Optional<int>): int {
    match (n) {
        Value(0) => { return 100; }
        Value(1..10) => { return 200; }
        Value(x) if x < 0 => { return 300; }
        Value(x) => { return x; }
        Empty => { return -1; }
    }
}

test(): int {
    var total = kind(Optional<Doc>.Empty) + kind(Optional<Doc>.Value(Doc.Text(""))) + kind(Optional<Doc>.Value(Doc.Text("abc")));
    total += kind(Optional<Doc>.Value(Doc.Line)) + kind(Optional<Doc>.Value(Doc.Pair(Doc.Line, Doc.Line)));
    total += kind(Optional<Doc>.Value(Doc.Pair(Doc.Text("a"), Doc.Pair(Doc.Line, Doc.Text("b")))));
    total += kind(Optional<Doc>.Value(Doc.Pair(Doc.Text("a"), Doc.Line)));
    total += count(Optional<int>.Value(0)) + count(Optional<int>.Value(5)) + count(Optional<int>.Value(-5));
    total += count(Optional<int>.Value(42)) + count(Optional<int>.Empty);
    var d = Doc.Pair(Doc.Text("x"), Doc.Line);
    if (d is Pair(Text(s), Line)) {
        total += (s.length as int) * 1000;
    }
    return total;
}
"#
    );
    assert_eq!(jit_census(&src), (1 + 30 + 2 + 3 + 4 + 5 + 100 + 200 + 300 + 42 - 1 + 1000, 0));
}

#[test]
fn a_bare_name_in_a_cases_values_is_a_case_of_the_values_enum() {
    let src = r#"
depth(o: Optional<Optional<int>>): int {
    return match (o) {
        Empty => 0,
        Value(Empty) => 1,
        Value(Value(n)) => 2 + n,
    };
}

test(): int {
    return depth(Optional<Optional<int>>.Empty) + depth(Optional<Optional<int>>.Value(Optional<int>.Empty)) * 10
        + depth(Optional<Optional<int>>.Value(Optional<int>.Value(5))) * 100;
}
"#;
    assert_eq!(jit_census(src), (10 + 700, 0));
}

#[test]
fn nested_patterns_count_toward_every_case_handled() {
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Optional<Doc>.Empty) { Empty => 0, Value(Text(t)) => 1, Value(Pair) => 2 }; }"
    ));
    assert!(err.contains("match on 'Optional<Doc>' does not handle 'Value(Line)'"), "{err}");
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Doc.Line) { Text(\"\") => 0, Line => 1, Pair => 2 }; }"
    ));
    assert!(err.contains("match on 'Doc' does not handle 'Text'"), "{err}");
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Doc.Line) { Text(t) => 0, Line => 1, Pair(Line, _) => 2, Pair(_, Line) => 3 }; }"
    ));
    assert!(err.contains("match on 'Doc' does not handle 'Pair(Text, Text)'"), "{err}");
}

#[test]
fn a_nested_pattern_the_earlier_arms_cover_is_an_error() {
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Doc.Line) { Pair(Line, _) => 0, Pair(_, _) => 1, Pair(Line, Line) => 2, else => 3 }; }"
    ));
    assert!(err.contains("case 'Pair' is already handled"), "{err}");
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Doc.Line) { Pair(Line, _) => 0, Pair(_, Line) => 1, Pair(Line, Line) => 2, else => 3 }; }"
    ));
    assert!(err.contains("pattern 'Pair(Line, Line)' is already handled"), "{err}");
}

#[test]
fn nested_pattern_errors() {
    let err = compile_error(&format!("{}{}", DOC, "test(): int { return match (Doc.Line) { Text(Line(x)) => 0, else => 1 }; }"));
    assert!(err.contains("'Line' cannot match a value of 'String': it is not an enum"), "{err}");
    let err = compile_error(&format!("{}{}", DOC, "test(): int { return match (Doc.Line) { Pair(x, x) => 0, else => 1 }; }"));
    assert!(err.contains("'x' binds an element here"), "{err}");
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): bool { var d = Doc.Line; return d is Text(t); }"
    ));
    assert!(err.contains("cannot bind 't' here"), "{err}");
}

#[test]
fn alternatives_bind_a_nested_name_at_the_same_place() {
    let src = format!(
        "{}{}",
        DOC,
        r#"
left_text(d: Doc): int {
    return match (d) {
        Pair(Text(t), Line), Pair(Text(t), Pair) => t.length as int,
        else => 0,
    };
}

test(): int {
    return left_text(Doc.Pair(Doc.Text("ab"), Doc.Line))
        + left_text(Doc.Pair(Doc.Text("abc"), Doc.Pair(Doc.Line, Doc.Line))) * 10
        + left_text(Doc.Pair(Doc.Text("abcd"), Doc.Text(""))) * 100;
}
"#
    );
    assert_eq!(jit_census(&src), (2 + 30, 0));
    let err = compile_error(&format!(
        "{}{}",
        DOC,
        "test(): int { return match (Doc.Line) { Pair(Text(t), _), Pair(_, Text(t)) => 1, else => 0 }; }"
    ));
    assert!(err.contains("'t' is bound at a different element than in the arm's first pattern"), "{err}");
}

//! `e?`, the propagation operator on `Result` and `Optional`
//! (docs/src/language/results.md): it yields the value, or returns the error
//! (or the empty optional) from the enclosing function, converting the error
//! through an `[Implicit]` constructor. Each case also checks that nothing
//! leaks, on the early return and on the normal path.

use crate::support::{compile_error, jit_cases};

const PROGRAM: &str = r#"
struct ParseError {
    String input;

    construct(this.input = "") {}
}

struct AppError {
    String text;

    [Implicit]
    construct(e: ParseError) {
        this.text = "parse: " + e.input;
    }
}

struct Counter {
    int calls = 0;

    construct() {}

    next(fail: bool): Result<int, ParseError> {
        this.calls += 1;
        if (fail) {
            return Result<int, ParseError>.err(ParseError($"call {this.calls}"));
        }
        return Result<int, ParseError>.ok(this.calls);
    }
}

parse(s: String): Result<int, ParseError> {
    if (s.is_empty) {
        return Result<int, ParseError>.err(ParseError(s));
    }
    if (s == "x") {
        return Result<int, ParseError>.err(ParseError("bad x"));
    }
    return Result<int, ParseError>.ok(s.length);
}

add(a: int, b: int): int {
    return a + b;
}

sum(a: String, b: String): Result<int, ParseError> {
    return Result<int, ParseError>.ok(add(parse(a)?, parse(b)?));
}

converted(s: String): Result<String, AppError> {
    var n = parse(s)?;
    return Result<String, AppError>.ok($"n = {n}");
}

type Outcome = Result<int, ParseError>;

aliased(s: String): Outcome {
    var n = parse(s)? * 2;
    return Outcome.ok(n);
}

check(ok: bool): Result<void> {
    if (!ok) {
        return Result<void>.err(Error("no"));
    }
    return Result<void>.ok();
}

statement(ok: bool): Result<int> {
    check(ok)?;
    return Result<int>.ok(1);
}

plus_one(o: int?): int? {
    return Optional<int>.some(o? + 1);
}

name_length(names: Array<String>, index: ulong): ulong? {
    var name = (index < names.count ? Optional<String>.some(names[index]) : Optional<String>.none())?;
    return Optional<ulong>.some(name.length);
}

nested(s: String): Result<int, ParseError> {
    var n = parse(converted_back(s)?)?;
    return Result<int, ParseError>.ok(n);
}

converted_back(s: String): Result<String, ParseError> {
    if (s == "y") {
        return Result<String, ParseError>.err(ParseError("y"));
    }
    return Result<String, ParseError>.ok(s + s);
}

loop_sum(items: Array<String>): Result<int, ParseError> {
    var total = 0;
    for (var item in items) {
        total += parse(item)?;
    }
    return Result<int, ParseError>.ok(total);
}

while_condition(c: Counter, fail_at: int): Result<int, ParseError> {
    var seen = 0;
    while (c.next(c.calls + 1 == fail_at)? < 3) {
        seen += 1;
    }
    return Result<int, ParseError>.ok(seen);
}

branch(s: String): Result<bool, ParseError> {
    if (parse(s)? > 2) {
        return Result<bool, ParseError>.ok(true);
    } else if (parse(s + "x")? > 1) {
        return Result<bool, ParseError>.ok(false);
    }
    return Result<bool, ParseError>.ok(false);
}

matched(s: String): Result<String, ParseError> {
    match (parse(s)?) {
        1 => {
            return Result<String, ParseError>.ok("one");
        }
        else => {
            return Result<String, ParseError>.ok("more");
        }
    }
}

closure(s: String): Result<int, ParseError> {
    var twice = (t: String): Result<int, ParseError> => Result<int, ParseError>.ok(parse(t)? * 2);
    return Result<int, ParseError>.ok(twice(s)? + 1);
}

ternary_still_works(c: bool): int {
    var a = c ? -1 : 1;
    var b = c ? (a) : 2;
    var d = c ? [1, 2] : [3];
    return a + b + d.count as int;
}

test_sum(): int {
    if (sum("ab", "cde").value() != 5) { return 1; }
    var bad = sum("ab", "");
    if (!bad.is_err() || bad.error().input != "") { return 2; }
    if (sum("x", "abc").error().input != "bad x") { return 3; }
    return 0;
}

test_converted(): int {
    if (converted("abc").value() != "n = 3") { return 1; }
    if (converted("x").error().text != "parse: bad x") { return 2; }
    return 0;
}

test_aliased(): int {
    if (aliased("abc").value() != 6) { return 1; }
    if (aliased("x").is_ok()) { return 2; }
    return 0;
}

test_statement(): int {
    if (statement(true).value() != 1) { return 1; }
    if (statement(false).error().message != "no") { return 2; }
    return 0;
}

test_optional(): int {
    if (plus_one(Optional<int>.some(1)).value() != 2) { return 1; }
    if (plus_one(Optional<int>.none()).is_some()) { return 2; }
    var names = ["ab", "cde"];
    if (name_length(names, 1).value() != 3) { return 3; }
    if (name_length(names, 2).is_some()) { return 4; }
    return 0;
}

test_nested(): int {
    if (nested("ab").value() != 4) { return 1; }
    if (nested("y").error().input != "y") { return 2; }
    return 0;
}

test_loop(): int {
    if (loop_sum(["a", "bc"]).value() != 3) { return 1; }
    if (loop_sum(["a", "x", "bc"]).error().input != "bad x") { return 2; }
    return 0;
}

test_while(): int {
    # The condition runs on every iteration: calls 1 and 2 are below 3.
    if (while_condition(Counter(), 0).value() != 2) { return 1; }
    var c = Counter();
    if (while_condition(c, 2).error().input != "call 2") { return 2; }
    if (c.calls != 2) { return 3; }
    return 0;
}

test_branch(): int {
    if (!branch("abc").value()) { return 1; }
    if (branch("ab").value()) { return 2; }
    if (branch("").is_ok()) { return 3; }
    return 0;
}

test_match(): int {
    if (matched("a").value() != "one") { return 1; }
    if (matched("ab").value() != "more") { return 2; }
    if (matched("x").is_ok()) { return 3; }
    return 0;
}

test_closure(): int {
    if (closure("ab").value() != 5) { return 1; }
    if (closure("x").error().input != "bad x") { return 2; }
    return 0;
}

test_ternary(): int {
    if (ternary_still_works(true) != 0) { return 1; }
    return 0;
}
"#;

#[test]
fn propagation() {
    jit_cases(
        PROGRAM,
        &[
            "test_sum",
            "test_converted",
            "test_aliased",
            "test_statement",
            "test_optional",
            "test_nested",
            "test_loop",
            "test_while",
            "test_branch",
            "test_match",
            "test_closure",
            "test_ternary",
        ],
    );
}

const HEADER: &str = "struct Other {\n    construct() {}\n}\nparse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmaybe(): int? {\n    return Optional<int>.some(1);\n}\n";

/// The first line of the error `body` (appended to [`HEADER`]) fails with.
fn first_line(body: &str) -> String {
    let source = format!("{}{}\ntest(): int {{\n    return 0;\n}}\n", HEADER, body);
    compile_error(&source).lines().next().unwrap_or_default().to_string()
}

#[test]
fn errors() {
    let cases = [
        (
            "f(): int {\n    return parse()?;\n}",
            "test.pep:11:19: error: '?' requires the enclosing function to return a Result",
        ),
        (
            "f(): Result<int> {\n    return Result<int>.ok(maybe()?);\n}",
            "test.pep:11:34: error: '?' requires the enclosing function to return an Optional",
        ),
        (
            "f(): Result<int, Other> {\n    return Result<int, Other>.ok(parse()?);\n}",
            "test.pep:11:41: error: cannot convert error type 'Error' to 'Other'",
        ),
        (
            "f(): Result<int> {\n    var x = 5?;\n    return Result<int>.ok(x);\n}",
            "test.pep:11:14: error: '?' requires a Result or an Optional, not 'i32'",
        ),
        (
            "f(): void {\n    parse()?;\n}",
            "test.pep:11:12: error: '?' requires the enclosing function to return a Result or an Optional",
        ),
        (
            "f(): Result<int> {\n    var g = (x: int) => parse()?;\n    return parse();\n}",
            "test.pep:11:32: error: '?' requires the enclosing function to declare its return type",
        ),
        (
            "f(): Result<int> {\n    var x = parse().value() + parse()?;\n    return Result<int>.ok(x);\n}",
            "test.pep:11:38: error: '?' cannot follow a call in the same statement",
        ),
        (
            "f(b: bool): Result<int> {\n    var x = b && parse()? > 0;\n    return Result<int>.ok(1);\n}",
            "test.pep:11:25: error: '?' cannot be used in the right operand of '&&'",
        ),
        (
            "f(b: bool): Result<int> {\n    var x = b ? parse()? : 0;\n    return Result<int>.ok(x);\n}",
            "test.pep:11:24: error: '?' cannot be used in a branch of '?:'",
        ),
        ("var g = parse()?;", "test.pep:10:16: error: '?' can be used only in a statement of a function body"),
    ];
    let failures: Vec<String> = cases
        .iter()
        .filter_map(|(body, expected)| {
            let actual = first_line(body);
            (actual != *expected).then(|| format!("{}\n  expected: {}\n  actual:   {}", body, expected, actual))
        })
        .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

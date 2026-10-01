//! Named arguments (`resize(width = 800)`): binding to parameters by name,
//! skipping defaulted parameters, evaluation in the order written, and the
//! reference counts of reordered and defaulted arguments.

use crate::support::{compile_error, compile_jit_with_runtime, jit_census};

#[test]
fn named_arguments_bind_by_name() {
    let source = r#"
window(title: String, width: int = 800, height: int = 600, resizable: bool = true): String {
    return $"{title} {width}x{height} {resizable}";
}
test(): int {
    if (window("a") != "a 800x600 true") { return 1; }
    if (window("a", resizable = false) != "a 800x600 false") { return 2; }
    if (window("a", height = 400, width = 1200) != "a 1200x400 true") { return 3; }
    if (window(title = "a", width = 1024) != "a 1024x600 true") { return 4; }
    if (window("a", 1, height = 2) != "a 1x2 true") { return 5; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn named_arguments_reach_every_kind_of_call() {
    let source = r#"
struct Point {
    var x: int;
    var y: int;
    construct(this.x = 0, this.y = 0) {}
    moved(dx: int = 0, dy: int = 0): Point { return Point(x + dx, y + dy); }
    static origin(scale: int = 1, shift: int = 0): Point { return Point(shift, shift * scale); }
    shifted(): Point { return moved(dy = 10); }
}
struct Box<T> {
    var value: T;
    construct(value: T) { this.value = value; }
    plus(extra: T, times: int = 1, base: T = value): T { return base + extra * times; }
}
enum Light: u8 {
    Red,
    Green,

    code(offset: int = 0, scale: int = 1): int { return (this == Light.Red ? 1 : 2) * scale + offset; }
}
trait Speaker {
    speak(word: String, times: int): String;
}
struct Dog {
    construct() {}
    speak(word: String, times: int): String { return $"{word}{times}"; }
}
extend Dog with Speaker;
struct Cat {
    construct() {}
}
extend Cat {
    purr(loud: bool = false, count: int = 1): int { return loud ? count * 10 : count; }
}
pair<T>(first: T, second: T, swap: bool = false): T {
    return swap ? second : first;
}
test(): int {
    var p = Point(y = 5);
    if (p.x != 0 || p.y != 5) { return 1; }
    var q = p.moved(dy = 2);
    if (q.x != 0 || q.y != 7) { return 2; }
    var o = Point.origin(shift = 3);
    if (o.x != 3 || o.y != 3) { return 3; }
    if (p.shifted().y != 15) { return 4; }
    var b = Box<int>(3);
    if (b.plus(base = 1, extra = 4) != 5) { return 5; }
    if (Light.Green.code(scale = 3) != 6) { return 6; }
    Speaker s = Dog();
    if (s.speak(times = 2, word = "w") != "w2") { return 7; }
    if (Cat().purr(count = 3) != 3) { return 8; }
    if (pair(second = 2, first = 1) != 1) { return 9; }
    if (pair(1, 2, swap = true) != 2) { return 10; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn named_arguments_pick_among_overloads() {
    let source = r#"
scale(x: int, factor: int = 2): int { return x * factor; }
scale(x: double, factor: double = 2.0): double { return x * factor; }
pick(a: int, b: int = 0): int { return 1; }
pick(a: String, c: int = 0): int { return 2; }
test(): int {
    if (scale(3, factor = 3) != 9) { return 1; }
    if (scale(1.5, factor = 2.0) != 3.0) { return 2; }
    if (pick(1, b = 1) != 1) { return 3; }
    if (pick("x", c = 1) != 2) { return 4; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn reordered_arguments_are_evaluated_in_the_order_written() {
    let source = r#"
struct Log {
    var text: String = "";
}
note(log: Log, s: String): String {
    log.text = log.text + s;
    return s;
}
join(first: String, second: String = "-", third: String = "+"): String { return first + second + third; }
struct Joiner {
    construct() {}
    make(log: Log): Joiner {
        log.text = log.text + "m";
        return Joiner();
    }
    join(left: String, right: String): String { return left + right; }
}
test(): int {
    var log = Log();
    var joined = join(third = note(log, "c"), first = note(log, "a"), second = "b");
    if (log.text != "ca") { return 1; }
    if (joined != "abc") { return 2; }
    join(third = note(log, "x"), first = note(log, "y"));
    if (log.text != "caxy") { return 3; }
    # A positional argument is still evaluated first, and a receiver that is
    # a call before the arguments.
    join(note(log, "p"), third = note(log, "t"), second = note(log, "s"));
    if (log.text != "caxypts") { return 4; }
    var joiner = Joiner();
    joiner.make(log).join(right = note(log, "r"), left = note(log, "l"));
    if (log.text != "caxyptsmrl") { return 5; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn reordered_and_skipped_arguments_do_not_leak() {
    let source = r#"
struct Item {
    var n: int;
    construct(n: int) { this.n = n; }
}
make(n: int): Item { return Item(n); }
struct Holder {
    var item: Item;
    construct(item: Item) { this.item = item; }
    sum(a: Item, b: Item): int { return item.n + a.n + b.n; }
}
total(a: Item, b: Item = Item(10), c: Item = Item(100)): int { return a.n + b.n + c.n; }
label(name: String = "anon", suffix: String = "!"): String { return name + suffix; }
test(): int {
    var kept = Item(1);
    if (total(c = make(3), a = make(1)) != 14) { return 1; }
    if (total(kept, c = kept) != 12) { return 2; }
    if (total(b = kept, a = make(2)) != 103) { return 3; }
    if (label(suffix = "?") != "anon?") { return 4; }
    if (label(suffix = label(), name = "x") != "xanon!") { return 5; }
    if (Holder(make(5)).sum(b = make(2), a = make(3)) != 10) { return 6; }
    return 0;
}
"#;
    assert_eq!(jit_census(source), (0, 0));
}

#[test]
fn aliases_and_former_names() {
    let source = r#"
[Alias("size", "count")]
[Rename("w", "width")]
resize(width: int, count: int = 1): int { return width * count; }
test(): int {
    if (resize(2, size = 3) != 6) { return 1; }
    if (resize(w = 2, count = 4) != 8) { return 2; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn named_argument_errors() {
    let cases = [
        ("f(a = 1, 2);", "positional argument cannot follow a named argument"),
        ("f(1, a = 2);", "argument for 'a' given twice"),
        ("f(1, widht = 2);", "no parameter named 'widht' in 'f'; did you mean 'width'?"),
        ("f(width = 2);", "missing argument for parameter 'a' in call to 'f'"),
        ("var g = f; g(a = 1);", "cannot name arguments in a call through a function value of type '(int, int, int) => int'"),
        ("puts(s = \"x\");", "cannot name arguments in a call to extern function 'puts'"),
        ("f(a = 1, size = 2, count = 3);", "argument for 'count' given twice"),
        ("X().m(q = 1);", "no parameter named 'q' in 'X.m'; did you mean 'p'?"),
    ];
    for (call, expected) in cases {
        let source = format!(
            r#"
extern int puts(char* s);
[Alias("size", "count")]
f(a: int, width: int = 3, count: int = 0): int {{ return a + width; }}
struct X {{
    construct() {{}}
    m(p: int): int {{ return p; }}
}}
test(): int {{
    {call}
    return 0;
}}
"#
        );
        let error = compile_error(&source);
        assert!(error.contains(expected), "{call}: expected '{expected}', got:\n{error}");
    }
}

#[test]
fn alias_and_rename_errors() {
    let cases = [
        (r#"[Alias("size", "nope")]"#, "no parameter named 'nope'"),
        (r#"[Alias("width", "count")]"#, "'width' is a parameter"),
        (r#"[Alias("size", "count")] [Rename("size", "width")]"#, "'size' is already another name of a parameter"),
        (r#"[Rename("w")]"#, "'Rename' takes two strings"),
    ];
    for (attributes, expected) in cases {
        let source = format!("{attributes}\nf(width: int, count: int = 0): int {{ return width; }}\ntest(): int {{ return f(1); }}\n");
        let error = compile_error(&source);
        assert!(error.contains(expected), "{attributes}: expected '{expected}', got:\n{error}");
    }
}

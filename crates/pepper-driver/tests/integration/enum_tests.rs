//! Enums, their cases with and without values, and `match` over them
//! (docs/src/language/enums.md).

use clap::Parser;
use std::path::PathBuf;
use std::process::Command;
use crate::support::compile_jit_with_runtime as run;

fn error_of(source: &str) -> String {
    match pepper_driver::compiler::compile_with_runtime("test.pep", source) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e.to_string(),
    }
}

const COLOR: &str = r#"
enum Color {
    Red,
    Green,
    Blue,
}

score(c: Color): int {
    match (c) {
        Red => { return 1; }
        Green => { return 10; }
        Blue => { return 100; }
    }
    return 0;
}
"#;

#[test]
fn match_picks_the_arm_of_the_case() {
    let src = format!("{}{}", COLOR, "test(): int { return score(Color.Red) + score(Color.Green) + score(Color.Blue); }");
    assert_eq!(run(&src), 111);
}

#[test]
fn cases_number_from_zero_and_continue_after_an_explicit_value() {
    let src = r#"
enum Level {
    Low,
    Middle = 10,
    High,
}
test(): int {
    return (Level.Low as int) + (Level.Middle as int) * 100 + (Level.High as int) * 10000;
}
"#;
    assert_eq!(run(src), 11 * 10000 + 10 * 100);
}

#[test]
fn negative_and_character_values() {
    let src = r#"
enum Sign {
    Minus = -1,
    Zero,
    Plus,
}
enum Bracket: u8 {
    Open = '(',
    Close = ')',
}
test(): int {
    return (Sign.Minus as int) + (Sign.Plus as int) * 10 + (Bracket.Close as int) * 100;
}
"#;
    assert_eq!(run(src), -1 + 10 + 41 * 100);
}

#[test]
fn several_patterns_share_an_arm_and_else_takes_the_rest() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
warm(c: Color): bool {
    match (c) {
        Red => { return true; }
        else => { return false; }
    }
    return false;
}
primary(c: Color): int {
    match (c) {
        Red, Blue => { return 1; }
        Green => { return 2; }
    }
    return 0;
}
test(): int {
    var total = 0;
    if (warm(Color.Red)) { total += 1; }
    if (!warm(Color.Blue)) { total += 10; }
    total += primary(Color.Blue) * 100 + primary(Color.Green) * 1000;
    return total;
}
"#
    );
    assert_eq!(run(&src), 1 + 10 + 100 + 2000);
}

#[test]
fn enum_values_are_stored_in_fields_arrays_and_locals() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
struct Pixel {
    Color color = Color.Green;
}
test(): int {
    var p = Pixel();
    var colors = Array<Color>();
    colors.append(Color.Blue);
    colors.append(p.color);
    p.color = colors[0];
    Color c = colors[1];
    return score(p.color) + score(c);
}
"#
    );
    assert_eq!(run(&src), 110);
}

#[test]
fn equality_compares_cases() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
test(): int {
    var c = Color.Green;
    var total = 0;
    if (c == Color.Green) { total += 1; }
    if (c != Color.Red) { total += 10; }
    if (c == Color.Blue) { total += 100; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 11);
}

#[test]
fn break_and_continue_in_an_arm_act_on_the_loop() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
test(): int {
    var colors = Array<Color>();
    colors.append(Color.Green);
    colors.append(Color.Red);
    colors.append(Color.Blue);
    colors.append(Color.Green);
    var total = 0;
    for (var c in colors) {
        match (c) {
            Green => { continue; }
            Blue => { break; }
            Red => { total += 1; }
        }
        total += 10;
    }
    return total;
}
"#
    );
    assert_eq!(run(&src), 11);
}

#[test]
fn a_representation_sets_the_stored_size() {
    let src = r#"
enum Small: u8 {
    A,
    B = 200,
}
enum Wide: long {
    Big = 5000000000,
}
test(): int {
    var total = 0;
    if (sizeof<Small>() == 1) { total += 1; }
    if (sizeof<Wide>() == 8) { total += 10; }
    if ((Small.B as int) == 200) { total += 100; }
    if ((Wide.Big as long) == 5000000000) { total += 1000; }
    return total;
}
"#;
    assert_eq!(run(src), 1111);
}

#[test]
fn a_wide_enum_field_of_a_generic_struct_starts_at_its_default() {
    // The constructor's zero of `T _value` converts as the enum's long, not
    // as an int.
    let src = r#"
enum Wide: long {
    Big = 5000000000,
    Bigger = 6000000000,
}
struct Holder<T> {
    T _value;
    construct() { }
    get(): T { return this._value; }
}
test(): int {
    var h = Holder<Wide>();
    var total = 0;
    if (h.get() == Wide.Big) { total += 1; }
    if (Wide.from_value(6000000000).value() == Wide.Bigger) { total += 10; }
    return total;
}
"#;
    assert_eq!(run(src), 11);
}

#[test]
fn match_on_a_call_result_and_inside_a_closure() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
next(c: Color): Color {
    match (c) {
        Red => { return Color.Green; }
        Green => { return Color.Blue; }
        Blue => { return Color.Red; }
    }
    return c;
}
test(): int {
    var f = (c: Color): int => {
        match (next(c)) {
            Red => { return 1; }
            else => { return 2; }
        }
        return 0;
    };
    return f(Color.Blue) * 10 + f(Color.Red);
}
"#
    );
    assert_eq!(run(&src), 12);
}

#[test]
fn match_in_a_generic_function_and_a_method() {
    let src = format!(
        "{}{}",
        COLOR,
        r#"
pick<T>(c: Color, a: T, b: T): T {
    match (c) {
        Red => { return a; }
        else => { return b; }
    }
    return b;
}
struct Lamp {
    Color color;
    brightness(): int {
        match (color) {
            Red => { return 3; }
            Green, Blue => { return 4; }
        }
        return 0;
    }
}
test(): int {
    var l = Lamp();
    l.color = Color.Blue;
    return pick<int>(Color.Red, 5, 6) + pick<long>(Color.Blue, 50, 60) as int + l.brightness() * 100;
}
"#
    );
    assert_eq!(run(&src), 5 + 60 + 400);
}

#[test]
fn a_module_scope_constant_holds_a_case() {
    let src = format!("{}{}", COLOR, "const favorite = Color.Blue;\ntest(): int { return score(favorite); }");
    assert_eq!(run(&src), 100);
}

#[test]
fn a_type_alias_names_an_enum() {
    let src = format!(
        "{}{}",
        COLOR,
        "type Hue = Color;\ntest(): int { Hue h = Color.Green; match (h) { Hue.Green => { return 1; } else => { return 2; } } return 0; }"
    );
    assert_eq!(run(&src), 1);
}

#[test]
fn a_platform_selects_cases() {
    let src = r#"
enum Os {
    [Target(OS(Windows))]
    Windows,
    [Target(!OS(Windows))]
    Other,
}
test(): int {
    [Target(OS(Windows))] {
        match (Os.Windows) {
            Windows => { return 1; }
        }
    }
    [Target(!OS(Windows))] {
        match (Os.Other) {
            Other => { return 1; }
        }
    }
    return 0;
}
"#;
    assert_eq!(run(src), 1);
}

#[test]
fn an_enum_does_not_mix_with_integers() {
    assert!(error_of(&format!("{}{}", COLOR, "test(): int { int x = Color.Red; return x; }"))
        .contains("cannot initialize variable 'x' of type 'int' with a value of type 'Color'"));
    assert!(error_of(&format!("{}{}", COLOR, "test(): int { Color c = 0; return 0; }"))
        .contains("cannot initialize variable 'c' of type 'Color' with a value of type 'i32'"));
    assert!(error_of(&format!("{}{}", COLOR, "test(): int { return score(2); }"))
        .contains("cannot pass a value of type 'i32' as argument 1 of 'score', which has type 'Color'"));
    assert!(error_of(&format!("{}{}", COLOR, "test(): int { var c = Color.Red + 1; return 0; }"))
        .contains("invalid operands to binary expression ('Color' and 'i32')"));
    assert!(error_of(&format!("{}{}", COLOR, "test(): int { var c = 1 as Color; return 0; }"))
        .contains("cannot convert a value to enum 'Color' with 'as'"));
}

#[test]
fn two_enums_do_not_mix() {
    let src = format!("{}{}", COLOR, "enum Size { Small }\ntest(): int { if (Color.Red == Size.Small) { return 1; } return 0; }");
    assert!(error_of(&src).contains("cannot compare a value of type 'Color' with a value of type 'Size'"));
}

#[test]
fn match_needs_an_enum() {
    assert!(error_of("test(): int { var x = 3.5; match (x) { A => {} } return 0; }")
        .contains("cannot match on a value of 'f64': 'match' needs an enum, an integer, 'char', 'bool' or 'String'"));
    assert!(error_of("test(): int { var x = 3; match (x) { A => {} else => {} } return 0; }")
        .contains("'A' is not a literal: a 'match' on 'i32' takes literal patterns"));
}

#[test]
fn a_slot_without_a_value_holds_the_zero_case_or_else_the_first() {
    let src = r#"
enum Color { Red = 1, Green = 0 }
enum Bracket: u8 { Open = '(', Close = ')' }
struct Holder {
    Color color;
    Bracket bracket;
}
test(): int {
    var h = Holder();
    Bracket b;
    var total = 0;
    if (h.color == Color.Green) { total += 1; }
    if (h.bracket == Bracket.Open) { total += 10; }
    if (b == Bracket.Open) { total += 100; }
    if (__default<Bracket>() == Bracket.Open) { total += 1000; }
    return total;
}
"#;
    assert_eq!(run(src), 1111);
}

// ── Methods (phase 2) ──

const LIGHT: &str = r#"
enum Light: u8 {
    Red,
    Amber = 5,
    Green,

    ## Whether traffic may go.
    may_go(): bool {
        return this == Light.Green;
    }

    next(): Light {
        match (this) {
            Red => { return Light.Green; }
            Amber => { return Light.Red; }
            Green => { return Light.Amber; }
        }
        return this;
    }

    # A bare call of another method acts on `this`.
    after_two(): Light {
        return next().next();
    }

    wait(extra: int): int {
        if (may_go()) { return 0; }
        return 30 + extra;
    }

    static first(): Light {
        return Light.Red;
    }
}
"#;

#[test]
fn methods_take_the_value_as_this() {
    let src = format!(
        "{}{}",
        LIGHT,
        r#"
test(): int {
    var light = Light.first();
    var total = 0;
    if (!light.may_go()) { total += 1; }
    if (light.next().may_go()) { total += 10; }
    if (light.after_two() == Light.Amber) { total += 100; }
    total += Light.Amber.wait(2) * 1000;
    return total;
}
"#
    );
    assert_eq!(run(&src), 1 + 10 + 100 + 32 * 1000);
}

#[test]
fn name_spells_the_case() {
    let src = format!(
        "{}{}",
        LIGHT,
        r#"
test(): int {
    var total = 0;
    if (Light.Red.name() == "Red") { total += 1; }
    var l = Light.Green;
    if (l.name() == "Green") { total += 10; }
    if (l.next().name() == "Amber") { total += 100; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 111);
}

#[test]
fn from_value_finds_the_case_or_fails() {
    let src = format!(
        "{}{}",
        LIGHT,
        r#"
test(): int {
    var total = 0;
    var found = Light.from_value(6);
    if (found.is_ok() and found.value() == Light.Green) { total += 1; }
    var missing = Light.from_value(3);
    if (!missing.is_ok()) { total += 10; }
    if (missing.error().message == "no case of 'Light' has this value") { total += 100; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 111);
}

#[test]
fn enums_key_hash_maps_and_fill_atomics() {
    let src = format!(
        "import async;\n{}{}",
        COLOR,
        r#"
test(): int {
    var counts = HashMap<Color, int>();
    counts[Color.Red] = 1;
    counts[Color.Blue] = 3;
    var seen = HashSet<Color>();
    seen.insert(Color.Green);
    var a = async.Atomic<Color>(Color.Red);
    a.store(Color.Blue);
    var total = counts[Color.Blue];
    if (seen.contains(Color.Green) and !seen.contains(Color.Red)) { total += 10; }
    if (a.load() == Color.Blue) { total += 100; }
    if (a.compare_exchange(Color.Blue, Color.Green) and a.load() == Color.Green) { total += 1000; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 1113);
}

#[test]
fn a_method_is_called_through_a_type_parameter() {
    let src = format!(
        "{}{}",
        LIGHT,
        r#"
describe<T>(value: T): String {
    return value.name();
}
test(): int {
    if (describe<Light>(Light.Amber) == "Amber") { return 1; }
    return 0;
}
"#
    );
    assert_eq!(run(&src), 1);
}

#[test]
fn method_errors() {
    let with = |body: &str| error_of(&format!("{}test(): int {{ {} return 0; }}", LIGHT, body));
    assert!(with("Light.Red.nope();").contains("no member named 'nope' in 'Light'"));
    assert!(with("Light.nope();").contains("no member named 'nope' in 'Light'"));
    assert!(with("Light.may_go();").contains("'may_go' is not static: call it on a value of 'Light', such as 'Light.Red.may_go()'"));
    assert!(with("Light.Red.first();").contains("'first' is a static method of 'Light': call it as 'Light.first(...)'"));
    assert!(with("var n = Light.Red.may_go;").contains("'may_go' is a method of 'Light': call it as 'may_go()'"));
    let declared = |member: &str| error_of(&format!("enum E {{ A\n    {}\n}}\ntest(): int {{ return 0; }}", member));
    assert!(declared("name(): String { return \"\"; }").contains("'name' is built into every enum and cannot be redeclared"));
    assert!(error_of(&format!("{}extend Light {{ extra(): int {{ return 1; }} }}\ntest(): int {{ return 0; }}", LIGHT))
        .contains("cannot extend enum 'Light' without a trait: declare its methods inside the enum"));
    assert!(declared("pick<T>(x: T): T { return x; }").contains("methods of an enum cannot be generic yet ('pick')"));
}

// ── Cases that carry values (phase 3) ──

const SHAPE: &str = r#"
enum Shape {
    Circle(radius: int),
    Rect(width: int, height: int),
    Empty,
}

area(s: Shape): int {
    match (s) {
        Circle(r) => { return 3 * r * r; }
        Rect(w, h) => { return w * h; }
        Empty => { return 0; }
    }
    return -1;
}
"#;

#[test]
fn a_case_carries_its_values_to_the_arm() {
    let src = format!(
        "{}{}",
        SHAPE,
        r#"
test(): int {
    return area(Shape.Circle(2)) + area(Shape.Rect(3, 4)) * 100 + area(Shape.Empty);
}
"#
    );
    assert_eq!(run(&src), 1212);
}

const DOC: &str = r#"
enum Doc {
    Text(text: String),
    Concat(parts: Array<Doc>),
    Indent(parts: Array<Doc>),
    Line,

    width(): int {
        match (this) {
            Text(t) => { return t.length as int; }
            Concat(parts), Indent(parts) => {
                var total = 0;
                for (var p in parts) { total += p.width(); }
                return total;
            }
            Line => { return 1; }
        }
        return 0;
    }
}
"#;

#[test]
fn alternatives_bind_one_name_and_nothing_leaks() {
    let src = format!(
        "{}{}",
        DOC,
        r#"
build(): int {
    var inner = Array<Doc>();
    inner.append(Doc.Text("ab"));
    var parts = Array<Doc>();
    parts.append(Doc.Text("hello"));
    parts.append(Doc.Line);
    parts.append(Doc.Indent(inner));
    return Doc.Concat(parts).width();
}
test(): int {
    var before = _pep_live_allocs();
    var width = build();
    if (_pep_live_allocs() != before) { return -1; }
    return width;
}
"#
    );
    assert_eq!(run(&src), 8);
}

#[test]
fn a_generic_enum_can_hold_itself() {
    let src = r#"
enum Tree<T> {
    Leaf,
    Node(left: Tree<T>, value: T, right: Tree<T>),
}

sum(t: Tree<int>): int {
    match (t) {
        Leaf => { return 0; }
        Node(l, v, r) => { return sum(l) + v + sum(r); }
    }
    return 0;
}

root(t: Tree<int>): int {
    match (t) {
        Node(_, v, _) => { return v; }
        else => { return -1; }
    }
    return 0;
}

test(): int {
    var leaf = Tree<int>.Leaf;
    var t = Tree<int>.Node(Tree<int>.Node(leaf, 1, leaf), 2, Tree<int>.Node(leaf, 4, leaf));
    return sum(t) * 10 + root(t) + root(leaf) * 100;
}
"#;
    assert_eq!(run(src), -28);
}

#[test]
fn a_case_without_values_is_one_shared_object() {
    let src = format!(
        "{}{}",
        DOC,
        r#"
line(): Doc { return Doc.Line; }
test(): int {
    var before = _pep_live_allocs();
    var total = 0;
    var a = Doc.Line;
    if (a === line()) { total += 1; }
    var many = Array<Doc>();
    var i = 0;
    while (i < 10) { many.append(Doc.Line); i += 1; }
    if (many[9] === a) { total += 10; }
    var w = __weak_from<Doc>(a);
    if (__weak_upgrade<Doc>(w) === a) { total += 100; }
    many = Array<Doc>();
    # Only the arrays allocated; the cases did not.
    if (_pep_live_allocs() - before != 1) { return -1; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 111);
}

#[test]
fn reference_enums_have_methods_traits_and_names() {
    let src = r#"
trait Describe {
    describe(): String;
}

[Shared]
enum Message {
    Quit,
    Move(x: int, y: int),
}

extend Message with Describe {
    describe(): String {
        match (this) {
            Quit => { return "quit"; }
            Move(x, y) => { return "move"; }
        }
        return "";
    }
}

enum Maybe<T> {
    Nothing,
    Just(value: T),

    or_else(fallback: T): T {
        match (this) {
            Just(v) => { return v; }
            Nothing => { return fallback; }
        }
        return fallback;
    }
}

length_of(d: Describe): int {
    return d.describe().length as int;
}

test(): int {
    var total = length_of(Message.Move(1, 2)) + length_of(Message.Quit) * 10;
    total += Maybe<int>.Just(5).or_else(0) * 100 + Maybe<int>.Nothing.or_else(7) * 1000;
    if (Maybe<String>.Just("x").name() == "Just" && Message.Quit.name() == "Quit") { total += 10000; }
    return total;
}
"#;
    assert_eq!(run(src), 17544);
}

#[test]
fn reference_enum_errors() {
    let declared = |cases: &str| error_of(&format!("enum Doc {{\n{}\n}}\ntest(): int {{ return 0; }}\n", cases));
    assert!(declared("A = 1, B(v: int),").contains("case 'A' of 'Doc' cannot have a value: its cases carry values"));
    assert!(declared("A(v: int = 1),").contains("the values of case 'A' cannot have defaults"));
    assert!(declared("A(v: int, v: int),").contains("redefinition of 'v' in case 'A'"));
    assert!(declared("A(v: int),\nA(): int { return 1; }").contains("case 'A' has the same name as a method of 'Doc'"));
    let used = |body: &str| {
        error_of(&format!(
            "{}test(): int {{\n    var d = Doc.Line;\n    {}\n    return 0;\n}}\n",
            DOC, body
        ))
    };
    assert!(used("var t = Doc.Text;").contains("case 'Text' of 'Doc' takes 1 value: 'Doc.Text(text)'"));
    assert!(used("var t = Doc.Txt;").contains("no case named 'Txt' in 'Doc'"));
    assert!(used("var t = Doc(0);").contains("cannot construct enum 'Doc' directly: its values are made by its cases"));
    assert!(used("match (d) { Text(a, b) => {} else => {} }").contains("too many bindings for case 'Text': expected 1, have 2"));
    assert!(used("match (d) { Concat => {} Text() => {} else => {} }").contains("too few bindings for case 'Text': expected 1, have 0"));
    assert!(used("match (d) { Text(t), Concat(t) => {} else => {} }")
        .contains("'t' has type 'Array<Doc>' here but 'String' in 'Text'"));
    assert!(used("match (d) { Text(t), Line => {} else => {} }")
        .contains("'t' is not bound by 'Line': every pattern of an arm binds the same names"));
    assert!(used("match (d) { Text(t) => { t = \"x\"; } else => {} }").contains("cannot assign to const variable 't'"));
    assert!(used("match (d) { Text(t) => {} Line => {} }").contains("match on 'Doc' does not handle 'Concat' and 'Indent'"));
}

fn run_binary(name: &str, files: &[(&str, &str)]) -> (bool, String) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
    std::env::set_current_dir(root).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_enum_{name}_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    for (file, source) in files {
        std::fs::write(dir.join(file), source).unwrap();
    }
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        dir.join(files[0].0).to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    pepper_driver::run(options).expect("compile + link");
    let output = Command::new(&out_path).output().expect("spawn linked binary");
    (output.status.success(), String::from_utf8_lossy(&output.stdout).into_owned())
}

#[test]
fn a_case_without_values_is_one_object_across_files() {
    let lib = "export enum Token {\n    Word(text: String),\n    End,\n}\nexport end(): Token { return Token.End; }\n";
    let main = "import \"lib\";\nmain(): int {\n    if (end() === Token.End) { return 0; }\n    return 1;\n}\n";
    let (ok, stdout) = run_binary("static_case_units", &[("main.pep", main), ("lib.pep", lib)]);
    assert!(ok, "stdout: {stdout}");
}

#[test]
fn matching_a_null_reference_enum_panics() {
    let main = "enum Token {\n    Word(text: String),\n    End,\n}\nmain(): int {\n    Token t;\n    match (t) {\n        Word(w) => {}\n        End => {}\n    }\n    return 0;\n}\n";
    let (ok, stdout) = run_binary("null_match", &[("main.pep", main)]);
    assert!(!ok, "expected a panic");
    assert!(stdout.contains("match on a null 'Token'"), "stdout: {stdout}");
}

#[test]
fn a_case_can_be_selected_by_platform() {
    let src = r#"
enum Handle {
    Path(text: String),
    [Target(OS(Windows))]
    Win(code: int),
    [Target(!OS(Windows))]
    Posix(fd: int),
}
test(): int {
    match (Handle.Path("x")) {
        Path(t) => { return t.length as int; }
        else => { return 2; }
    }
    return 0;
}
"#;
    assert_eq!(run(src), 1);
}

// ── `match` expressions, `is`, and literal patterns (phase 4) ──

#[test]
fn a_match_expression_produces_the_arms_value() {
    let src = format!(
        "{}{}",
        SHAPE,
        r#"
enum Color { Red, Green, Blue }

score(c: Color): int {
    var s = match (c) {
        Red => 1,
        Green, Blue => 10,
    };
    return s;
}

sides(s: Shape): int {
    return match (s) {
        Circle(_) => 0,
        Rect(w, h) => w == h ? 1 : 4,
        else => -100,
    };
}

test(): int {
    return score(Color.Red) + score(Color.Blue) * 10 + sides(Shape.Rect(2, 3)) * 1000 + sides(Shape.Empty);
}
"#
    );
    assert_eq!(run(&src), 101 + 4000 - 100);
}

#[test]
fn a_match_expression_owns_its_value_and_nothing_leaks() {
    let src = format!(
        "{}{}",
        DOC,
        r#"
text_of(d: Doc): String {
    return match (d) {
        Text(t) => t,
        else => String("none"),
    };
}
make(s: String): Doc { return Doc.Text(s); }
test(): int {
    var before = _pep_live_allocs();
    var total = 0;
    var i = 0;
    while (i < 3) {
        var a = text_of(Doc.Line);
        var b = text_of(make("abc"));
        var c = match (make("xy")) { Text(t) => t, else => String("") };
        total += (a.length as int) + (b.length as int) * 10 + (c.length as int) * 100;
        i += 1;
    }
    if (_pep_live_allocs() != before) { return -1; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 3 * (4 + 30 + 200));
}

#[test]
fn match_and_ternary_arms_of_different_integer_types_convert_where_they_flow() {
    // `0` is an `int` and `length()` a `long`: the value has the arms'
    // common type (`long`), converted to each slot it flows into.
    let src = r#"
enum Message {
    Empty,
    Text(text: String),
}

describe(m: Message): int {
    return match (m) {
        Empty => 0,
        Text(text) => text.length,
    };
}

long_first(m: Message): int {
    return match (m) {
        Text(text) => text.length,
        Empty => 0,
    };
}

take(x: int): int { return x; }

take_long(x: long): long { return x; }

pick(c: bool, s: String): int {
    return c ? 0 : s.length;
}

test(): int {
    var m = Message.Text("four");
    var init: int = match (m) {
        Empty => 0,
        Text(text) => text.length,
    };
    var inferred = match (m) {
        Empty => 0,
        Text(text) => text.length,
    };
    var argument = take(match (m) {
        Empty => 0,
        Text(text) => text.length,
    });
    var wide = take_long(match (m) {
        Empty => 0,
        Text(text) => text.length,
    });
    var assigned = 0;
    assigned = match (m) {
        Empty => 0,
        Text(text) => text.length,
    };
    var ternary: int = init == 4 ? 1 : "ab".length;
    var unsigned_arm = init == 4 ? 200 as byte : -1;
    var signed_arm: long = init == 4 ? -1 as char : 7 as long;
    if (describe(m) != 4 || describe(Message.Empty) != 0 || long_first(m) != 4) { return 1; }
    if (init != 4 || inferred != 4 as long || argument != 4 || wide != 4 as long) { return 2; }
    if (assigned != 4 || ternary != 1 || pick(false, "four") != 4 || pick(true, "four") != 0) { return 3; }
    if (unsigned_arm != 200 || signed_arm != -1 as long) { return 4; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn a_match_expression_must_handle_every_case() {
    let err = error_of(&format!("{}{}", SHAPE, "test(): int { return match (Shape.Empty) { Empty => 0 }; }"));
    assert!(err.contains("match on 'Shape' does not handle 'Circle' and 'Rect'"), "{err}");
    let err = error_of(&format!(
        "{}{}",
        SHAPE,
        "test(): int { return match (Shape.Empty) { Circle(r) => ((x: int): int => r + x)(1), else => 0 }; }"
    ));
    assert!(err.contains("a closure cannot use 'r', bound by an arm of a 'match' expression"), "{err}");
    let err = error_of("enum Color { Red, Green }\ntest(): int { var x = match (Color.Red) { Red => 1, Green => \"x\" }; return 0; }");
    assert!(err.contains("'match' arm has a value of type 'String', but the first arm's is 'i32'"), "{err}");
}

#[test]
fn literal_patterns_match_integers_characters_booleans_and_strings() {
    let src = r#"
keyword(word: String): int {
    match (word) {
        "import" => { return 1; }
        "export", "extern" => { return 2; }
        else => { return 0; }
    }
    return -1;
}

digit(c: byte): int {
    return match (c) {
        '0' => 0,
        '1' => 1,
        else => -1,
    };
}

sign(n: int): int {
    return match (n) {
        0 => 0,
        -1, -2 => 1,
        else => 2,
    };
}

test(): int {
    var total = keyword("import") + keyword("extern") * 10 + keyword("x") * 100;
    total += (digit('1') + digit('x') * 10 + 10) * 1000;
    total += sign(-2) * 100000 + sign(7) * 1000000;
    var flag = false;
    total += match (flag) { true => 0, false => 10000000 };
    return total;
}
"#;
    assert_eq!(run(src), 21 + 1000 + 100000 + 2000000 + 10000000);
}

#[test]
fn literal_pattern_errors() {
    let err = error_of("test(): int { return match (3) { 1 => 1 }; }");
    assert!(err.contains("match on 'i32' needs an 'else' arm"), "{err}");
    let err = error_of("test(): int { return match (3) { 1, 2 => 1, 1 => 2, else => 0 }; }");
    assert!(err.contains("value '1' is already handled"), "{err}");
    let err = error_of("enum Color { Red }\ntest(): int { return match (Color.Red) { 1 => 1, else => 0 }; }");
    assert!(err.contains("cannot compare a value of type 'Color' with a value of type 'i32'"), "{err}");
}

#[test]
fn is_tests_a_case_and_binds_in_its_block() {
    let src = format!(
        "{}{}",
        SHAPE,
        r#"
enum List {
    Empty,
    Cons(head: int, tail: List),
}

test(): int {
    var total = 0;
    var s = Shape.Rect(2, 5);
    if (s is Rect(w, h)) {
        total += w * h;
    } else {
        total -= 1000;
    }
    if (s is Circle(r)) { total += r; } else if (s is Rect(_, h)) { total += h * 100; }
    var list = List.Cons(1, List.Cons(2, List.Cons(3, List.Empty)));
    var sum = 0;
    while (list is Cons(head, tail)) {
        sum += head;
        list = tail;
    }
    total += sum * 1000;
    var empty = s is Empty;
    if (!empty && !(s is Circle)) { total += 10000; }
    return total;
}
"#
    );
    assert_eq!(run(&src), 10 + 500 + 6000 + 10000);
}

#[test]
fn a_chain_of_overloaded_indexers_lowers_every_index() {
    // #408: `root["a"]["b"][3]` left its last index unlowered when the
    // indexers were overloaded, and LLVM rejected the call on it.
    let src = r#"
enum Tree {
    Leaf(value: int),
    Branch(children: Array<Tree>),

    [](index: ulong): Tree {
        if (this is Branch(children)) {
            return children[index];
        }
        return Tree.Leaf(-1);
    }

    [](name: String): Tree {
        return Tree.Leaf(-2);
    }

    number(): int {
        if (this is Leaf(value)) {
            return value;
        }
        return -9;
    }
}

test(): int {
    var inner = Array<Tree>();
    inner.append(Tree.Leaf(7));
    var outer = Array<Tree>();
    outer.append(Tree.Branch(inner));
    var root = Tree.Branch(outer);
    if (root["a"]["b"][3].number() != -1) { return 1; }
    if (root[0]["x"][0].number() != -1) { return 2; }
    return root[0][0].number();
}
"#;
    assert_eq!(run(src), 7);
}

#[test]
fn a_case_may_be_named_string() {
    // #409: the case `String` must not take over the `String(...)` calls the
    // compiler makes from string literals, in the enum's own methods (the
    // built-in `name()` included) and closures.
    let src = r#"
enum Json {
    Null,
    Number(value: int),
    String(value: String),
    Array(items: Array<Json>),

    describe(): String {
        match (this) {
            Null => { return "null"; }
            Number(n) => { return $"number {n}"; }
            String(s) => { return "<" + s + ">"; }
            Array(items) => {
                var count = (x: ulong): String => $"count {x}";
                return count(items.count);
            }
        }
        return "";
    }

    static text(s: String): Json {
        return String(s);
    }
}

test(): int {
    var items = Array<Json>();
    items.append(Json.Null);
    var parts = Array<String>();
    parts.append(Json.String("x").describe());
    parts.append(Json.text("y").describe());
    parts.append(Json.Number(4).describe());
    parts.append(Json.Array(items).describe());
    parts.append(Json.String("z").name());
    var all = parts[0] + parts[1] + parts[2] + parts[3] + parts[4];
    return all == "<x><y>number 4count 1String" ? 1 : 0;
}
"#;
    assert_eq!(run(src), 1);
}

#[test]
fn is_bindings_are_scoped_to_the_block() {
    let err = error_of(&format!("{}{}", SHAPE, "test(): int { var ok = Shape.Empty is Circle(r); return 0; }"));
    assert!(err.contains("cannot bind 'r' here: 'is' binds names only as the whole condition of an 'if' or 'while'"), "{err}");
}

#[test]
fn is_stays_usable_as_a_name() {
    let src = r#"
struct Token {
    var text: String;
    construct(text: String) { this.text = text; }
    is(other: String): bool { return text == other; }
}
test(): int {
    var t = Token("x");
    var is = 2;
    if (t.is("x")) { return is; }
    return 0;
}
"#;
    assert_eq!(run(src), 2);
}

#[test]
fn a_ternary_of_a_call_and_a_variable_copies_the_variable() {
    let src = r#"
struct Box {
    var v: int;
    construct(v: int) { this.v = v; }
}
make(v: int): Box { return Box(v); }
test(): int {
    var before = _pep_live_allocs();
    var y = Box(1);
    var total = 0;
    var i = 0;
    while (i < 2) {
        var s = i == 0 ? make(10) : y;
        total += s.v;
        i += 1;
    }
    total += y.v * 100;
    y = Box(0);
    if (_pep_live_allocs() - before != 1) { return -1; }
    return total;
}
"#;
    assert_eq!(run(src), 111);
}

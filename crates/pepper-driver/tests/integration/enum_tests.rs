//! Enums whose cases carry no values, and `match` over them
//! (docs/src/language/enums.md).

use pepper_codegen::CodeGenerator;

fn run(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

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
fn missing_cases_are_an_error() {
    let src = format!("{}{}", COLOR, "test(): int { match (Color.Red) { Red => {} } return 0; }");
    assert!(error_of(&src).contains("error: match on 'Color' does not handle 'Green' and 'Blue'"));
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
    assert!(error_of("test(): int { var x = 3; match (x) { A => {} } return 0; }")
        .contains("cannot match on a value of 'i32': 'match' needs an enum"));
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
        "{}{}",
        COLOR,
        r#"
test(): int {
    var counts = HashMap<Color, int>();
    counts[Color.Red] = 1;
    counts[Color.Blue] = 3;
    var seen = HashSet<Color>();
    seen.insert(Color.Green);
    var a = Atomic<Color>(Color.Red);
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
    let declared = |member: &str| error_of(&format!("enum E {{ A\n    {}\n}}\ntest(): int {{ return 0; }}", member));
    assert!(declared("name(): String { return \"\"; }").contains("'name' is built into every enum and cannot be redeclared"));
    assert!(error_of(&format!("{}extend Light {{ extra(): int {{ return 1; }} }}\ntest(): int {{ return 0; }}", LIGHT))
        .contains("cannot extend enum 'Light': declare its methods inside the enum"));
    assert!(declared("pick<T>(x: T): T { return x; }").contains("methods of an enum cannot be generic yet ('pick')"));
}

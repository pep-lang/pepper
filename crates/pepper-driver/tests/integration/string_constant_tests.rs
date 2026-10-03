//! `StringConstant` (#493): a string literal's own type, a `[Value]`
//! pointer to its NUL-terminated constant bytes. A literal flowing into a
//! `StringConstant` slot is that value and allocates nothing; a literal
//! where a `String` is expected is a `String` as before; a
//! `StringConstant` converts to a `String` through `String`'s `[Implicit]`
//! constructor; and it has `String`'s read API. A `const` with no
//! written type initialized from a literal is one (#516), and it compares
//! with a `String` either way round (#516).

use crate::support::{jit_cases, sema};
use pepper_sema::model::{Expression, Module};

/// How many `StringConstant(raw, size, length)` calls function `name` makes.
fn constants_in(module: &Module, name: &str) -> usize {
    let function = module.functions.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("no function '{name}'"));
    let mut count = 0;
    pepper_sema::passes::visit_function(function, &mut |e| {
        if matches!(e, Expression::FunctionCall { function, args, .. }
            if function == "StringConstant" && matches!(args.first(), Some(Expression::StringLiteral { is_raw: true, .. })))
        {
            count += 1;
        }
    });
    count
}

const PROGRAM: &str = r##"
import io;

extern ulong strlen(char* text);

const GREETING: StringConstant = "hello";

# No written type: a `const` initialized from a literal is a StringConstant.
const INFERRED = "inferred";

struct Label {
    StringConstant text;
}

which(text: StringConstant): int {
    return 1;
}

which(text: String): int {
    return 2;
}

constant_size(text: StringConstant): ulong {
    return text.size;
}

returns_constant(flag: bool): StringConstant {
    if (flag) {
        return "yes";
    }
    return flag ? "never" : "no";
}

takes_string(text: String): String {
    return text;
}

literals_are_constants(): int {
    StringConstant a = "abc";
    var label = Label();
    label.text = "field";
    if (a.size != 3 || a.length != 3 || label.text.size != 5) {
        return 1;
    }
    if (constant_size("héllo") != 6 || returns_constant(false) != "no") {
        return 2;
    }
    if (strlen(GREETING.c_str()) != 5 || strlen(a.c_str()) != 3 || strlen(GREETING) != 5) {
        return 3;
    }
    assert(a.size == 3, a);
    var empty = StringConstant();
    if (strlen(empty.c_str()) != 0 || !empty.is_empty) {
        return 4;
    }
    return 0;
}

literals_are_strings(): int {
    var s = "a";
    s.append("b");
    if (s != "ab" || takes_string("x") != "x") {
        return 1;
    }
    # Compare components: the separator is `\` on Windows.
    var parts = io.Path("docs").join("guide.md").components();
    if (parts.count != 2 || parts[0] != "docs" || parts[1] != "guide.md") {
        return 2;
    }
    var names = Array<String>();
    names.append("first");
    names.append(GREETING);
    if (names[1] != "hello") {
        return 3;
    }
    return 0;
}

overloads_prefer_constants(): int {
    var s = "text";
    StringConstant c = "text";
    if (which("literal") != 1 || which(s) != 2 || which(c) != 1) {
        return 1;
    }
    return 0;
}

converts_to_string(): int {
    String copy = GREETING;
    copy.append("!");
    if (copy != "hello!" || GREETING != "hello") {
        return 1;
    }
    if (takes_string(GREETING) != "hello" || GREETING.to_string() != "hello" || String(GREETING) != "hello") {
        return 2;
    }
    if ($"{GREETING}, world" != "hello, world") {
        return 3;
    }
    return 0;
}

read_api(): int {
    StringConstant text = "  a,b,c  ";
    if (text.find(",") != 3 || text.rfind(",") != 5 || !text.contains("b")) {
        return 1;
    }
    if (text.trim() != "a,b,c" || text.trim_start() != "a,b,c  " || text.trim_end() != "  a,b,c") {
        return 2;
    }
    var parts = text.trim().split(",");
    if (parts.count != 3 || parts[2] != "c") {
        return 3;
    }
    StringConstant word = "héllo";
    if (word[1] != "é" || word.substr(1, 2) != "él" || word.substr_bytes(0, 1) != "h") {
        return 4;
    }
    if (!word.starts_with("hé") || !word.ends_with("lo") || word.byte_at(0) != 'h') {
        return 5;
    }
    if (word.upper() != "HéLLO" || word + "!" != "héllo!" || word.repeat(2) != "héllohéllo") {
        return 6;
    }
    StringConstant other = "héllo";
    if (word != other || word.compare("z") >= 0 || !(word < "z")) {
        return 7;
    }
    var n = 0;
    for (var c in word) {
        n = n + 1;
    }
    if (n != 5 || word.bytes().count != 6) {
        return 8;
    }
    StringConstant lines = "one\ntwo";
    StringConstant comma = ", ";
    if (lines.lines().count != 2 || comma.join(lines.lines()) != "one, two") {
        return 9;
    }
    if (word.replace("l", "L") != "héLLo" || word.split_once("l").is_empty()) {
        return 10;
    }
    return 0;
}

builders(): int {
    StringConstant csv = ",a,,é,";
    var parts = csv.split(",");
    if (parts.count != 5 || parts[0] != "" || parts[2] != "" || parts[3] != "é" || parts[3].length != 1 || parts[4] != "") {
        return 1;
    }
    var pair = csv.split_once("é");
    if (pair.is_empty()) {
        return 2;
    }
    match (pair) {
        Value(halves) => {
            if (halves.0 != ",a,," || halves.1 != ",") {
                return 3;
            }
        }
        Empty => {
            return 3;
        }
    }
    StringConstant text = "aéa";
    var replaced = text.replace("a", "bb");
    if (replaced != "bbébb" || replaced.length != 5 || text.replace("x", "y") != "aéa") {
        return 4;
    }
    StringConstant crlf = "one\r\ntwo\n\nthree";
    var lines = crlf.lines();
    if (lines.count != 4 || lines[0] != "one" || lines[2] != "" || lines[3] != "three") {
        return 5;
    }
    StringConstant mixed = "AbÉ";
    if (mixed.lower() != "abÉ" || mixed.upper() != "ABÉ" || mixed.lower().length != 3) {
        return 6;
    }
    StringConstant dash = "-é-";
    var joined = dash.join(lines);
    if (joined != "one-é-two-é--é-three" || joined.length != 20) {
        return 7;
    }
    var empty = StringConstant();
    if (empty.repeat(3) != "" || empty.lower() != "" || empty.lines().count != 0 || empty.split(",").count != 1) {
        return 8;
    }
    if (dash.repeat(2).length != 6 || dash.repeat(0) != "") {
        return 9;
    }
    return 0;
}

inferred_constants(): int {
    const LOCAL = "local";
    # Each assignment compiles only if the constant is a StringConstant.
    StringConstant global = INFERRED;
    StringConstant local = LOCAL;
    if (which(INFERRED) != 1 || which(LOCAL) != 1 || global.size != 8 || local.size != 5) {
        return 1;
    }
    if (takes_string(INFERRED) != "inferred" || strlen(INFERRED) != 8) {
        return 2;
    }
    return 0;
}

mixed_comparisons(): int {
    String same = "hello";
    String before = "a";
    String after = "z";
    if (!(GREETING == same) || GREETING != same || !(same == GREETING) || same != GREETING) {
        return 1;
    }
    if (GREETING == after || !(GREETING != after)) {
        return 2;
    }
    if (!(GREETING < after) || !(GREETING <= after) || GREETING > after || GREETING >= after) {
        return 3;
    }
    if (GREETING < before || GREETING <= before || !(GREETING > before) || !(GREETING >= before)) {
        return 4;
    }
    if (GREETING < same || !(GREETING <= same) || GREETING > same || !(GREETING >= same)) {
        return 5;
    }
    return 0;
}

hash_keys(): int {
    var counts = HashMap<StringConstant, int>();
    counts["a"] = 1;
    counts["b"] = 2;
    StringConstant key = "a";
    if (counts[key] != 1 || counts.count != 2) {
        return 1;
    }
    if (hash<StringConstant>("abc") != hash<String>("abc")) {
        return 2;
    }
    var keywords = HashSet<StringConstant>();
    keywords.insert("if");
    keywords.insert("else");
    if (!keywords.contains("if") || keywords.contains("while")) {
        return 3;
    }
    var words = Array<StringConstant>();
    words.append("b");
    words.append("a");
    if (words.find("a").is_empty()) {
        return 4;
    }
    return 0;
}
"##;

#[test]
fn string_constants_run() {
    jit_cases(
        PROGRAM,
        &["literals_are_constants", "literals_are_strings", "overloads_prefer_constants", "converts_to_string", "read_api", "builders", "inferred_constants", "mixed_comparisons", "hash_keys"],
    );
}

#[test]
fn a_literal_in_a_constant_slot_is_its_constant_bytes() {
    let module = sema(PROGRAM).expect("compile");
    // `StringConstant a = "abc"`, the field, the argument, and the right
    // side of `!=`.
    assert_eq!(constants_in(&module, "literals_are_constants"), 4);
    // Both returns and both arms of the ternary.
    assert_eq!(constants_in(&module, "returns_constant"), 3);
    // Only the five right sides of `!=` (a `String`'s operators take a
    // `StringConstant` too); the stored and passed literals stay `String`s.
    assert_eq!(constants_in(&module, "literals_are_strings"), 5);
}

#[test]
fn mixed_comparisons_copy_nothing() {
    let module = sema(PROGRAM).expect("compile");
    // `GREETING` on the left calls a `String` overload; it never becomes a
    // `String` through `to_string()`.
    let function = module.functions.iter().find(|f| f.name == "mixed_comparisons").expect("mixed_comparisons");
    let mut copies = 0;
    pepper_sema::passes::visit_function(function, &mut |e| {
        if matches!(e, Expression::MethodCall { method, .. } if method == "to_string") {
            copies += 1;
        }
    });
    assert_eq!(copies, 0);
    // `const INFERRED = "inferred"` holds the literal's constant bytes.
    let global = module.globals.iter().find(|g| g.name == "INFERRED").expect("INFERRED");
    assert_eq!(global.ty.to_string(), "StringConstant");
}

//! The `json` module: parsing every kind of value, numbers at the edges of
//! the integer range, strings and their escapes, strict RFC 8259 errors with
//! their line and column, JSONC, compact and indented output, editing a
//! value, and nesting deep enough that recursion would overflow. Each test
//! returns 0 on success or a distinct negative code per check, and must
//! leave no allocation behind.

use crate::support::jit_census;

fn run(source: &str) -> i32 {
    let (result, leaked) = jit_census(source);
    assert_eq!(leaked, 0, "allocations leaked or double-released");
    result
}

#[test]
fn parses_every_kind_of_value() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    var parsed = json.parse(" {\"name\": \"pepper\", \"on\": true, \"off\": false, \"none\": null, \"list\": [1, 2.5, \"x\"], \"nested\": {\"port\": 8080}} ");
    if (parsed.is_err()) { return -1; }
    var root = parsed.value();
    if (root["name"].as_string().value() != "pepper") { return -2; }
    if (!root["on"].as_bool().value()) { return -3; }
    if (root["off"].as_bool().value()) { return -4; }
    if (!root["none"].is_null() or !root.contains("none")) { return -5; }
    if (root["list"][0].as_int().value() != 1) { return -6; }
    if (root["list"][1].as_double().value() != 2.5) { return -7; }
    if (root["list"][2].as_string().value() != "x") { return -8; }
    if (root["nested"]["port"].as_int().value_or(80) != 8080) { return -9; }
    # Lookups that find nothing give Null and chain.
    if (!root["missing"]["deeper"][3].is_null() or root.contains("missing")) { return -10; }
    if (!root["list"][3].is_null() or !root["name"]["x"].is_null()) { return -11; }
    # The as_ methods give none for another kind.
    if (root["name"].as_int().is_some() or root["list"].as_object().is_some()) { return -12; }
    if (root["list"].as_array().value().count != 3) { return -13; }
    if (root.as_object().value().count != 6) { return -14; }
    # Keys keep the order the text wrote them in.
    var keys = "";
    for (var (key, _) in root.as_object().value()) {
        keys = keys + key + ",";
    }
    if (keys != "name,on,off,none,list,nested,") { return -15; }
    match (root["list"][1]) {
        Number(value) => { if (value != 2.5) { return -16; } }
        else => { return -17; }
    }
    # A repeated key keeps its first place and its last value.
    var repeated = json.parse("{\"a\": 1, \"b\": 2, \"a\": 3}").value();
    if (repeated.to_string() != "{\"a\":3,\"b\":2}") { return -18; }
    # A byte-order mark is skipped; whitespace is space, tab, CR and LF.
    if (json.parse("\u{FEFF}\t\r\n 7 \n").value().as_int().value() != 7) { return -19; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn keeps_integers_within_53_bits() {
    assert_eq!(
        run(r##"
import json;

kind(text: String): String {
    return json.parse(text).value().name();
}

test(): int {
    if (kind("9007199254740991") != "Integer") { return -1; }
    if (kind("-9007199254740991") != "Integer") { return -2; }
    if (kind("9007199254740992") != "Number") { return -3; }
    if (kind("-9007199254740992") != "Number") { return -4; }
    if (kind("123456789012345678901234567890") != "Number") { return -5; }
    if (kind("0") != "Integer" or kind("-0") != "Integer") { return -6; }
    if (kind("1.0") != "Number" or kind("1e2") != "Number" or kind("1E-2") != "Number") { return -7; }
    if (json.parse("1e2").value().as_int().value() != 100) { return -8; }
    if (json.parse("2.5").value().as_int().is_some()) { return -9; }
    if (json.parse("1e300").value().as_int().is_some()) { return -10; }
    if (json.parse("-12").value().as_double().value() != -12.0) { return -11; }
    if (json.parse("0.125e1").value().as_double().value() != 1.25) { return -12; }
    if (json.parse("[9007199254740993]").value().to_string() != "[9007199254740992.0]") { return -13; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn decodes_string_escapes() {
    assert_eq!(
        run(r##"
import json;

text_of(source: String): String {
    return json.parse(source).value().as_string().value();
}

test(): int {
    if (text_of("\"plain\"") != "plain") { return -1; }
    if (text_of("\"\"") != "") { return -2; }
    if (text_of("\"a\\\"b\\\\c\\/d\"") != "a\"b\\c/d") { return -3; }
    if (text_of("\"\\b\\f\\n\\r\\t\"") != "\u{8}\u{C}\n\r\t") { return -4; }
    if (text_of("\"\\u00e9\\u20AC\"") != "é€") { return -5; }
    if (text_of("\"\\ud834\\udd1e\"") != "𝄞") { return -6; }
    if (text_of("\"héllo 𝄞\"") != "héllo 𝄞") { return -7; }
    if (text_of("\"x\\u0000y\"").size != 3) { return -8; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn reports_errors_with_line_and_column() {
    assert_eq!(
        run(r##"
import json;

error_of(source: String): String {
    var parsed = json.parse(source, path = "t.json");
    if (parsed.is_ok()) {
        return "ok";
    }
    return parsed.error().to_string();
}

test(): int {
    if (error_of("") != "t.json:1:1: error: expected a value") { return -1; }
    if (error_of("[1 2]") != "t.json:1:4: error: expected ',' or ']'") { return -2; }
    if (error_of("{\"a\": 1 \"b\"}") != "t.json:1:9: error: expected ',' or '}'") { return -3; }
    if (error_of("{\"a\" 1}") != "t.json:1:6: error: expected ':'") { return -4; }
    if (error_of("{1: 2}") != "t.json:1:2: error: expected a member name in double quotes") { return -5; }
    if (error_of("[1,]") != "t.json:1:3: error: trailing comma is not allowed; parse with 'comments = true' to accept JSONC") { return -6; }
    if (error_of("[,1]") != "t.json:1:2: error: expected a value") { return -7; }
    if (error_of("[\n  1,\n  tru\n]") != "t.json:3:3: error: expected a value") { return -8; }
    if (error_of("01") != "t.json:1:2: error: a number cannot start with '0'") { return -9; }
    if (error_of("-") != "t.json:1:2: error: expected a digit") { return -10; }
    if (error_of("1.") != "t.json:1:3: error: expected a digit") { return -11; }
    if (error_of("1e+") != "t.json:1:4: error: expected a digit") { return -12; }
    if (error_of("+1") != "t.json:1:1: error: expected a value") { return -13; }
    if (error_of("1e400") != "t.json:1:1: error: number is too large for a double") { return -14; }
    if (error_of("\"abc") != "t.json:1:1: error: unterminated string") { return -15; }
    if (error_of("\"a\tb\"") != "t.json:1:3: error: control character in a string; write it as an escape such as '\\n'") { return -16; }
    if (error_of("\"\\q\"") != "t.json:1:2: error: invalid escape '\\q'") { return -17; }
    if (error_of("\"\\u12\"") != "t.json:1:2: error: '\\u' needs four hexadecimal digits") { return -18; }
    if (error_of("\"\\uD800\"") != "t.json:1:2: error: unpaired surrogate '\\uD800'") { return -19; }
    if (error_of("\"\\uDC00\"") != "t.json:1:2: error: unpaired surrogate '\\uDC00'") { return -20; }
    if (error_of("\"\\uD800\\u0041\"") != "t.json:1:2: error: unpaired surrogate '\\uD800'") { return -21; }
    if (error_of("1 2") != "t.json:1:3: error: expected the end of the text after the value") { return -22; }
    if (error_of("// note\n1") != "t.json:1:1: error: comments are not allowed; parse with 'comments = true' to accept JSONC") { return -23; }
    if (error_of("nul") != "t.json:1:1: error: expected a value") { return -24; }
    if (error_of("nullx") != "t.json:1:1: error: expected a value") { return -25; }
    if (error_of("NaN") != "t.json:1:1: error: expected a value") { return -26; }
    if (error_of("'a'") != "t.json:1:1: error: expected a value") { return -27; }
    # Without a path the error starts at the line.
    if (json.parse("[").error().to_string() != "1:2: error: expected a value") { return -28; }
    var error = json.parse("\n\n  [}").error();
    if (error.line != 3 or error.column != 4 or error.offset != 5) { return -29; }
    if (error.message != "expected a value before '}'") { return -30; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn rejects_invalid_utf8_at_the_byte() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    var bytes = "[\"ab".bytes();
    bytes.append(255);
    bytes.append(34);
    bytes.append(93);
    var text = String(unsafe_cast<__ptr<char>>(bytes._data), bytes.count);
    var error = json.parse(text).error();
    if (error.to_string() != "1:5: error: invalid UTF-8") { return -1; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn accepts_jsonc_on_request() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    var text = "// settings\n{\n  \"a\": [1, 2,], /* inline */\n  \"b\": {\"c\": true,},\n}\n// end";
    if (json.parse(text).is_ok()) { return -1; }
    var parsed = json.parse(text, comments = true);
    if (parsed.is_err()) { return -2; }
    if (parsed.value().to_string() != "{\"a\":[1,2],\"b\":{\"c\":true}}") { return -3; }
    var open = json.parse("[1 /* never closed", comments = true, path = "s.json");
    if (open.error().to_string() != "s.json:1:4: error: unterminated '/*' comment") { return -4; }
    # A comma alone is still an error.
    if (json.parse("[,]", comments = true).is_ok()) { return -5; }
    if (json.parse("{,}", comments = true).is_ok()) { return -6; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn writes_compact_and_indented_text() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    var reply = json.JsonValue.object();
    reply["id"] = json.JsonValue.Integer(42);
    reply["tags"] = json.JsonValue.array([json.JsonValue.String("a"), json.JsonValue.String("b")]);
    reply["empty"] = json.JsonValue.array();
    reply["none"] = json.JsonValue.object();
    reply["ratio"] = json.JsonValue.Number(0.5);
    reply["ok"] = json.JsonValue.Bool(false);
    reply["nothing"] = json.JsonValue.Null;
    var compact = "{\"id\":42,\"tags\":[\"a\",\"b\"],\"empty\":[],\"none\":{},\"ratio\":0.5,\"ok\":false,\"nothing\":null}";
    if (reply.to_string() != compact) { return -1; }
    if ($"{reply}" != compact) { return -2; }
    var pretty = "{\n  \"id\": 42,\n  \"tags\": [\n    \"a\",\n    \"b\"\n  ],\n  \"empty\": [],\n  \"none\": {},\n  \"ratio\": 0.5,\n  \"ok\": false,\n  \"nothing\": null\n}";
    if (reply.to_pretty_string() != pretty) { return -3; }
    var list = json.JsonValue.array([json.JsonValue.array([json.JsonValue.Integer(1)])]);
    if (list.to_pretty_string(indent = 4) != "[\n    [\n        1\n    ]\n]") { return -4; }
    if (list.to_pretty_string(0) != "[\n[\n1\n]\n]") { return -5; }
    # Strings escape quotes, backslashes and control characters.
    var text = json.JsonValue.String("q\"b\\n\n\t\u{1}é😀");
    if (text.to_string() != "\"q\\\"b\\\\n\\n\\t\\u0001é😀\"") { return -6; }
    if (text.to_string(ascii_only = true) != "\"q\\\"b\\\\n\\n\\t\\u0001\\u00e9\\ud83d\\ude00\"") { return -7; }
    # NaN and the infinities are not JSON.
    var zero = 0.0;
    var odd = json.JsonValue.array([json.JsonValue.Number(zero / zero), json.JsonValue.Number(1.0 / zero)]);
    if (odd.to_string() != "[null,null]") { return -8; }
    # Text round-trips, keys in their order.
    var source = "{\"z\":1,\"a\":[true,{\"m\":\"\\u00e9\"}],\"k\":-2.5e-7}";
    var again = json.parse(json.parse(source).value().to_string()).value().to_string();
    if (again != "{\"z\":1,\"a\":[true,{\"m\":\"é\"}],\"k\":-2.5e-07}") { return -9; }
    if (json.parse(again).value().to_string() != again) { return -10; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn edits_arrays_and_objects() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    var root = json.parse("{\"list\": [1, 2], \"name\": \"a\"}").value();
    var list = root["list"];
    list.append(json.JsonValue.Integer(3));
    list[0] = json.JsonValue.String("one");
    root["name"] = json.JsonValue.String("b");
    root["added"] = json.JsonValue.Bool(true);
    if (root.to_string() != "{\"list\":[\"one\",2,3],\"name\":\"b\",\"added\":true}") { return -1; }
    if (!root.remove("name") or root.remove("name")) { return -2; }
    if (root.to_string() != "{\"list\":[\"one\",2,3],\"added\":true}") { return -3; }
    # The array is held by reference: changing it changes the value.
    root["list"].as_array().value().pop();
    if (root["list"].to_string() != "[\"one\",2]") { return -4; }
    if (json.JsonValue.Integer(1).remove("x") or json.JsonValue.Null.contains("x")) { return -5; }
    return 0;
}
"##),
        0
    );
}

#[test]
fn nests_deeply_without_recursion() {
    assert_eq!(
        run(r##"
import json;

test(): int {
    ulong depth = 1000;
    var text = "[".repeat(depth) + "]".repeat(depth);
    var parsed = json.parse(text);
    if (parsed.is_err()) { return -1; }
    if (parsed.value().to_string() != text) { return -2; }
    var pretty = parsed.value().to_pretty_string(indent = 1);
    if (json.parse(pretty).value().to_string() != text) { return -3; }
    var deeper = json.parse("[".repeat(depth + 1) + "]".repeat(depth + 1));
    if (deeper.error().to_string() != "1:1001: error: arrays and objects nest more than 1000 deep") { return -4; }
    var objects = "{\"a\":".repeat(3000) + "1" + "}".repeat(3000);
    if (json.parse(objects, max_depth = 3000).value().to_string() != objects) { return -5; }
    # An unclosed run far past the limit stops at the limit.
    if (json.parse("[".repeat(100000)).is_ok()) { return -6; }
    return 0;
}
"##),
        0
    );
}

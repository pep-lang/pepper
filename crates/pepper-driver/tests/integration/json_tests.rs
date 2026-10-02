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

const CONFIG: &str = r##"
import json;

enum Mode {
    Fast,
    Safe,
}

struct Tls {
    var cert: String;
}

struct ServerConfig {
    var host: String;
    [Required]
    var port: int;
    [Name("max-connections")]
    var max_connections: u16;
    [Ignore]
    var started_at: long;
    var tls: Tls?;
    var timeout: double?;
    var mode: Mode;
    var ratio: double;
    var debug: bool;
    var tags: Array<String>;
    var limits: HashMap<String, int>;
    var headers: OrderedMap<String, String>;
    var extra: json.JsonValue;
}
"##;

#[test]
fn encodes_and_decodes_structs() {
    assert_eq!(
        run(&format!(
            "{}{}",
            CONFIG,
            r##"
test(): int {
    var config = ServerConfig();
    config.host = "localhost";
    config.port = 8080;
    config.max_connections = 16;
    config.started_at = 99;
    var tls = Tls();
    tls.cert = "a.pem";
    config.tls = Optional<Tls>.some(tls);
    config.mode = Mode.Safe;
    config.ratio = 0.5;
    config.tags = ["a", "b"];
    config.headers = OrderedMap<String, String>();
    config.headers["x"] = "1";
    config.extra = json.parse("[1, {\"k\": null}]").value();
    var text = json.encode(config);
    var expected = "{\"host\":\"localhost\",\"port\":8080,\"max-connections\":16,\"tls\":{\"cert\":\"a.pem\"},\"timeout\":null,\"mode\":\"Safe\",\"ratio\":0.5,\"debug\":false,\"tags\":[\"a\",\"b\"],\"limits\":null,\"headers\":{\"x\":\"1\"},\"extra\":[1,{\"k\":null}]}";
    if (text != expected) { print(text); return -1; }

    var decoded = json.decode<ServerConfig>(text);
    if (decoded.is_err()) { print(decoded.error().to_string()); return -2; }
    var back = decoded.value();
    if (back.port != 8080 or back.max_connections != 16 or back.started_at != 0) { return -3; }
    if (back.tls.value().cert != "a.pem" or back.timeout.is_some()) { return -4; }
    if (back.mode != Mode.Safe or back.tags.count != 2 or back.headers["x"] != "1") { return -5; }
    if (back.limits !== __null) { return -6; }
    if (json.encode(back) != text) { return -7; }

    # Missing keys keep their defaults; JSONC and maps.
    var small = json.decode<ServerConfig>("{\"port\": 1, // a comment\n \"limits\": {\"a\": 2,},}", comments = true);
    if (small.is_err()) { print(small.error().to_string()); return -8; }
    if (small.value().host !== __null or small.value().limits["a"] != 2) { return -9; }

    # Other top-level types, and to_json / from_json.
    if (json.encode([1, 2, 3]) != "[1,2,3]") { return -10; }
    if (json.decode<Array<int>>("[4, 5]").value()[1] != 5) { return -11; }
    if (json.decode<u64>("9007199254740991").value() != 9007199254740991) { return -12; }
    if (json.to_json(Mode.Fast).as_string().value() != "Fast") { return -13; }
    if (json.from_json<Mode>(json.JsonValue.String("Safe")).value() != Mode.Safe) { return -14; }
    if (!json.encode(config, indent = 2).contains("\n  \"port\": 8080,")) { return -15; }
    return 0;
}
"##
        )),
        0
    );
}

#[test]
fn reports_decode_errors_with_their_path() {
    assert_eq!(
        run(&format!(
            "{}{}",
            CONFIG,
            r##"
error_of(text: String): String {
    var decoded = json.decode<ServerConfig>(text, path = "s.json");
    if (decoded.is_ok()) { return "ok"; }
    return decoded.error().to_string();
}

reject(text: String): String {
    return json.decode<ServerConfig>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

test(): int {
    if (error_of("{\"port\": \"80\"}") != "s.json: error: $.port: expected a number, found a string") { return -1; }
    if (error_of("{}") != "s.json: error: $: missing required key 'port'") { return -2; }
    if (error_of("{\"port\": 1, \"tls\": {\"cert\": 3}}") != "s.json: error: $.tls.cert: expected a string, found a number") { return -3; }
    if (error_of("{\"port\": 1, \"max-connections\": 70000}") != "s.json: error: $[\"max-connections\"]: 70000 does not fit in 'u16'") { return -4; }
    if (error_of("{\"port\": 1.5}") != "s.json: error: $.port: expected an integer, found 1.5") { return -5; }
    if (error_of("{\"port\": 1, \"mode\": \"Slow\"}") != "s.json: error: $.mode: 'Slow' is not a case of 'Mode'") { return -6; }
    if (error_of("{\"port\": 1, \"tags\": [\"a\", null, 3]}") != "s.json: error: $.tags[2]: expected a string, found a number") { return -7; }
    if (error_of("{\"port\": 1, \"limits\": {\"a b\": true}}") != "s.json: error: $.limits[\"a b\"]: expected a number, found a boolean") { return -8; }
    if (error_of("{\"port\": 1, \"debug\": null}") != "s.json: error: $.debug: expected a boolean, found null") { return -9; }
    if (error_of("[]") != "s.json: error: $: expected an object, found an array") { return -10; }
    if (error_of("{\"port\": 1,}") != "s.json:1:11: error: trailing comma is not allowed; parse with 'comments = true' to accept JSONC") { return -11; }
    if (error_of("{\"port\": 1, \"unknown\": 2}") != "ok") { return -12; }
    if (reject("{\"port\": 1, \"unknown\": 2}") != "error: $.unknown: unknown key 'unknown'") { return -13; }
    if (reject("{\"port\": 1, \"started_at\": 2}") != "error: $.started_at: unknown key 'started_at'") { return -14; }
    return 0;
}
"##
        )),
        0
    );
}

#[test]
fn rejects_types_it_cannot_convert() {
    let error = crate::support::compile_error(
        "import json;\n\nstruct Job {\n    var name: String;\n    var outcome: Result<int>;\n}\n\ntest(): int {\n    var text = json.encode(Job());\n    return 0;\n}\n",
    );
    assert!(error.contains("error: 'encode' cannot convert property 'outcome' of type 'Result<int>' to JSON"), "{}", error);
    assert!(error.contains("test.pep:9:16: note: 'encode<Job>' is used by 'test' here"), "{}", error);
    let error = crate::support::compile_error(
        "import json;\n\nstruct Inner {\n    var handle: __ptr<void>;\n}\n\nstruct Job {\n    var inner: Inner;\n}\n\ntest(): int {\n    var job = json.decode<Job>(\"{}\");\n    return 0;\n}\n",
    );
    assert!(error.contains("error: 'decode' cannot convert property 'handle' of type"), "{}", error);
    assert!(error.contains("note: '_from_json<Inner>' is used by '_from_json<Job>' here"), "{}", error);
    assert!(error.contains("test.pep:12:15: note: 'decode<Job>' is used by 'test' here"), "{}", error);
}

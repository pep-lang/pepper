# The json module's parser: every kind of value, numbers at the edges of
# the integer range, strings and their escapes, strict RFC 8259 errors with
# their line and column, invalid UTF-8, JSONC on request, and nesting deep
# enough that recursion would overflow.

import json;

[Test]
parses_every_kind_of_value() {
    var parsed = json.parse(
        " {\"name\": \"pepper\", \"on\": true, \"off\": false, \"none\": null, \"list\": [1, 2.5, \"x\"], \"nested\": {\"port\": 8080}} "
    );
    expect_false(parsed.is_err());
    var root = parsed.value();
    expect_equal(root["name"].as_string().value(), "pepper");
    expect_true(root["on"].as_bool().value());
    expect_false(root["off"].as_bool().value());
    expect_true(root["none"].is_null());
    expect_true(root.contains("none"));
    expect_equal(root["list"][0].as_int().value(), 1);
    expect_equal(root["list"][1].as_double().value(), 2.5);
    expect_equal(root["list"][2].as_string().value(), "x");
    expect_equal(root["nested"]["port"].as_int().value_or(80), 8080);
    # Lookups that find nothing give Null and chain.
    expect_true(root["missing"]["deeper"][3].is_null());
    expect_false(root.contains("missing"));
    expect_true(root["list"][3].is_null());
    expect_true(root["name"]["x"].is_null());
    # The as_ methods give none for another kind.
    expect_false(root["name"].as_int().is_value());
    expect_false(root["list"].as_object().is_value());
    expect_equal(root["list"].as_array().value().count, 3);
    expect_equal(root.as_object().value().count, 6);
    # Keys keep the order the text wrote them in.
    var keys = "";
    for (var (key, _) in root.as_object().value()) {
        keys = keys + key + ",";
    }
    expect_equal(keys, "name,on,off,none,list,nested,");
    match (root["list"][1]) {
        Number(value) => {
            expect_equal(value, 2.5);
        }
        else => {
            panic("list[1] is not a Number");
        }
    }
    # A repeated key keeps its first place and its last value.
    var repeated = json.parse("{\"a\": 1, \"b\": 2, \"a\": 3}").value();
    expect_equal(repeated.to_string(), "{\"a\":3,\"b\":2}");
    # A byte-order mark is skipped; whitespace is space, tab, CR and LF.
    expect_equal(json.parse("\u{FEFF}\t\r\n 7 \n").value().as_int().value(), 7);
}

kind(text: String): String {
    return json.parse(text).value().name();
}

[Test]
keeps_integers_within_53_bits() {
    expect_equal(kind("9007199254740991"), "Integer");
    expect_equal(kind("-9007199254740991"), "Integer");
    expect_equal(kind("9007199254740992"), "Number");
    expect_equal(kind("-9007199254740992"), "Number");
    expect_equal(kind("123456789012345678901234567890"), "Number");
    expect_equal(kind("0"), "Integer");
    expect_equal(kind("-0"), "Integer");
    expect_equal(kind("1.0"), "Number");
    expect_equal(kind("1e2"), "Number");
    expect_equal(kind("1E-2"), "Number");
    expect_equal(json.parse("1e2").value().as_int().value(), 100);
    expect_false(json.parse("2.5").value().as_int().is_value());
    expect_false(json.parse("1e300").value().as_int().is_value());
    expect_equal(json.parse("-12").value().as_double().value(), -12.0);
    expect_equal(json.parse("0.125e1").value().as_double().value(), 1.25);
    expect_equal(json.parse("[9007199254740993]").value().to_string(), "[9007199254740992.0]");
}

text_of(source: String): String {
    return json.parse(source).value().as_string().value();
}

[Test]
decodes_string_escapes() {
    expect_equal(text_of("\"plain\""), "plain");
    expect_equal(text_of("\"\""), "");
    expect_equal(text_of("\"a\\\"b\\\\c\\/d\""), "a\"b\\c/d");
    expect_equal(text_of("\"\\b\\f\\n\\r\\t\""), "\u{8}\u{C}\n\r\t");
    expect_equal(text_of("\"\\u00e9\\u20AC\""), "é€");
    expect_equal(text_of("\"\\ud834\\udd1e\""), "𝄞");
    expect_equal(text_of("\"héllo 𝄞\""), "héllo 𝄞");
    expect_equal(text_of("\"x\\u0000y\"").size, 3);
}

error_of(source: String): String {
    var parsed = json.parse(source, path = "t.json");
    if (parsed.is_ok()) {
        return "ok";
    }
    return parsed.error().to_string();
}

[Test]
reports_errors_with_line_and_column() {
    expect_equal(error_of(""), "t.json:1:1: error: expected a value");
    expect_equal(error_of("[1 2]"), "t.json:1:4: error: expected ',' or ']'");
    expect_equal(error_of("{\"a\": 1 \"b\"}"), "t.json:1:9: error: expected ',' or '}'");
    expect_equal(error_of("{\"a\" 1}"), "t.json:1:6: error: expected ':'");
    expect_equal(error_of("{1: 2}"), "t.json:1:2: error: expected a member name in double quotes");
    expect_equal(
        error_of("[1,]"),
        "t.json:1:3: error: trailing comma is not allowed; parse with 'comments = true' to accept JSONC"
    );
    expect_equal(error_of("[,1]"), "t.json:1:2: error: expected a value");
    expect_equal(error_of("[\n  1,\n  tru\n]"), "t.json:3:3: error: expected a value");
    expect_equal(error_of("01"), "t.json:1:2: error: a number cannot start with '0'");
    expect_equal(error_of("-"), "t.json:1:2: error: expected a digit");
    expect_equal(error_of("1."), "t.json:1:3: error: expected a digit");
    expect_equal(error_of("1e+"), "t.json:1:4: error: expected a digit");
    expect_equal(error_of("+1"), "t.json:1:1: error: expected a value");
    expect_equal(error_of("1e400"), "t.json:1:1: error: number is too large for a double");
    expect_equal(error_of("\"abc"), "t.json:1:1: error: unterminated string");
    expect_equal(
        error_of("\"a\tb\""), "t.json:1:3: error: control character in a string; write it as an escape such as '\\n'"
    );
    expect_equal(error_of("\"\\q\""), "t.json:1:2: error: invalid escape '\\q'");
    expect_equal(error_of("\"\\u12\""), "t.json:1:2: error: '\\u' needs four hexadecimal digits");
    expect_equal(error_of("\"\\uD800\""), "t.json:1:2: error: unpaired surrogate '\\uD800'");
    expect_equal(error_of("\"\\uDC00\""), "t.json:1:2: error: unpaired surrogate '\\uDC00'");
    expect_equal(error_of("\"\\uD800\\u0041\""), "t.json:1:2: error: unpaired surrogate '\\uD800'");
    expect_equal(error_of("1 2"), "t.json:1:3: error: expected the end of the text after the value");
    expect_equal(
        error_of("// note\n1"),
        "t.json:1:1: error: comments are not allowed; parse with 'comments = true' to accept JSONC"
    );
    expect_equal(error_of("nul"), "t.json:1:1: error: expected a value");
    expect_equal(error_of("nullx"), "t.json:1:1: error: expected a value");
    expect_equal(error_of("NaN"), "t.json:1:1: error: expected a value");
    expect_equal(error_of("'a'"), "t.json:1:1: error: expected a value");
    # Without a path the error starts at the line.
    expect_equal(json.parse("[").error().to_string(), "1:2: error: expected a value");
    var error = json.parse("\n\n  [}").error();
    expect_equal(error.line, 3);
    expect_equal(error.column, 4);
    expect_equal(error.offset, 5);
    expect_equal(error.message, "expected a value before '}'");
}

[Test]
rejects_invalid_utf8_at_the_byte() {
    var bytes = "[\"ab".bytes();
    bytes.append(255);
    bytes.append(34);
    bytes.append(93);
    var text = String(unsafe_cast<__ptr<char>>(bytes._data), bytes.count);
    var error = json.parse(text).error();
    expect_equal(error.to_string(), "1:5: error: invalid UTF-8");
}

[Test]
accepts_jsonc_on_request() {
    var text = "// settings\n{\n  \"a\": [1, 2,], /* inline */\n  \"b\": {\"c\": true,},\n}\n// end";
    expect_false(json.parse(text).is_ok());
    var parsed = json.parse(text, comments = true);
    expect_false(parsed.is_err());
    expect_equal(parsed.value().to_string(), "{\"a\":[1,2],\"b\":{\"c\":true}}");
    var open = json.parse("[1 /* never closed", comments = true, path = "s.json");
    expect_equal(open.error().to_string(), "s.json:1:4: error: unterminated '/*' comment");
    # A comma alone is still an error.
    expect_false(json.parse("[,]", comments = true).is_ok());
    expect_false(json.parse("{,}", comments = true).is_ok());
}

[Test]
nests_deeply_without_recursion() {
    ulong depth = 1000;
    var text = "[".repeat(depth) + "]".repeat(depth);
    var parsed = json.parse(text);
    expect_false(parsed.is_err());
    expect_equal(parsed.value().to_string(), text);
    var pretty = parsed.value().to_pretty_string(indent = 1);
    expect_equal(json.parse(pretty).value().to_string(), text);
    var deeper = json.parse("[".repeat(depth + 1) + "]".repeat(depth + 1));
    expect_equal(deeper.error().to_string(), "1:1001: error: arrays and objects nest more than 1000 deep");
    # Releasing a value still recurses through its nested values, so a depth
    # past the default stays modest: Windows gives the main thread 1 MB.
    var objects = "{\"a\":".repeat(1200) + "1" + "}".repeat(1200);
    expect_equal(json.parse(objects, max_depth = 1200).value().to_string(), objects);
    # An unclosed run far past the limit stops at the limit.
    expect_false(json.parse("[".repeat(100000)).is_ok());
}

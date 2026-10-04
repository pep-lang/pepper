# The TOML 1.0 cases of toml-test (https://github.com/toml-lang/toml-test),
# copied into toml-test/ with its license: `parse` must accept every
# valid/ file and give the values its .json file lists, and reject every
# invalid/ file. files-toml-1.0.0 names the cases; to update them, copy
# that list and the files it names from a newer toml-test.

import io;
import json;
import text;
import toml;

const CORPUS = "toml/test/toml-test/";

[Test]
passes_the_toml_test_corpus() {
    var names = io.File.read_to_string(io.Path(CORPUS + "files-toml-1.0.0")).value();
    var count = 0;
    var failures = Array<String>();
    for (var name in names.split("\n")) {
        if (!name.ends_with(".toml")) {
            continue;
        }
        count += 1;
        var failure = _check_case(name);
        if (!failure.is_empty) {
            failures.append($"{name}: {failure}");
        }
    }
    for (var failure in failures) {
        print(failure);
    }
    expect_equal(count, 709);
    expect_true(failures.is_empty);
}

# Why the case `name` fails, or empty when it passes.
_check_case(name: String): String {
    var bytes = io.File.read_bytes(io.Path(CORPUS + name)).value();
    # `parse` checks UTF-8 itself, but a String cannot hold invalid UTF-8.
    var decoded = text.Utf8.decode(bytes);
    var valid = name.starts_with("valid/");
    if (decoded.is_empty()) {
        return valid ? "rejected: invalid UTF-8" : "";
    }
    var parsed = toml.parse(decoded.value(), path = name);
    if (!valid) {
        return parsed.is_err() ? "" : "accepted";
    }
    if (parsed.is_err()) {
        return $"rejected: {parsed.error().to_string()}";
    }
    var json_name = name.substr_bytes(0, name.size - 5) + ".json";
    var expected = json.parse(io.File.read_to_string(io.Path(CORPUS + json_name)).value()).value();
    return _matches(parsed.value(), expected) ? "" : $"differs: got {parsed.value().to_string()}";
}

# Whether `value` is the value toml-test's tagged JSON `expected` lists:
# a table as an object, an array as an array, anything else as
# {"type": ..., "value": ...} with the value as text.
_matches(value: toml.TomlValue, expected: json.JsonValue): bool {
    var leaf = _is_leaf(expected);
    var kind = leaf ? expected["type"].as_string().value() : "";
    var want = leaf ? expected["value"].as_string().value() : "";
    match (value) {
        Table(members) => {
            var object = expected.as_object();
            if (leaf || object.is_empty() || object.value().count != members.count) {
                return false;
            }
            for (var (key, member) in members) {
                if (!expected.contains(key) || !_matches(member, expected[key])) {
                    return false;
                }
            }
            return true;
        }
        Array(items) => {
            var array = expected.as_array();
            if (array.is_empty() || array.value().count != items.count) {
                return false;
            }
            for (var index in 0..items.count) {
                if (!_matches(items[index], array.value()[index])) {
                    return false;
                }
            }
            return true;
        }
        String(text) => { return kind == "string" && text == want; }
        Integer(number) => {
            var parsed = long.parse(want);
            return kind == "integer" && parsed.is_value() && parsed.value() == number;
        }
        Float(number) => { return kind == "float" && _same_float(number, want); }
        Boolean(flag) => { return kind == "bool" && want == (flag ? "true" : "false"); }
        DateTime(when) => {
            var actual_kind = "datetime";
            if (!when.has_offset) {
                actual_kind = when.has_date ? (when.has_time ? "datetime-local" : "date-local") : "time-local";
            }
            return kind == actual_kind && _date_time_text(when.to_string()) == _date_time_text(want);
        }
    }
    return false;
}

# Whether `value` is an object of exactly a "type" and a string "value".
_is_leaf(value: json.JsonValue): bool {
    var object = value.as_object();
    return object.is_value()
        && object.value().count == 2
        && value["type"].as_string().is_value()
        && value["value"].as_string().is_value();
}

# Whether `number` is the float `text` spells, nan matching any nan.
_same_float(number: double, text: String): bool {
    if (text.ends_with("nan")) {
        return number != number;
    }
    if (text.ends_with("inf")) {
        return number == (text.starts_with("-") ? -1.0 / 0.0 : 1.0 / 0.0);
    }
    var parsed = double.parse(text);
    return parsed.is_value() && parsed.value() == number;
}

# A date-time's text in one spelling: `T` and `Z` upper case, a space read
# as `T`, the fraction as nine digits, and `+00:00` as `Z`.
_date_time_text(text: String): String {
    var out = text.upper().replace(" ", "T");
    var split = out.split_once(".");
    if (split.is_value()) {
        var (head, rest) = split.value();
        var stop: ulong = 0;
        while (stop < rest.size && rest.byte_at(stop) >= '0' && rest.byte_at(stop) <= '9') {
            stop += 1;
        }
        var digits = rest.substr_bytes(0, stop);
        while (digits.size < 9) {
            digits = digits + "0";
        }
        out = $"{head}.{digits.substr_bytes(0, 9)}{rest.substr_bytes(stop, rest.size - stop)}";
    }
    if (out.ends_with("+00:00")) {
        out = out.substr_bytes(0, out.size - 6) + "Z";
    }
    return out;
}

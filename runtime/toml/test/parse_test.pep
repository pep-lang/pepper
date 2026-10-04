# The toml module's parser: every kind of value, strings and their
# escapes, tables, dotted keys, and errors with their line and column.

import toml;

parsed(text: String): toml.TomlValue {
    var result = toml.parse(text);
    if (result.is_err()) {
        print(result.error().to_string());
        panic("parse failed");
    }
    return result.value();
}

error_of(text: String): String {
    var result = toml.parse(text, path = "pep.toml");
    expect_true(result.is_err());
    return result.error().to_string();
}

[Test]
parses_every_kind_of_value() {
    var root = parsed(
        "title = \"demo\"\ncount = 1_000\nhex = 0xff\nratio = 0.5\nbig = 1e10\non = true\nwhen = 1979-05-27T07:32:00.25-07:00\nday = 1979-05-27\nat = 07:32:00\nlist = [1, \"two\", [3]]\npoint = { x = 1, y = 2 }\n"
    );
    expect_equal(root["title"].as_string().value(), "demo");
    expect_equal(root["count"].as_int().value(), 1000);
    expect_equal(root["hex"].as_int().value(), 255);
    expect_equal(root["ratio"].as_float().value(), 0.5);
    expect_equal(root["big"].as_float().value(), 10000000000.0);
    expect_true(root["on"].as_bool().value());
    var when = root["when"].as_date_time().value();
    expect_true(when.year == 1979 && when.hour == 7 && when.nanosecond == 250000000);
    expect_true(when.has_offset && when.offset_minutes == -420);
    expect_equal(when.to_string(), "1979-05-27T07:32:00.25-07:00");
    expect_false(root["day"].as_date_time().value().has_time);
    expect_false(root["at"].as_date_time().value().has_date);
    expect_equal(root["list"][1].as_string().value(), "two");
    expect_equal(root["list"][2][0].as_int().value(), 3);
    expect_equal(root["point"]["y"].as_int().value(), 2);
    expect_true(root.try_get("missing").is_empty());
    expect_equal(root["point"].type_name(), "table");
    expect_equal(root["count"].as_float().value(), 1000.0);
    expect_true(root["ratio"].as_int().is_empty());
}

[Test]
parses_strings_and_escapes() {
    var root = parsed(
        "basic = \"tab\\there \\u00e9 \\U0001F600\"\nliteral = 'C:\\path'\nmulti = \"\"\"\nline one\nline two \\\n    joined\"\"\"\nraw = '''\nkeep \\n as is'''\nquotes = \"\"\"two \"\" quotes\"\"\"\"\n"
    );
    expect_equal(root["basic"].as_string().value(), "tab\there é 😀");
    expect_equal(root["literal"].as_string().value(), "C:\\path");
    expect_equal(root["multi"].as_string().value(), "line one\nline two joined");
    expect_equal(root["raw"].as_string().value(), "keep \\n as is");
    expect_equal(root["quotes"].as_string().value(), "two \"\" quotes\"");
    var crlf = parsed("text = \"\"\"\r\na\r\nb\"\"\"\r\n");
    expect_equal(crlf["text"].as_string().value(), "a\nb");
}

[Test]
parses_tables_and_dotted_keys() {
    var root = parsed(
        "[server]\nhost = \"localhost\"\n\n[server.limits]\nmax = 10\n\n[[bin]]\nname = \"a\"\n\n[[bin]]\nname = \"b\"\n\n[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n"
    );
    expect_equal(root["server"]["limits"]["max"].as_int().value(), 10);
    expect_equal(root["bin"].as_array().value().count, 2);
    expect_equal(root["bin"][1]["name"].as_string().value(), "b");
    expect_true(root.lookup("fruit.apple.taste.sweet").value().as_bool().value());
    expect_equal(root.lookup("fruit.\"apple\".color").value().as_string().value(), "red");
    expect_true(root.lookup("fruit.pear").is_empty());
    expect_true(root.lookup("fruit..pear").is_empty());
    var keys = Array<String>();
    for (var (key, member) in root.as_table().value()) {
        keys.append(key);
    }
    expect_true(keys.count == 3 && keys[0] == "server" && keys[1] == "bin" && keys[2] == "fruit");
}

[Test]
reports_errors_with_line_and_column() {
    expect_equal(error_of("name \"demo\""), "pep.toml:1:6: error: expected '=' after the key");
    expect_equal(error_of("a = 1\na = 2\n"), "pep.toml:2:1: error: duplicate key 'a'");
    expect_equal(error_of("[a]\n[a]\n"), "pep.toml:2:2: error: table 'a' is already defined");
    expect_equal(error_of("a = {}\n[a]\n"), "pep.toml:2:2: error: table 'a' is already defined");
    expect_equal(
        error_of("[fruit]\napple.color = \"red\"\n[fruit.apple]\n"),
        "pep.toml:3:2: error: table 'fruit.apple' is already defined"
    );
    expect_equal(error_of("a = 1\n[a.b]\n"), "pep.toml:2:2: error: 'a' is already defined as an integer, not a table");
    expect_equal(error_of("a = [1, 2\n"), "pep.toml:2:1: error: expected ',' or ']'");
    expect_equal(error_of("a = { b = 1,\n c = 2 }\n"), "pep.toml:1:13: error: expected a key");
    expect_equal(
        error_of("a = { b = 1, }\n"), "pep.toml:1:14: error: a trailing comma is not allowed in an inline table"
    );
    expect_equal(error_of("a = 01\n"), "pep.toml:1:5: error: an integer cannot start with '0'");
    expect_equal(error_of("a = 1__0\n"), "pep.toml:1:6: error: an underscore must sit between two digits");
    expect_equal(error_of("a = 2023-02-29\n"), "pep.toml:1:5: error: 2023-02-29 is not a day of the calendar");
    expect_equal(
        error_of("a = \"open\n"),
        "pep.toml:1:10: error: line break in a string; use '\"\"\"' or ''''' for a multi-line string"
    );
    expect_equal(error_of("a = \"\\x41\"\n"), "pep.toml:1:6: error: invalid escape '\\x'");
    expect_equal(error_of("a = 9223372036854775808\n"), "pep.toml:1:5: error: integer does not fit in 64 bits");
    expect_equal(error_of("a = 1 b = 2\n"), "pep.toml:1:7: error: expected a line break after the value");
    var deep = "a = " + "[".repeat(2000) + "]".repeat(2000);
    expect_equal(error_of(deep), "pep.toml:1:1005: error: arrays and inline tables nest more than 1000 deep");
    var deeper = toml.parse("a = " + "[".repeat(3000) + "]".repeat(3000), max_depth = 3000);
    expect_false(deeper.is_err());
}

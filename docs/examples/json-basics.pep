# JSON: parse text, look values up, change them, and write them back.
import json;

main(): int {
    var text = "{\"name\": \"pepper\", \"server\": {\"port\": 8080}, \"tags\": [\"fast\"]}";
    var parsed = json.parse(text, path = "config.json");
    if (parsed.is_err()) {
        print(parsed.error().to_string());   # config.json:1:17: error: ...
        return 1;
    }
    var root = parsed.value();

    # Lookups chain, and a missing key gives Null instead of panicking.
    assert(root["name"].as_string().value() == "pepper", "a string");
    assert(root["server"]["port"].as_int().value_or(80) == 8080, "a number");
    assert(root["server"]["host"].as_string().value_or("localhost") == "localhost", "a default");

    # Match on the case to handle every kind.
    var described = match (root["tags"]) {
        Array(items) => $"{items.count} tag",
        Null => "no tags",
        else => "not a list",
    };
    assert(described == "1 tag", "an array");

    # Change the value in place, then write it back. Keys keep their order.
    root["tags"].append(json.JsonValue.String("safe"));
    root["debug"] = json.JsonValue.Bool(false);
    assert(root.to_string() == "{\"name\":\"pepper\",\"server\":{\"port\":8080},\"tags\":[\"fast\",\"safe\"],\"debug\":false}", "compact");

    # Build a value from scratch.
    var reply = json.JsonValue.object();
    reply["id"] = json.JsonValue.Integer(42);
    reply["ok"] = json.JsonValue.Bool(true);
    assert(reply.to_pretty_string() == "{\n  \"id\": 42,\n  \"ok\": true\n}", "indented");

    # An error names the line and column.
    var bad = json.parse("{\n  \"a\": 1\n  \"b\": 2\n}", path = "bad.json");
    assert(bad.error().to_string() == "bad.json:3:3: error: expected ',' or '}'", "where");

    # JSONC: comments and trailing commas, on request.
    var settings = json.parse("{\n  // the theme\n  \"theme\": \"dark\",\n}", comments = true);
    assert(settings.value()["theme"].as_string().value() == "dark", "JSONC");
    return 0;
}

# The json module's conversion between JSON and structs: encode, decode,
# to_json and from_json, the Required, Name and Ignore attributes, and the
# errors decode reports with the path of the value.

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

[Test]
encodes_and_decodes_structs() {
    var config = ServerConfig();
    config.host = "localhost";
    config.port = 8080;
    config.max_connections = 16;
    config.started_at = 99;
    var tls = Tls();
    tls.cert = "a.pem";
    config.tls = Optional<Tls>.Value(tls);
    config.mode = Mode.Safe;
    config.ratio = 0.5;
    config.tags = ["a", "b"];
    config.headers = OrderedMap<String, String>();
    config.headers["x"] = "1";
    config.extra = json.parse("[1, {\"k\": null}]").value();
    var text = json.encode(config);
    var expected = "{\"host\":\"localhost\",\"port\":8080,\"max-connections\":16,\"tls\":{\"cert\":\"a.pem\"},\"timeout\":null,\"mode\":\"Safe\",\"ratio\":0.5,\"debug\":false,\"tags\":[\"a\",\"b\"],\"limits\":null,\"headers\":{\"x\":\"1\"},\"extra\":[1,{\"k\":null}]}";
    expect_equal(text, expected);

    var decoded = json.decode<ServerConfig>(text);
    if (decoded.is_err()) {
        panic(decoded.error().to_string());
    }
    var back = decoded.value();
    expect_equal(back.port, 8080);
    expect_equal(back.max_connections, 16);
    expect_equal(back.started_at, 0);
    expect_equal(back.tls.value().cert, "a.pem");
    expect_false(back.timeout.is_value());
    expect_true(back.mode == Mode.Safe);
    expect_equal(back.tags.count, 2);
    expect_equal(back.headers["x"], "1");
    expect_true(back.limits === __null);
    expect_equal(json.encode(back), text);

    # Missing keys keep their defaults; JSONC and maps.
    var small = json.decode<ServerConfig>("{\"port\": 1, // a comment\n \"limits\": {\"a\": 2,},}", comments = true);
    if (small.is_err()) {
        panic(small.error().to_string());
    }
    expect_true(small.value().host === __null);
    expect_equal(small.value().limits["a"], 2);

    # Other top-level types, and to_json / from_json.
    expect_equal(json.encode([1, 2, 3]), "[1,2,3]");
    expect_equal(json.decode<Array<int>>("[4, 5]").value()[1], 5);
    expect_equal(json.decode<u64>("9007199254740991").value(), 9007199254740991);
    expect_equal(json.to_json(Mode.Fast).as_string().value(), "Fast");
    expect_true(json.from_json<Mode>(json.JsonValue.String("Safe")).value() == Mode.Safe);
    expect_true(json.encode(config, indent = 2).contains("\n  \"port\": 8080,"));
}

error_of(text: String): String {
    var decoded = json.decode<ServerConfig>(text, path = "s.json");
    if (decoded.is_ok()) { return "ok"; }
    return decoded.error().to_string();
}

reject(text: String): String {
    return json.decode<ServerConfig>(text, unknown_keys = json.UnknownKeys.Reject).error().to_string();
}

[Test]
reports_decode_errors_with_their_path() {
    expect_equal(error_of("{\"port\": \"80\"}"), "s.json:1:10: error: $.port: expected a number, found a string");
    expect_equal(error_of("{}"), "s.json:1:1: error: $: missing required key 'port'");
    expect_equal(
        error_of("{\"port\": 1, \"tls\": {\"cert\": 3}}"),
        "s.json:1:29: error: $.tls.cert: expected a string, found a number"
    );
    expect_equal(
        error_of("{\"port\": 1, \"max-connections\": 70000}"),
        "s.json:1:32: error: $[\"max-connections\"]: 70000 does not fit in 'u16'"
    );
    expect_equal(error_of("{\"port\": 1.5}"), "s.json:1:10: error: $.port: expected an integer, found 1.5");
    expect_equal(
        error_of("{\"port\": 1, \"mode\": \"Slow\"}"), "s.json:1:21: error: $.mode: 'Slow' is not a case of 'Mode'"
    );
    expect_equal(
        error_of("{\"port\": 1, \"tags\": [\"a\", null, 3]}"),
        "s.json:1:33: error: $.tags[2]: expected a string, found a number"
    );
    expect_equal(
        error_of("{\"port\": 1, \"limits\": {\"a b\": true}}"),
        "s.json:1:31: error: $.limits[\"a b\"]: expected a number, found a boolean"
    );
    expect_equal(
        error_of("{\"port\": 1, \"debug\": null}"), "s.json:1:22: error: $.debug: expected a boolean, found null"
    );
    expect_equal(error_of("[]"), "s.json:1:1: error: $: expected an object, found an array");
    expect_equal(
        error_of("{\"port\": 1,}"),
        "s.json:1:11: error: trailing comma is not allowed; parse with 'comments = true' to accept JSONC"
    );
    expect_equal(error_of("{\"port\": 1, \"unknown\": 2}"), "ok");
    expect_equal(reject("{\"port\": 1, \"unknown\": 2}"), "1:24: error: $.unknown: unknown key 'unknown'");
    expect_equal(reject("{\"port\": 1, \"started_at\": 2}"), "1:27: error: $.started_at: unknown key 'started_at'");
}

struct P {
    var name: String;
}

# `p`, and so `t`, are typed only once `from_json<P>`'s `Result` is
# specialized; `t["name"]` then picks `JsonValue`'s string indexer and `n`
# is an `Optional<String>` (#471).
[Test]
indexes_the_json_of_a_decoded_value_held_in_a_var() {
    var decoded = json.from_json<P>(json.parse("{\"name\": \"pepper\"}").value());
    var p = decoded.value();
    var t = json.to_json(p);
    var n = t["name"].as_string();
    expect_true(n.is_value());
    expect_equal(n.value(), "pepper");
    expect_equal($"{n.is_value()}", "true");
}

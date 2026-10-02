# JSON: convert structs to JSON text and back, through reflection.
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
    # The key is "max-connections", not the property's name.
    [Name("max-connections")]
    var max_connections: int;
    # Never written or read.
    [Ignore]
    var started_at: long;
    # `null` or missing when none.
    var tls: Tls?;
    var mode: Mode;
    var tags: Array<String>;
}

main(): int {
    var config = ServerConfig();
    config.host = "localhost";
    config.port = 8080;
    config.max_connections = 64;
    config.mode = Mode.Safe;
    config.tags = ["web"];
    var text = json.encode(config);
    assert(
        text == "{\"host\":\"localhost\",\"port\":8080,\"max-connections\":64,\"tls\":null,\"mode\":\"Safe\",\"tags\":[\"web\"]}",
        "properties in declaration order"
    );

    var decoded = json.decode<ServerConfig>("{\"port\": 443, \"tls\": {\"cert\": \"site.pem\"}}");
    if (decoded.is_err()) {
        print(decoded.error().to_string());
        return 1;
    }
    var back = decoded.value();
    assert(back.port == 443, "a number");
    assert(back.tls.value().cert == "site.pem", "a nested struct");
    assert(back.mode == Mode.Fast, "a missing key keeps its default");

    # An error names where in the document it is.
    var bad = json.decode<ServerConfig>("{\"port\": 443, \"mode\": \"Slow\"}", path = "server.json");
    assert(bad.error().to_string() == "server.json: error: $.mode: 'Slow' is not a case of 'Mode'", "a path");
    var missing = json.decode<ServerConfig>("{}");
    assert(missing.error().to_string() == "error: $: missing required key 'port'", "[Required]");
    return 0;
}

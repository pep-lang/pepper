<!-- Generated from runtime/json/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The json module

JSON: parse text into a `JsonValue`, look values up and change them, and
write them back as compact or indented text.

Bring it in with `import json`. Parsing follows RFC 8259 strictly, and
accepts JSONC (comments and trailing commas) on request. Objects keep
their keys in the order they were written, so a document round-trips
unchanged. `encode` and `decode` convert structs to JSON text and back.

- [JsonValue](json-value.md): `JsonValue`
- [Parsing](json-parse.md): `parse`, `JsonError`
- [Documents with comments](json-document.md): `parse_document`,
  `JsonDocument`
- [Struct conversion](json-convert.md): `encode`, `decode`, `to_json`,
  `from_json`, `UnknownKeys`, with the attributes of the
  [serialize](serialize-module.md) module

**Example**
```pepper
    import json;

    main(): int {
        var parsed = json.parse("{\"name\": \"pepper\", \"port\": 8080}");
        if (parsed.is_err()) {
            print(parsed.error().to_string());
            return 1;
        }
        var root = parsed.value();
        assert(root["name"].as_string().value() == "pepper", "a string");
        assert(root["port"].as_int().value_or(80) == 8080, "a number");
        root["debug"] = json.JsonValue.Bool(true);
        assert(root.to_string() == "{\"name\":\"pepper\",\"port\":8080,\"debug\":true}", "compact");
        return 0;
    }
```

Source: `runtime/json/module.pep`

# YAML

YAML 1.2 is read and written by the
[yaml package](https://github.com/pep-lang/pepper-yaml), which has
the same shape as the [`json`](json.md) and [`toml`](toml.md) modules: a
`YamlValue` to look values up in and change, clang-style errors at the
line and column, documents that keep their comments when edited, and
struct conversion with the [`serialize`](../reference/serialize-module.md)
attributes. It is a package rather than part of the runtime because few
programs need YAML; add it with
`pepper package add pep-lang/pepper-yaml --name yaml`.

```pepper
import yaml;

main(): int {
    var parsed = yaml.parse("server:\n  port: 8080\n  debug: no\n", path = "config.yaml");
    if (parsed.is_err()) {
        print(parsed.error().to_string());
        return 1;
    }
    var root = parsed.value();
    print(root["server"]["port"].as_int().value());       # 8080
    print(root["server"]["debug"].as_string().value());   # no
    root["server"]["port"] = yaml.YamlValue.Integer(9090);
    print(root.to_string());
    return 0;
}
```

- **The core schema**: `yes`, `no`, `on` and `off` are strings, not
  booleans, so `NO` (Norway) stays `NO`.
- **Safe for untrusted text**: only the core schema's tags (`!!str`,
  `!!int`, ...) are read, and any other tag is an error; aliases may not
  stand for more than `max_alias_nodes` nodes, which stops the "billion
  laughs" attack.
- **Merge keys**: `yaml.parse(text, merge_keys = true)` applies YAML
  1.1's `<<` (`<<: *defaults`), which CI and compose files use to reuse a
  mapping; the mapping's own keys win, and merged nodes count toward
  `max_alias_nodes`. By default `<<` is an ordinary key, as YAML 1.2
  says.
- **Several documents** in one stream (`---`) are read by
  `yaml.parse_all` and written by `yaml.write_all`.
- **`yaml.parse_document`** keeps comments, key order, flow or block
  style and scalar styles through edits, as `json.parse_document` keeps a
  JSONC file's comments.
- **`yaml.encode`** and **`yaml.decode<T>`** convert structs exactly as
  `json.encode` and `json.decode` do.

The package's README lists what it reads and its limits: a mapping's keys
are strings, and there is no streaming reader yet.

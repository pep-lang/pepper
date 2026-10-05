<!-- Generated from runtime/toml/module.pep by `pep-doc reference`. Do not edit. -->

# The toml module

TOML: parse a document into a `TomlValue`, look values up and change
them, write tables back as documents, edit a document in place keeping
its comments and layout, and convert structs to TOML and back.

Bring it in with `import toml`. Parsing follows TOML 1.0 and checks all
of its rules; errors carry a line and column, like a compiler's. Tables
keep their keys in the order they were written.

- [TomlValue](toml-value.md): `TomlValue`, `TomlDateTime`
- [Parsing](toml-parse.md): `parse`, `TomlError`
- [Writing](toml-write.md): `to_string`, `to_document`
- [Documents with comments](toml-document.md): `parse_document`,
  `TomlDocument`, for changing a file people edit, such as `pep.toml`,
  without reformatting it
- [Struct conversion](toml-convert.md): `encode`, `decode`, `to_toml`,
  `from_toml`, `UnknownKeys`, with the attributes of the
  [serialize](serialize-module.md) module

**Example**
```pepper
import toml;

main(): int {
    var parsed = toml.parse("[package]\nname = \"demo\"\nversion = \"0.1.0\"\n");
    if (parsed.is_err()) {
        print(parsed.error().to_string());
        return 1;
    }
    var root = parsed.value();
    assert(root.lookup("package.name").value().as_string().value() == "demo", "a string");
    var package = root["package"];
    package["edition"] = toml.TomlValue.Integer(2026);
    print(root.to_document());
    return 0;
}
```

Source: `runtime/toml/module.pep`

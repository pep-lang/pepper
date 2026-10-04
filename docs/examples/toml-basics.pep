# TOML: parse a document, look values up, edit it in place keeping its
# comments, and read it into a struct.
import toml;

struct Package {
    [Required]
    var name: String;
    var version: String;
}

struct Manifest {
    [Required]
    var package: Package;
}

main(): int {
    var text = "[package]\nname = \"demo\"  # the name\nversion = \"0.1.0\"\n";
    var parsed = toml.parse(text, path = "pep.toml");
    if (parsed.is_err()) {
        print(parsed.error().to_string());   # pep.toml:2:6: error: ...
        return 1;
    }
    var root = parsed.value();
    assert(root["package"]["name"].as_string().value() == "demo", "a string");
    assert(root.lookup("package.version").value().as_string().value() == "0.1.0", "a dotted lookup");
    assert(root.try_get("dependencies").is_empty(), "a missing key");

    # Change a value, then write the tables back as a document.
    var package = root["package"];
    package["edition"] = toml.TomlValue.Integer(2026);
    assert(root.to_document() == "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nedition = 2026\n", "a document");

    # Edit the text in place: comments and layout stay as written.
    var document = toml.parse_document(text, path = "pep.toml").value();
    document.set(["dependencies", "yaml"], toml.TomlValue.String("0.3")).value();
    assert(
        document.to_string() == "[package]\nname = \"demo\"  # the name\nversion = \"0.1.0\"\n\n[dependencies]\nyaml = \"0.3\"\n",
        "an edit"
    );

    # Read it into a struct, with the serialize attributes json uses.
    Manifest manifest = toml.decode<Manifest>(text).value();
    assert(manifest.package.version == "0.1.0", "a struct");

    # An error names the line and column.
    var bad = toml.parse("name \"demo\"\n", path = "bad.toml");
    assert(bad.error().to_string() == "bad.toml:1:6: error: expected '=' after the key", "where");
    return 0;
}

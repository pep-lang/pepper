# TomlDocument: edits that keep a file's comments and layout.

import toml;

[Test]
edits_a_document_in_place() {
    var text = "# Manifest\n[package]\nname = \"demo\"  # the name\n\n# What it needs\n[dependencies]\n  json5 = \"1.0\"\n  # Big, but needed\n  yaml = { version = \"0.3\", features = [\"a\"] }\n\n[[bin]]\nname = \"demo\"\n";
    var document = toml.parse_document(text, path = "pep.toml").value();
    expect_equal(document.to_string(), text);
    document.set(["package", "version"], toml.TomlValue.String("0.2.0")).value();
    document.set(["dependencies", "zip"], toml.TomlValue.String("2")).value();
    document.set(["dependencies", "yaml", "version"], toml.TomlValue.String("0.4")).value();
    expect_equal(
        document.to_string(),
        "# Manifest\n[package]\nname = \"demo\"  # the name\nversion = \"0.2.0\"\n\n# What it needs\n[dependencies]\n  json5 = \"1.0\"\n  # Big, but needed\n  yaml = { version = \"0.4\", features = [\"a\"] }\n  zip = \"2\"\n\n[[bin]]\nname = \"demo\"\n"
    );
    document.remove(["dependencies", "yaml"]).value();
    expect_false(document.to_string().contains("Big"));
    expect_equal(document.get(["dependencies", "zip"]).value().as_string().value(), "2");
    expect_equal(document.root()["package"]["version"].as_string().value(), "0.2.0");
    expect_false(document.remove(["dependencies", "missing"]).value());
    var local = toml.TomlValue.table();
    local["path"] = toml.TomlValue.String("../local");
    document.set(["dependencies", "local"], local, inline = true).value();
    expect_true(document.to_string().contains("  local = { path = \"../local\" }\n"));
    document.set(["dev-dependencies", "check"], toml.TomlValue.String("1")).value();
    expect_true(document.to_string().ends_with("name = \"demo\"\n\n[dev-dependencies]\ncheck = \"1\"\n"));
    var inside = document.set(["bin", "name"], toml.TomlValue.String("x"));
    expect_true(inside.is_err());
    expect_equal(
        inside.error().to_string(),
        "pep.toml: error: cannot edit 'bin.name' inside the array of tables 'bin'; set or remove it whole"
    );
    var not_table = document.set(["package", "name", "x"], toml.TomlValue.Integer(1));
    expect_equal(not_table.error().message, "cannot edit 'package.name.x': 'package.name' is a string, not a table");
    document.remove(["dependencies"]).value();
    document.remove(["bin"]).value();
    expect_equal(
        document.to_string(),
        "# Manifest\n[package]\nname = \"demo\"  # the name\nversion = \"0.2.0\"\n\n[dev-dependencies]\ncheck = \"1\"\n"
    );
    var dotted = toml.parse_document("a.b = 1\na.c = 2\n\n[x]\n").value();
    dotted.set(["a", "d"], toml.TomlValue.Integer(3)).value();
    dotted.remove(["a", "c"]).value();
    expect_equal(dotted.to_string(), "a.b = 1\na.d = 3\n\n[x]\n");
    var fresh = toml.TomlDocument();
    var package = toml.TomlValue.table();
    package["name"] = toml.TomlValue.String("fresh");
    fresh.set(["package"], package).value();
    fresh.set(["dependencies", "json5"], toml.TomlValue.String("1")).value();
    expect_equal(fresh.to_string(), "[package]\nname = \"fresh\"\n\n[dependencies]\njson5 = \"1\"\n");
    var crlf = toml.parse_document("[a]\r\nb = 1").value();
    crlf.set(["a", "c"], toml.TomlValue.Integer(2)).value();
    expect_equal(crlf.to_string(), "[a]\r\nb = 1\nc = 2\n");
}

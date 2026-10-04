# Writing TomlValue back out: documents, inline tables, quoted keys, and
# nesting deep enough that recursion would overflow.

import toml;

[Test]
writes_documents() {
    var root = toml.TomlValue.table();
    root["title"] = toml.TomlValue.String("say \"hi\"\n");
    root["pi"] = toml.TomlValue.Float(3.0);
    root["inf"] = toml.TomlValue.Float(1.0 / 0.0);
    var server = toml.TomlValue.table();
    server["ports"] = toml.TomlValue.array([toml.TomlValue.Integer(80), toml.TomlValue.Integer(443)]);
    root["server"] = server;
    var first = toml.TomlValue.table();
    first["name"] = toml.TomlValue.String("a");
    var odd = toml.TomlValue.table();
    odd["key with spaces"] = toml.TomlValue.Boolean(true);
    first["meta"] = odd;
    var second = toml.TomlValue.table();
    second["name"] = toml.TomlValue.String("b");
    root["bin"] = toml.TomlValue.array([first, second]);
    var text = root.to_document();
    expect_equal(
        text,
        "title = \"say \\\"hi\\\"\\n\"\npi = 3.0\ninf = inf\n\n[server]\nports = [80, 443]\n\n[[bin]]\nname = \"a\"\n\n[bin.meta]\n\"key with spaces\" = true\n\n[[bin]]\nname = \"b\"\n"
    );
    var back = toml.parse(text).value();
    expect_equal(back.to_document(), text);
    expect_true(back["bin"][0]["meta"]["key with spaces"].as_bool().value());
    expect_equal(root["server"].to_string(), "{ ports = [80, 443] }");
    var empty = toml.TomlValue.table();
    empty["nothing"] = toml.TomlValue.table();
    expect_equal(empty.to_document(), "[nothing]\n");
    var deep = toml.TomlValue.Integer(1);
    for (var index in 0..3000) {
        deep = toml.TomlValue.array([deep]);
    }
    expect_equal(deep.to_string().size, 6001);
}

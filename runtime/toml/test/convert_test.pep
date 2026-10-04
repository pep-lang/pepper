# Struct conversion: decode, encode, to_toml and from_toml with the
# serialize attributes, and their errors.

import toml;

enum Source {
    Registry,
    Path(path: String),
    Git(url: String, branch: String?),
}

struct Dependency {
    var version: String?;
    var source: Source;
}

struct Package {
    [Required]
    var name: String;
    var version: String;
    var authors: Array<String>;
    var edition: int?;
    [Name("build-script")]
    var build_script: String?;
    [Ignore]
    var cache: int;
    var published: toml.TomlDateTime;
}

struct Manifest {
    [Required]
    var package: Package;
    var dependencies: OrderedMap<String, Dependency>;
}

[Test]
converts_structs() {
    var text = "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\nbuild-script = \"build.pep\"\npublished = 2026-10-02\ncache = 5\n\n[dependencies.json5]\nversion = \"1\"\nsource = \"Registry\"\n\n[dependencies.local]\nsource = { Path = { path = \"../x\" } }\n\n[dependencies.git]\nsource.Git.url = \"https://example.com/a.git\"\n";
    var decoded = toml.decode<Manifest>(text, path = "pep.toml");
    if (decoded.is_err()) {
        print(decoded.error().to_string());
    }
    # An explicit type works around a type-inference bug (bugs/var-inference-after-from-json.md).
    Manifest manifest = decoded.value();
    expect_equal(manifest.package.name, "demo");
    expect_equal(manifest.package.authors[0], "Ada");
    expect_true(manifest.package.edition.is_empty());
    expect_equal(manifest.package.build_script.value(), "build.pep");
    expect_equal(manifest.package.cache, 0);
    expect_equal(manifest.package.published.year, 2026);
    expect_equal(manifest.dependencies.count, 3);
    expect_true(manifest.dependencies["json5"].source is Registry);
    if (manifest.dependencies["local"].source is Path(path)) {
        expect_equal(path, "../x");
    } else {
        expect_true(false);
    }
    if (manifest.dependencies["git"].source is Git(url, branch)) {
        expect_true(url == "https://example.com/a.git" && branch.is_empty());
    } else {
        expect_true(false);
    }
    var encoded = toml.encode(manifest);
    expect_true(
        encoded.starts_with(
            "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\nbuild-script = \"build.pep\"\npublished = 2026-10-02\n"
        )
    );
    expect_false(encoded.contains("cache"));
    expect_false(encoded.contains("edition"));
    var again = toml.decode<Manifest>(encoded).value();
    expect_true(again.dependencies["local"].source is Path);

    var mismatch = toml.decode<Manifest>("[package]\nname = 7\n", path = "pep.toml");
    expect_equal(
        mismatch.error().to_string(), "pep.toml:2:8: error: $.package.name: expected a string, found an integer"
    );
    var missing = toml.decode<Manifest>("[package]\nversion = \"1\"\n", path = "pep.toml");
    expect_equal(missing.error().to_string(), "pep.toml:1:1: error: $.package: missing required key 'name'");
    var unknown = toml.decode<Manifest>("[package]\nname = \"a\"\nnope = 1\n", unknown_keys = toml.UnknownKeys.Reject);
    expect_equal(unknown.error().message, "$.package.nope: unknown key 'nope'");
    var small = toml.decode<Package>("name = \"a\"\nedition = 3000000000\n");
    expect_equal(small.error().message, "$.edition: 3000000000 does not fit in 'int'");
    var case_error = toml.decode<Dependency>("source = \"Nowhere\"\n");
    expect_equal(case_error.error().message, "$.source: 'Nowhere' is not a case of 'Source'");
    var table = toml.to_toml(manifest.package).value();
    expect_equal(table["build-script"].as_string().value(), "build.pep");
    var back = toml.from_toml<Package>(table).value();
    expect_equal(back.name, "demo");
}

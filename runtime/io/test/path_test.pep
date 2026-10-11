# io.Path: joining, parent, file name, stem and extension, components,
# normalizing, and the POSIX and Windows rules for absolute paths and
# separators, in pure Pepper.

import io;

# The expected text of a path the implementation builds: `/` written here is
# the platform separator, `\` on Windows.
native(text: String): String {
    var out = text;
    [Target(OS(Windows))]
    {
        out = text.replace("/", "\\");
    }
    return out;
}

text_of(path: io.Path): String {
    return path.to_string();
}

[Test]
join_replaces_on_an_absolute_path_and_inserts_the_separator() {
    expect_equal(io.Path("a").join(io.Path("b")).to_string(), native("a/b"));
    expect_equal(io.Path("a/").join(io.Path("b")).to_string(), "a/b");
    expect_equal(io.Path("a").join(io.Path("/abs")).to_string(), "/abs");
    expect_equal(io.Path("").join(io.Path("b")).to_string(), "b");
    expect_equal(io.Path("a").join(io.Path("")).to_string(), "a");
    expect_equal(io.Path("usr").join("lib").join("x.so").to_string(), native("usr/lib/x.so"));
    expect_equal(io.Path("usr").join_str("lib").to_string(), native("usr/lib"));
}

[Test]
parent_drops_the_last_component() {
    expect_equal(io.Path("/a/b/c.txt").parent().value().to_string(), "/a/b");
    expect_equal(io.Path("/a").parent().value().to_string(), "/");
    expect_true(io.Path("/").parent().is_empty());
    expect_true(io.Path("a").parent().is_empty());
    expect_equal(io.Path("a/b/").parent().value().to_string(), "a");
    expect_equal(io.Path("a//b").parent().value().to_string(), "a");
    expect_true(io.Path("").parent().is_empty());
    expect_true(io.Path(".").parent().is_empty());
    expect_true(io.Path("..").parent().is_empty());
}

[Test]
file_name_stem_and_extension() {
    expect_equal(io.Path("/a/b/c.txt").file_name().value(), "c.txt");
    expect_equal(io.Path("a/b/").file_name().value(), "b");
    expect_true(io.Path("/").file_name().is_empty());
    expect_true(io.Path("a/..").file_name().is_empty());
    expect_true(io.Path("").file_name().is_empty());
    expect_equal(io.Path("c.tar.gz").file_stem().value(), "c.tar");
    expect_equal(io.Path("c.tar.gz").extension().value(), "gz");
    expect_equal(io.Path("/x/.bashrc").file_stem().value(), ".bashrc");
    expect_true(io.Path("/x/.bashrc").extension().is_empty());
    expect_equal(io.Path("foo.").file_stem().value(), "foo");
    expect_equal(io.Path("foo.").extension().value(), "");
    expect_true(io.Path("a.b/c").extension().is_empty());
    expect_equal(io.Path("noext").file_stem().value(), "noext");
    expect_true(io.Path("noext").extension().is_empty());
    expect_true(io.Path("/").file_stem().is_empty());
    expect_equal(io.Path.dot_index("c.tar.gz").value(), 5);
    expect_true(io.Path.dot_index(".bashrc").is_empty());
    expect_true(io.Path.dot_index("").is_empty());
}

[Test]
with_extension_replaces_adds_or_removes() {
    expect_equal(io.Path("a/b.txt").with_extension("md").to_string(), "a/b.md");
    expect_equal(io.Path("a/b").with_extension("rs").to_string(), "a/b.rs");
    expect_equal(io.Path("a/b.txt").with_extension("").to_string(), "a/b");
    expect_equal(io.Path(".bashrc").with_extension("x").to_string(), ".bashrc.x");
    expect_equal(io.Path("/").with_extension("x").to_string(), "/");
}

[Test]
components_split_at_separators() {
    var c = io.Path("/usr//lib/./x/").components();
    expect_equal(c.count, 4);
    expect_equal(c[0], "/");
    expect_equal(c[1], "usr");
    expect_equal(c[2], "lib");
    expect_equal(c[3], "x");
    var d = io.Path("./a/b").components();
    expect_equal(d.count, 3);
    expect_equal(d[0], ".");
    expect_equal(d[1], "a");
    expect_equal(d[2], "b");
    var e = io.Path("a/../b").components();
    expect_equal(e.count, 3);
    expect_equal(e[1], "..");
    expect_equal(io.Path("").components().count, 0);
}

[Test]
normalize_rebuilds_with_the_platform_separator() {
    expect_equal(io.Path("a/./b/../c").normalize().to_string(), native("a/c"));
    expect_equal(io.Path("/../x").normalize().to_string(), native("/x"));
    expect_equal(io.Path("../a/..").normalize().to_string(), "..");
    expect_equal(io.Path("a/..").normalize().to_string(), ".");
    expect_equal(io.Path("a//b/").normalize().to_string(), native("a/b"));
    expect_equal(io.Path("./").normalize().to_string(), ".");
    expect_equal(io.Path("").normalize().to_string(), "");
}

[Test]
relative_empty_and_equality() {
    expect_false(io.Path("x").is_absolute());
    expect_true(io.Path("x").is_relative());
    expect_false(io.Path("").is_absolute());
    expect_true(io.Path("").is_empty);
    expect_false(io.Path("a").is_empty);
    expect_equal(io.Path.separator(), native("/"));
    expect_true(io.Path("a/b") == io.Path("a/b"));
    expect_true(io.Path("a/b") != io.Path("a/c"));
    expect_equal(io.Path("q").to_string(), "q");
    expect_equal(text_of(io.Path("z")), "z");
}

[Test]
posix_rules() {
    # A root makes a path absolute; `\` is an ordinary byte.
    [Target(!OS(Windows))]
    {
        expect_true(io.Path("/x").is_absolute());
        expect_equal(io.Path("//a//b/").normalize().to_string(), "/a/b");
        expect_equal(io.Path("a\\b").file_name().value(), "a\\b");
    }
}

[Test]
windows_rules() {
    # `\` and `/` both separate; absolute needs a drive and a root, or a UNC
    # `\\server\share` prefix.
    [Target(OS(Windows))]
    {
        expect_false(io.Path("/x").is_absolute());
        expect_false(io.Path("C:x").is_absolute());
        expect_true(io.Path("C:/x").is_absolute());
        expect_true(io.Path(native("C:/x")).is_absolute());
        expect_true(io.Path(native("//server/share/x")).is_absolute());
        expect_equal(io.Path(native("a/b/c.txt")).parent().value().to_string(), native("a/b"));
        expect_equal(io.Path(native("a/b/c.txt")).file_name().value(), "c.txt");
        expect_equal(io.Path("C:/a//./b/").normalize().to_string(), native("C:/a/b"));
        expect_equal(io.Path("C:/x").parent().value().to_string(), "C:/");
        expect_true(io.Path("C:/").parent().is_empty());
        var components = io.Path(native("C:/a/b")).components();
        expect_equal(components.count, 4);
        expect_equal(components[0], "C:");
        expect_equal(components[1], native("/"));
        expect_equal(components[2], "a");
        expect_equal(components[3], "b");
        expect_equal(io.Path("a").join("C:/x").to_string(), "C:/x");
        expect_equal(io.Path(native("C:/a")).join("b").to_string(), native("C:/a/b"));
    }
}

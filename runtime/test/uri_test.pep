# Uri: parsing absolute URIs with any scheme and relative references, the
# errors parse reports, percent-decoding, and putting a URI back together.

[Test]
parses_components() {
    var u = Uri.parse("HTTPS://user:pw@Example.com:8443/a%20b/c?x=1&y#top").value();
    expect_equal(u.scheme, "https");
    expect_true(u.is_absolute());
    expect_equal(u.user_info.value_or(""), "user:pw");
    expect_equal(u.host.value_or(""), "Example.com");
    expect_equal(u.port.value_or(0), 8443);
    expect_equal(u.path, "/a%20b/c");
    expect_equal(u.query.value_or(""), "x=1&y");
    expect_equal(u.fragment.value_or(""), "top");
    expect_equal(u.authority().value_or(""), "user:pw@Example.com:8443");
    expect_equal(u.path_and_query(), "/a%20b/c?x=1&y");
    expect_equal(u.to_string(), "https://user:pw@Example.com:8443/a%20b/c?x=1&y#top");
    expect_equal($"{u}", u.to_string());

    var mail = Uri.parse("mailto:someone@example.com").value();
    expect_equal(mail.scheme, "mailto");
    expect_false(mail.host.is_value());
    expect_equal(mail.path, "someone@example.com");
    expect_false(mail.query.is_value());

    var file = Uri.parse("file:///tmp/x").value();
    expect_equal(file.host.value_or("?"), "");
    expect_equal(file.path, "/tmp/x");
    expect_equal(file.to_string(), "file:///tmp/x");

    var v6 = Uri.parse("http://[::1]:8080").value();
    expect_equal(v6.host.value_or(""), "::1");
    expect_equal(v6.port.value_or(0), 8080);
    expect_equal(v6.authority().value_or(""), "[::1]:8080");
    var scoped = Uri.parse("http://[fe80::1%25eth0]:8080/").value();
    expect_equal(scoped.host.value_or(""), "fe80::1%25eth0");
    expect_equal(Uri.decode(scoped.host.value()).value(), "fe80::1%eth0");
    expect_equal(scoped.to_string(), "http://[fe80::1%25eth0]:8080/");
    expect_equal(v6.path_and_query(), "/");

    var empty = Uri.parse("git+ssh://h/?#").value();
    expect_equal(empty.scheme, "git+ssh");
    expect_false(empty.port.is_value());
    expect_equal(empty.query.value_or("x"), "");
    expect_equal(empty.fragment.value_or("x"), "");
    var no_port = Uri.parse("http://h:/").value();
    expect_false(no_port.port.is_value());
    expect_equal(no_port.host.value_or(""), "h");
}

[Test]
parses_relative_references() {
    var target = Uri.parse("/items?page=2").value();
    expect_false(target.is_absolute());
    expect_false(target.host.is_value());
    expect_equal(target.path, "/items");
    expect_equal(target.query.value_or(""), "page=2");
    var net = Uri.parse("//cdn.example.com/lib.js").value();
    expect_equal(net.scheme, "");
    expect_equal(net.host.value_or(""), "cdn.example.com");
    var bare = Uri.parse("a/b:c").value();
    expect_equal(bare.path, "a/b:c");
    expect_false(bare.is_absolute());
    var nothing = Uri.parse("").value();
    expect_equal(nothing.to_string(), "");
    expect_equal(nothing.path_and_query(), "/");
    var fragment = Uri.parse("#part").value();
    expect_equal(fragment.path, "");
    expect_equal(fragment.fragment.value_or(""), "part");
}

[Test]
reports_invalid_uris() {
    for (var text in [
        "a b",
        "1http://x",
        ":x",
        "http://[::1/",
        "http://[::1]x/",
        "http://h:99999/",
        "http://h:8a/",
        "/a%2",
        "/a%zz",
        "/caf\u{E9}"
    ]) {
        expect_true(Uri.parse(text).is_err());
    }
    expect_equal(Uri.parse("http://h:99999/").error().message, "invalid URI 'http://h:99999/': invalid port '99999'");
}

[Test]
decodes_percent_escapes() {
    expect_equal(Uri.decode("caf%C3%A9%21").value(), "caf\u{E9}!");
    expect_equal(Uri.decode("a+b%2Bc").value(), "a+b+c");
    expect_equal(Uri.decode("%ff").value(), "\u{FFFD}");
    expect_true(Uri.decode("100%").is_err());
    expect_true(Uri.decode("%g0").is_err());
    expect_equal(Uri.decode("").value(), "");
}

# RFC 3986 section 5.4: each reference resolved against the RFC's base.
[Test]
resolves_references_as_rfc_3986_does() {
    var base = Uri.parse("http://a/b/c/d;p?q").value();
    var cases = [
        "g:h",
        "g:h",
        "g",
        "http://a/b/c/g",
        "./g",
        "http://a/b/c/g",
        "g/",
        "http://a/b/c/g/",
        "/g",
        "http://a/g",
        "//g",
        "http://g",
        "?y",
        "http://a/b/c/d;p?y",
        "g?y",
        "http://a/b/c/g?y",
        "#s",
        "http://a/b/c/d;p?q#s",
        "g#s",
        "http://a/b/c/g#s",
        "g?y#s",
        "http://a/b/c/g?y#s",
        ";x",
        "http://a/b/c/;x",
        "g;x",
        "http://a/b/c/g;x",
        "",
        "http://a/b/c/d;p?q",
        ".",
        "http://a/b/c/",
        "./",
        "http://a/b/c/",
        "..",
        "http://a/b/",
        "../",
        "http://a/b/",
        "../g",
        "http://a/b/g",
        "../..",
        "http://a/",
        "../../",
        "http://a/",
        "../../g",
        "http://a/g",
        "../../../g",
        "http://a/g",
        "../../../../g",
        "http://a/g",
        "/./g",
        "http://a/g",
        "/../g",
        "http://a/g",
        "g.",
        "http://a/b/c/g.",
        ".g",
        "http://a/b/c/.g",
        "g..",
        "http://a/b/c/g..",
        "..g",
        "http://a/b/c/..g",
        "./../g",
        "http://a/b/g",
        "./g/.",
        "http://a/b/c/g/",
        "g/./h",
        "http://a/b/c/g/h",
        "g/../h",
        "http://a/b/c/h",
        "g;x=1/./y",
        "http://a/b/c/g;x=1/y",
        "g;x=1/../y",
        "http://a/b/c/y",
        "g?y/./x",
        "http://a/b/c/g?y/./x",
        "g?y/../x",
        "http://a/b/c/g?y/../x",
        "g#s/./x",
        "http://a/b/c/g#s/./x",
        "g#s/../x",
        "http://a/b/c/g#s/../x",
        "http:g",
        "http:g",
    ];
    ulong i = 0;
    while (i < cases.count) {
        var resolved = base.resolve(Uri.parse(cases[i]).value());
        expect_equal(resolved.to_string(), cases[i + 1]);
        i = i + 2;
    }
    # A base with an authority and an empty path merges under `/`.
    expect_equal(Uri.parse("http://h").value().resolve(Uri.parse("g").value()).to_string(), "http://h/g");
}

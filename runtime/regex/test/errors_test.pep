# The regex module's errors for invalid patterns, and escaping.

import regex;

error_of(pattern: String): String {
    var result = regex.Regex.parse(pattern);
    if (result.is_ok()) {
        return "<valid>";
    }
    return result.error().message;
}

[Test]
rejects_invalid_patterns() {
    expect_equal(error_of("(a"), "invalid regex '(a': missing ')' at offset 0");
    expect_equal(error_of("a)"), "invalid regex 'a)': unmatched ')' at offset 1");
    expect_equal(error_of("[a"), "invalid regex '[a': missing ']' at offset 0");
    expect_equal(error_of("*a"), "invalid regex '*a': missing argument to repetition operator '*' at offset 0");
    expect_equal(error_of("a**"), "invalid regex 'a**': invalid nested repetition operator at offset 2");
    expect_equal(
        error_of("a{3,2}"), "invalid regex 'a{3,2}': invalid repeat count: minimum is larger than maximum at offset 1"
    );
    expect_equal(error_of("a{1001}"), "invalid regex 'a{1001}': repeat count exceeds 1000 at offset 1");
    expect_equal(error_of("[z-a]"), "invalid regex '[z-a]': invalid character class range at offset 2");
    expect_equal(error_of("(\\w)\\1"), "invalid regex '(\\w)\\1': backreferences are not supported at offset 4");
    expect_equal(error_of("a(?=b)"), "invalid regex 'a(?=b)': lookaround is not supported at offset 1");
    expect_equal(error_of("(?<!a)b"), "invalid regex '(?<!a)b': lookaround is not supported at offset 0");
    expect_equal(error_of("\\q"), "invalid regex '\\q': unknown escape '\\q' at offset 0");
    expect_equal(error_of("a\\"), "invalid regex 'a\\': trailing backslash at offset 1");
    expect_equal(error_of("(?x)a"), "invalid regex '(?x)a': unknown flag 'x' at offset 2");
    expect_equal(error_of("(?<a>x)(?<a>y)"), "invalid regex '(?<a>x)(?<a>y)': duplicate group name 'a' at offset 7");
    expect_equal(error_of("(?<>x)"), "invalid regex '(?<>x)': empty group name at offset 0");
    expect_equal(error_of("[[:nope:]]"), "invalid regex '[[:nope:]]': unknown character class '[:nope:]' at offset 1");
    expect_equal(error_of("\\xZZ"), "invalid regex '\\xZZ': invalid hexadecimal escape at offset 0");
    expect_equal(error_of("[\\d-z]"), "<valid>");
    expect_equal(
        error_of("[a-\\d]"), "invalid regex '[a-\\d]': a class such as '\\d' cannot bound a range at offset 3"
    );
    expect_true(error_of("(a{1000}){1000}").contains("exceeds 100000 instructions"));
    expect_equal(error_of("(?i)"), "<valid>");
    expect_equal(error_of("x{"), "<valid>");

    var deep = "(".repeat(300) + ")".repeat(300);
    expect_true(error_of(deep).contains("groups nest more than 250 deep"));
    var fine = "(".repeat(200) + "a" + ")".repeat(200);
    expect_true(regex.Regex(fine).is_match("a"));

    expect_equal(regex.Regex.escape("1+1=2? [x]"), "1\\+1=2\\? \\[x\\]");
    var literal = "a.b*c(d)|e$^{f}\\";
    expect_equal(regex.Regex(regex.Regex.escape(literal)).find("xx" + literal).value().start(), 2);
}

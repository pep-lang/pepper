# The regex module's searches: iterating over matches, replacing,
# splitting, UTF-8 text and byte offsets, and linear time on patterns that
# make backtracking engines explode.

import regex;

joined(pieces: String[]): String {
    return "|".join(pieces);
}

all(pattern: String, text: String): String {
    var found = Array<String>();
    for (var found_match in regex.Regex(pattern).find_all(text)) {
        found.append(found_match.text());
    }
    return joined(found);
}

[Test]
iterates_replaces_and_splits() {
    expect_equal(all("\\d+", "1 22 333"), "1|22|333");
    expect_equal(all("\\d+", "none"), "");
    # Empty matches: one at each position, but none right after a match.
    expect_equal(all("x*", "ab"), "||");
    expect_equal(all("a*", "aba"), "a|a");
    expect_equal(all("", "é"), "|");

    var offsets = Array<String>();
    for (var found_match in regex.Regex("o").find_all("foo boo")) {
        offsets.append(to_string(found_match.start()));
    }
    expect_equal(joined(offsets), "1|2|5|6");

    var space = regex.Regex("\\s+");
    expect_equal(space.replace_all("a  b\t\nc", " "), "a b c");
    expect_equal(space.replace("a  b  c", "_"), "a_b  c");
    expect_equal(space.replace("abc", "_"), "abc");
    expect_equal(regex.Regex("a*").replace_all("baaac", "-"), "-b-c-");

    var pair = regex.Regex("(\\w+) (?<second>\\w+)");
    expect_equal(pair.replace("hello world", "$2 $1"), "world hello");
    expect_equal(pair.replace("hello world", "${second}-${1}"), "world-hello");
    expect_equal(pair.replace("hello world", "[$0] $$1 $x $"), "[hello world] $1 $x $");
    expect_equal(pair.replace("hello world", "${1}0"), "hello0");
    expect_equal(regex.Regex("(a)|(b)").replace_all("ab", "<$1>"), "<a><>");

    var comma = regex.Regex(",\\s*");
    expect_equal(joined(comma.split("a, b,c")), "a|b|c");
    expect_equal(joined(comma.split(",a,")), "|a|");
    expect_equal(comma.split("abc").count, 1);
    expect_equal(comma.split("").count, 1);

    regex.Match after = regex.Regex("\\d").find_at("1a2b3", 1).value();
    expect_equal(after.text(), "2");
    expect_equal(after.start(), 2);
    expect_false(regex.Regex("\\d").find_at("1a2", 3).is_value());
    # Assertions see the text before the start.
    expect_false(regex.Regex("^a").find_at("aa", 1).is_value());
}

[Test]
matches_code_points_and_reports_byte_offsets() {
    regex.Match found = regex.Regex("é.").find("café!").value();
    expect_equal(found.text(), "é!");
    expect_equal(found.start(), 3);
    expect_equal(found.end(), 6);
    expect_equal(regex.Regex("^.$").find("🙂").value().text(), "🙂");
    expect_equal(regex.Regex("[^a]+").find("a日本a").value().text(), "日本");
    expect_equal(regex.Regex("[à-ÿ]+").find("voilà!").value().text(), "à");
    expect_equal(regex.Regex("\\x{1F642}").find("hi 🙂").value().start(), 3);
    expect_equal(regex.Regex("\\w+").find("été").value().text(), "t");
    expect_equal(regex.Regex(".").replace_all("ñü", "x"), "xx");
}

[Test]
runs_in_linear_time() {
    var a_run = "a".repeat(5000);
    expect_false(regex.Regex("(a*)*b").is_match(a_run));
    expect_equal(regex.Regex("(a|aa)+$").find(a_run).value().end(), 5000);
    expect_false(regex.Regex("(x+x+)+y").is_match("x".repeat(5000)));
    expect_equal(regex.Regex("(a?){30}a{30}").find("a".repeat(30)).value().end(), 30);
    var count = 0;
    for (var found_match in regex.Regex("a").find_all(a_run)) {
        count += 1;
    }
    expect_equal(count, 5000);
}

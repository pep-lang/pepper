# The regex module's pattern syntax: leftmost-first matching, classes,
# repetition, anchors, groups and flags.

import regex;

# The text of the first match of `pattern` in `text`, or "<none>".
first(pattern: String, text: String): String {
    var found = regex.Regex(pattern).find(text);
    if (found.is_empty()) {
        return "<none>";
    }
    return found.value().text();
}

[Test]
matches_the_syntax() {
    expect_equal(first("b+", "abbbc"), "bbb");
    expect_equal(first("a.c", "xabcx"), "abc");
    expect_equal(first("a.c", "a\nc"), "<none>");
    expect_equal(first("[a-c]+", "xxcabz"), "cab");
    expect_equal(first("[^a-c]+", "abxyc"), "xy");
    expect_equal(first("[]a]+", "x]a]y"), "]a]");
    expect_equal(first("[a-]+", "x-a-y"), "-a-");
    expect_equal(first("\\d+", "ab123c"), "123");
    expect_equal(first("\\D+", "12ab3"), "ab");
    expect_equal(first("\\w+", "  hi_9!"), "hi_9");
    expect_equal(first("\\s+", "a \t\nb"), " \t\n");
    expect_equal(first("[\\d.]+", "v1.25!"), "1.25");
    expect_equal(first("[[:alpha:]]+", "12abc3"), "abc");
    expect_equal(first("[[:^digit:]]+", "12abc3"), "abc");
    expect_equal(first("\\x41\\x{42}", "zABz"), "AB");
    expect_equal(first("\\.\\*", "a.*b"), ".*");
    expect_equal(first("a{2}", "aaaa"), "aa");
    expect_equal(first("a{2,}", "aaaa"), "aaaa");
    expect_equal(first("a{1,3}", "aaaa"), "aaa");
    expect_equal(first("a{,2}", "a{,2}"), "a{,2}");
    expect_equal(first("x{0}y", "xy"), "y");
    expect_equal(first("a+?", "aaa"), "a");
    expect_equal(first("a*?b", "aab"), "aab");
    expect_equal(first("a{2,3}?", "aaaa"), "aa");
    expect_equal(first("<.+>", "<a><b>"), "<a><b>");
    expect_equal(first("<.+?>", "<a><b>"), "<a>");
    # Leftmost first: the earliest start wins, then the earlier branch.
    expect_equal(first("b|ab", "ab"), "ab");
    expect_equal(first("a|ab", "ab"), "a");
    expect_equal(first("ab|a", "ab"), "ab");
    expect_equal(first("", "abc"), "");
    expect_equal(first("colou?r", "my color"), "color");
    expect_equal(first("(?:ab)+", "ababa"), "abab");
    # Anchors and word boundaries.
    expect_equal(first("^a", "ba"), "<none>");
    expect_equal(first("a$", "ab"), "<none>");
    expect_equal(first("^a$", "a"), "a");
    expect_equal(first("\\bcat\\b", "concat cat"), "cat");
    expect_equal(regex.Regex("\\bcat\\b").find("concat cat").value().start(), 7);
    expect_equal(first("\\Bat", "at cat"), "at");
    expect_equal(regex.Regex("\\Bat").find("at cat").value().start(), 4);
    expect_equal(first("\\Aa\\z", "a"), "a");
    expect_equal(first("\\Aa", "ba"), "<none>");
    expect_true(regex.Regex("^\\d+$").is_match("2026"));
    expect_false(regex.Regex("^\\d+$").is_match("2026a"));
    expect_false(regex.Regex("x").is_match(""));
    expect_true(regex.Regex("x*").is_match(""));
}

[Test]
reports_groups() {
    var date = regex.Regex("(\\d{4})-(\\d{2})-(\\d{2})");
    expect_equal(date.group_count(), 3);
    var found = date.find("due 2026-10-01!").value();
    expect_equal(found.text(), "2026-10-01");
    expect_equal(found.start(), 4);
    expect_equal(found.end(), 14);
    expect_equal(found.group(0).value(), "2026-10-01");
    expect_equal(found.group(1).value(), "2026");
    expect_equal(found.group(3).value(), "01");
    expect_equal(found.group_count(), 3);
    var (start, end) = found.group_range(2).value();
    expect_equal(start, 9);
    expect_equal(end, 11);

    var named = regex.Regex("(?<key>\\w+)=(?P<value>\\w*)");
    var pair = named.find("x  name=pepper").value();
    expect_equal(pair.group("key").value(), "name");
    expect_equal(pair.group("value").value(), "pepper");
    expect_equal(pair.group(2).value(), "pepper");

    # A group that does not take part is none; an empty one is "".
    regex.Match either = regex.Regex("(a)|(b)").find("b").value();
    expect_false(either.group(1).is_value());
    expect_equal(either.group(2).value(), "b");
    expect_false(either.group_range(1).is_value());
    regex.Match empty = regex.Regex("x(y*)z").find("xz").value();
    expect_equal(empty.group(1).value(), "");

    # A repeated group keeps its last iteration.
    regex.Match last = regex.Regex("(\\w)+").find("abc").value();
    expect_equal(last.group(1).value(), "c");
    # Nested groups are numbered by their opening '('.
    regex.Match nested = regex.Regex("((a)(b))").find("ab").value();
    expect_equal(nested.group(1).value(), "ab");
    expect_equal(nested.group(2).value(), "a");
    expect_equal(nested.group(3).value(), "b");
    expect_equal($"{nested}", "ab");
    expect_equal($"{named}", named.pattern());
}

[Test]
applies_flags() {
    expect_equal(first("(?i)hello", "say HeLLo"), "HeLLo");
    expect_equal(first("(?i)[a-c]+", "xAbCd"), "AbC");
    expect_equal(first("(?i)[^a]+", "AAbB"), "bB");
    expect_equal(first("a(?i:b)c", "aBc aBC"), "aBc");
    expect_equal(first("(?i)a(?-i)b", "AB Ab"), "Ab");
    # A flag set inside a group ends with the group.
    expect_equal(first("((?i)a)a", "AA Aa"), "Aa");
    expect_equal(first("(?m)^b$", "a\nb\nc"), "b");
    expect_equal(first("^b$", "a\nb\nc"), "<none>");
    expect_equal(first("(?m)a$", "a\nb"), "a");
    expect_equal(first("(?s)a.b", "a\nb"), "a\nb");
    expect_equal(first("(?U)a+", "aaa"), "a");
    expect_equal(first("(?U)a+?", "aaa"), "aaa");
    expect_equal(first("(?is)A.B", "a\nb"), "a\nb");
}

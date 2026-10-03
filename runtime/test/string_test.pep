# String: emptiness, UTF-8 length and indexing, substr, find/rfind, prefix
# and suffix, concatenation, comparison, trim/case/lines/repeat, bytes,
# split/join/replace, integer to_string, long.parse, and StringBuilder.

# `prefix`, then the byte `value`, then `suffix`, without validating.
raw(prefix: String, value: u8, suffix: String): String {
    var bytes = Array<u8>();
    for (var b in prefix.bytes()) {
        bytes.append(b);
    }
    bytes.append(value);
    for (var b in suffix.bytes()) {
        bytes.append(b);
    }
    return String(unsafe_cast<__ptr<char>>(bytes._data), bytes.count);
}

[Test]
empty_string() {
    var e = "";
    expect_true(e.is_empty);
    expect_equal(e.length, 0);
    expect_equal(e.size, 0);
    expect_equal(e, "");
}

[Test]
negative_indexing_from_end() {
    var s = "TEST";
    expect_equal(s[-1], "T");
    expect_equal(s[-4], "T");
    expect_equal(s[-3], "E");
}

[Test]
utf8_length_counts_chars_not_bytes() {
    var u = "aé中";
    expect_equal(u.length, 3);
    expect_equal(u.size, 6);
    expect_equal(u[0], "a");
    expect_equal(u[1], "é");
    expect_equal(u[2], "中");
}

[Test]
substr_boundaries() {
    var s = "TEST";
    expect_equal(s.substr(4, 5), "");
    expect_equal(s.substr(0, 99), "TEST");
    expect_equal(s.substr(1, 2), "ES");
    expect_equal(s.substr(3, 1), "T");
}

[Test]
find_and_contains_boundaries() {
    var s = "TEST";
    expect_equal(s.find("TEST"), 0);
    expect_equal(s.find("ZZ"), -1);
    expect_false(s.contains("ZZ"));
    expect_true(s.contains("T"));
    expect_equal(s.find("ST"), 2);
}

[Test]
prefix_suffix_boundaries() {
    var s = "TEST";
    expect_true(s.starts_with(""));
    expect_true(s.ends_with(""));
    expect_false(s.starts_with("TESTING"));
    expect_false(s.ends_with("ESTING"));
    expect_true(s.starts_with("TE"));
    expect_true(s.ends_with("ST"));
}

[Test]
clone_is_independent() {
    var s = "TEST";
    var c = s.clone();
    c.append("!");
    expect_equal(c, "TEST!");
    expect_equal(s, "TEST");
}

[Test]
plus_operator_concatenates() {
    var a = "ab";
    var b = "cd";
    expect_equal(a + b, "abcd");
    expect_equal(a, "ab");
    expect_equal(b, "cd");
    expect_equal("" + "solo", "solo");
}

[Test]
inequality_operator() {
    var s = "TEST";
    expect_true(s != "TESTS");
    expect_true(s != "TETS");
    expect_false(s != "TEST");
    expect_true("a" != "");
}

[Test]
append_grows_capacity() {
    var s = "ab";
    expect_equal(s.size, 2);
    for (var i in 0..64) {
        s += "x";
    }
    expect_equal(s.length, 66);
    expect_equal(s[0], "a");
    expect_equal(s[65], "x");
}

[Test]
equality_ignores_capacity() {
    var a = "hello";
    var b = "";
    b += "he";
    b += "llo";
    expect_true(a == b);
    expect_false(a != b);
}

[Test]
utf8_find_and_substr() {
    var u = "aé中";
    expect_equal(u.find("中"), 3);
    expect_true(u.contains("é"));
    expect_equal(u.substr(1, 2), "é中");
    expect_equal(u.substr(0, 1), "a");
}

[Test]
byte_access_substr_bytes_and_compare() {
    var s = "a=b";
    expect_true(s.byte_at(1) == '=');
    var key_value = "key=value";
    var equals = key_value.find("=") as ulong;
    expect_equal(key_value.substr_bytes(0, equals), "key");
    expect_equal(key_value.substr_bytes(equals + 1, key_value.size - equals - 1), "value");
    expect_equal(key_value.substr_bytes(3, 0), "");
    expect_equal("aé".substr_bytes(1, 2).length, 1);
    expect_true("apple".compare("banana") < 0);
    expect_true("banana".compare("apple") > 0);
    expect_true("ab".compare("abc") < 0);
    expect_equal("x".compare("x"), 0);
    expect_equal("".compare(""), 0);
    expect_true("a" < "b" && "b" > "a" && "a" <= "a" && "a" >= "a");
    expect_false("b" < "a");
    expect_false("a" > "b");
}

[Test]
trim_case_lines_and_repeat() {
    expect_equal("code;  \r\n".trim_end(), "code;");
    expect_equal("   ".trim_end(), "");
    expect_equal("  x".trim_end(), "  x");
    var lines = "first\r\nsecond\n\nfourth".lines();
    expect_equal(lines.count, 4);
    expect_equal(lines[0], "first");
    expect_equal(lines[1], "second");
    expect_equal(lines[2], "");
    expect_equal(lines[3], "fourth");
    expect_equal("a\nb\n".lines().count, 2);
    expect_equal("".lines().count, 0);
    expect_equal("\n".lines().count, 1);
    expect_equal("ab".repeat(3), "ababab");
    expect_equal("é".repeat(2).length, 2);
    expect_equal("x".repeat(0), "");
    expect_equal("".repeat(5), "");
    expect_equal("  \tcode".trim_start(), "code");
    expect_equal(" \t value \r\n".trim(), "value");
    expect_equal("   ".trim(), "");
    expect_equal("Content-Type 1".lower(), "content-type 1");
    expect_equal("get ÄÖ".upper(), "GET ÄÖ");
    expect_equal("Ärger".lower(), "Ärger");
    expect_equal("Ärger".lower().length, 5);
    expect_equal("".upper(), "");
}

[Test]
bytes_and_from_bytes() {
    var data = "hé".bytes();
    expect_equal(data.count, 3);
    expect_equal(data[0], 104);
    expect_equal(data[1], 195);
    expect_equal(data[2], 169);
    expect_equal(String._from_bytes(data), "hé");
    expect_equal(String._from_bytes(data).length, 2);
    data.append(255);
    data.append(105);
    expect_equal(String._from_bytes(data), "hé\u{FFFD}i");
    expect_equal(String._from_bytes(data).length, 4);
    var cut = Array<u8>();
    cut.append(226);
    cut.append(130);
    expect_equal(String._from_bytes(cut), "\u{FFFD}\u{FFFD}");
    var surrogate = Array<u8>();
    surrogate.append(237);
    surrogate.append(160);
    surrogate.append(128);
    expect_equal(String._from_bytes(surrogate).length, 3);
    expect_equal(String._from_bytes(Array<u8>()), "");
}

[Test]
integer_to_string() {
    expect_equal(to_string(-42), "-42");
    expect_equal(to_string(0), "0");
    int line = 3;
    expect_equal(to_string(line), "3");
    ulong big = 0xFFFFFFFFFFFFFFFF;
    expect_equal(to_string(big), "18446744073709551615");
    long small = -9223372036854775807 - 1;
    expect_equal(to_string(small), "-9223372036854775808");
    byte b = 200;
    expect_equal(to_string(b), "200");
    uint u = 7;
    expect_equal(to_string(u), "7");
    short s = -5;
    expect_equal(to_string(s), "-5");
    ushort us = 5;
    expect_equal(to_string(us), "5");
    char c = -1;
    expect_equal(to_string(c), "-1");
}

[Test]
string_builder() {
    var out = StringBuilder();
    expect_true(out.is_empty);
    expect_equal(out.to_string(), "");
    out.append("line ").append(to_string(3)).append("\n");
    expect_equal(out.to_string(), "line 3\n");
    expect_equal(out.length, 7);
    expect_equal(out.size, 7);
    var many = StringBuilder(4);
    for (var i in 0..1000) {
        many.append("é");
    }
    var t = many.to_string();
    expect_equal(t.length, 1000);
    expect_equal(t.size, 2000);
    many.clear();
    expect_true(many.is_empty);
    expect_equal(many.to_string(), "");
    many.append("again");
    expect_equal(many.to_string(), "again");
}

[Test]
find_from_rfind_split_join_replace() {
    expect_equal("a,b,c".find(",", 2), 3);
    expect_equal("a,b,c".find(",", 4), -1);
    expect_equal("a,b,c".find(",", 99), -1);
    expect_equal("héllo".find("l", 1), 3);
    expect_equal("a/b/c".rfind("/"), 3);
    expect_equal("abc".rfind("x"), -1);
    expect_equal("abc".rfind(""), 3);
    expect_equal("abcabc".rfind("abc"), 3);
    var parts = "a,b,,c".split(",");
    expect_equal(parts.count, 4);
    expect_equal(parts[2], "");
    expect_equal(parts[3], "c");
    expect_equal("".split(",").count, 1);
    expect_equal(",a,".split(",").count, 3);
    expect_equal("a--b".split("--").count, 2);
    var once = "Host: x: y".split_once(": ");
    expect_true(once.is_value());
    var (name, value) = once.value();
    expect_equal(name, "Host");
    expect_equal(value, "x: y");
    expect_false("abc".split_once(":").is_value());
    expect_equal(", ".join(parts), "a, b, , c");
    expect_equal(", ".join(Array<String>()), "");
    expect_equal("aaa".replace("aa", "b"), "ba");
    expect_equal("a\r\nb\r\n".replace("\r\n", "\n"), "a\nb\n");
    expect_equal("héllo wörld".replace("ö", "o"), "héllo world");
    expect_equal("abc".replace("x", "y"), "abc");
}

# The UTF-8 helpers skip ASCII eight bytes at a time once aligned, and `find`
# uses `memmem`, then checks only the bytes before the match. Puts the
# non-ASCII byte at every offset around the 8-byte steps, and invalid bytes
# before and after a match.
[Test]
utf8_scans_across_word_boundaries() {
    for (var at in 0..40) {
        var offset = at as ulong;
        var s = "a".repeat(offset) + "é" + "b".repeat(40 - offset);
        expect_equal(s.length, 41);
        expect_equal(s.find("é"), at as long);
        expect_equal(s.find("b"), (at + 2) as long);
        expect_equal(s.substr(offset, 1), "é");
        expect_equal(s.substr(offset + 1, 1), "b");
        if (at > 0) {
            expect_equal(s.substr(offset - 1, 1), "a");
        }
        # A lone continuation byte makes the length 0.
        var bad = raw("a".repeat(offset), 0x80, "b".repeat(40 - offset));
        expect_equal(bad.length, 0);
    }
    var before = raw("ab", 0xFF, "cd");
    expect_equal(before.find("cd"), -1);
    expect_equal(before.find("ab"), 0);
    var after = raw("ab", 0xC3, "cd");
    expect_equal(after.find("b"), 1);
    expect_equal(after.find("d"), -1);
    expect_equal("héllo".find("l", 2), -1);
    expect_equal("héllo".find("é"), 1);
    expect_equal("x".find("xy"), -1);
    # split and replace stop at the first separator with invalid UTF-8 before
    # it, as `find` from there would.
    var mixed = raw("a,b", 0xFF, ",c");
    expect_equal(mixed.split(",").count, 2);
    expect_equal(mixed.split(",")[0], "a");
    expect_equal(mixed.replace(",", ";").find(";"), 1);
    expect_equal(mixed.replace(",", ";").size, mixed.size);
    expect_equal("é,ü,".split(",").count, 3);
    expect_equal("é,ü,".replace(",", ""), "éü");
}

# #511: `find` re-checked that the whole rest of the String was valid UTF-8
# on every call, so `split`, `replace` and a `find(_, from)` loop were
# quadratic. Linear, they take milliseconds; quadratic, this 240 KB text
# takes about two minutes, past the runner's timeout.
[Test]
find_split_replace_are_linear() {
    var text = "wörd,".repeat(40000);
    expect_equal(text.split(",").count, 40001);
    expect_equal(text.replace(",", ";").size, text.size);
    ulong found = 0;
    var at = text.find(",");
    while (at >= 0) {
        found = found + 1;
        at = text.find(",", (at as ulong) + 1);
    }
    expect_equal(found, 40000);
}

[Test]
long_parse() {
    expect_equal(long.parse("-42").value(), -42);
    expect_equal(long.parse("+7").value(), 7);
    expect_equal(long.parse("ff", 16).value(), 255);
    expect_equal(long.parse("FF", 16).value(), 255);
    expect_equal(long.parse("101", 2).value(), 5);
    expect_equal(long.parse("z", 36).value(), 35);
    expect_false(long.parse("12x").is_value());
    expect_false(long.parse("").is_value());
    expect_false(long.parse("-").is_value());
    expect_false(long.parse(" 1").is_value());
    expect_false(long.parse("2", 2).is_value());
    expect_equal(long.parse("9223372036854775807").value(), 9223372036854775807);
    expect_false(long.parse("9223372036854775808").is_value());
    expect_equal(long.parse("-9223372036854775808").value(), -9223372036854775807 - 1);
    expect_false(long.parse("-9223372036854775809").is_value());
    expect_false(long.parse("99999999999999999999999").is_value());
}

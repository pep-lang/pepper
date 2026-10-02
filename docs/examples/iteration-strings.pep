main(): int {
    var word = "héllo ✓";

    # A String yields one code point at a time, as a one-code-point String.
    var count = 0;
    var copy = "";
    for (var c in word) {
        assert(c.length == 1, "each piece is one code point");
        copy.append(c);
        count = count + 1;
    }
    assert(count == 7, "7 code points");
    assert(copy == word, "the pieces rebuild the string");

    # Each piece is the same value as indexing the string.
    var i = 0;
    for (var c in word) {
        assert(c == word[i], "same as word[i]");
        i = i + 1;
    }

    # An empty string runs the body zero times.
    for (var c in "") {
        assert(false, "never runs");
    }
    return 0;
}

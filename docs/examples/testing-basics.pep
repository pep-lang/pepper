# Counts the words in `text`: the runs of characters between spaces.
word_count(text: String): ulong {
    ulong count = 0;
    for (var word in text.split(" ")) {
        if (!word.is_empty) {
            count += 1;
        }
    }
    return count;
}

[Test]
counts_the_words() {
    expect_equal(word_count("salt and pepper"), 3);
    expect_equal(word_count("  spaced   out "), 2);
}

[Test]
an_empty_string_has_no_words() {
    expect_equal(word_count(""), 0);
    expect_true(word_count(" ") == 0);
}

[Test]
[ShouldPanic("out of bounds")]
reading_past_the_last_word_panics() {
    var words = "salt pepper".split(" ");
    var third = words[2];
}

# A normal build leaves the tests out and runs this.
main(): int {
    print(word_count("salt and pepper"));
    return 0;
}

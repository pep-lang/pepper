# Every simple statement ends with a `;`; line breaks mean nothing.
is_small(n: int): bool {
    return n > 0 && n < 10;
}

main(): int {
    var width = 3;
    var height = 4; var depth = 5;

    # A statement may span several lines, breaking before or after an
    # operator.
    var volume = width * height
        * depth;
    assert(volume == 60, "3 * 4 * 5");

    var in_range = is_small(width)
        && is_small(height)
        && !is_small(volume);
    assert(in_range, "3 and 4 are small; 60 is not");

    var words = Array<String>();
    words.append("line");
    words.append("breaks");
    var long_words = 0;
    # A chain of calls may break before each `.`.
    for (var word in words
        .iterate()
        .filter((w) => w.length() > 4)) {  # comments are fine anywhere
        long_words += 1;
    }
    assert(long_words == 1, "one word is longer than four characters");

    # So may a call's arguments.
    assert(volume + words[0].length() == 64,
        "60 + 4");
    return 0;
}

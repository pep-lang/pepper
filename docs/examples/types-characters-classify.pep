# Classify and convert ASCII characters, as C's ctype.h does.
main(): int {
    assert('7'.is_digit() and 'f'.is_hex_digit(), "digits");
    assert('q'.is_alphabetic() and 'Q'.is_upper() and 'q'.is_lower(), "letters");
    assert('\t'.is_whitespace() and '\t'.is_blank(), "whitespace");
    assert(';'.is_punctuation() and !'_'.is_alphanumeric(), "punctuation");
    assert('\n'.is_control() and !'\n'.is_printable(), "control");
    assert('a'.to_upper() == 'A' and '?'.to_upper() == '?', "case");

    # The digit's value in a base, or none when it is not a digit there.
    assert('F'.digit_value(16).value() == 15, "hexadecimal");
    assert('9'.digit_value(8).is_empty(), "not an octal digit");

    # Count the words and digits of a String, a byte at a time.
    var text = "Call 555-0100 at 9 a.m.";
    var words = 0;
    var digits = 0;
    var in_word = false;
    for (var b in text.bytes()) {
        if (b.is_digit()) {
            digits = digits + 1;
        }
        if (b.is_alphanumeric() and !in_word) {
            words = words + 1;
        }
        in_word = b.is_alphanumeric();
    }

    # A char answers the same, and bytes above 127 (negative as a char)
    # are never letters.
    char e_acute = -61;   # the first byte of "é" in UTF-8
    assert(!e_acute.is_alphabetic() and !e_acute.is_ascii(), "not ASCII");

    print($"{words} words, {digits} digits");   # 7 words, 8 digits
    return 0;
}

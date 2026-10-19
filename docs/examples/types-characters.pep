# Character literals are bytes.
is_lower(c: int): bool {
    return c >= 'a' and c <= 'z';
}

main(): int {
    var letter = 'a';   # a byte holding 97
    assert(letter == 97, "a character literal is its ASCII code");
    assert('"' == 34 and '\n' == 10 and '\'' == 39, "escapes work as in strings");

    # Compare the bytes of a String with character literals.
    var text = "x = 1";
    var bytes = text.c_str();
    assert(bytes[0] == 'x' and bytes[2] == '=', "compare raw bytes");
    assert(is_lower(bytes[0]), "a byte widens to int");

    # Arithmetic works as on any integer.
    int digit = bytes[4] - '0';
    assert(digit == 1, "the digit's value");

    print($"{letter}");   # 97
    return 0;
}

# Output:
# 97

# String.format: braces name the arguments by position.
main(): int {
    var a = 2;
    var b = 3;
    assert(String.format("{0} + {1} = {2}", a, b, a + b) == "2 + 3 = 5", "in order");

    # An index can repeat or come out of order, with its own specification.
    assert(String.format("{1} before {0}", "first", "second") == "second before first", "reordered");
    assert(String.format("{0} is {0:x} in hex", 255) == "255 is ff in hex", "repeated");
    assert(String.format("[{0:>4}] {{literal}}", a) == "[   2] {literal}", "padding and braces");
    return 0;
}

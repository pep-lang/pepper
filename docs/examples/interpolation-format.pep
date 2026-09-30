# Format specifications: padding, signs and other bases after a `:`.
main(): int {
    var count = 42;
    var name = "Pepper";

    # Width and alignment pad any value; numbers go right by default.
    assert($"[{count:6}]" == "[    42]", "a number goes right");
    assert($"[{name:10}]" == "[Pepper    ]", "text goes left");
    assert($"[{name:>10}]" == "[    Pepper]", "right");
    assert($"[{name:*^10}]" == "[**Pepper**]", "centered with a fill");

    # Integers take a sign, zero padding and a base.
    assert($"{count:+}" == "+42", "a plus sign");
    assert($"{count:05}" == "00042", "zero padding");
    assert($"{255:x} {255:X} {5:b} {8:o}" == "ff FF 101 10", "bases");
    assert($"0x{255:08x}" == "0x000000ff", "padded hexadecimal");
    assert($"{-42:x}" == "-2a", "a negative number keeps its sign");

    # The `:` after the whole expression starts the specification.
    assert($"[{count > 1 ? "many" : "one":>5}]" == "[ many]", "a ternary");
    return 0;
}

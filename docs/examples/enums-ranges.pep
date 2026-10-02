# Range and constant patterns: a `match` on an integer or a character
# compares with ranges (`1..9`, `'a'..>'z'`) and module-scope constants.
const LIMIT = 100;

size(n: int): String {
    return match (n) {
        0 => "none",
        # `1..10` stops before 10; `10..>99` includes 99.
        1..10 => "a few",
        10..>99 => "many",
        LIMIT => "the limit",
        else => "out of range",
    };
}

kind(c: char): String {
    return match (c) {
        'a'..>'z', 'A'..>'Z' => "letter",
        '0'..>'9' => "digit",
        else => "other",
    };
}

# Ranges that cover every value of the type need no `else`.
half(b: u8): int {
    return match (b) {
        0..128 => 0,
        128..>255 => 1,
    };
}

main(): int {
    assert(size(0) == "none" && size(9) == "a few" && size(10) == "many", "ranges");
    assert(size(100) == "the limit" && size(-1) == "out of range", "a constant, then else");
    assert(kind('q') == "letter" && kind('7') == "digit" && kind('!') == "other", "character ranges");
    u8 high = 200;
    assert(half(3) == 0 && half(high) == 1, "every u8 is handled");

    # In a tuple pattern, a range or a constant compares its element.
    var pair = (LIMIT, true);
    var which = match (pair) {
        (0..LIMIT, _) => 1,
        (LIMIT, true) => 2,
        (_, _) => 3,
    };
    assert(which == 2, "the constant matches the first element");
    return 0;
}

# Arithmetic that overflows panics; these methods say what to do instead.
main(): int {
    int big = 2147483647;

    # big + 1 would stop the program: "integer overflow in 'int' addition".
    # wrapping_ wraps around, as C's unsigned arithmetic does.
    assert(big.wrapping_add(1) == -2147483648, "wraps to the lowest int");

    # checked_ returns none on overflow.
    assert(big.checked_add(1).is_none(), "no int is big + 1");
    assert(big.checked_sub(1).value() == 2147483646, "big - 1 fits");

    # saturating_ clamps to the type's range.
    assert(big.saturating_mul(2) == 2147483647, "clamped to the highest int");
    byte level = 10;
    assert(level.saturating_sub(20) == 0, "a byte stops at 0");

    # overflowing_ returns the wrapped result and whether it overflowed.
    var (product, overflowed) = big.overflowing_mul(2);
    assert(product == -2 && overflowed, "wrapped, and overflowed");

    # A hash multiplies with wrapping on purpose (FNV-1a).
    ulong hash = 0xcbf29ce484222325;
    var text = "pepper";
    for (var i in 0..text.size) {
        hash = (hash ^ (text.byte_at(i) as ulong)).wrapping_mul(0x100000001b3);
    }
    assert(hash == 0xac11131d51a77079, "the FNV-1a hash of 'pepper'");
    return 0;
}

# Bit operations on integers: counting, reversing and rotating bits.
main(): int {
    uint mask = 0x00F0;
    assert(mask.trailing_zeros() == 4, "the lowest set bit is bit 4");
    assert(mask.leading_zeros() == 24, "the highest set bit is bit 7");
    assert(mask.count_ones() == 4, "four bits are set");

    # Zero has no set bit: its counts are the type's width.
    assert((0 as ulong).trailing_zeros() == 64, "no set bit");

    # The methods work at their type's own width.
    byte low = 1;
    assert(low.leading_zeros() == 7, "a byte has 8 bits");
    assert(low.rotate_right(1) == 0x80, "the bottom bit comes back at the top");

    # Byte order: swap_bytes converts between little and big endian.
    assert((0x12345678 as uint).swap_bytes() == 0x78563412, "bytes reversed");
    assert((1 as uint).reverse_bits() == 0x80000000, "bits reversed");

    # min, max and abs.
    assert((-7).abs() == 7, "without its sign");
    assert((3).min(5) == 3 && (3).max(5) == 5, "smaller and larger");
    return 0;
}

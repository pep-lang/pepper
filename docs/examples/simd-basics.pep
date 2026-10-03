import simd;

# The index of the first byte of `text` that is not ASCII, or its size:
# sixteen bytes per step, then one at a time for the rest.
first_non_ascii(text: String): ulong {
    var bytes = unsafe_cast<__ptr<byte>>(text.c_str());
    ulong i = 0;
    while (i + 16 <= text.size) {
        var high = simd.Vector<byte, 16>.load(bytes + i).greater_equal(0x80 as byte).to_bits();
        if (high != 0) {
            return i + high.trailing_zeros();
        }
        i = i + 16;
    }
    while (i < text.size && bytes[i] < 0x80) {
        i = i + 1;
    }
    return i;
}

main(): int {
    # A vector holds `N` lanes and computes on all of them at once.
    var a = simd.Vector<int, 4>(10);
    a[1] = 20;
    var b = a * 2 + 1;
    assert(b[0] == 21 && b[1] == 41 && b.sum() == 104, "lane-wise arithmetic");

    # A comparison gives a mask, one bool per lane.
    var big = b.greater(30);
    assert(big.to_bits() == 2 && big.any() && !big.all(), "a mask");
    var capped = big.select(simd.Vector<int, 4>(30), b);
    assert(capped.maximum() == 30, "select");

    # Floats, and conversions between lane types.
    var halves = a.convert<float>() * 0.5;
    assert(halves[1] == 10.0 && halves.square_root()[0] < 2.3, "floats");

    assert(first_non_ascii("plain ascii, then caf\u{e9}") == 21, "a scan");
    assert(first_non_ascii("short") == 5, "no match");
    return 0;
}

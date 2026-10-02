# Floating-point functions: square root, rounding, sign and fused
# multiply-add.
main(): int {
    var side = (2.0).square_root();
    assert(side * side > 1.999 && side * side < 2.001, "close to 2");

    assert((-1.5).floor() == -2.0, "toward negative infinity");
    assert((-1.5).ceiling() == -1.0, "toward positive infinity");
    assert((-1.5).truncate() == -1.0, "toward zero");
    assert((2.5).round() == 3.0, "halfway cases away from zero");

    assert((-4.0).abs() == 4.0, "without its sign");
    assert((4.0).copy_sign(-1.0) == -4.0, "the sign of the argument");
    assert((2.0).multiply_add(3.0, 1.0) == 7.0, "2 * 3 + 1, rounded once");
    assert((1.5).min(-2.0) == -2.0 && (1.5).max(-2.0) == 1.5, "smaller and larger");
    return 0;
}

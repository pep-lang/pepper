# The math module's constants, gcd and lcm, and the floating-point methods
# of float and double: trigonometry, hyperbolic functions, exponentials,
# logarithms, roots, remainders and classification.

import math;

# Whether `actual` is within `tolerance` of `expected`.
private close(actual: double, expected: double, tolerance: double = 1e-12): bool {
    return (actual - expected).abs() <= tolerance;
}

[Test]
constants() {
    expect_true(close(math.TAU, 2 * math.PI, 0));
    expect_true(close(math.E.logarithm(), 1));
    expect_true(math.INFINITY.is_infinite() && !math.INFINITY.sign_bit());
    expect_true((-math.INFINITY).is_infinite() && (-math.INFINITY).sign_bit());
    expect_true(math.NAN.is_nan());
    expect_true(1.0 + math.DOUBLE_EPSILON != 1.0);
    expect_true(1.0 + math.DOUBLE_EPSILON / 2 == 1.0);
    expect_true(math.DOUBLE_MAX.is_finite() && (math.DOUBLE_MAX * 2).is_infinite());
    expect_true(math.DOUBLE_MIN_POSITIVE > 0);
    float one = 1.0;
    expect_true(one + math.FLOAT_EPSILON != one);
    expect_true(math.FLOAT_MAX.is_finite() && math.FLOAT_MIN_POSITIVE > 0);
}

[Test]
trigonometry() {
    expect_true(close((math.PI / 6).sine(), 0.5));
    expect_true(close((math.PI / 3).cosine(), 0.5));
    expect_true(close((math.PI / 4).tangent(), 1));
    expect_true(close((0.5).arc_sine(), math.PI / 6));
    expect_true(close((0.5).arc_cosine(), math.PI / 3));
    expect_true(close((1.0).arc_tangent(), math.PI / 4));
    expect_true((2.0).arc_sine().is_nan());
    expect_true(close((1.0).arc_tangent2(-1.0), 3 * math.PI / 4));
    expect_true(close((-1.0).arc_tangent2(-1.0), -3 * math.PI / 4));
    float quarter = (math.PI / 2) as float;
    expect_true(close(quarter.sine() as double, 1, 1e-6));
}

[Test]
hyperbolic() {
    expect_true(close((1.0).hyperbolic_sine(), (math.E - 1 / math.E) / 2));
    expect_true(close((1.0).hyperbolic_cosine(), (math.E + 1 / math.E) / 2));
    expect_true(close((1.0).hyperbolic_tangent().arc_hyperbolic_tangent(), 1));
    expect_true(close((2.0).hyperbolic_sine().arc_hyperbolic_sine(), 2));
    expect_true(close((2.0).hyperbolic_cosine().arc_hyperbolic_cosine(), 2));
    expect_true((0.5).arc_hyperbolic_cosine().is_nan());
}

[Test]
exponentials_and_logarithms() {
    expect_true(close((1.0).exponential(), math.E));
    expect_equal((10.0).exponential2(), 1024.0);
    expect_equal((1024.0).logarithm2(), 10.0);
    expect_equal((100.0).logarithm10(), 2.0);
    expect_true(close(math.E.logarithm(), 1));
    expect_true((0.0).logarithm() == -math.INFINITY);
    expect_true((-1.0).logarithm().is_nan());
    # Near zero, the one-step forms keep digits that `exp(x) - 1` loses.
    var tiny = 1e-20;
    expect_equal(tiny.exponential_minus_one(), tiny);
    expect_equal(tiny.logarithm_one_plus(), tiny);
    expect_equal(tiny.exponential() - 1, 0.0);
    float f = 3.0;
    expect_true(f.exponential2() == 8.0 && (8.0 as float).logarithm2() == 3.0);
}

[Test]
roots_and_remainders() {
    expect_equal((-8.0).cube_root(), -2.0);
    expect_equal((3.0).hypotenuse(4.0), 5.0);
    expect_true(math.DOUBLE_MAX.hypotenuse(1.0).is_finite());
    expect_equal((7.0).remainder(2.0), -1.0);
    expect_equal((5.0).remainder(2.0), 1.0);
    expect_equal(7.0 % 2.0, 1.0);
    expect_true((1.0).remainder(0.0).is_nan());
    expect_equal(2.0 ** 10, 1024.0);
    float f = 27.0;
    expect_true(f.cube_root() == 3.0 && (f.remainder(5.0)) == 2.0);
}

[Test]
classification() {
    expect_true(!(1.0).is_nan() && !(1.0).is_infinite() && (1.0).is_finite());
    expect_true(math.NAN.is_nan() && !math.NAN.is_infinite() && !math.NAN.is_finite());
    expect_true(!math.INFINITY.is_nan() && !math.INFINITY.is_finite());
    expect_true((-0.0).sign_bit() && !(0.0).sign_bit() && (-2.0).sign_bit());
    float f = -0.0;
    expect_true(f.sign_bit() && !f.is_nan() && f.is_finite());
}

[Test]
greatest_common_divisor_and_least_common_multiple() {
    expect_equal(math.gcd(12, 18), 6 as long);
    expect_equal(math.gcd(-12, 18), 6 as long);
    expect_equal(math.gcd(0, 5), 5 as long);
    expect_equal(math.gcd(0, 0), 0 as long);
    expect_equal(math.lcm(4, 6), 12 as long);
    expect_equal(math.lcm(-4, 6), 12 as long);
    expect_equal(math.lcm(0, 6), 0 as long);
}

[Test]
[ShouldPanic("overflow")]
lcm_overflow_panics() {
    math.lcm(9223372036854775807, 2);
}

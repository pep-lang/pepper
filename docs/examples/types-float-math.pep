# Floating-point math: trigonometry, logarithms, powers, classification,
# and the math module's constants and integer functions.
import math;

main(): int {
    var angle = math.PI / 6;
    assert((angle.sine() - 0.5).abs() < 1e-12, "sin 30 degrees is 1/2");
    assert(((1.0).arc_tangent2(1.0) - math.PI / 4).abs() < 1e-12, "45 degrees");

    assert((1024.0).logarithm2() == 10.0, "2 to the 10th is 1024");
    assert((1.0).exponential() == math.E, "e to the 1st");
    assert(2.0 ** 10 == 1024.0 && (-8.0).cube_root() == -2.0, "powers and roots");
    assert((3.0).hypotenuse(4.0) == 5.0, "a 3-4-5 triangle");

    assert(math.NAN.is_nan() && math.NAN != math.NAN, "NaN is not equal to itself");
    assert(math.INFINITY.is_infinite() && !math.INFINITY.is_finite(), "infinite");
    assert((-0.0).sign_bit() && !(-0.0 < 0), "negative zero");

    assert(math.gcd(12, 18) == 6 && math.lcm(4, 6) == 12, "integers");
    return 0;
}

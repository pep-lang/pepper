# Operators on numbers and booleans.
main(): int {
    # Arithmetic.
    assert(2 + 3 * 4 == 14, "* binds tighter than +");
    assert((2 + 3) * 4 == 20, "parentheses group");
    assert(17 % 5 == 2, "remainder");
    assert(-(3) == -3, "negation");

    # Exponentiation is right-associative: 2 ** 3 ** 2 is 2 ** 9.
    assert(2 ** 10 == 1024, "power");
    assert(2 ** 3 ** 2 == 512, "right-associative");
    # With a floating-point operand, the result is floating point.
    assert(2.0 ** -2 == 0.25, "float power");
    assert(9 ** 0.5 == 3.0, "square root");

    # Comparison yields a bool.
    var small = 3 < 5;
    assert(small, "3 < 5");
    assert(5 >= 5 && 4 <= 5 && 6 > 5 && 5 == 5 && 5 != 6, "comparisons");
    # On numbers, `===` and `!==` are the same as `==` and `!=`.
    assert(5 === 5 && 5 !== 6, "identity on numbers");

    # Logical operators; 'and' and 'or' are spellings of && and ||.
    var t = true;
    var f = false;
    assert(t && !f, "and, not");
    assert(f || t, "or");
    assert(t and (f or t), "word forms");

    # Bitwise operators.
    assert((6 & 3) == 2, "and");
    assert((6 | 3) == 7, "or");
    assert((6 ^ 3) == 5, "exclusive or");
    assert(~0 == -1, "complement");
    assert(1 << 4 == 16 && 256 >> 2 == 64, "shifts");

    # Compound assignment and increment.
    var n = 5;
    n += 3;   # 8
    n -= 2;   # 6
    n *= 4;   # 24
    n /= 5;   # 4
    n %= 3;   # 1
    n <<= 3;  # 8
    n >>= 1;  # 4
    n &= 6;   # 4
    assert(n == 4, "compound assignment");
    n++;
    ++n;
    n--;
    assert(n == 5, "increment and decrement");

    # The conditional (ternary) operator.
    var sign = n > 0 ? "positive" : "not positive";
    assert(sign == "positive", "ternary");
    return 0;
}

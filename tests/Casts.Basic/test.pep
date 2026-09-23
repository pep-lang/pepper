main(): int {
    # float -> int truncates toward zero (static_cast semantics).
    var e = 1.5e2 as int;
    if (e != 150) { return -1; }

    # int narrowing keeps the low bits.
    var w = 300 as byte;
    if (w != 44) { return -2; }

    # bool widening zero-extends: true == 1, not -1.
    var b = true as int;
    if (b != 1) { return -3; }

    # int -> float widens.
    var f = 7 as float;
    if (f != 7.0) { return -4; }

    # cast binds tighter than unary: -(x as int).
    var n = -(2.9 as int);
    if (n != -2) { return -5; }

    return 0;
}

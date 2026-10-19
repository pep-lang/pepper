# Each cast runs on a value read at run time (the program's argument count
# is 1), so none folds to a constant.
main(args: String[]): int {
    var one = args.count as int;
    var one_and_a_half = 1.5 * (one as double);

    # float -> int truncates toward zero (static_cast semantics).
    var e = (one_and_a_half * 100.0) as int;
    if (e != 150) { return -1; }

    # int narrowing keeps the low bits.
    var w = (300 * one) as byte;
    if (w != 44) { return -2; }

    # bool widening zero-extends: true == 1, not -1.
    var b = (one == 1) as int;
    if (b != 1) { return -3; }

    # int -> float widens.
    var f = (7 * one) as float;
    if (f != 7.0) { return -4; }

    # cast binds tighter than unary: -(x as int).
    var n = -((2.9 * (one as double)) as int);
    if (n != -2) { return -5; }

    return 0;
}

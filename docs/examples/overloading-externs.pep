# C's `abs` and `llabs` behind one Pepper name. An extern binds one C
# symbol, so each gets its own name, and Pepper functions overload them.
[Link(name = "abs")]
extern int c_abs(int x);
[Link(name = "llabs")]
extern long c_llabs(long x);

magnitude(x: int): int { return c_abs(x); }
magnitude(x: long): long { return c_llabs(x); }

main(): int {
    assert(magnitude(-3) == 3, "int");
    var big: long = -5000000000;
    assert(magnitude(big) == 5000000000, "long");
    return 0;
}

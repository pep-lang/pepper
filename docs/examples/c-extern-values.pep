# An extern function is a function value, like a Pepper function.
extern int abs(int x);
extern ulong strlen(char* s);

apply(f: (int) => int, x: int): int {
    return f(x);
}

main(): int {
    # Its type comes from the prototype: `abs` is an `(int) => int`.
    var absolute = abs;
    assert(absolute(-3) == 3, "through a local");
    assert(apply(abs, -4) == 4, "as an argument");

    # A `char*` parameter is a `__ptr<char>` in the function type.
    var length: (__ptr<char>) => ulong = strlen;
    var word = "four";
    assert(length(word.c_str()) == 4, "strlen");

    # Where a C function pointer is expected, it is the C function itself.
    var pointer: extern (int) => int = abs;
    assert(pointer(-5) == 5, "C function pointer");
    return 0;
}

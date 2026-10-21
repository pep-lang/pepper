# Externs bound to C symbols that Pepper functions are named after: `abs`
# here, and `exit`, the deprecated prelude's. Each call reaches its own
# function, so the program exits with 3 + 97.

[Link(name = "abs")]
extern int c_abs(int value);

[Link(name = "exit")]
extern void c_exit(int status);

abs(value: int): int {
    return value + 100;
}

main(): int {
    c_exit(c_abs(-3) + abs(-3));
    return 0;
}

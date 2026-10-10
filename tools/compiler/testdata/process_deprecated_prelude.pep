# The deprecated prelude `arguments()` and `exit()` (programs_test.pep).

main(): int {
    if (arguments().count == 2) {
        exit(4);
    }
    return 0;
}

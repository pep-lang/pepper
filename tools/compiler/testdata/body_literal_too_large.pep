# A literal past `ulong`'s range in a function body, which the build reads
# after the declarations: the error shows the line (`programs_test.pep`).
main(): int {
    ulong a = 18446744073709551616;
    return 0;
}

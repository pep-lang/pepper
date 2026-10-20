# A member String does not have, in an interpolation: the error names the
# member (`programs_test.pep`).
main(): int {
    var s = "hello";
    print($"{s} {s.count}");
    return 0;
}

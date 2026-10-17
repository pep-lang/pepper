# A program's own `arguments` function, which `main`'s arguments ignore
# (programs_test.pep).

arguments(base: int): int {
    return base;
}

main(args: String[]): int {
    return (args.count as int) * 10 + arguments(9);
}

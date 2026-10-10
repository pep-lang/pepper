# A program's own `arguments` function, which `main`'s arguments ignore
# (programs_test.pep).

arguments(): int {
    return 9;
}

main(args: String[]): int {
    return (args.count as int) * 10 + arguments();
}

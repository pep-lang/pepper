# A `main` with arguments and no return type that falls off its end
# (programs_test.pep).

main(args: String[]) {
    if (args.count > 1) {
        return 3;
    }
}

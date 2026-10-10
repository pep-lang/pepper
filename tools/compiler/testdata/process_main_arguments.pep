# Prints the arguments `main` receives after the program's name, and exits
# with their count, the name included (programs_test.pep).

main(args: String[]): int {
    var index = 1;
    while (index < args.count) {
        print("[" + args[index] + "]");
        index = index + 1;
    }
    return args[0].contains("process_main_arguments") ? args.count as int : 100;
}

import process;

# args holds the program name, then each command-line argument.
main(args: String[]): int {
    if (args.count > 2) {
        print("usage: greet [NAME]");
        process.exit(2);  # ends the program here, with status 2
    }
    var name = "world";
    if (args.count == 2) {
        name = args[1];
    }
    print("Hello, " + name + "!");
    return 0;
}

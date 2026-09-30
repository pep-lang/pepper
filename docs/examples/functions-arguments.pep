# arguments() holds the program name, then each command-line argument.
main(): int {
    var parts = arguments();
    if (parts.count() > 2) {
        print("usage: greet [NAME]");
        exit(2);  # ends the program here, with status 2
    }
    var name = "world";
    if (parts.count() == 2) {
        name = parts[1];
    }
    print("Hello, " + name + "!");
    return 0;
}

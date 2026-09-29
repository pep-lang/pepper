# The print builtin writes each argument on its own line.
main(): int {
    print("Hello, world!");     # a String
    print(42);                  # an integer
    print(true);                # a bool prints as 1 or 0
    var name = "Pepper";
    print("Hi, " + name, 3 + 4); # two lines: "Hi, Pepper" and "7"
    return 0;
}

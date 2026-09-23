var counter = 7;
var name = "pepper";

main(): int {
    # Read a global.
    if (counter != 7) { return -1; }

    # Write through a global, then read it back.
    counter += 3;
    if (counter != 10) { return -2; }

    # String globals keep their value.
    if (name.length() != 6) { return -3; }

    return 0;
}

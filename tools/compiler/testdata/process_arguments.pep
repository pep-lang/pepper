# Prints its arguments after the program's name, and exits with their
# count, the name included (programs_test.pep).

import process;

main(): int {
    var parts = process.arguments();
    var index = 1;
    while (index < parts.count) {
        print("[" + parts[index] + "]");
        index = index + 1;
    }
    return parts.count as int;
}

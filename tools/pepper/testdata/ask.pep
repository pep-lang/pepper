# Prints `ready`, then what it reads from standard input to the end.

import [File] from io;

main(): int {
    print("ready");
    var rest = File.stdin().read_string().value();
    print("got " + rest);
    return 0;
}

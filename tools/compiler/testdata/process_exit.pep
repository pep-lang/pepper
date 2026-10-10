# Exits with 7 from a function, after printing (programs_test.pep).

import process;

stop() {
    print("before");
    process.exit(7);
}

main(): int {
    stop();
    print("after");
    return 0;
}

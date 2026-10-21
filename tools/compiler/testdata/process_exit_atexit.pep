# process.exit runs C's `atexit` handlers, except in a copy process.fork()
# started, whose handlers are the parent's (programs_test.pep).

import process;

extern int atexit(void* function);
extern int puts(char* text);

said_goodbye() {
    puts("exit handler ran");
}

main(): int {
    var handler: extern () => void = said_goodbye;
    atexit(handler);
    var forked = process.fork();
    if (forked.is_err()) {
        print("no fork");
    } else if (!forked.value().is_value()) {
        process.exit(5);
    } else {
        var status = forked.value().value().wait().value();
        print($"child {status.code().value()}");
    }
    process.exit(7);
    return 0;
}

# process.exit runs C's `atexit` handlers, except in a copy process.fork()
# started, whose handlers are the parent's, even from a thread the copy
# starts (programs_test.pep).

import async;
import process;

extern int atexit(void* function);
extern int puts(char* text);

said_goodbye() {
    puts("exit handler ran");
}

exit_with_five() {
    process.exit(5);
}

main(): int {
    var handler: extern () => void = said_goodbye;
    atexit(handler);
    var forked = process.fork();
    if (forked.is_err()) {
        print("no fork");
    } else if (!forked.value().is_value()) {
        async.Thread.spawn(exit_with_five).join();
    } else {
        var status = forked.value().value().wait().value();
        print($"child {status.code().value()}");
    }
    process.exit(7);
    return 0;
}

import async;
import [File] from io;
import process;

# Panics in the way the argument names, with a panic hook that writes the
# message and location it gets to standard error:
# - `panic`, `assert`, `bounds` and `overflow`: each kind of panic;
# - `taken`: after `take_panic_hook`, which restores the default;
# - `nested`: the hook itself panics;
# - `thread`: the hook is set on the main thread, the panic is on another;
# - `chained`: a second hook runs the first one, which it took.
main(): int {
    var how = process.arguments()[1];
    set_panic_hook((message, location) => File.stderr().write_all($"hook: {message} at {location}\n"));
    if (how == "panic") {
        panic("boom");
    } else if (how == "assert") {
        assert(how.size == 0, "not empty");
    } else if (how == "bounds") {
        var values = [1, 2, 3];
        print($"{values[how.size]}");
    } else if (how == "overflow") {
        int big = 2147483647;
        print($"{big + how.size as int}");
    } else if (how == "taken") {
        var hook = take_panic_hook();
        hook("called", "directly");
        panic("no hook");
    } else if (how == "nested") {
        set_panic_hook((message, location) => panic("in the hook"));
        panic("first");
    } else if (how == "thread") {
        async.Thread.spawn(() => panic("on a thread")).join();
    } else if (how == "chained") {
        var first = take_panic_hook();
        set_panic_hook((message, location) => {
            File.stderr().write_all("second\n");
            first(message, location);
        });
        panic("chain");
    }
    return 0;
}

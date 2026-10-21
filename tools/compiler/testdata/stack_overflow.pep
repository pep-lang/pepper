import async;
import [File] from io;
import process;

# Recurses `n` deep: far enough to overflow any stack when `n` is large.
# The print after the call keeps an optimizer from making it a loop.
depth(n: int): int {
    if (n == 0) {
        return 0;
    }
    var below = depth(n - 1);
    if (below < 0) {
        print("unreachable");
    }
    return below + 1;
}

# Overflows the stack on the thread the argument names: `main`, `thread`
# (a spawned Thread) or `task` (a task's fiber); `none` recurses safely.
main(): int {
    var where = process.arguments()[1];
    # Without the guard an overflow ends the program with no message, and
    # the test would see only that: say why instead, in its stderr.
    if (where != "none" and !_pep_stack_guard_installed()) {
        File.stderr().write_all("main did not install the stack guard: built by a pep-build older than it?\n");
        return 3;
    }
    var n = where == "none" ? 1000 : 100000000;
    if (where == "thread") {
        async.Thread.spawn(() => print($"{depth(n)}")).join();
    } else if (where == "task") {
        async.run(() => {
            var task = async.spawn<int>(() => depth(n));
            print($"{task.join().value()}");
        });
    } else {
        print($"{depth(n)}");
    }
    return 0;
}

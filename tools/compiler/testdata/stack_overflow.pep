import async;
import process;

# Recurses `n` deep: far enough to overflow any stack when `n` is large.
depth(n: int): int {
    if (n == 0) {
        return 0;
    }
    return 1 + depth(n - 1);
}

# Overflows the stack on the thread the argument names: `main`, `thread`
# (a spawned Thread) or `task` (a task's fiber); `none` recurses safely.
main(): int {
    var where = process.arguments()[1];
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

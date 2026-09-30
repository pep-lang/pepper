# shared function types: function values that threads can share.
import async;

const total = Atomic<long>(0);

# A named function holds no state, so it is always thread-safe.
add_one() {
    total.fetch_add(1);
}

# A [Shared] struct's fields must be thread-safe: a function field is shared.
[Shared]
struct Task {
    const weight: long;
    const run: shared (long) => void;
    construct(this.weight = 1, this.run = (n: long) => {}) {}
}

# A plain function type takes any function of the same signature.
apply(f: (long) => long, x: long): long {
    return f(x);
}

main(): int {
    # A closure converts to a shared type when everything it captures is
    # thread-safe: here nothing but the module-scope Atomic.
    var add: shared (long) => void = (n: long) => { total.fetch_add(n); };
    var task = Task(10, add);

    # A thread body is a shared () => void. This closure captures a
    # [Shared] struct.
    var worker = async.Thread.spawn(() => { task.run(task.weight); });
    var other = async.Thread.spawn(add_one);
    worker.join();
    other.join();
    assert(total.load() == 11, "both threads ran");

    # A shared value can be used where a plain one is expected.
    var step: long = 5;
    var add_step: shared (long) => long = (x: long) => x + step;
    assert(apply(add_step, 1) == 6, "shared value passed as plain");

    # A plain closure may capture anything, but stays on this thread.
    var name = "worker";
    var greet = () => name + " done";
    assert(greet() == "worker done", "plain closure");
    return 0;
}

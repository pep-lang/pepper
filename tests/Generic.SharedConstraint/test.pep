# The built-in constraint `T: Shared` accepts exactly the thread-safe types:
# numbers, `[Shared]` structs, `shared` function types, pointers to and
# tuples of thread-safe types, and parameters constrained `Shared`. It
# composes with traits.

import async;

trait Named {
    name(): String;
}

[Shared]
struct Settings {
    const workers: int;
    construct(this.workers = 1) {}
    name(): String { return "settings"; }
}

extend Settings with Named {}

# A Shared struct that stores one value of any thread-safe type.
[Shared]
struct Cell<T: Shared> {
    const value: T;
    construct(value: T) { this.value = value; }
}

enum Mode {
    Idle,
    Busy,
}

keep<T: Shared>(value: T): Cell<T> { return Cell<T>(value); }

label<T: Shared & Named>(value: T): String { return value.name(); }

main(): int {
    if (keep(7).value != 7) {
        return 1;
    }
    if (keep(Settings(4)).value.workers != 4) {
        return 2;
    }
    var pair = keep((1, Settings(2)));
    if (pair.value.1.workers != 2) {
        return 3;
    }
    if (label(Settings()) != "settings") {
        return 4;
    }
    var work: shared () => int = () => 5;
    if (keep(work).value() != 5) {
        return 5;
    }
    # Atomic<T: Shared> takes every thread-safe type.
    var count = async.Atomic<int>(1);
    count.fetch_add(2);
    var ratio = async.Atomic<double>(0.5);
    var mode = async.Atomic<Mode>(Mode.Idle);
    mode.store(Mode.Busy);
    var settings = async.Atomic<Settings>(Settings(8));
    if (count.load() != 3 or ratio.load() != 0.5 or mode.load() != Mode.Busy or settings.load().workers != 8) {
        return 6;
    }
    async.run(() => {
        var task = async.spawn<Settings>(() => { return Settings(3); });
        assert(task.join().value().workers == 3, "spawned");
        assert(async.run_blocking<int>(() => { return 6; }) == 6, "blocking");
    });
    return 0;
}

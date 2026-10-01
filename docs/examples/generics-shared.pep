import async;

[Shared]
struct Settings {
    const workers: int;
    construct(this.workers = 1) {}
}

# A cell that any thread may read: its value must be thread-safe.
[Shared]
struct Cell<T: Shared> {
    const value: T;
    construct(value: T) { this.value = value; }
}

share<T: Shared>(value: T): Cell<T> { return Cell<T>(value); }

main(): int {
    var count = share(3);
    var settings = share(Settings(4));
    assert(count.value == 3 and settings.value.workers == 4, "shared cells");

    # The runtime states the same rule: spawn<T: Shared>.
    async.run(() => {
        var task = async.spawn<Settings>(() => { return Settings(2); });
        assert(task.join().value().workers == 2, "spawned");
    });
    return 0;
}

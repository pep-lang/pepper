import async;

# A struct that threads can share: declared [Shared], every field const and
# thread-safe.
[Shared]
struct Settings {
    const Port: int;
    const Retries: int;
    construct(this.Port = 0, this.Retries = 0) {}
}

# Atomic<T> of a [Shared] struct: threads read the current settings, and one
# of them can replace them.
const current = Atomic<Settings>(Settings(8080, 3));
const seen = Atomic<long>(0);

read_settings() {
    var settings = current.load();
    seen.fetch_add(settings.Port);
}

main(): int {
    var readers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        readers.append(async.Thread.spawn(read_settings));
        i = i + 1;
    }
    for (var reader in readers) {
        reader.join();
    }
    assert(seen.load() == 4 * 8080, "every reader saw the settings");

    current.store(Settings(9090, 5));
    assert(current.load().Port == 9090, "replaced");
    return 0;
}

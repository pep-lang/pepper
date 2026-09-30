import async;

[Shared]
struct Settings {
    const workers: long;
    construct(this.workers = 1) {}
}

const builds = async.Atomic<long>(0);

load_settings(): Settings {
    builds.fetch_add(1);
    return Settings(async.logical_cpus() as long);
}

# Built by the first thread that calls get(), not before main runs.
const settings = async.Lazy<Settings>(load_settings);

# Runs initialize() once, however many threads call it.
const setup = async.Once();
const setups = async.Atomic<long>(0);

initialize() {
    setups.fetch_add(1);
}

work() {
    setup.call(initialize);
    assert(settings.get().workers >= 1, "every thread sees the settings");
}

main(): int {
    assert(!settings.is_built(), "nothing is built before first use");
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 4) {
        workers.append(async.Thread.spawn(work));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(builds.load() == 1, "the settings were built once");
    assert(setups.load() == 1, "initialize ran once");
    assert(setup.is_done(), "done");
    return 0;
}

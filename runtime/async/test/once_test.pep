# Once and Lazy<T>: a body runs exactly once under racing threads, a value
# is built once and every thread gets the same one, and a Once's body that
# calls the same Once panics.

import async;

[Shared]
struct Settings {
    const workers: long;
    construct(this.workers = 0) {}
}

const once = async.Once();
const once_runs = async.Atomic<long>(0);
const lazy_runs = async.Atomic<long>(0);
const same = async.Atomic<long>(0);

slow_setup() {
    async.Thread.sleep(20);
    once_runs.fetch_add(1);
}

build_settings(): Settings {
    lazy_runs.fetch_add(1);
    async.Thread.sleep(20);
    return Settings(7);
}

const first = async.Atomic<Settings>();

race(settings: async.Lazy<Settings>) {
    once.call(slow_setup);
    # Everything the body did is visible once call returns.
    expect_equal(once_runs.load(), 1);
    var s = settings.get();
    first.compare_exchange(__default<Settings>(), s);
    if (__address<Settings>(s) == __address<Settings>(first.load())) {
        same.fetch_add(1);
    }
}

make_settings(): Settings {
    return Settings(1);
}

make_lazy() {
    var l = async.Lazy<Settings>(make_settings);
    expect_equal(l.get().workers, 1);
}

[Test]
once_and_lazy() {
    # A local Lazy, so that the value it builds is released when the test
    # ends.
    var settings = async.Lazy<Settings>(build_settings);
    expect_false(once.is_done());
    expect_false(settings.is_built());
    var workers = Array<async.Thread>();
    var i = 0;
    while (i < 8) {
        workers.append(async.Thread.spawn(() => {
            race(settings);
        }));
        i = i + 1;
    }
    for (var worker in workers) {
        worker.join();
    }
    expect_equal(once_runs.load(), 1);
    expect_true(once.is_done());
    # Later calls do not run a body.
    once.call(slow_setup);
    expect_equal(once_runs.load(), 1);
    # Lazy built its value once, and every thread got the same value.
    expect_equal(lazy_runs.load(), 1);
    expect_equal(same.load(), 8);
    expect_equal(settings.get().workers, 7);
    expect_true(settings.is_built());
    first.store(__default<Settings>());

    # A dropped Lazy releases its value.
    var before = _pep_live_allocs();
    make_lazy();
    expect_equal(_pep_live_allocs(), before);
}

const reentered = async.Once();

again() {
    reentered.call(again);
}

# A Once's body that calls `call` on the same Once panics instead of
# waiting for itself.
[Test]
[ShouldPanic("Once.call: the body called 'call' on the Once that is running it")]
once_reentry_panics() {
    reentered.call(again);
}

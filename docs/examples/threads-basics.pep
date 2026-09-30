import async;

const finished = async.Atomic<int>(0);

# A thread body is a function that takes nothing and returns nothing.
count_to_a_million() {
    var me = async.Thread.current();
    assert(me.name() == "counter", "a spawned thread sees its own Thread");
    var total: long = 0;
    var i = 0;
    while (i < 1000000) {
        total = total + 1;
        i = i + 1;
    }
    finished.fetch_add(1);
}

main(): int {
    var main_thread = async.Thread.current();
    assert(main_thread.name() == "main", "the main thread is named main");

    var first = async.Thread.spawn(count_to_a_million, "counter");
    var second = async.Thread.spawn(count_to_a_million, "counter");
    assert(first.id() != second.id(), "every thread has its own id");

    first.join();
    second.join();
    assert(first.is_finished(), "join waits for the body to return");
    assert(finished.load() == 2, "both bodies ran");

    # How many threads can run at once, and on how many cores.
    assert(async.logical_cpus() >= async.physical_cpus(), "hyperthreads count once in physical_cpus");
    return 0;
}

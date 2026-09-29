<!-- Generated from runtime/async/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The async module

Threads and concurrency, modeled on Rust's `std::thread` and C++
`std::thread`.

Like `io`, `async` is a module: bring it in with `import async` (and write
`async.Thread`, `async.logical_cpus()`) or import names directly with
`import [Thread, ThreadLocal] from async`.

- [Thread](async-thread.md): starting, naming and joining threads, `ThreadId` and `ThreadBody`
- [ThreadLocal](async-thread_local.md): a variable with a separate value on every thread
- [Processor counts](async-cpus.md): `logical_cpus()` and `physical_cpus()`

Only thread-safe values can be shared between threads: numbers, function
values, and `[Shared]` structs such as `Atomic<T>`, `Thread` and
`ThreadLocal<T>`. See the language guide's Threads chapter.

**Example**
```pepper
    import async;

    var hits = Atomic<long>(0);

    work() {
        hits.fetch_add(1);
    }

    main(): int {
        var workers = Array<async.Thread>();
        var n = async.logical_cpus();
        var i: ulong = 0;
        while (i < n) {
            workers.append(async.Thread.spawn(work));
            i = i + 1;
        }
        for (var worker in workers) {
            worker.join();
        }
        assert(hits.load() == n as long, "every worker ran");
        return 0;
    }
```

Source: `runtime/async/module.pep`

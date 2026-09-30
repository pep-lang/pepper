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
- [Channel](async-channel.md): `Channel<T>`, a queue that carries values between threads, and its `ChannelIterator<T>`
- [Mutex](async-mutex.md): `Mutex<T>`, the `MutexGuard<T>` a `with` block holds, and `Condition<T>`
- [Once](async-once.md): `Once`, which runs a function once, and `Lazy<T>`, a value built on first use

Only thread-safe values can be shared between threads: numbers, `shared`
function values (such as a thread's body), and `[Shared]` structs such as
`Atomic<T>`, `Thread`, `ThreadLocal<T>`, `Channel<T>` and `Mutex<T>`. The
synchronization types carry and guard thread-safe values only, so
`Channel<String>` is a compile error. See the language guide's Threads
chapter.

**Example**
```pepper
    import async;

    const hits = Atomic<long>(0);

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

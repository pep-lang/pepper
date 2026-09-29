## Threads: starting, naming, identifying and joining operating-system
## threads.

# A `Thread` is shared between the thread that spawned it (its handle) and
# the thread itself (`Thread.current()`), so it is `[Shared]`: atomic counts
# and only const, thread-safe fields. Its name is kept as a raw UTF-8 copy
# because a `String` field would not be thread-safe; `name()` returns a new
# String each time.
#
# Spawning hands the new thread one reference to its `Thread` through a
# malloc'd slot. The entry point (`_async_thread_main`, a C-callable function
# passed with `__function_pointer`) takes that reference, records it as the
# thread's current Thread, runs the body, and marks the thread finished.

import "thread_local";
import "sys_posix";
import "sys_windows";

## Identifies a thread for as long as the program runs: every thread,
## whether started with `Thread.spawn` or not, gets a distinct id the first
## time it is asked for one, and ids are never reused.
##
## Ids are assigned by the runtime in the order threads ask for them, starting
## at 1; they are not the operating system's thread ids. A `ThreadId` is a
## number, so it can be compared, hashed and used as a `HashMap` key.
##
## @see Thread.id
export type ThreadId = ulong;

## The type of a thread's body: a function that takes no arguments and
## returns nothing. `Thread.spawn` runs one on a new thread.
##
## @see Thread.spawn
export type ThreadBody = () => void;

# The next id to hand out.
var _async_next_id = Atomic<ulong>(1);

# The current thread's `Thread`, set by the entry point of spawned threads and
# on first use by `Thread.current()` everywhere else.
var _async_current = ThreadLocal<Thread>();

# The operating system's identity of the thread that ran the program's
# initializers (the main thread), to name it "main" in `Thread.current()`.
var _async_main_os_thread = _async_sys_os_thread();

## An operating-system thread.
##
## Start one with `Thread.spawn`, which runs a function on a new thread and
## returns its `Thread`, and wait for it to finish with `join()`. Every
## thread, including the main thread, can get its own `Thread` with
## `Thread.current()`.
##
## A `Thread` is `[Shared]`: the thread that started it and the thread itself
## can both hold it. Dropping every reference without joining detaches the
## thread: it keeps running, and its resources are freed when it finishes.
##
## The body runs until it returns; there is no way to stop a thread from the
## outside. A `panic` or failed `assert` on any thread ends the whole program.
##
## @example
##     import async;
##
##     var total = Atomic<long>(0);
##
##     add_ten() {
##         total.fetch_add(10);
##     }
##
##     main(): int {
##         var a = async.Thread.spawn(add_ten, "adder a");
##         var b = async.Thread.spawn(add_ten, "adder b");
##         a.join();
##         b.join();
##         assert(total.load() == 20, "both threads ran");
##         return 0;
##     }
[Shared]
export struct Thread {
    ## The thread's id.
    const Id: ThreadId;

    ## The name's UTF-8 bytes, NUL-terminated, or null for an unnamed thread.
    const NameData: __ptr<char>;

    ## The name's size in bytes.
    const NameSize: ulong;

    ## The name's length in code points.
    const NameLength: ulong;

    ## The function the thread runs (a no-op for a thread that was not
    ## started by `spawn`, such as the main thread).
    const Body: ThreadBody;

    ## The operating-system handle while the thread can still be joined or
    ## detached (a `pthread_t` or a Windows `HANDLE`), else null.
    const Handle: Atomic<__ptr<void>>;

    ## 1 once the body has returned, else 0.
    const Finished: Atomic<int>;

    ## Creates a `Thread` value for a thread that is already running. Programs
    ## get threads from `spawn` and `current()` instead; a `Thread` made
    ## directly is not attached to any thread and cannot be joined.
    ##
    ## @param name the thread's name; empty for an unnamed thread
    ## @param body the function the thread runs
    construct(String name, ThreadBody body) {
        Id = _async_next_id.fetch_add(1);
        NameSize = name.size();
        NameLength = name.length();
        if (NameSize > 0) {
            NameData = _pep_malloc(NameSize + 1);
            memcpy(NameData, name.c_str(), NameSize);
        }
        Body = body;
        Handle = Atomic<__ptr<void>>(__null);
        Finished = Atomic<int>(0);
    }

    destruct {
        # Dropped without join(): let the thread run on and free itself.
        var handle = Handle.exchange(__null);
        if (handle != __null) {
            _async_sys_detach(handle);
        }
        _pep_free(NameData);
    }

    ## Starts a new thread that runs `body`.
    ##
    ## The new thread starts right away and runs until `body` returns. Its
    ## `Thread.current()` is the `Thread` returned here.
    ##
    ## @param body the function to run on the new thread
    ## @param name a name for the thread, returned by `name()`; empty by default
    ## @returns the new thread, to `join()` or query
    ## @panics if the operating system cannot create another thread
    ## @example
    ##     var worker = Thread.spawn(do_work, "worker");
    ##     worker.join();
    static Thread spawn(ThreadBody body, String name = "") {
        var thread = Thread(name, body);
        # The new thread's own reference, which its entry point takes over.
        __ptr<Thread> start = _pep_malloc(8);
        start[0] = thread;
        var handle = _async_sys_spawn(__function_pointer(_async_thread_main), start);
        if (handle == __null) {
            start[0] = __default<Thread>();
            _pep_free(start);
            panic("Thread.spawn: the operating system could not create a thread");
        }
        thread.Handle.store(handle);
        return thread;
    }

    ## Returns the `Thread` of the thread that calls it.
    ##
    ## For a thread started with `spawn` this is the `Thread` that `spawn`
    ## returned. Any other thread (the main thread, or one started by C code)
    ## gets a `Thread` the first time it asks and the same one afterwards; the
    ## main thread's is named `main`, the others are unnamed. Such a `Thread`
    ## cannot be joined.
    ##
    ## @returns the calling thread
    ## @example
    ##     var me = Thread.current();
    ##     print(me.name(), "\n");   # "main" on the main thread
    static Thread current() {
        var thread = _async_current.get();
        if (thread) {
            return thread;
        }
        var name = "";
        if (_async_sys_os_thread() == _async_main_os_thread) {
            name = "main";
        }
        # Never spawned: nothing to join, and the body is never run.
        var adopted = Thread(name, _async_no_body);
        _async_current.set(adopted);
        return adopted;
    }

    ## Pauses the calling thread for at least `milliseconds` milliseconds.
    ##
    ## The operating system may sleep longer, but never shorter.
    ##
    ## @param milliseconds how long to sleep; 0 returns right away
    static void sleep(ulong milliseconds) {
        if (milliseconds > 0) {
            _async_sys_sleep(milliseconds);
        }
    }

    ## Returns the thread's id, which no other thread in the program has.
    ##
    ## @returns the thread's id
    ThreadId id() {
        return Id;
    }

    ## Returns the name the thread was given.
    ##
    ## @returns the name passed to `spawn`, `main` for the main thread, or an empty String for an unnamed thread
    String name() {
        if (NameSize == 0) {
            return String();
        }
        return String(NameData, NameSize, NameLength);
    }

    ## Reports whether the thread's body has returned.
    ##
    ## A thread that is not finished may finish at any moment, so a `false`
    ## result can be out of date by the time it is used. Always false for a
    ## `Thread` that was not started by `spawn`.
    ##
    ## @returns true once the body has returned
    bool is_finished() {
        return Finished.load() == 1;
    }

    ## Reports whether `join()` can be called: the thread was started by
    ## `spawn` and has not been joined yet.
    ##
    ## @returns true if the thread can be joined
    bool is_joinable() {
        return Handle.load() != __null;
    }

    ## Waits for the thread's body to return.
    ##
    ## Returns right away if it already has. A thread can be joined once; a
    ## `Thread` from `current()` for a thread not started by `spawn` cannot be
    ## joined at all. Everything the thread did before it finished is visible
    ## to the caller after `join()` returns.
    ##
    ## @panics if the thread cannot be joined (see `is_joinable()`), or if a thread tries to join itself
    void join() {
        if (Id == Thread.current().id()) {
            panic("Thread.join: a thread cannot join itself");
        }
        var handle = Handle.exchange(__null);
        if (handle == __null) {
            panic("Thread.join: the thread was already joined, or was not started by Thread.spawn");
        }
        _async_sys_join(handle);
    }
}

# The body of a Thread that `current()` made for a thread it did not spawn.
export _async_no_body() {}

# Runs a spawned thread: `start` is the slot holding the thread's own
# reference to its Thread (see `spawn`).
export _async_thread_run(start: __ptr<void>) {
    __ptr<Thread> slot = start;
    Thread thread = slot[0];
    slot[0] = __default<Thread>();
    _pep_free(slot);
    _async_current.set(thread);
    thread.Body();
    thread.Finished.store(1);
}

# The C entry point of a spawned thread: `void* (*)(void*)` for pthreads, and
# `DWORD (WINAPI *)(void*)` on Windows.
[Target(!OS(Windows))] export _async_thread_main(start: __ptr<void>): __ptr<void> {
    _async_thread_run(start);
    return __null;
}
[Target(OS(Windows))] export _async_thread_main(start: __ptr<void>): uint {
    _async_thread_run(start);
    return 0;
}

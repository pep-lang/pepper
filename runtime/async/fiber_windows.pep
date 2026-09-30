# Windows fibers for the task runtime in task.pep, over the Fibers API
# (kernel32). Every declaration carries [Target(OS(Windows))];
# fiber_posix.pep declares the same `_async_fiber_*` functions with the same
# signatures for Linux and macOS.
#
# A context is a fiber handle. The thread running the scheduler becomes a
# fiber with ConvertThreadToFiber for the length of `async.run` and back
# with ConvertFiberToThread afterwards. The Fibers API, rather than hand-written
# assembly, keeps the stack limits in the thread information block and the
# exception chain correct for each fiber. FIBER_FLAG_FLOAT_SWITCH makes a
# switch save the floating-point state too, as the POSIX switch does.

[Target(OS(Windows))]
extern void* ConvertThreadToFiber(void* parameter);
[Target(OS(Windows))]
extern int ConvertFiberToThread();
[Target(OS(Windows))]
extern void* CreateFiberEx(ulong commit, ulong reserve, uint flags, void* start, void* parameter);
[Target(OS(Windows))]
extern void DeleteFiber(void* fiber);
[Target(OS(Windows))]
extern void SwitchToFiber(void* fiber);

# FIBER_FLAG_FLOAT_SWITCH.
[Target(OS(Windows))]
const _FIBER_FLOAT_SWITCH = 1;

# The calling thread as a context: what a fiber switches back to.
[Target(OS(Windows))]
export _async_fiber_thread_context(): __ptr<void> {
    var fiber = ConvertThreadToFiber(__null);
    assert(fiber != __null, "async.run: this thread is already a fiber");
    return fiber;
}

# Turns the thread back from a fiber (`_async_fiber_thread_context`).
[Target(OS(Windows))]
export _async_fiber_release_thread_context(context: __ptr<void>) {
    ConvertFiberToThread();
}

# A new fiber with `stack_size` bytes of reserved stack whose first switch
# calls `entry(null)`; null if the system has no memory for it. `entry`
# must never return.
[Target(OS(Windows))]
export _async_fiber_create(stack_size: ulong, entry: __ptr<void>): __ptr<void> {
    return CreateFiberEx(0, stack_size, _FIBER_FLOAT_SWITCH, entry, __null);
}

# Deletes a fiber and its stack. The fiber must not be the one running.
[Target(OS(Windows))]
export _async_fiber_destroy(context: __ptr<void>) {
    DeleteFiber(context);
}

# Resumes `to`; returns when something switches back to the running fiber
# (`from`, which the Fibers API tracks itself).
[Target(OS(Windows))]
export _async_fiber_switch(from: __ptr<void>, to: __ptr<void>) {
    SwitchToFiber(to);
}

# A thread-local key shared by every fiber on a thread. The `_async_sys_key_*`
# keys are fiber local storage (FlsAlloc), which gives each fiber its own
# value, so the worker is published through thread local storage instead.
[Target(OS(Windows))]
extern uint TlsAlloc();
[Target(OS(Windows))]
extern void* TlsGetValue(uint index);
[Target(OS(Windows))]
extern int TlsSetValue(uint index, void* value);

[Target(OS(Windows))]
export _async_fiber_key_create(): ulong {
    var index = TlsAlloc();
    assert(index != 4294967295, "async: no thread-local keys left");   # TLS_OUT_OF_INDEXES
    return index as ulong;
}

[Target(OS(Windows))]
export _async_fiber_key_get(key: ulong): __ptr<void> {
    return TlsGetValue(key as uint);
}

[Target(OS(Windows))]
export _async_fiber_key_set(key: ulong, value: __ptr<void>) {
    TlsSetValue(key as uint, value);
}

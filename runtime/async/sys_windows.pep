# Windows platform layer for async. Every declaration carries
# [Target(OS(Windows))]; sys_posix.pep declares the same `_async_sys_*`
# functions with the same signatures for Linux and macOS. These are exported
# to the other async files only: module.pep does not re-export them.
#
# Thread handles are `HANDLE`s, as `__ptr<void>`. Thread-local keys are fiber
# local storage indexes (`FlsAlloc`), the Windows keys that take a
# destructor callback. Everything here is in kernel32, which is linked by
# default.

[Target(OS(Windows))] extern void* CreateThread(void* attributes, ulong stack_size, void* start, void* parameter, uint flags, uint* thread_id);
[Target(OS(Windows))] extern uint WaitForSingleObject(void* handle, uint milliseconds);
[Target(OS(Windows))] extern int CloseHandle(void* handle);
[Target(OS(Windows))] extern uint GetCurrentThreadId();
[Target(OS(Windows))] extern void Sleep(uint milliseconds);
[Target(OS(Windows))] extern uint FlsAlloc(void* callback);
[Target(OS(Windows))] extern int FlsFree(uint index);
[Target(OS(Windows))] extern void* FlsGetValue(uint index);
[Target(OS(Windows))] extern int FlsSetValue(uint index, void* value);
[Target(OS(Windows))] extern uint GetActiveProcessorCount(ushort group);
[Target(OS(Windows))] extern int GetLogicalProcessorInformationEx(int relationship, void* buffer, uint* length);

# ── Threads ──────────────────────────────────────────────────────────────────

# Starts a thread running `start(argument)`; its handle, or null on failure.
[Target(OS(Windows))] export _async_sys_spawn(start: __ptr<void>, argument: __ptr<void>): __ptr<void> {
    return CreateThread(__null, 0, start, argument, 0, __null);
}

[Target(OS(Windows))] export _async_sys_join(handle: __ptr<void>) {
    WaitForSingleObject(handle, 4294967295);   # INFINITE
    CloseHandle(handle);
}

[Target(OS(Windows))] export _async_sys_detach(handle: __ptr<void>) {
    CloseHandle(handle);
}

# The operating system's identity of the calling thread.
[Target(OS(Windows))] export _async_sys_os_thread(): ulong {
    return GetCurrentThreadId() as ulong;
}

[Target(OS(Windows))] export _async_sys_sleep(milliseconds: ulong) {
    # Sleep takes a 32-bit count, and 0xFFFFFFFF means forever: sleep in
    # steps below it.
    var left = milliseconds;
    while (left > 0) {
        var step = left > 4000000000 ? 4000000000 : left;
        Sleep(step as uint);
        left = left - step;
    }
}

# ── Thread-local keys ────────────────────────────────────────────────────────

# A new key whose `destructor(value)` runs on each exiting thread with a
# non-null value.
[Target(OS(Windows))] export _async_sys_key_create(destructor: __ptr<void>): ulong {
    var index = FlsAlloc(destructor);
    if (index == 4294967295) {   # FLS_OUT_OF_INDEXES
        panic("ThreadLocal: the operating system has no thread-local keys left");
    }
    return index as ulong;
}

[Target(OS(Windows))] export _async_sys_key_delete(key: ulong) {
    FlsFree(key as uint);
}

[Target(OS(Windows))] export _async_sys_key_get(key: ulong): __ptr<void> {
    return FlsGetValue(key as uint);
}

[Target(OS(Windows))] export _async_sys_key_set(key: ulong, value: __ptr<void>) {
    FlsSetValue(key as uint, value);
}

# ── Processor counts (0 when unknown) ────────────────────────────────────────

[Target(OS(Windows))] export _async_sys_logical_cpus(): ulong {
    return GetActiveProcessorCount(65535) as ulong;   # ALL_PROCESSOR_GROUPS
}

# One SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX record per core
# (RelationProcessorCore); each record starts with its Relationship (4 bytes)
# and Size (4 bytes).
[Target(OS(Windows))] export _async_sys_physical_cpus(): ulong {
    __ptr<uint> length = _pep_malloc(4);
    # Asking with no buffer fails and reports the size needed.
    GetLogicalProcessorInformationEx(0, __null, length);
    uint size = length[0];
    var cores: ulong = 0;
    if (size > 0) {
        __ptr<u8> buffer = _pep_malloc(size as ulong);
        if (GetLogicalProcessorInformationEx(0, buffer, length) != 0) {
            ulong offset = 0;
            while (offset + 8 <= length[0] as ulong) {
                __ptr<uint> record = (buffer + offset) as __ptr<uint>;
                var record_size = record[1] as ulong;
                if (record_size == 0) {
                    break;
                }
                cores = cores + 1;
                offset = offset + record_size;
            }
        }
        _pep_free(buffer);
    }
    _pep_free(length);
    return cores;
}

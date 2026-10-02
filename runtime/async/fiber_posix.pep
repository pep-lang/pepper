# POSIX (Linux, macOS) fibers for the task runtime in task.pep. Every
# declaration carries [Target(OS(Linux) || OS(Mac))] or a narrower target;
# fiber_windows.pep declares the same `_async_fiber_*` functions with the
# same signatures over the Windows Fibers API, and fiber_wasi.pep for WASI,
# which has none.
#
# A context is a malloc'd block of three words: the saved stack pointer, the
# base of the fiber's mapping, and the mapping's length (both zero for the
# thread's own context, which runs on the thread's stack). A fiber's stack is
# an anonymous private mapping whose lowest page is a guard (PROT_NONE), so an
# overflow faults instead of writing over other memory. Pages are committed
# on first touch; Linux maps with MAP_NORESERVE so a large reserve costs
# address space only.
#
# The switch itself is the `__switch_context` intrinsic, which the code
# generator defines as a few instructions of assembly (see
# crates/pepper-codegen/src/context.rs); `__prepare_context` lays out a new
# stack so that the first switch into it calls `entry(null)`.

import "sys_posix";

[Target(OS(Linux) || OS(Mac))]
extern void __switch_context(void* save, void* resume);
[Target(OS(Linux) || OS(Mac))]
extern void* __prepare_context(void* stack_top, void* entry);
[Target(OS(Linux) || OS(Mac))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(OS(Linux) || OS(Mac))]
extern int munmap(void* address, ulong length);
[Target(OS(Linux) || OS(Mac))]
extern int mprotect(void* address, ulong length, int protection);
[Target(OS(Linux) || OS(Mac))]
extern long sysconf(int name);

# PROT_READ | PROT_WRITE; PROT_NONE is 0 and MAP_PRIVATE is 2 everywhere.
[Target(OS(Linux) || OS(Mac))]
const _FIBER_READ_WRITE = 3;

# MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, and _SC_PAGESIZE.
[Target(OS(Linux))]
const _FIBER_MAP_FLAGS = 16418;
[Target(OS(Linux))]
const _FIBER_PAGE_SIZE_NAME = 30;

# MAP_PRIVATE | MAP_ANON (macOS has no MAP_NORESERVE; it commits lazily
# anyway), and _SC_PAGESIZE.
[Target(OS(Mac))]
const _FIBER_MAP_FLAGS = 4098;
[Target(OS(Mac))]
const _FIBER_PAGE_SIZE_NAME = 29;

# The calling thread as a context: what a fiber switches back to.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_thread_context(): __ptr<void> {
    return _pep_malloc(24);
}

# Frees what `_async_fiber_thread_context` made.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_release_thread_context(context: __ptr<void>) {
    _pep_free(context);
}

# A new fiber with a stack of `stack_size` bytes (rounded up to whole pages,
# plus a guard page) whose first switch calls `entry(null)`; null if the
# system has no memory for the stack. `entry` must never return.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_create(stack_size: ulong, entry: __ptr<void>): __ptr<void> {
    var page = sysconf(_FIBER_PAGE_SIZE_NAME) as ulong;
    var length = (stack_size + page - 1) / page * page + page;
    var base = mmap(__null, length, _FIBER_READ_WRITE, _FIBER_MAP_FLAGS, -1, 0);
    if (unsafe_cast<ulong>(base) == ~(0 as ulong)) {
        return __null;
    }
    mprotect(base, page, 0);
    var context = _pep_malloc(24);
    __ptr<u8> top = base;
    __ptr<__ptr<void>> pointers = context;
    __ptr<ulong> words = context;
    pointers[0] = __prepare_context(top + length, entry);
    pointers[1] = base;
    words[2] = length;
    return context;
}

# Unmaps a fiber's stack and frees its context. The fiber must not be the
# one running.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_destroy(context: __ptr<void>) {
    __ptr<__ptr<void>> pointers = context;
    __ptr<ulong> words = context;
    munmap(pointers[1], words[2]);
    _pep_free(context);
}

# Saves the running context into `from` and resumes `to`. Returns when
# something switches back to `from`.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_switch(from: __ptr<void>, to: __ptr<void>) {
    __ptr<__ptr<void>> resume = to;
    __switch_context(from, resume[0]);
}

# A thread-local key shared by every fiber on a thread: a pthread key, since
# a switch leaves the thread's own storage alone.
[Target(OS(Linux) || OS(Mac))]
export _async_fiber_key_create(): ulong {
    return _async_sys_key_create(__null);
}

[Target(OS(Linux) || OS(Mac))]
export _async_fiber_key_get(key: ulong): __ptr<void> {
    return _async_sys_key_get(key);
}

[Target(OS(Linux) || OS(Mac))]
export _async_fiber_key_set(key: ulong, value: __ptr<void>) {
    _async_sys_key_set(key, value);
}

# POSIX (Linux, macOS) fibers for the task runtime in task.pep. Every
# declaration carries [Target(OS(Linux) || OS(Mac))] or a narrower target;
# fiber_windows.pep declares the same `_async_fiber_*` functions with the
# same signatures over the Windows Fibers API, and fiber_wasi.pep for WASI,
# which has none.
#
# A context is a malloc'd block of three words: the saved stack pointer, the
# base of the fiber's mapping, and the mapping's length (both zero for the
# thread's own context, which runs on the thread's stack, but see Android
# below). A fiber's stack is
# an anonymous private mapping whose lowest page is a guard (PROT_NONE), so an
# overflow faults instead of writing over other memory. Pages are committed
# on first touch; Linux maps with MAP_NORESERVE so a large reserve costs
# address space only.
#
# The switch itself is the `__switch_context` intrinsic, which the code
# generator defines as a few instructions of assembly (see
# tools/compiler/codegen/globals.pep); `__prepare_context` lays out a new
# stack so that the first switch into it calls `entry(null)`.
#
# Android: bionic's frame-pointer unwinder, which GWP-ASan runs on a sampled
# malloc or free, follows saved frame pointers while they stay below the
# thread's stack top (`pthread_internal_t::stack_top`). On a fiber that bound
# is the thread's stack, not the fiber's, so a frame pointer register that
# code without frame pointers left holding data (bionic's own on x86-64,
# OpenSSL's) passes the check, and the walk reads unmapped memory (#253). So
# there a thread's context keeps that stack top in its length word, and a
# switch points the field at the top of the stack it resumes, as a thread's
# own would be.

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
[Target(OS(Linux) && !OS(Android))]
const _FIBER_PAGE_SIZE_NAME = 30;
# Bionic numbers sysconf's names its own way.
[Target(OS(Android))]
const _FIBER_PAGE_SIZE_NAME = 39;

# MAP_PRIVATE | MAP_ANON (macOS has no MAP_NORESERVE; it commits lazily
# anyway), and _SC_PAGESIZE.
[Target(OS(Mac))]
const _FIBER_MAP_FLAGS = 4098;
[Target(OS(Mac))]
const _FIBER_PAGE_SIZE_NAME = 29;

# The calling thread as a context: what a fiber switches back to.
[Target((OS(Linux) && !OS(Android)) || OS(Mac))]
_async_fiber_thread_context(): __ptr<void> {
    return _pep_malloc(24);
}

# The calling thread as a context, holding the thread's stack top in its
# length word, or 0 when bionic's field does not look like one.
[Target(OS(Android))]
_async_fiber_thread_context(): __ptr<void> {
    var context = _pep_malloc(24);
    var top = _async_fiber_stack_top()[0];
    var here = unsafe_cast<ulong>(_fiber_frame_address(0));
    # shortcut: the field's offset is bionic's private layout (the same from
    # Android 11, where the field came in, to 14 at least); a value that is
    # not just above this frame leaves the field alone. Recheck on a new
    # Android.
    if (top > here && top - here < 0x40000000 && top % 8 == 0) {
        __ptr<ulong> words = context;
        words[2] = top;
    }
    return context;
}

# Where bionic keeps the calling thread's stack top: `stack_top` in its
# `pthread_internal_t`, which `pthread_self()` points at (64-bit ABIs).
[Target(OS(Android))]
_async_fiber_stack_top(): __ptr<ulong> {
    return unsafe_cast<__ptr<ulong>>(pthread_self() + 144);
}

[Target(OS(Android))]
[Link(name = "llvm.frameaddress")]
extern void* _fiber_frame_address(int level);

# Frees what `_async_fiber_thread_context` made.
[Target(OS(Linux) || OS(Mac))]
_async_fiber_release_thread_context(context: __ptr<void>) {
    _pep_free(context);
}

# A new fiber with a stack of `stack_size` bytes (rounded up to whole pages,
# plus a guard page) whose first switch calls `entry(null)`; null if the
# system has no memory for the stack. `entry` must never return.
[Target(OS(Linux) || OS(Mac))]
_async_fiber_create(stack_size: ulong, entry: __ptr<void>): __ptr<void> {
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
_async_fiber_destroy(context: __ptr<void>) {
    __ptr<__ptr<void>> pointers = context;
    __ptr<ulong> words = context;
    munmap(pointers[1], words[2]);
    _pep_free(context);
}

# Saves the running context into `from` and resumes `to`. Returns when
# something switches back to `from`.
[Target((OS(Linux) && !OS(Android)) || OS(Mac))]
_async_fiber_switch(from: __ptr<void>, to: __ptr<void>) {
    __ptr<__ptr<void>> resume = to;
    __switch_context(from, resume[0]);
}

# As above, and points bionic's stack top at `to`'s when the thread's
# context has one (a switch is always between a thread and a fiber, so
# `from` or `to` is the thread's).
[Target(OS(Android))]
_async_fiber_switch(from: __ptr<void>, to: __ptr<void>) {
    __ptr<__ptr<void>> resume = to;
    __ptr<ulong> from_words = from;
    __ptr<ulong> to_words = to;
    if (from_words[2] != 0 && to_words[2] != 0) {
        _async_fiber_stack_top()[0] = to_words[1] + to_words[2];
    }
    __switch_context(from, resume[0]);
}

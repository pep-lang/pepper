# Stack overflow reports: a thread that runs past the end of its stack hits
# a guard page, and instead of the silent crash that follows, the program
# writes `panic: stack overflow` to standard error and aborts, as a panic
# does. There is too little stack left to format anything, or to print a
# backtrace, so the message is a fixed string written with one system call.
#
# The compiler calls `_pep_stack_guard_start` first thing in `main`, which
# installs the process's handler and sets up the main thread; every `Thread`
# calls `_pep_stack_guard_thread_start` and `_pep_stack_guard_thread_end`
# around its body (async/thread.pep).
#
# Windows: a vectored exception handler, added last so that handlers added
# before it run first, takes EXCEPTION_STACK_OVERFLOW and passes every other
# exception on. A debugger sees each exception before it. The system raises
# the exception with only the guard page left, so `SetThreadStackGuarantee`
# keeps more in reserve on each thread, and on each fiber (fiber_windows.pep),
# since a fiber carries its own guarantee.
#
# Linux and macOS: a SIGSEGV and SIGBUS handler runs on an alternate signal
# stack (`sigaltstack`, one per thread, mapped with a guard page of its own),
# since the faulting stack has no room left. It reports an overflow only when
# the fault address lies just below the running stack: the thread's own,
# recorded when the thread starts, or the task fiber's, which the fiber
# switch records (fiber_posix.pep). Any other fault goes to the handler that
# was there before, or, when there was none, restores the default action and
# returns, so the fault happens again and ends the program as it always did.

extern void* calloc(ulong count, ulong size);
extern void free(void* p);
extern ulong strlen(char* s);
extern void abort();

[Target(OS(Windows))]
extern void* AddVectoredExceptionHandler(uint first, extern (__ptr<void>) => int handler);
[Target(OS(Windows))]
extern int SetThreadStackGuarantee(uint* size);
[Target(OS(Windows))]
extern void* GetStdHandle(uint which);
[Target(OS(Windows))]
extern int WriteFile(void* file, void* buffer, uint size, uint* written, void* overlapped);

# What a stack overflow writes to standard error.
const _STACK_OVERFLOW_MESSAGE = "panic: stack overflow\n";

# The stack each thread keeps for the handler: 20 KiB, as Rust keeps.
[Target(OS(Windows))]
const _STACK_GUARANTEE: uint = 20480;

# EXCEPTION_STACK_OVERFLOW, and EXCEPTION_CONTINUE_SEARCH.
[Target(OS(Windows))]
const _STACK_OVERFLOW_CODE: uint = 3221225725;
[Target(OS(Windows))]
const _STACK_CONTINUE_SEARCH = 0;

# Where WriteFile puts the count it wrote: the handler has no stack to
# spare, and must not allocate.
[Target(OS(Windows))]
const _pep_stack_written: __ptr<uint> = calloc(1, 4);

# Installs the handler and sets up the main thread. The compiler calls it
# at the start of `main`.
[Target(OS(Windows))]
export _pep_stack_guard_start() {
    var handler: extern (__ptr<void>) => int = _pep_stack_overflow_filter;
    AddVectoredExceptionHandler(0, handler);
    _pep_stack_guard_thread_start();
}

# Sets up the calling thread or fiber: keeps stack in reserve for the handler.
[Target(OS(Windows))]
export _pep_stack_guard_thread_start() {
    __ptr<uint> size = calloc(1, 4);
    size[0] = _STACK_GUARANTEE;
    SetThreadStackGuarantee(size);
    free(size);
}

# Undoes `_pep_stack_guard_thread_start` as a thread ends: nothing to undo.
[Target(OS(Windows))]
export _pep_stack_guard_thread_end() {}

# The vectored exception handler: `info` is an EXCEPTION_POINTERS, whose
# first field points at the EXCEPTION_RECORD, whose first field is the code.
[Target(OS(Windows))]
[Unsafe("overflow")]
_pep_stack_overflow_filter(info: __ptr<void>): int {
    __ptr<__ptr<uint>> pointers = info;
    if (pointers[0][0] != _STACK_OVERFLOW_CODE) {
        return _STACK_CONTINUE_SEARCH;
    }
    # STD_ERROR_HANDLE is (DWORD)-12.
    var error = GetStdHandle(4294967284);
    __ptr<char> message = _STACK_OVERFLOW_MESSAGE;
    WriteFile(error, message, strlen(message) as uint, _pep_stack_written, __null);
    abort();
    return _STACK_CONTINUE_SEARCH;
}

[Target(OS(Linux) || OS(Mac))]
extern int sigaction(int number, void* action, void* old);
[Target(OS(Linux) || OS(Mac))]
extern int sigaltstack(void* stack, void* old);
[Target(OS(Linux) || OS(Mac))]
extern long sysconf(int name);
[Target(OS(Linux) || OS(Mac))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(OS(Linux) || OS(Mac))]
extern int mprotect(void* address, ulong length, int protection);
[Target(OS(Linux) || OS(Mac))]
extern int munmap(void* address, ulong length);
[Target(OS(Linux) || OS(Mac))]
extern ulong pthread_self();

[Target(OS(Linux))]
extern int pthread_getattr_np(ulong thread, void* attributes);
[Target(OS(Linux))]
extern int pthread_attr_getstack(void* attributes, void** address, ulong* size);
[Target(OS(Linux))]
extern int pthread_attr_destroy(void* attributes);
[Target(OS(Mac))]
extern void* pthread_get_stackaddr_np(ulong thread);
[Target(OS(Mac))]
extern ulong pthread_get_stacksize_np(ulong thread);

# How far below a stack's lowest page a fault still counts as an overflow:
# a frame larger than the guard page can step over it, and Linux keeps
# 1 MiB unmapped below the main thread's stack.
[Target(OS(Linux) || OS(Mac))]
const _STACK_GUARD_REACH: ulong = 1048576;

# The handler's own stack, with a guard page below it.
[Target(OS(Linux) || OS(Mac))]
const _STACK_SIGNAL_STACK_SIZE: ulong = 65536;

# The struct sigaction layout: its size, and where sa_flags and the handler
# sit. glibc puts the handler first and a 128-byte sigset_t before the flags;
# bionic on 64-bit Android uses the kernel's layout, flags first; Apple's has
# a 4-byte sigset_t. Then SA_SIGINFO | SA_ONSTACK, SA_SIGINFO, SIGBUS,
# SS_DISABLE, _SC_PAGESIZE, MAP_PRIVATE | MAP_ANONYMOUS, si_addr's offset in
# siginfo_t, and the offsets of ss_size and ss_flags in stack_t.
[Target(OS(Linux) && !OS(Android))]
const _STACK_ACTION_SIZE: ulong = 152;
[Target(OS(Linux) && !OS(Android))]
const _STACK_ACTION_HANDLER: ulong = 0;
[Target(OS(Linux) && !OS(Android))]
const _STACK_ACTION_FLAGS: ulong = 136;
[Target(OS(Android))]
const _STACK_ACTION_SIZE: ulong = 32;
[Target(OS(Android))]
const _STACK_ACTION_HANDLER: ulong = 8;
[Target(OS(Android))]
const _STACK_ACTION_FLAGS: ulong = 0;
[Target(OS(Linux))]
const _STACK_SA_FLAGS = 134217732;
[Target(OS(Linux))]
const _STACK_SA_SIGINFO = 4;
[Target(OS(Linux))]
const _STACK_SIGBUS = 7;
[Target(OS(Linux))]
const _STACK_SS_DISABLE = 2;
[Target(OS(Linux))]
const _STACK_PAGE_SIZE_NAME = 30;
[Target(OS(Linux))]
const _STACK_MAP_FLAGS = 34;
[Target(OS(Linux))]
const _STACK_SI_ADDR: ulong = 16;
[Target(OS(Linux))]
const _STACK_SS_SIZE: ulong = 16;
[Target(OS(Linux))]
const _STACK_SS_FLAGS: ulong = 8;

[Target(OS(Mac))]
const _STACK_ACTION_SIZE: ulong = 16;
[Target(OS(Mac))]
const _STACK_ACTION_HANDLER: ulong = 0;
[Target(OS(Mac))]
const _STACK_ACTION_FLAGS: ulong = 12;
[Target(OS(Mac))]
const _STACK_SA_FLAGS = 65;
[Target(OS(Mac))]
const _STACK_SA_SIGINFO = 64;
[Target(OS(Mac))]
const _STACK_SIGBUS = 10;
[Target(OS(Mac))]
const _STACK_SS_DISABLE = 4;
[Target(OS(Mac))]
const _STACK_PAGE_SIZE_NAME = 29;
[Target(OS(Mac))]
const _STACK_MAP_FLAGS = 4098;
[Target(OS(Mac))]
const _STACK_SI_ADDR: ulong = 24;
[Target(OS(Mac))]
const _STACK_SS_SIZE: ulong = 8;
[Target(OS(Mac))]
const _STACK_SS_FLAGS: ulong = 16;

# SIGSEGV.
[Target(OS(Linux) || OS(Mac))]
const _STACK_SIGSEGV = 11;

[Target(OS(Linux) || OS(Mac))]
const _pep_stack_page: ulong = sysconf(_STACK_PAGE_SIZE_NAME) as ulong;

# The actions SIGSEGV and SIGBUS had before `_pep_stack_guard_start`, one
# after the other: what a fault that is not an overflow goes to.
[Target(OS(Linux) || OS(Mac))]
const _pep_stack_old_actions: __ptr<u8> = calloc(2, _STACK_ACTION_SIZE);

# The lowest address of the calling thread's stack, and the base of the
# mapping of the fiber running on it (its guard page), or 0 while the thread
# runs on its own stack.
[Target(OS(Linux) || OS(Mac))]
[ThreadLocal]
var _pep_stack_low: ulong;
[Target(OS(Linux) || OS(Mac))]
[ThreadLocal]
var _pep_stack_fiber_base: ulong;

# The calling thread's alternate signal stack mapping (guard page included),
# or null.
[Target(OS(Linux) || OS(Mac))]
[ThreadLocal]
var _pep_stack_signal_stack: __ptr<void>;

# Installs the handler and sets up the main thread. The compiler calls it
# at the start of `main`.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_start() {
    _pep_stack_guard_thread_start();
    __ptr<u8> action = calloc(1, _STACK_ACTION_SIZE);
    __ptr<extern (int, __ptr<void>, __ptr<void>) => void> handler = action + _STACK_ACTION_HANDLER;
    handler[0] = _pep_stack_overflow_handler;
    __ptr<int> flags = action + _STACK_ACTION_FLAGS;
    flags[0] = _STACK_SA_FLAGS;
    sigaction(_STACK_SIGSEGV, action, _pep_stack_old_actions);
    sigaction(_STACK_SIGBUS, action, _pep_stack_old_actions + _STACK_ACTION_SIZE);
    free(action);
}

# Sets up the calling thread: records where its stack ends and gives it an
# alternate signal stack. A thread the system cannot give one runs without.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_thread_start() {
    _pep_stack_low = _pep_stack_thread_low();
    var length = _STACK_SIGNAL_STACK_SIZE + _pep_stack_page;
    var base = mmap(__null, length, 3, _STACK_MAP_FLAGS, -1, 0);
    if (unsafe_cast<long>(base) == -1) {
        return;
    }
    mprotect(base, _pep_stack_page, 0);
    __ptr<u8> stack = calloc(1, 24);
    __ptr<__ptr<u8>> sp = stack;
    __ptr<u8> bytes = base;
    sp[0] = bytes + _pep_stack_page;
    __ptr<ulong> size = stack + _STACK_SS_SIZE;
    size[0] = _STACK_SIGNAL_STACK_SIZE;
    if (sigaltstack(stack, __null) == 0) {
        _pep_stack_signal_stack = base;
    } else {
        munmap(base, length);
    }
    free(stack);
}

# Undoes `_pep_stack_guard_thread_start` as a thread ends: turns its
# alternate signal stack off and unmaps it.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_thread_end() {
    if (_pep_stack_signal_stack == __null) {
        return;
    }
    __ptr<u8> stack = calloc(1, 24);
    __ptr<int> flags = stack + _STACK_SS_FLAGS;
    flags[0] = _STACK_SS_DISABLE;
    sigaltstack(stack, __null);
    free(stack);
    munmap(_pep_stack_signal_stack, _STACK_SIGNAL_STACK_SIZE + _pep_stack_page);
    _pep_stack_signal_stack = __null;
}

# Records the fiber about to run on the calling thread: `base` is its stack
# mapping, whose lowest page is the guard, or null for the thread's own stack.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_enter_fiber(base: __ptr<void>) {
    _pep_stack_fiber_base = unsafe_cast<ulong>(base);
}

# The lowest address of the calling thread's stack.
[Target(OS(Linux))]
_pep_stack_thread_low(): ulong {
    __ptr<u8> attributes = calloc(1, 128);
    __ptr<__ptr<void>> address = calloc(1, 8);
    __ptr<ulong> size = calloc(1, 8);
    ulong low = 0;
    if (pthread_getattr_np(pthread_self(), attributes) == 0) {
        if (pthread_attr_getstack(attributes, address, size) == 0) {
            low = unsafe_cast<ulong>(address[0]);
        }
        pthread_attr_destroy(attributes);
    }
    free(attributes);
    free(address);
    free(size);
    return low;
}

[Target(OS(Mac))]
_pep_stack_thread_low(): ulong {
    var thread = pthread_self();
    return unsafe_cast<ulong>(pthread_get_stackaddr_np(thread)) - pthread_get_stacksize_np(thread);
}

# Whether a fault at `address` is an overflow of the stack whose lowest
# usable address is `low` (0: none known): it lies in the reach below it, or
# in its lowest page, where a glibc that counts the guard page reports it.
[Target(OS(Linux) || OS(Mac))]
[Unsafe("overflow")]
_pep_stack_overflowed(address: ulong, low: ulong): bool {
    return low != 0 && address < low + _pep_stack_page && address + _STACK_GUARD_REACH >= low;
}

# The SIGSEGV and SIGBUS handler, on the thread's alternate signal stack.
[Target(OS(Linux) || OS(Mac))]
[Unsafe("overflow")]
_pep_stack_overflow_handler(number: int, info: __ptr<void>, context: __ptr<void>) {
    # A thread with no alternate stack (one C code started) never set the
    # thread-locals, and reading one there can allocate on macOS: the
    # context's uc_stack.ss_flags, at byte 24 on every target, says so.
    __ptr<u8> interrupted = context;
    __ptr<int> stack_flags = interrupted + 24;
    if ((stack_flags[0] & _STACK_SS_DISABLE) == 0) {
        __ptr<u8> bytes = info;
        __ptr<ulong> fault = bytes + _STACK_SI_ADDR;
        var fiber = _pep_stack_fiber_base;
        var low = fiber != 0 ? fiber + _pep_stack_page : _pep_stack_low;
        if (_pep_stack_overflowed(fault[0], low)) {
            _pep_write_error(_STACK_OVERFLOW_MESSAGE);
            abort();
        }
    }
    __ptr<u8> old = _pep_stack_old_actions + (number == _STACK_SIGSEGV ? 0 : _STACK_ACTION_SIZE);
    __ptr<ulong> old_handler = old + _STACK_ACTION_HANDLER;
    __ptr<int> old_flags = old + _STACK_ACTION_FLAGS;
    var previous = old_handler[0];
    # SIG_DFL is 0 and SIG_IGN 1: put the old action back, and the fault,
    # happening again, takes it.
    if (previous <= 1) {
        sigaction(number, old, __null);
        return;
    }
    if ((old_flags[0] & _STACK_SA_SIGINFO) != 0) {
        var chained = unsafe_cast<__ptr<void>>(previous) as extern (int, __ptr<void>, __ptr<void>) => void;
        chained(number, info, context);
    } else {
        var chained = unsafe_cast<__ptr<void>>(previous) as extern (int) => void;
        chained(number);
    }
}

[Target(OS(Wasi))]
export _pep_stack_guard_start() {}

[Target(OS(Wasi))]
export _pep_stack_guard_thread_start() {}

[Target(OS(Wasi))]
export _pep_stack_guard_thread_end() {}

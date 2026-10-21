# Stack overflow reports: a thread that runs past the end of its stack hits
# a guard page, and instead of the silent crash that follows, the program
# writes `panic: stack overflow` to standard error and aborts, as a panic
# does. There is too little stack left to format anything, or to print a
# backtrace, so the message is a fixed string written with one system call,
# and the panic hook (`set_panic_hook`) does not run.
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
# stack (`sigaltstack`, one per thread, from the C heap), since the faulting
# stack has no room left. It reports an overflow only when the fault address
# lies next to the stack pointer the signal's context saved, so it needs no
# record of which stack (a thread's or a task fiber's) was running, and
# switching fibers costs nothing extra. Any other fault goes to the handler
# that was there before, or, when there was none, restores the default
# action and returns, so the fault happens again and ends the program as it
# always did.
#
# Nothing here runs on a hot path: once per program, once per `Thread`
# start and end, and on Windows once per fiber stack (fibers are reused).

extern void* malloc(ulong size);
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

# 1 once `_pep_stack_guard_start` has installed the handler.
const _pep_stack_installed: __ptr<int> = calloc(1, 4);

# Whether `main` installed the stack overflow handler: false in a program
# built by a compiler older than the call (or on WASI). The overflow tests
# check it first, so a missing call fails with that reason, not a crash.
export _pep_stack_guard_installed(): bool {
    return _pep_stack_installed[0] == 1;
}

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
    _pep_stack_installed[0] = 1;
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
extern void* signal(int number, void* handler);
[Target(OS(Linux) || OS(Mac))]
extern void memset(void* p, int c, ulong n);

# How far from the faulting stack pointer a fault still counts as an
# overflow: a call or push faults just below it, and a frame that moves the
# stack pointer past the guard page faults above it, as far as the frame
# reaches.
[Target(OS(Linux) || OS(Mac))]
const _STACK_GUARD_BELOW: ulong = 65536;
[Target(OS(Linux) || OS(Mac))]
const _STACK_GUARD_ABOVE: ulong = 1048576;

# The handler's own stack.
[Target(OS(Linux) || OS(Mac))]
const _STACK_SIGNAL_STACK_SIZE: ulong = 65536;

# The struct sigaction layout: its size, and where sa_flags and the handler
# sit. glibc puts the handler first and a 128-byte sigset_t before the flags;
# bionic on 64-bit Android uses the kernel's layout, flags first; Apple's has
# a 4-byte sigset_t. Then SA_SIGINFO | SA_ONSTACK, SA_SIGINFO, SIGBUS,
# SS_DISABLE, si_addr's offset in siginfo_t, and the offsets of ss_size and
# ss_flags in stack_t.
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
const _STACK_SI_ADDR: ulong = 24;
[Target(OS(Mac))]
const _STACK_SS_SIZE: ulong = 8;
[Target(OS(Mac))]
const _STACK_SS_FLAGS: ulong = 16;

# SIGSEGV.
[Target(OS(Linux) || OS(Mac))]
const _STACK_SIGSEGV = 11;

# The actions SIGSEGV and SIGBUS had before `_pep_stack_guard_start`, one
# after the other: what a fault that is not an overflow goes to.
[Target(OS(Linux) || OS(Mac))]
const _pep_stack_old_actions: __ptr<u8> = calloc(2, _STACK_ACTION_SIZE);

# The calling thread's alternate signal stack block (see
# `_pep_stack_guard_thread_start`), or null.
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
    _pep_stack_installed[0] = 1;
}

# Sends the faults on SIGSEGV or SIGBUS (`number`) that are not a stack
# overflow to `handler`, in place of the action the signal had before the
# program started, as `signal(number, handler)` would without the stack
# guard. In a program whose `main` did not install the guard (a compiler
# older than it), it calls `signal` itself. The test runner ends a test's
# processes this way (testing/runner.pep).
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_set_fallback(number: int, handler: extern (int) => void) {
    if (_pep_stack_installed[0] == 0) {
        signal(number, handler);
        return;
    }
    __ptr<u8> old = _pep_stack_old_actions + (number == _STACK_SIGSEGV ? 0 : _STACK_ACTION_SIZE);
    memset(old, 0, _STACK_ACTION_SIZE);
    __ptr<extern (int) => void> slot = old + _STACK_ACTION_HANDLER;
    slot[0] = handler;
}

# Gives the calling thread an alternate signal stack: one block from the C
# heap (not zeroed) holding the stack_t that describes it, then the stack,
# so a thread start costs one `malloc` and one `sigaltstack`. A thread the
# system cannot give one runs without.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_thread_start() {
    __ptr<u8> block = malloc(32 + _STACK_SIGNAL_STACK_SIZE);
    if (block == __null) {
        return;
    }
    __ptr<__ptr<u8>> sp = block;
    sp[0] = block + 32;
    __ptr<ulong> size = block + _STACK_SS_SIZE;
    size[0] = _STACK_SIGNAL_STACK_SIZE;
    __ptr<int> flags = block + _STACK_SS_FLAGS;
    flags[0] = 0;
    if (sigaltstack(block, __null) == 0) {
        _pep_stack_signal_stack = block;
    } else {
        free(block);
    }
}

# Undoes `_pep_stack_guard_thread_start` as a thread ends: turns its
# alternate signal stack off and frees it.
[Target(OS(Linux) || OS(Mac))]
export _pep_stack_guard_thread_end() {
    __ptr<u8> block = _pep_stack_signal_stack;
    if (block == __null) {
        return;
    }
    __ptr<int> flags = block + _STACK_SS_FLAGS;
    flags[0] = _STACK_SS_DISABLE;
    sigaltstack(block, __null);
    free(block);
    _pep_stack_signal_stack = __null;
}

# The stack pointer when the fault happened, from the handler's `context`
# (a ucontext_t): Linux keeps it in uc_mcontext (x86-64 gregs[REG_RSP], or
# AArch64's sigcontext.sp), macOS in the mcontext uc_mcontext points at
# (after its 16-byte exception state: x86-64 __rsp, or AArch64 __sp).
[Target(OS(Linux) && Arch(x64))]
_pep_stack_pointer(context: __ptr<u8>): ulong {
    __ptr<ulong> sp = context + 160;
    return sp[0];
}

[Target(OS(Linux) && Arch(aarch64))]
_pep_stack_pointer(context: __ptr<u8>): ulong {
    __ptr<ulong> sp = context + 432;
    return sp[0];
}

[Target(OS(Mac) && Arch(x64))]
_pep_stack_pointer(context: __ptr<u8>): ulong {
    __ptr<__ptr<u8>> machine = context + 48;
    __ptr<ulong> sp = machine[0] + 72;
    return sp[0];
}

[Target(OS(Mac) && Arch(aarch64))]
_pep_stack_pointer(context: __ptr<u8>): ulong {
    __ptr<__ptr<u8>> machine = context + 48;
    __ptr<ulong> sp = machine[0] + 264;
    return sp[0];
}

# The SIGSEGV and SIGBUS handler, on the thread's alternate signal stack.
# A fault next to the stack pointer is an overflow, whichever stack it is
# (a thread's or a task fiber's), so nothing has to track which one runs.
[Target(OS(Linux) || OS(Mac))]
[Unsafe("overflow")]
_pep_stack_overflow_handler(number: int, info: __ptr<void>, context: __ptr<void>) {
    __ptr<u8> bytes = info;
    __ptr<ulong> fault = bytes + _STACK_SI_ADDR;
    var address = fault[0];
    var sp = _pep_stack_pointer(context);
    if (address + _STACK_GUARD_BELOW >= sp && address < sp + _STACK_GUARD_ABOVE) {
        _pep_write_error(_STACK_OVERFLOW_MESSAGE);
        abort();
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

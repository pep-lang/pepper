## The running program's arguments and exit, kept for the deprecated
## prelude `arguments()` and `exit()`; the `process` module has them now.

# Imported so the allocator's globals exist before `_pep_forked`'s.
import "internals";

[Target(OS(Linux))]
extern void* fopen(char* path, char* mode);
[Target(OS(Linux))]
extern ulong fread(void* buffer, ulong size, ulong count, void* stream);
[Target(OS(Linux))]
extern int fclose(void* stream);
[Target(OS(Mac))]
extern int* _NSGetArgc();
[Target(OS(Mac))]
extern void* _NSGetArgv();
[Target(OS(Windows))]
extern int* __p___argc();
[Target(OS(Windows))]
extern void* __p___argv();
[Target(OS(Windows))]
extern void* __p___wargv();
# The Universal CRT fills `__wargv` only for a `wmain`, or when asked here.
[Target(OS(Windows))]
extern int _configure_wide_argv(int mode);
[Target(OS(Windows))]
extern ulong wcslen(ushort* text);
[Target(OS(Windows))]
extern void* malloc(ulong size);
[Target(OS(Windows))]
extern void free(void* pointer);
[Target(OS(Windows))]
extern void memcpy(void* dest, void* src, ulong n);
[Target(OS(Windows))]
extern int WideCharToMultiByte(
    uint codepage, uint flags, ushort* src, int src_len, char* dst, int dst_len, void* default_char, int* used_default
);
[Target(OS(Wasi))]
extern ushort __wasi_args_sizes_get(void* count, void* buffer_size);
[Target(OS(Wasi))]
extern ushort __wasi_args_get(void* values, void* buffer);
extern void _Exit(int status);
extern int fflush(void* stream);
# C's `exit`. The IR name `exit` is Pepper's deprecated `exit`, so the
# symbol is spelled with LLVM's `\x01` (no prefix added; Mach-O's C
# symbols start with `_`) until pep-lang/pepper#76 is fixed.
[Target(!OS(Mac))]
[Link(name = "\x01exit")]
extern void _c_exit(int status);
[Target(OS(Mac))]
[Link(name = "\x01_exit")]
extern void _c_exit(int status);

# Nonzero in the copy `process.fork()` starts: its exit skips the parent's
# `atexit` handlers. Process-wide, so a thread the copy starts skips them too.
const _pep_forked: __ptr<int> = _pep_new_forked_flag();

_pep_new_forked_flag(): __ptr<int> {
    __ptr<int> flag = _pep_malloc(4);
    flag[0] = 0;
    return flag;
}

## Deprecated: use `process.arguments` instead.
##
## Returns the program's command-line arguments, as `process.arguments()`
## does.
##
## @returns the program name followed by its arguments
[Deprecated("use 'process.arguments' instead (import process)")]
export arguments(): Array<String> {
    return _arguments();
}

# The arguments a `main(args: String[])` receives: the compiler's
# synthesized `main()` calls this (sema's `lower_main_arguments`), under a
# name a program's own `arguments` cannot shadow. `process.arguments()`
# calls it too.
export _pep_arguments(): Array<String> {
    return _arguments();
}

## Deprecated: use `process.exit` instead.
##
## Ends the program at once with status `code`, as `process.exit(code)`
## does: C's `atexit` handlers run and the C output streams are flushed.
##
## @param code the exit status: 0 for success, anything else for failure
[Deprecated("use 'process.exit' instead (import process)")]
export exit(code: int) {
    _pep_exit(code);
}

# Ends the program: `process.exit` and the deprecated `exit`. C's `exit`
# runs the `atexit` handlers and flushes C stdio; a forked copy ends as
# `_pep_exit_now` does.
export _pep_exit(code: int) {
    if (__atomic_load<int>(_pep_forked) != 0) {
        _pep_exit_now(code);
    }
    _c_exit(code);
}

# Ends the program without running `atexit` handlers, after flushing C
# stdio: a forked copy, whose handlers are the parent's, Windows' `exec`,
# which stands in for replacing the process, and a test's watchdog.
export _pep_exit_now(code: int) {
    fflush(__null);
    _Exit(code);
}

# Marks this process as a forked copy, for `_pep_exit`.
export _pep_mark_forked() {
    __atomic_store<int>(_pep_forked, 1);
}

# The arguments from the C runtime's `argc`/`argv`.
_arguments_from(count: int, values: __ptr<__ptr<char>>): Array<String> {
    var result = Array<String>();
    var index = 0;
    while (index < count) {
        result.append(String(values[index]));
        index = index + 1;
    }
    return result;
}

[Target(OS(Mac))]
_arguments(): Array<String> {
    __ptr<void> raw = _NSGetArgv();
    __ptr<__ptr<__ptr<char>>> values = raw;
    return _arguments_from(_NSGetArgc()[0], values[0]);
}

# Windows' `argv` is in the ANSI code page, which cannot hold every
# character and is not UTF-8: read the UTF-16 one, split by the same rules.
[Target(OS(Windows))]
_arguments(): Array<String> {
    return _arguments_from(__p___argc()[0], _utf8_argv());
}

# The UTF-8 `argv` `_arguments` reads, converted on the first call and kept
# for the program's life, so a later call costs what the C `argv` does.
[Target(OS(Windows))]
const _pep_utf8_argv: __ptr<ulong> = _pep_new_utf8_argv_slot();

[Target(OS(Windows))]
_pep_new_utf8_argv_slot(): __ptr<ulong> {
    __ptr<ulong> slot = _pep_malloc(8);
    slot[0] = 0;
    return slot;
}

[Target(OS(Windows))]
_utf8_argv(): __ptr<__ptr<char>> {
    var kept = __atomic_load<ulong>(_pep_utf8_argv);
    if (kept != 0) {
        return unsafe_cast<__ptr<__ptr<char>>>(kept);
    }
    __ptr<void> raw = __p___wargv();
    __ptr<__ptr<__ptr<u16>>> wide = raw;
    if (wide[0] == __null) {
        _configure_wide_argv(1);  # _crt_argv_unexpanded_arguments
    }
    if (wide[0] == __null) {
        # Out of memory: the ANSI arguments are better than none.
        __ptr<void> narrow = __p___argv();
        __ptr<__ptr<__ptr<char>>> values = narrow;
        return values[0];
    }
    # C's `malloc`, not `_pep_malloc`: kept for good, it is no test's leak.
    var count = __p___argc()[0] as ulong;
    __ptr<__ptr<char>> values = malloc(count * sizeof<__ptr<char>>() + 1);
    ulong index = 0;
    while (index < count) {
        var value = wide[0][index];
        var text = _pep_win_narrow(value, wcslen(value) as int);
        __ptr<char> copy = malloc(text.size + 1);
        memcpy(copy, text.c_str(), text.size + 1);
        values[index] = copy;
        index = index + 1;
    }
    var made = unsafe_cast<ulong>(values);
    if (!__atomic_cmpxchg<ulong>(_pep_utf8_argv, 0, made)) {
        # Another thread kept its copy first.
        index = 0;
        while (index < count) {
            free(values[index]);
            index = index + 1;
        }
        free(values);
        return unsafe_cast<__ptr<__ptr<char>>>(__atomic_load<ulong>(_pep_utf8_argv));
    }
    return values;
}

# `n` UTF-16 units at `w` as a UTF-8 String, each unpaired surrogate
# becoming U+FFFD: `io`'s `_io_win_narrow`, here so `_arguments` can use it.
[Target(OS(Windows))]
export _pep_win_narrow(w: __ptr<u16>, n: int): String {
    if (n <= 0) {
        return String();
    }
    # A unit takes at most 3 bytes (a pair 4), so one call fills the buffer.
    var capacity = n * 3;
    __ptr<char> buffer = _pep_malloc(capacity as ulong);
    # ASCII, the usual case, is copied without the call.
    var ascii = 0;
    while (ascii < n) {
        if (w[ascii] >= 128) {
            break;
        }
        buffer[ascii] = w[ascii] as char;
        ascii = ascii + 1;
    }
    if (ascii == n) {
        var copied = String(buffer, n as ulong, n as ulong);
        _pep_free(buffer);
        return copied;
    }
    var size = WideCharToMultiByte(65001, 0, w, n, buffer, capacity, __null, __null);  # CP_UTF8
    if (size <= 0) {
        _pep_free(buffer);
        return String();
    }
    var result = String(buffer, size as ulong);
    _pep_free(buffer);
    return result;
}

# WASI hands the arguments to the program through `args_get`, into memory
# the program provides: a pointer per argument, into a buffer holding them
# all, each followed by a NUL byte.
[Target(OS(Wasi))]
_arguments(): Array<String> {
    # Two 32-bit `size_t`s: the count and the buffer's size.
    __ptr<uint> sizes = _pep_malloc(8);
    if (__wasi_args_sizes_get(sizes, sizes + 1) != 0) {
        _pep_free(sizes);
        return Array<String>();
    }
    var count = sizes[0];
    __ptr<__ptr<char>> values = _pep_malloc((count as ulong) * sizeof<__ptr<char>>() + 1);
    __ptr<char> buffer = _pep_malloc((sizes[1] as ulong) + 1);
    _pep_free(sizes);
    var result = Array<String>();
    if (__wasi_args_get(values, buffer) == 0) {
        result = _arguments_from(count as int, values);
    }
    _pep_free(values);
    _pep_free(buffer);
    return result;
}

# glibc keeps `argv` to itself, so Linux reads the arguments back from
# /proc/self/cmdline: each one followed by a NUL byte.
[Target(OS(Linux))]
_arguments(): Array<String> {
    var result = Array<String>();
    var stream = fopen("/proc/self/cmdline", "rb");
    if (stream == __null) {
        return result;
    }
    ulong capacity = 4096;
    ulong size = 0;
    __ptr<char> buffer = _pep_malloc(capacity);
    while (true) {
        if (size == capacity) {
            buffer = _pep_realloc(buffer, capacity, capacity * 2);
            capacity = capacity * 2;
        }
        var read = fread(buffer + size, 1, capacity - size, stream);
        if (read == 0) {
            break;
        }
        size = size + read;
    }
    fclose(stream);
    ulong start = 0;
    ulong index = 0;
    while (index < size) {
        if (buffer[index] == 0) {
            result.append(String(buffer + start, index - start));
            start = index + 1;
        }
        index = index + 1;
    }
    _pep_free(buffer);
    return result;
}

## The running program: its command-line arguments and how it ends.

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
extern void _Exit(int status);
extern int fflush(void* stream);

## Returns the program's command-line arguments.
##
## Element 0 is the program as it was started (usually its path), and the
## arguments typed after it follow in order, as the shell passed them: a
## quoted argument with spaces is one element. Each call builds a new array.
##
## On Windows the arguments are in the process's ANSI code page, so text
## outside it is not preserved.
##
## @returns the program name followed by its arguments
## @example
##     main(): int {
##         var parts = arguments();
##         if (parts.count() > 1) {
##             print(parts[1]);
##         }
##         return 0;
##     }
export arguments(): Array<String> {
    return _arguments();
}

## Ends the program at once with status `code`.
##
## Flushes standard output and every other C output stream first, so text
## printed so far is not lost. Nothing else runs: locals are not released,
## destructors do not run, and other threads stop where they are. Returning
## from `main` is the usual way to end; `exit` is for ending from deep inside
## a call.
##
## @param code the exit status: 0 for success, anything else for failure
##   (only its low 8 bits reach a POSIX parent)
## @example
##     if (arguments().count() < 2) {
##         print("usage: tool FILE");
##         exit(2);
##     }
export exit(code: int) {
    # C `_Exit`, not `exit`: this function takes the name, and flushing
    # here does what `exit` would before it ends the process.
    fflush(__null);
    _Exit(code);
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

[Target(OS(Windows))]
_arguments(): Array<String> {
    __ptr<void> raw = __p___argv();
    __ptr<__ptr<__ptr<char>>> values = raw;
    return _arguments_from(__p___argc()[0], values[0]);
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

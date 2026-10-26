## What the runtime does only on iOS and Android: sending an app's standard
## output and error to the platform's log, and, on Android, taking the
## app's folders from the app (see
## [iOS and Android](../language/mobile.md)).

# Every declaration carries [Target(OS(IOS) || OS(Android))] or a narrower
# target, so nothing here reaches another system's program.
#
# Logging. An app's standard output and error lead nowhere: Android's
# zygote and iOS's launchd point them at /dev/null. So when the program
# starts (a module-scope initializer, which a library runs when it is
# loaded), each of the two that is /dev/null or closed is pointed at a pipe
# instead, and a thread reads it and writes each line to the platform's
# log: logcat on Android (`__android_log_write`, tagged with the program's
# or library's file name), the unified log on iOS (`os_log`, with that name
# as its subsystem). A stream attached to anything else, a terminal or a
# pipe as `adb shell` and `simctl spawn` give a program, or Xcode's console,
# stays as it is. Nothing is checked per write, so printing costs what it
# does elsewhere.
#
# `_pep_write_error` (internals.pep), which panics, backtraces and the
# debugger channel write through, also logs its text itself, at once, so a
# panic reaches the log before the process aborts, whether or not standard
# error is attached.
#
# App folders. Android gives native code no way to find the app's folders,
# so the app passes them to `pepper_set_app_directories`, exported to C
# (and to Java and Kotlin by the bindings). `os.app_directories` reads them,
# and `io.Directory.temp()` uses the cache folder.

# `_pep_platform_log` levels: standard output, standard error, and panics.
const _PEP_LOG_OUTPUT: int = 0;
export const _PEP_LOG_ERROR: int = 1;
# The bytes a reader thread holds at once: a longer line is logged in parts.
const _PEP_LOG_BUFFER: ulong = 4096;

extern void* malloc(ulong size);
extern void* calloc(ulong count, ulong size);
extern void free(void* p);
extern void memcpy(void* dest, void* src, ulong n);
extern void memmove(void* dest, void* src, ulong n);
extern int memcmp(void* a, void* b, ulong n);
extern ulong strlen(char* s);

[Target(OS(IOS) || OS(Android))]
extern int pipe(int* ends);
[Target(OS(IOS) || OS(Android))]
extern int dup2(int from, int to);
[Target(OS(IOS) || OS(Android))]
extern int close(int fd);
[Target(OS(IOS) || OS(Android))]
extern long read(int fd, void* buffer, ulong size);
[Target(OS(IOS) || OS(Android))]
extern int fcntl(int fd, int command, ...);
[Target(OS(IOS) || OS(Android))]
extern int fstat(int fd, void* status);
[Target(OS(IOS) || OS(Android))]
extern int stat(char* path, void* status);
[Target(OS(IOS) || OS(Android))]
extern int pthread_create(void* thread, void* attributes, void* start, void* argument);
[Target(OS(IOS) || OS(Android))]
extern int pthread_detach(void* thread);
[Target(OS(IOS) || OS(Android))]
extern int dladdr(void* address, void* info);
[Target(OS(Android))]
[Link("log")]
extern int __android_log_write(int priority, char* tag, char* text);
[Target(OS(IOS))]
extern void* os_log_create(char* subsystem, char* category);
[Target(OS(IOS))]
extern void _os_log_impl(void* dso, void* log, u8 kind, char* format, void* buffer, uint size);

# The logging state, from C's malloc and kept for the process's life:
# [1] and [2] are 1 when standard output or error goes to the log through a
# reader thread; [3] is the tag (a C string); on iOS [4] is the image's
# Mach-O header (os_log's `dso`) and [5] the os_log handle.
[Target(OS(IOS) || OS(Android))]
const _pep_platform_log_state: __ptr<ulong> = _pep_platform_log_start();

[Target(OS(IOS) || OS(Android))]
_pep_platform_log_start(): __ptr<ulong> {
    __ptr<ulong> state = calloc(6, 8);
    # Dl_info { dli_fname, dli_fbase, dli_sname, dli_saddr }
    __ptr<ulong> info = calloc(4, 8);
    __ptr<char> tag = "pepper";
    if (dladdr(__function_pointer(_pep_platform_log_start), info) != 0 && info[0] != 0) {
        tag = _pep_platform_log_tag(unsafe_cast<__ptr<char>>(info[0]));
    }
    state[3] = unsafe_cast<ulong>(tag);
    [Target(OS(IOS))]
    {
        state[4] = info[1];
        state[5] = unsafe_cast<ulong>(os_log_create(tag, "pepper"));
    }
    free(info);
    for (var fd in 1..3) {
        if (_pep_stream_detached(fd)) {
            state[fd] = _pep_platform_log_route(fd) ? 1 : 0;
        }
    }
    return state;
}

# The file name of the image at `path`, without a `lib` prefix or a `.so`
# or `.dylib` extension: `greeter` for `.../libgreeter.so`. A C string from
# C's malloc.
[Target(OS(IOS) || OS(Android))]
_pep_platform_log_tag(path: __ptr<char>): __ptr<char> {
    var size = strlen(path);
    ulong start = size;
    while (start > 0 && path[start - 1] != '/') {
        start -= 1;
    }
    var end = size;
    for (var extension in [".so", ".dylib"]) {
        var length = extension.size;
        if (end - start > length && memcmp(path + end - length, extension.c_str(), length) == 0) {
            end -= length;
        }
    }
    if (end - start > 3 && memcmp(path + start, "lib", 3) == 0) {
        start += 3;
    }
    __ptr<char> tag = malloc(end - start + 1);
    memcpy(tag, path + start, end - start);
    tag[end - start] = 0;
    return tag;
}

# Whether `fd` leads nowhere: closed, or /dev/null. The first 16 bytes of
# struct stat identify the file on every layout here (Android's st_dev and
# st_ino, Darwin's st_dev, st_mode, st_nlink and st_ino).
[Target(OS(IOS) || OS(Android))]
_pep_stream_detached(fd: int): bool {
    __ptr<u8> stream = calloc(1, 256);
    __ptr<u8> null_device = calloc(1, 256);
    var detached = fstat(fd, stream) != 0
        || (stat("/dev/null", null_device) == 0 && memcmp(stream, null_device, 16) == 0);
    free(stream);
    free(null_device);
    return detached;
}

# Points `fd` at a pipe whose reader thread logs what it reads; whether it
# could.
[Target(OS(IOS) || OS(Android))]
_pep_platform_log_route(fd: int): bool {
    __ptr<int> ends = malloc(8);
    if (pipe(ends) != 0) {
        free(ends);
        return false;
    }
    # The read end stays out of child processes (F_SETFD, FD_CLOEXEC).
    fcntl(ends[0], 2, 1);
    # The thread's argument: the read end, then the level, taken over by it.
    __ptr<int> job = malloc(8);
    job[0] = ends[0];
    job[1] = fd == 1 ? _PEP_LOG_OUTPUT : _PEP_LOG_ERROR;
    __ptr<__ptr<void>> thread = malloc(8);
    var started = pthread_create(thread, __null, __function_pointer(_pep_platform_log_reader), job) == 0;
    if (started) {
        pthread_detach(thread[0]);
        dup2(ends[1], fd);
    } else {
        close(ends[0]);
        free(job);
    }
    close(ends[1]);
    free(ends);
    free(thread);
    return started;
}

# A reader thread: logs each line read from `job`'s pipe until it closes.
# shortcut: a read the system interrupts ends the thread; retry on EINTR if a
# signal handler without SA_RESTART ever runs on it.
[Target(OS(IOS) || OS(Android))]
_pep_platform_log_reader(job: __ptr<void>): __ptr<void> {
    __ptr<int> fields = job;
    var fd = fields[0];
    var level = fields[1];
    free(job);
    __ptr<char> buffer = malloc(_PEP_LOG_BUFFER);
    ulong held = 0;
    while (true) {
        var count = read(fd, buffer + held, _PEP_LOG_BUFFER - held);
        if (count <= 0) {
            break;
        }
        held += count as ulong;
        # Up to the last line break, or all of a full buffer.
        var end = held;
        while (end > 0 && buffer[end - 1] != '\n') {
            end -= 1;
        }
        if (end == 0 && held == _PEP_LOG_BUFFER) {
            end = held;
        }
        if (end > 0) {
            _pep_platform_log(level, buffer, end);
            memmove(buffer, buffer + end, held - end);
            held -= end;
        }
    }
    if (held > 0) {
        _pep_platform_log(level, buffer, held);
    }
    close(fd);
    free(buffer);
    return __null;
}

# Whether standard output (1) or error (2) goes to the log through a reader
# thread, rather than where the program was started with.
[Target(OS(IOS) || OS(Android))]
export _pep_platform_log_routes(fd: int): bool {
    # Null when a module-scope initializer panics before this one ran.
    return _pep_platform_log_state != __null && _pep_platform_log_state[fd] == 1;
}

# Logs the `size` bytes at `text` at `level`, a message for each line.
[Target(OS(IOS) || OS(Android))]
export _pep_platform_log(level: int, text: __ptr<char>, size: ulong) {
    if (_pep_platform_log_state == __null) {
        return;
    }
    # One NUL-terminated copy, each line break made a NUL in turn.
    __ptr<char> lines = malloc(size + 1);
    if (lines == __null) {
        return;
    }
    memcpy(lines, text, size);
    lines[size] = 0;
    ulong start = 0;
    while (start < size) {
        var end = start;
        while (end < size && lines[end] != '\n') {
            end += 1;
        }
        lines[end] = 0;
        _pep_platform_log_line(level, lines + start);
        start = end + 1;
    }
    free(lines);
}

[Target(OS(Android))]
_pep_platform_log_line(level: int, line: __ptr<char>) {
    # ANDROID_LOG_INFO and ANDROID_LOG_ERROR.
    __android_log_write(level == _PEP_LOG_OUTPUT ? 4 : 6, unsafe_cast<__ptr<char>>(_pep_platform_log_state[3]), line);
}

[Target(OS(IOS))]
_pep_platform_log_line(level: int, line: __ptr<char>) {
    if (_pep_platform_log_state[5] == 0) {
        return;
    }
    # What clang's os_log builds for "%{public}s": a header (non-scalar
    # items, one item), then the item (a public string, 8 bytes) and the
    # pointer.
    __ptr<u8> buffer = malloc(16);
    buffer[0] = 2;
    buffer[1] = 1;
    buffer[2] = 34;
    buffer[3] = 8;
    __ptr<__ptr<char>> argument = malloc(8);
    argument[0] = line;
    memcpy(buffer + 4, argument, 8);
    # OS_LOG_TYPE_DEFAULT and OS_LOG_TYPE_ERROR. The format must lie in the
    # image `dso` names, as a literal here does.
    _os_log_impl(
        unsafe_cast<__ptr<void>>(_pep_platform_log_state[4]),
        unsafe_cast<__ptr<void>>(_pep_platform_log_state[5]),
        level == _PEP_LOG_OUTPUT ? 0 : 16,
        "%{public}s",
        buffer,
        12
    );
    free(argument);
    free(buffer);
}

# The folders `pepper_set_app_directories` gave, as C strings from C's
# malloc: [0] the files folder, [1] the cache folder; 0 until it is called.
[Target(OS(Android))]
const _pep_app_directories: __ptr<ulong> = calloc(2, 8);

## Tells the Pepper runtime where the app's folders are, as Android gives
## native code no way to find them: call it once, early (in the
## `Application`'s or first activity's `onCreate`), before Pepper code uses
## them. The C library exports it as `pepper_set_app_directories`, and the
## Java bindings (`--bindings java`, `--lib aar`) as
## `pepperSetAppDirectories` on the library's class:
##
##     Greeter.pepperSetAppDirectories(getFilesDir().getPath(), getCacheDir().getPath());
##
## Then `os.app_directories()` returns them, and `io.Directory.temp()` is
## the cache folder (unless `TMPDIR` is set). A later call replaces them.
##
## @param files the app's files folder, `Context.getFilesDir()`
## @param cache the app's cache folder, `Context.getCacheDir()`
[Target(OS(Android))]
[Export]
export pepper_set_app_directories(files: String, cache: String) {
    # Never freed: a thread may still be reading the folders a later call
    # replaces.
    __atomic_store<ulong>(_pep_app_directories, unsafe_cast<ulong>(_pep_c_copy(files)));
    __atomic_store<ulong>(_pep_app_directories + 1, unsafe_cast<ulong>(_pep_c_copy(cache)));
}

# A NUL-terminated copy of `text` from C's malloc.
[Target(OS(Android))]
_pep_c_copy(text: String): __ptr<char> {
    __ptr<char> copy = malloc(text.size + 1);
    memcpy(copy, text.c_str(), text.size + 1);
    return copy;
}

# The folder `pepper_set_app_directories` gave: 0 for files, 1 for the
# cache; null before it is called.
[Target(OS(Android))]
export _pep_app_directory(index: ulong): __ptr<char> {
    return unsafe_cast<__ptr<char>>(__atomic_load<ulong>(_pep_app_directories + index));
}

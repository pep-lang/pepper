# POSIX (Linux, macOS) platform layer for process. Every declaration carries
# [Target(!OS(Windows))] or a narrower target; sys_windows.pep declares the
# same `_process_sys_*` functions with the same signatures for Windows.
#
# A child starts with posix_spawnp, which searches the PATH and reports a
# failed exec as its result. Pipes are made close-on-exec, so a child
# started by another thread does not inherit them; posix_spawn's file
# actions give the child its own ends as descriptors 0, 1 and 2. On macOS,
# POSIX_SPAWN_CLOEXEC_DEFAULT closes every other descriptor in the child.

import io;
import os;
import "child";
import "command";

[Target(!OS(Windows))]
extern int posix_spawnp(int* pid, char* file, void* actions, void* attributes, void* argv, void* envp);
[Target(!OS(Windows))]
extern int posix_spawn_file_actions_init(void* actions);
[Target(!OS(Windows))]
extern int posix_spawn_file_actions_destroy(void* actions);
[Target(!OS(Windows))]
extern int posix_spawn_file_actions_adddup2(void* actions, int from, int to);
[Target(!OS(Windows))]
extern int posix_spawn_file_actions_addopen(void* actions, int descriptor, char* path, int flags, uint mode);
[Target(!OS(Windows))]
extern int posix_spawn_file_actions_addchdir_np(void* actions, char* path);
[Target(OS(Mac))]
extern int posix_spawn_file_actions_addinherit_np(void* actions, int descriptor);
[Target(!OS(Windows))]
extern int posix_spawnattr_init(void* attributes);
[Target(!OS(Windows))]
extern int posix_spawnattr_destroy(void* attributes);
[Target(!OS(Windows))]
extern int posix_spawnattr_setflags(void* attributes, short flags);
[Target(OS(Linux))]
extern int pipe2(int* descriptors, int flags);
[Target(OS(Mac))]
extern int pipe(int* descriptors);
[Target(OS(Mac))]
extern int fcntl(int descriptor, int command, ...);
[Target(!OS(Windows))]
extern int close(int descriptor);
[Target(!OS(Windows))]
extern int waitpid(int pid, int* status, int options);
[Target(!OS(Windows))]
extern int kill(int pid, int signal);
[Target(!OS(Windows))]
extern int getpid();
[Target(OS(Linux))]
extern long readlink(char* path, char* buffer, ulong size);
[Target(OS(Mac))]
extern int _NSGetExecutablePath(char* buffer, uint* size);
[Target(OS(Mac))]
extern char* realpath(char* path, char* resolved);
[Target(!OS(Windows))]
extern void free(void* pointer);

# A child process: its id.
[Target(!OS(Windows))]
export type _ProcessHandle = int;

# Bigger than posix_spawn_file_actions_t and posix_spawnattr_t on both
# systems (80 and 336 bytes on glibc, a pointer on macOS).
[Target(!OS(Windows))]
const _PROCESS_SPAWN_STATE_SIZE: ulong = 512;

[Target(!OS(Windows))]
export _process_sys_names_ignore_case(): bool {
    return false;
}

[Target(!OS(Windows))]
export _process_sys_error_message(code: io.ErrorCode): String {
    return io._io_sys_error_message(code);
}

[Target(!OS(Windows))]
export _process_sys_id(): ulong {
    return getpid() as ulong;
}

[Target(OS(Linux))]
export _process_sys_executable_path(): io.IoResult<io.Path> {
    ulong capacity = 4096;
    while (true) {
        __ptr<char> buffer = _pep_malloc(capacity);
        var link = "/proc/self/exe";
        var size = readlink(link.c_str(), buffer, capacity);
        if (size < 0) {
            var error = io.IoError.last();
            _pep_free(buffer);
            return io.IoResult<io.Path>.err(error);
        }
        if ((size as ulong) < capacity) {
            var path = String(buffer, size as ulong);
            _pep_free(buffer);
            return io.IoResult<io.Path>.ok(io.Path(path));
        }
        _pep_free(buffer);
        capacity = capacity * 2;
    }
    return io.IoResult<io.Path>.err(io.IoError());
}

[Target(OS(Mac))]
export _process_sys_executable_path(): io.IoResult<io.Path> {
    __ptr<uint> size = _pep_malloc(4);
    size[0] = 0;
    _NSGetExecutablePath(__null, size);
    __ptr<char> buffer = _pep_malloc(size[0] as ulong + 1);
    var failed = _NSGetExecutablePath(buffer, size) != 0;
    _pep_free(size);
    if (failed) {
        _pep_free(buffer);
        return io.IoResult<io.Path>.err(io.IoError(22, "the executable path does not fit"));
    }
    var resolved = realpath(buffer, __null);
    _pep_free(buffer);
    if (resolved == __null) {
        return io.IoResult<io.Path>.err(io.IoError.last());
    }
    var path = String(resolved);
    free(resolved);
    return io.IoResult<io.Path>.ok(io.Path(path));
}

# A new pipe, both ends close-on-exec: [read, write] in `descriptors`.
[Target(OS(Linux))]
_process_pipe(descriptors: __ptr<int>): bool {
    return pipe2(descriptors, 524288) == 0;  # O_CLOEXEC
}

[Target(OS(Mac))]
_process_pipe(descriptors: __ptr<int>): bool {
    if (pipe(descriptors) != 0) {
        return false;
    }
    fcntl(descriptors[0], 2, 1);  # F_SETFD, FD_CLOEXEC
    fcntl(descriptors[1], 2, 1);
    return true;
}

# Flags for posix_spawnattr_setflags.
[Target(OS(Linux))]
_process_spawn_flags(): short {
    return 0;
}

[Target(OS(Mac))]
_process_spawn_flags(): short {
    return 16384;  # POSIX_SPAWN_CLOEXEC_DEFAULT
}

# Keeps the parent's descriptor `descriptor` open in the child.
[Target(OS(Linux))]
_process_inherit(actions: __ptr<void>, descriptor: int) {
    # Descriptors without close-on-exec, as 0, 1 and 2 are, stay open.
}

[Target(OS(Mac))]
_process_inherit(actions: __ptr<void>, descriptor: int) {
    posix_spawn_file_actions_addinherit_np(actions, descriptor);
}

# Arranges standard stream `descriptor` of the child per `stream`; for a
# pipe, stores the parent's end in `parent_end` and the child's in
# `child_end` (both -1 otherwise). Returns 0 or an errno value.
[Target(!OS(Windows))]
_process_stream(
    actions: __ptr<void>, descriptor: int, stream: Stream, parent_end: __ptr<int>, child_end: __ptr<int>
): int {
    parent_end[0] = -1;
    child_end[0] = -1;
    if (stream == Stream.Inherit) {
        _process_inherit(actions, descriptor);
        return 0;
    }
    if (stream == Stream.Null) {
        var device = "/dev/null";
        var flags = descriptor == 0 ? 0 : 1;  # O_RDONLY, O_WRONLY
        return posix_spawn_file_actions_addopen(actions, descriptor, device.c_str(), flags, 0);
    }
    __ptr<int> ends = _pep_malloc(8);
    if (!_process_pipe(ends)) {
        var code = io.IoError.last().code;
        _pep_free(ends);
        return code;
    }
    # The child reads standard input from the read end and writes the
    # others to the write end.
    var child = descriptor == 0 ? ends[0] : ends[1];
    parent_end[0] = descriptor == 0 ? ends[1] : ends[0];
    child_end[0] = child;
    _pep_free(ends);
    return posix_spawn_file_actions_adddup2(actions, child, descriptor);
}

# A null-terminated array of the C strings of `values`, which must outlive
# it; free it with `_pep_free`.
[Target(!OS(Windows))]
_process_c_strings(values: Array<String>): __ptr<__ptr<char>> {
    __ptr<__ptr<char>> array = _pep_malloc((values.count() + 1) * 8);
    ulong index = 0;
    while (index < values.count()) {
        array[index] = values[index].c_str();
        index = index + 1;
    }
    array[values.count()] = __null;
    return array;
}

[Target(!OS(Windows))]
export _process_sys_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    __ptr<void> actions = _pep_malloc(_PROCESS_SPAWN_STATE_SIZE);
    __ptr<void> attributes = _pep_malloc(_PROCESS_SPAWN_STATE_SIZE);
    posix_spawn_file_actions_init(actions);
    posix_spawnattr_init(attributes);
    posix_spawnattr_setflags(attributes, _process_spawn_flags());

    # [parent, child] ends for stdin, stdout and stderr.
    __ptr<int> ends = _pep_malloc(24);
    var code = _process_stream(actions, 0, stdin, ends, ends + 1);
    if (code == 0) {
        code = _process_stream(actions, 1, stdout, ends + 2, ends + 3);
    } else {
        ends[2] = -1;
        ends[3] = -1;
    }
    if (code == 0) {
        code = _process_stream(actions, 2, stderr, ends + 4, ends + 5);
    } else {
        ends[4] = -1;
        ends[5] = -1;
    }
    var directory = "";
    if (code == 0 && command._working_directory.is_some()) {
        directory = command._working_directory.value().to_string();
        code = posix_spawn_file_actions_addchdir_np(actions, directory.c_str());
    }

    var argument_values = Array<String>();
    argument_values.append(command.program);
    for (var argument in command._arguments) {
        argument_values.append(argument);
    }
    var argv = _process_c_strings(argument_values);
    var environment_values = Array<String>();
    __ptr<__ptr<char>> envp = os._os_environ();
    var built_environment = command._changes_environment();
    if (built_environment) {
        environment_values = command._environment_entries();
        envp = _process_c_strings(environment_values);
    }

    __ptr<int> pid = _pep_malloc(4);
    pid[0] = 0;
    if (code == 0) {
        code = posix_spawnp(pid, command.program.c_str(), actions, attributes, argv, envp);
    }
    var process_id = pid[0];
    _pep_free(pid);
    _pep_free(argv);
    if (built_environment) {
        _pep_free(envp);
    }
    posix_spawn_file_actions_destroy(actions);
    posix_spawnattr_destroy(attributes);
    _pep_free(actions);
    _pep_free(attributes);

    # The child has its ends now; the parent keeps its own.
    var index = 0;
    while (index < 3) {
        if (ends[index * 2 + 1] >= 0) {
            close(ends[index * 2 + 1]);
        }
        index = index + 1;
    }
    if (code != 0) {
        index = 0;
        while (index < 3) {
            if (ends[index * 2] >= 0) {
                close(ends[index * 2]);
            }
            index = index + 1;
        }
        _pep_free(ends);
        var message = _process_sys_error_message(code);
        return io.IoResult<Child>.err(io.IoError(code, $"cannot start '{command.program}': {message}"));
    }
    var child = Child();
    child._handle = process_id;
    child._id = process_id as ulong;
    child._stdin = _process_pipe_file(ends[0], "<child stdin>");
    child._stdout = _process_pipe_file(ends[2], "<child stdout>");
    child._stderr = _process_pipe_file(ends[4], "<child stderr>");
    _pep_free(ends);
    return io.IoResult<Child>.ok(child);
}

# A File owning the pipe end `descriptor`, or a closed File for -1.
[Target(!OS(Windows))]
_process_pipe_file(descriptor: int, name: String): io.File {
    var file = io.File();
    if (descriptor >= 0) {
        file._handle = descriptor;
        file.path = io.Path(name);
    }
    return file;
}

[Target(!OS(Windows))]
export _process_sys_borrowed_file(handle: io.FileHandle): io.File {
    var file = io.File();
    file._handle = handle;
    file._owned = false;
    return file;
}

[Target(!OS(Windows))]
export _process_sys_wait_raw(handle: _ProcessHandle, block: bool): long {
    __ptr<int> status = _pep_malloc(4);
    while (true) {
        status[0] = 0;
        var result = waitpid(handle, status, block ? 0 : 1);  # WNOHANG
        if (result == 0) {
            _pep_free(status);
            return -1;
        }
        if (result < 0) {
            var code = io.IoError.last().code;
            if (code == 4) {  # EINTR
                continue;
            }
            _pep_free(status);
            return -2 - (code as long);
        }
        var value = status[0];
        _pep_free(status);
        var signal = value & 127;
        if (signal == 0) {
            return ((value >> 8) & 255) as long;
        }
        return (signal as long) << 32;
    }
    return -1;
}

[Target(!OS(Windows))]
export _process_sys_kill(handle: _ProcessHandle): io.IoResult<void> {
    if (kill(handle, 9) != 0) {  # SIGKILL
        return io.IoResult<void>.err(io.IoError.last());
    }
    return io.IoResult<void>.ok();
}

[Target(!OS(Windows))]
export _process_sys_release(handle: _ProcessHandle) {}

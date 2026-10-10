# POSIX (Linux, macOS) platform layer for process. Every declaration carries
# [Target(OS(Linux) || OS(Mac))] or a narrower target; sys_windows.pep and
# sys_wasi.pep declare the same `_process_sys_*` functions with the same
# signatures for Windows and WASI.
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

[Target(OS(Linux) || OS(Mac))]
extern int posix_spawnp(int* pid, char* file, void* actions, void* attributes, void* argv, void* envp);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawn_file_actions_init(void* actions);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawn_file_actions_destroy(void* actions);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawn_file_actions_adddup2(void* actions, int from, int to);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawn_file_actions_addopen(void* actions, int descriptor, char* path, int flags, uint mode);
[Target(OS(Mac))]
extern int posix_spawn_file_actions_addchdir_np(void* actions, char* path);
[Target(OS(Linux))]
extern void* dlsym(void* handle, char* name);
[Target(OS(Mac))]
extern int posix_spawn_file_actions_addinherit_np(void* actions, int descriptor);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawnattr_init(void* attributes);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawnattr_destroy(void* attributes);
[Target(OS(Linux) || OS(Mac))]
extern int posix_spawnattr_setflags(void* attributes, short flags);
[Target(OS(Linux))]
extern int execvpe(char* file, void* argv, void* envp);
[Target(OS(Linux))]
extern int pipe2(int* descriptors, int flags);
[Target(OS(Mac))]
extern int pipe(int* descriptors);
[Target(OS(Mac))]
extern int fcntl(int descriptor, int command, ...);
[Target(OS(Linux) || OS(Mac))]
extern int close(int descriptor);
[Target(OS(Linux) || OS(Mac))]
extern int waitpid(int pid, int* status, int options);
[Target(OS(Linux) || OS(Mac))]
extern int fork();
[Target(OS(Linux) || OS(Mac))]
extern int fflush(void* stream);
[Target(OS(Linux))]
extern int dup2(int from, int to);
[Target(OS(Linux))]
extern int chdir(char* path);
[Target(OS(Linux))]
extern int open(char* path, int flags, ...);
[Target(OS(Linux))]
extern long read(int descriptor, void* buffer, ulong count);
[Target(OS(Linux))]
extern long write(int descriptor, void* buffer, ulong count);
[Target(OS(Linux))]
extern void _exit(int status);
[Target(OS(Linux) || OS(Mac))]
extern int kill(int pid, int signal);
[Target(OS(Linux) || OS(Mac))]
extern int getpid();
[Target(OS(Linux))]
extern long readlink(char* path, char* buffer, ulong size);
[Target(OS(Mac))]
extern int _NSGetExecutablePath(char* buffer, uint* size);
[Target(OS(Mac))]
extern char* realpath(char* path, char* resolved);
[Target(OS(Linux) || OS(Mac))]
extern void free(void* pointer);

# A child process: its id.
[Target(OS(Linux) || OS(Mac))]
type _ProcessHandle = int;

# Bigger than posix_spawn_file_actions_t and posix_spawnattr_t on both
# systems (80 and 336 bytes on glibc, a pointer on macOS).
[Target(OS(Linux) || OS(Mac))]
const _PROCESS_SPAWN_STATE_SIZE: ulong = 512;

[Target(OS(Linux) || OS(Mac))]
_process_sys_names_ignore_case(): bool {
    return false;
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_error_message(code: io.ErrorCode): String {
    return io._io_sys_error_message(code);
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_id(): ulong {
    return getpid() as ulong;
}

[Target(OS(Linux))]
_process_sys_executable_path(): io.IoResult<io.Path> {
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
_process_sys_executable_path(): io.IoResult<io.Path> {
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
[Target(OS(Linux) || OS(Mac))]
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
[Target(OS(Linux) || OS(Mac))]
_process_c_strings(values: Array<String>): __ptr<__ptr<char>> {
    __ptr<__ptr<char>> array = _pep_malloc((values.count + 1) * 8);
    ulong index = 0;
    while (index < values.count) {
        array[index] = values[index].c_str();
        index = index + 1;
    }
    array[values.count] = __null;
    return array;
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    # posix_spawn cannot change the child's folder without
    # posix_spawn_file_actions_addchdir_np: fork and exec then, as Rust's
    # standard library does.
    if (command._working_directory.is_value() and !_process_spawn_changes_folder()) {
        return _process_fork_spawn(command, stdin, stdout, stderr);
    }
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
    if (code == 0 && command._working_directory.is_value()) {
        directory = command._working_directory.value().to_string();
        code = _process_add_chdir(actions, directory.c_str());
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

# Runs `program` in place of this process with `argv` and `envp`: execvpe
# on Linux. Returns the errno value it failed with.
[Target(OS(Linux))]
_process_exec_program(program: String, argv: __ptr<__ptr<char>>, envp: __ptr<__ptr<char>>): int {
    execvpe(program.c_str(), argv, envp);
    return io.IoError.last().code;
}

# macOS has no execvpe; posix_spawnp with POSIX_SPAWN_SETEXEC searches the
# PATH the same way and replaces this process instead of starting another.
[Target(OS(Mac))]
_process_exec_program(program: String, argv: __ptr<__ptr<char>>, envp: __ptr<__ptr<char>>): int {
    __ptr<void> attributes = _pep_malloc(_PROCESS_SPAWN_STATE_SIZE);
    posix_spawnattr_init(attributes);
    posix_spawnattr_setflags(attributes, 64);  # POSIX_SPAWN_SETEXEC
    __ptr<int> pid = _pep_malloc(4);
    var code = posix_spawnp(pid, program.c_str(), __null, attributes, argv, envp);
    _pep_free(pid);
    posix_spawnattr_destroy(attributes);
    _pep_free(attributes);
    return code;
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_exec(command: Command): io.IoError {
    # The program starts in the working directory this process has when it
    # execs, so enter the Command's and come back if the exec fails.
    var previous = Optional<io.Path>.Empty;
    if (command._working_directory.is_value()) {
        var current = io.Directory.current();
        if (current.is_err()) {
            return current.error();
        }
        var entered = io.Directory.set_current(command._working_directory.value());
        if (entered.is_err()) {
            return entered.error();
        }
        previous = Optional<io.Path>.Value(current.value());
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
    var code = _process_exec_program(command.program, argv, envp);
    _pep_free(argv);
    if (built_environment) {
        _pep_free(envp);
    }
    if (previous.is_value()) {
        io.Directory.set_current(previous.value());
    }
    var message = _process_sys_error_message(code);
    return io.IoError(code, $"cannot start '{command.program}': {message}");
}

# A File owning the pipe end `descriptor`, or a closed File for -1.
[Target(OS(Linux) || OS(Mac))]
_process_pipe_file(descriptor: int, name: String): io.File {
    var file = io.File();
    if (descriptor >= 0) {
        file._handle = descriptor;
        file.path = io.Path(name);
    }
    return file;
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_borrowed_file(handle: io.FileHandle): io.File {
    var file = io.File();
    file._handle = handle;
    file._owned = false;
    return file;
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_wait_raw(handle: _ProcessHandle, block: bool): long {
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

[Target(OS(Linux) || OS(Mac))]
_process_sys_kill(handle: _ProcessHandle): io.IoResult<void> {
    if (kill(handle, 9) != 0) {  # SIGKILL
        return io.IoResult<void>.err(io.IoError.last());
    }
    return io.IoResult<void>.ok();
}

[Target(OS(Linux) || OS(Mac))]
_process_sys_release(handle: _ProcessHandle) {}

# Whether posix_spawn can start a child in another folder.
# `PEPPER_PROCESS_FORK_SPAWN` set says no, so the tests reach the fork path
# on a glibc that has posix_spawn_file_actions_addchdir_np.
[Target(OS(Linux))]
_process_spawn_changes_folder(): bool {
    var forced = os.environment("PEPPER_PROCESS_FORK_SPAWN");
    if (forced.is_value() and !forced.value().is_empty) {
        return false;
    }
    var name = "posix_spawn_file_actions_addchdir_np";
    return dlsym(__null, name.c_str()) != __null;
}

[Target(OS(Mac))]
_process_spawn_changes_folder(): bool {
    return true;
}

# Starts `command` with fork and exec, for a working directory posix_spawn
# cannot set (glibc before 2.29). Everything the child needs is made before
# the fork: between fork and exec it only duplicates descriptors, changes
# folder and execs, and reports a failure through a close-on-exec pipe, as
# Rust's standard library does.
[Target(OS(Linux))]
_process_fork_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    var streams = [stdin, stdout, stderr];
    # What the child does with each stream, read without Pepper code:
    # 0 keep, 1 /dev/null, 2 the pipe's child end.
    __ptr<int> kinds = _pep_malloc(12);
    # [parent, child] ends for stdin, stdout and stderr; -1 when unused.
    __ptr<int> ends = _pep_malloc(24);
    var index = 0;
    while (index < 6) {
        ends[index] = -1;
        index = index + 1;
    }
    var code = 0;
    index = 0;
    while (index < 3) {
        kinds[index] = streams[index] == Stream.Pipe ? 2 : (streams[index] == Stream.Null ? 1 : 0);
        index = index + 1;
    }
    index = 0;
    while (index < 3 and code == 0) {
        if (kinds[index] == 2) {
            __ptr<int> pair = _pep_malloc(8);
            if (_process_pipe(pair)) {
                ends[index * 2] = index == 0 ? pair[1] : pair[0];
                ends[index * 2 + 1] = index == 0 ? pair[0] : pair[1];
            } else {
                code = io.IoError.last().code;
            }
            _pep_free(pair);
        }
        index = index + 1;
    }
    # The pipe the child writes errno to when it cannot exec.
    __ptr<int> report = _pep_malloc(8);
    if (code == 0 and pipe2(report, 524288) != 0) {  # O_CLOEXEC
        code = io.IoError.last().code;
    }
    if (code != 0) {
        _process_close_ends(ends, 0);
        _pep_free(ends);
        _pep_free(kinds);
        _pep_free(report);
        var message = _process_sys_error_message(code);
        return io.IoResult<Child>.err(io.IoError(code, $"cannot start '{command.program}': {message}"));
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
    var directory = command._working_directory.value().to_string();
    var program = command.program;
    var device = "/dev/null";
    __ptr<char> directory_text = directory.c_str();
    __ptr<char> program_text = program.c_str();
    __ptr<char> device_text = device.c_str();
    __ptr<int> failed = _pep_malloc(4);
    var process_id = fork();
    if (process_id == 0) {
        # The child: nothing here allocates.
        var at = 0;
        while (at < 3) {
            if (kinds[at] == 2) {
                dup2(ends[at * 2 + 1], at);
            } else if (kinds[at] == 1) {
                var opened = open(device_text, at == 0 ? 0 : 1);
                if (opened >= 0) {
                    dup2(opened, at);
                }
            }
            at = at + 1;
        }
        if (chdir(directory_text) == 0) {
            execvpe(program_text, argv, envp);
        }
        failed[0] = io.IoError.last().code;
        write(report[1], failed, 4);
        _exit(127);
    }
    close(report[1]);
    _process_close_ends(ends, 1);
    if (process_id < 0) {
        code = io.IoError.last().code;
    } else {
        failed[0] = 0;
        # Four bytes: the child's errno, it did not exec; none: it did.
        if (read(report[0], failed, 4) == 4) {
            code = failed[0];
            __ptr<int> status = _pep_malloc(4);
            waitpid(process_id, status, 0);
            _pep_free(status);
        }
    }
    close(report[0]);
    _pep_free(report);
    _pep_free(failed);
    _pep_free(kinds);
    _pep_free(argv);
    if (built_environment) {
        _pep_free(envp);
    }
    if (code != 0) {
        _process_close_ends(ends, 0);
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

# macOS's posix_spawn always changes folder, so it never forks to start a
# child.
[Target(OS(Mac))]
_process_fork_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    return io.IoResult<Child>.err(io.IoError(78, "fork and exec spawning is Linux-only"));
}

# Closes the open ends of `ends` on side `side`: 0, the parent's; 1, the
# child's.
[Target(OS(Linux))]
_process_close_ends(ends: __ptr<int>, side: int) {
    var index = 0;
    while (index < 3) {
        if (ends[index * 2 + side] >= 0) {
            close(ends[index * 2 + side]);
            ends[index * 2 + side] = -1;
        }
        index = index + 1;
    }
}

# Adds a change of folder to `actions`. glibc has
# posix_spawn_file_actions_addchdir_np from 2.29 on, and the prebuilt
# toolchain links for glibc 2.28, so Linux looks it up when a child needs a
# working directory and fails with ENOSYS where there is none.
[Target(OS(Linux))]
_process_add_chdir(actions: __ptr<void>, path: __ptr<char>): int {
    var name = "posix_spawn_file_actions_addchdir_np";
    var symbol = dlsym(__null, name.c_str());
    if (symbol == __null) {
        return 38;
    }
    var add = symbol as extern (__ptr<void>, __ptr<char>) => int;
    return add(actions, path);
}

[Target(OS(Mac))]
_process_add_chdir(actions: __ptr<void>, path: __ptr<char>): int {
    return posix_spawn_file_actions_addchdir_np(actions, path);
}

# Starts a copy of this process with fork(2), after flushing C stdio (where
# `print` buffers), so neither copy writes the other's buffered output.
[Target(OS(Linux) || OS(Mac))]
_process_sys_fork(): io.IoResult<Child?> {
    fflush(__null);
    var process_id = fork();
    if (process_id < 0) {
        return io.IoResult<Child?>.err(io.IoError(11, "cannot start a copy of this process"));
    }
    if (process_id == 0) {
        return io.IoResult<Child?>.ok(Optional<Child>.Empty);
    }
    var child = Child();
    child._handle = process_id;
    child._id = process_id as ulong;
    return io.IoResult<Child?>.ok(Optional<Child>.Value(child));
}

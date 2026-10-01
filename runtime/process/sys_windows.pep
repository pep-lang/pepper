# Windows platform layer for process: the same `_process_sys_*` functions
# as sys_posix.pep, on CreateProcessW.
#
# A child inherits the handles marked inheritable when it starts, so the
# child's ends of its streams are made inheritable only while a spawn holds
# `_process_spawn_lock`: another thread's child cannot inherit them. The
# parent's ends never are. A Child closes its process `HANDLE` when it is
# released.

import async;
import io;
import "child";
import "command";

[Target(OS(Windows))]
extern int CreateProcessW(
    ushort* application,
    ushort* command_line,
    void* process_attributes,
    void* thread_attributes,
    int inherit_handles,
    uint flags,
    void* environment,
    ushort* directory,
    void* startup_info,
    void* process_information
);
[Target(OS(Windows))]
extern int CreatePipe(void** read, void** write, void* attributes, uint size);
[Target(OS(Windows))]
extern int SetHandleInformation(ulong handle, uint mask, uint flags);  # as io declares it, for sockets
[Target(OS(Windows))]
extern void* GetStdHandle(uint which);
[Target(OS(Windows))]
extern int DuplicateHandle(
    void* source_process, void* source, void* target_process, void** target, uint access, int inherit, uint options
);
[Target(OS(Windows))]
extern void* GetCurrentProcess();
[Target(OS(Windows))]
extern int CloseHandle(void* handle);
[Target(OS(Windows))]
extern void* CreateFileW(
    ushort* path, uint access, uint share, void* attributes, uint disposition, uint flags, void* template
);
[Target(OS(Windows))]
extern uint WaitForSingleObject(void* handle, uint milliseconds);
[Target(OS(Windows))]
extern int GetExitCodeProcess(void* handle, uint* code);
[Target(OS(Windows))]
extern int TerminateProcess(void* handle, uint code);
[Target(OS(Windows))]
extern uint GetCurrentProcessId();
[Target(OS(Windows))]
extern uint GetModuleFileNameW(void* module, ushort* buffer, uint size);
[Target(OS(Windows))]
extern uint GetLastError();
[Target(OS(Windows))]
extern void memcpy(void* destination, void* source, ulong size);

# A child process: its `HANDLE`.
[Target(OS(Windows))]
export type _ProcessHandle = __ptr<void>;

# The value `_process_spawn_lock` guards: nothing; the lock is what matters.
[Target(OS(Windows))]
[Shared]
struct _SpawnLock {
    construct() {}
}

# Held while a spawn has inheritable handles open.
[Target(OS(Windows))]
const _process_spawn_lock = async.Mutex<_SpawnLock>(_SpawnLock());

[Target(OS(Windows))]
export _process_sys_names_ignore_case(): bool {
    return true;
}

[Target(OS(Windows))]
export _process_sys_error_message(code: io.ErrorCode): String {
    return io._io_sys_error_message(code);
}

[Target(OS(Windows))]
export _process_sys_id(): ulong {
    return GetCurrentProcessId() as ulong;
}

[Target(OS(Windows))]
export _process_sys_executable_path(): io.IoResult<io.Path> {
    uint capacity = 512;
    while (true) {
        __ptr<u16> buffer = _pep_malloc((capacity as ulong) * 2);
        var length = GetModuleFileNameW(__null, buffer, capacity);
        if (length == 0) {
            var error = io.IoError.last();
            _pep_free(buffer);
            return io.IoResult<io.Path>.err(error);
        }
        if (length < capacity) {
            var path = io._io_win_narrow(buffer, length as int);
            _pep_free(buffer);
            return io.IoResult<io.Path>.ok(io.Path(path));
        }
        # Truncated: try a bigger buffer.
        _pep_free(buffer);
        capacity = capacity * 2;
    }
    return io.IoResult<io.Path>.err(io.IoError());
}

# Appends `argument` to `line`, quoted the way the C runtime's command-line
# parser (and CommandLineToArgvW) splits it back out: inside quotes, a run
# of backslashes is doubled before a quote (which is escaped) and at the
# end, and kept as it is elsewhere.
[Target(OS(Windows))]
_process_quote(line: String, argument: String): String {
    var plain = argument.size() > 0;
    ulong index = 0;
    while (index < argument.size()) {
        var c = argument.byte_at(index);
        if (c == 32 || c == 9 || c == 10 || c == 11 || c == 34) {
            plain = false;
        }
        index = index + 1;
    }
    if (plain) {
        return line + argument;
    }
    var bytes = Array<u8>();
    bytes.append(34);
    index = 0;
    ulong backslashes = 0;
    while (index < argument.size()) {
        var c = argument.byte_at(index);
        if (c == 92) {
            backslashes = backslashes + 1;
        } else {
            if (c == 34) {
                backslashes = backslashes * 2 + 1;
            }
            while (backslashes > 0) {
                bytes.append(92);
                backslashes = backslashes - 1;
            }
            bytes.append(c);
        }
        index = index + 1;
    }
    backslashes = backslashes * 2;
    while (backslashes > 0) {
        bytes.append(92);
        backslashes = backslashes - 1;
    }
    bytes.append(34);
    return line + String._from_bytes(bytes);
}

# The command line: the program, then each argument, quoted as needed and
# separated by spaces.
[Target(OS(Windows))]
_process_command_line(command: Command): String {
    var line = _process_quote("", command.program);
    for (var argument in command._arguments) {
        line = _process_quote(line + " ", argument);
    }
    return line;
}

# The environment block for CreateProcessW with CREATE_UNICODE_ENVIRONMENT:
# each NAME=VALUE in UTF-16 with its NUL, then one more NUL (two for an
# empty block). Free it with `_pep_free`.
[Target(OS(Windows))]
_process_environment_block(entries: Array<String>): __ptr<u16> {
    ulong total = 2;
    for (var entry in entries) {
        var wide = io._io_win_wide(entry);
        total = total + (io._io_win_wide_len(wide) as ulong) + 1;
        _pep_free(wide);
    }
    __ptr<u16> block = _pep_malloc(total * 2);
    ulong at = 0;
    for (var entry in entries) {
        var wide = io._io_win_wide(entry);
        var length = io._io_win_wide_len(wide) as ulong;
        memcpy(block + at, wide, (length + 1) * 2);
        at = at + length + 1;
        _pep_free(wide);
    }
    block[at] = 0;
    block[at + 1] = 0;
    return block;
}

# SECURITY_ATTRIBUTES with bInheritHandle set; free it with `_pep_free`.
[Target(OS(Windows))]
_process_inheritable(): __ptr<void> {
    __ptr<u32> attributes = _pep_malloc(24);
    attributes[0] = 24;  # nLength
    attributes[1] = 0;
    attributes[2] = 0;  # lpSecurityDescriptor
    attributes[3] = 0;
    attributes[4] = 1;  # bInheritHandle
    attributes[5] = 0;
    return attributes;
}

# The inheritable handle the child gets for standard stream `which` (0, 1
# or 2) per `stream`; for a pipe, the parent's end goes to `parent_end`
# (null otherwise). Null when there is none.
[Target(OS(Windows))]
_process_stream(which: int, stream: Stream, parent_end: __ptr<__ptr<void>>): __ptr<void> {
    parent_end[0] = __null;
    __ptr<__ptr<void>> slot = _pep_malloc(16);
    slot[0] = __null;
    slot[1] = __null;
    __ptr<void> result = __null;
    if (stream == Stream.Inherit) {
        # STD_INPUT_HANDLE is -10, then -11 and -12, as a DWORD.
        var own = GetStdHandle((4294967286 - which) as uint);
        if (own != __null && own as long != -1) {
            # A duplicate, inheritable whatever the original is.
            var process = GetCurrentProcess();
            if (DuplicateHandle(process, own, process, slot, 0, 1, 2) != 0) {  # DUPLICATE_SAME_ACCESS
                result = slot[0];
            }
        }
    } else if (stream == Stream.Null) {
        var device = io._io_win_wide("NUL");
        var attributes = _process_inheritable();
        # GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
        # OPEN_EXISTING.
        result = CreateFileW(device, 3221225472, 3, attributes, 3, 0, __null);
        _pep_free(attributes);
        _pep_free(device);
        if (result as long == -1) {  # INVALID_HANDLE_VALUE
            result = __null;
        }
    } else {
        var attributes = _process_inheritable();
        if (CreatePipe(slot, slot + 1, attributes, 0) != 0) {
            # The child reads standard input from the read end and writes
            # the others to the write end.
            var child = which == 0 ? slot[0] : slot[1];
            var parent = which == 0 ? slot[1] : slot[0];
            SetHandleInformation(parent as ulong, 1, 0);  # HANDLE_FLAG_INHERIT off
            parent_end[0] = parent;
            result = child;
        }
        _pep_free(attributes);
    }
    _pep_free(slot);
    return result;
}

[Target(OS(Windows))]
export _process_sys_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    var line = io._io_win_wide(_process_command_line(command));
    __ptr<u16> directory = __null;
    if (command._working_directory.is_some()) {
        directory = io._io_win_wide(command._working_directory.value().to_string());
    }
    __ptr<u16> environment = __null;
    if (command._changes_environment()) {
        environment = _process_environment_block(command._environment_entries());
    }
    # The child's stdin, stdout and stderr, then the parent's ends.
    __ptr<__ptr<void>> handles = _pep_malloc(48);
    ulong index = 0;
    while (index < 6) {
        handles[index] = __null;
        index = index + 1;
    }
    # STARTUPINFOW (104 bytes) and PROCESS_INFORMATION (24 bytes).
    __ptr<u8> startup = _pep_malloc(104);
    index = 0;
    while (index < 104) {
        startup[index] = 0;
        index = index + 1;
    }
    __ptr<u8> information = _pep_malloc(24);
    __ptr<u32> words = startup;
    words[0] = 104;   # cb
    words[15] = 256;  # dwFlags, at offset 60: STARTF_USESTDHANDLES

    var ok = 0;
    uint code = 0;
    with (var held = _process_spawn_lock.lock()) {
        handles[0] = _process_stream(0, stdin, handles + 3);
        handles[1] = _process_stream(1, stdout, handles + 4);
        handles[2] = _process_stream(2, stderr, handles + 5);
        __ptr<__ptr<void>> slots = startup + 80;  # hStdInput, hStdOutput, hStdError
        slots[0] = handles[0];
        slots[1] = handles[1];
        slots[2] = handles[2];
        # CREATE_UNICODE_ENVIRONMENT
        ok = CreateProcessW(__null, line, __null, __null, 1, 1024, environment, directory, startup, information);
        if (ok == 0) {
            code = GetLastError();
        }
        # The child has its own copies now.
        index = 0;
        while (index < 3) {
            if (handles[index] != __null) {
                CloseHandle(handles[index]);
            }
            index = index + 1;
        }
    }
    _pep_free(line);
    if (directory != __null) {
        _pep_free(directory);
    }
    if (environment != __null) {
        _pep_free(environment);
    }
    _pep_free(startup);
    if (ok == 0) {
        _pep_free(information);
        index = 3;
        while (index < 6) {
            if (handles[index] != __null) {
                CloseHandle(handles[index]);
            }
            index = index + 1;
        }
        _pep_free(handles);
        var message = _process_sys_error_message(code);
        return io.IoResult<Child>.err(io.IoError(code, $"cannot start '{command.program}': {message}"));
    }
    __ptr<__ptr<void>> process_handles = information;
    var process = process_handles[0];
    CloseHandle(process_handles[1]);  # the child's main thread
    __ptr<u32> ids = information;
    var child = Child();
    child._handle = process;
    child._id = ids[4] as ulong;  # dwProcessId, at offset 16
    _pep_free(information);
    child._stdin = _process_pipe_file(handles[3], "<child stdin>");
    child._stdout = _process_pipe_file(handles[4], "<child stdout>");
    child._stderr = _process_pipe_file(handles[5], "<child stderr>");
    _pep_free(handles);
    return io.IoResult<Child>.ok(child);
}

# A File owning the pipe end `handle`, or a closed File for null.
[Target(OS(Windows))]
_process_pipe_file(handle: __ptr<void>, name: String): io.File {
    var file = io.File();
    if (handle != __null) {
        file._handle = handle;
        file.path = io.Path(name);
    }
    return file;
}

[Target(OS(Windows))]
export _process_sys_borrowed_file(handle: io.FileHandle): io.File {
    var file = io.File();
    file._handle = handle;
    file._owned = false;
    return file;
}

[Target(OS(Windows))]
export _process_sys_wait_raw(handle: _ProcessHandle, block: bool): long {
    var process = handle;
    # INFINITE, or 0 to poll.
    var result = WaitForSingleObject(process, block ? 4294967295 : 0);
    if (result == 258) {  # WAIT_TIMEOUT
        return -1;
    }
    if (result != 0) {  # not WAIT_OBJECT_0
        return -2 - (GetLastError() as long);
    }
    __ptr<u32> code = _pep_malloc(4);
    if (GetExitCodeProcess(process, code) == 0) {
        _pep_free(code);
        return -2 - (GetLastError() as long);
    }
    var value = code[0] as long;
    _pep_free(code);
    return value;
}

[Target(OS(Windows))]
export _process_sys_kill(handle: _ProcessHandle): io.IoResult<void> {
    if (TerminateProcess(handle, 1) == 0) {
        return io.IoResult<void>.err(io.IoError.last());
    }
    return io.IoResult<void>.ok();
}

[Target(OS(Windows))]
export _process_sys_release(handle: _ProcessHandle) {
    if (handle != __null) {
        CloseHandle(handle);
    }
}

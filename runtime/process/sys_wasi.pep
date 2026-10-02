# WASI (WebAssembly) platform layer for process: the same `_process_sys_*`
# functions as sys_posix.pep and sys_windows.pep, each with
# [Target(OS(Wasi))]. A WASI preview 1 program cannot start another
# process, so spawning and exec fail with ENOTSUP; it has no process id or
# executable path of its own either.

import io;
import "child";
import "command";

# A child process: never made on WASI.
[Target(OS(Wasi))]
export type _ProcessHandle = int;

[Target(OS(Wasi))]
export _process_sys_names_ignore_case(): bool {
    return false;
}

[Target(OS(Wasi))]
export _process_sys_error_message(code: io.ErrorCode): String {
    return io._io_sys_error_message(code);
}

# WASI has no process ids; the one program is process 1.
[Target(OS(Wasi))]
export _process_sys_id(): ulong {
    return 1;
}

[Target(OS(Wasi))]
export _process_sys_executable_path(): io.IoResult<io.Path> {
    return io.IoResult<io.Path>.err(_process_wasi_unsupported("an executable path"));
}

[Target(OS(Wasi))]
export _process_sys_spawn(command: Command, stdin: Stream, stdout: Stream, stderr: Stream): io.IoResult<Child> {
    return io.IoResult<Child>.err(_process_wasi_unsupported("starting a process"));
}

[Target(OS(Wasi))]
export _process_sys_exec(command: Command): io.IoError {
    return _process_wasi_unsupported("starting a process");
}

[Target(OS(Wasi))]
export _process_sys_borrowed_file(handle: io.FileHandle): io.File {
    var file = io.File();
    file._handle = handle;
    file._owned = false;
    return file;
}

[Target(OS(Wasi))]
export _process_sys_wait_raw(handle: _ProcessHandle, block: bool): long {
    return -2 - 58;  # ENOTSUP
}

[Target(OS(Wasi))]
export _process_sys_kill(handle: _ProcessHandle): io.IoResult<void> {
    return io.IoResult<void>.err(_process_wasi_unsupported("killing a process"));
}

[Target(OS(Wasi))]
export _process_sys_release(handle: _ProcessHandle) {}

# ENOTSUP, for what WASI cannot do.
[Target(OS(Wasi))]
_process_wasi_unsupported(what: String): io.IoError {
    return io.IoError(58, what + " is not supported on WASI");
}

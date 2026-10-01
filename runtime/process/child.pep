## A running child process (`Child`), the pipes to it, and how it ended
## (`ExitStatus`).

import async;
import io;
import "command";
import "sys_posix";
import "sys_windows";

extern void memcpy(void* destination, void* source, ulong size);

## How a child process ended: with an exit code, or (on POSIX) killed by a
## signal.
##
## @example
##     var status = process.Command("false").run().value().status;
##     assert(!status.success(), "false fails");
##     assert(status.code().value() == 1, "with code 1");
export struct ExitStatus {
    # The exit code; 0 when a signal ended the process.
    var _code: int;
    # The signal that ended the process, or 0.
    var _signal: int;

    ## Creates an ExitStatus.
    ##
    ## @param code the exit code, when the process exited
    ## @param signal the signal that ended the process, or 0 when it exited
    construct(code: int = 0, signal: int = 0) {
        _code = code;
        _signal = signal;
    }

    ## Returns whether the process exited with code 0.
    ##
    ## @returns true for exit code 0
    success(): bool {
        return _signal == 0 && _code == 0;
    }

    ## Returns the exit code: the value the process passed to `exit` or
    ## returned from `main`. On POSIX only its low 8 bits reach the parent,
    ## so it is from 0 to 255; on Windows it is the whole 32-bit code (an
    ## unhandled exception gives an `NTSTATUS` such as `0xC0000005`, a
    ## negative number here).
    ##
    ## @returns the exit code, or none when a signal ended the process
    code(): int? {
        if (_signal != 0) {
            return Optional<int>.none();
        }
        return Optional<int>.some(_code);
    }

    ## Returns the signal that ended the process (POSIX only; a Windows
    ## process always has an exit code).
    ##
    ## @returns the signal number, such as 9 for `SIGKILL`, or none when the
    ##   process exited
    signal(): int? {
        if (_signal == 0) {
            return Optional<int>.none();
        }
        return Optional<int>.some(_signal);
    }

    ## Returns how the process ended as text.
    ##
    ## @returns `exit code N` or `signal N`
    to_string(): String {
        if (_signal != 0) {
            return $"signal {_signal}";
        }
        return $"exit code {_code}";
    }
}

extend ExitStatus with ToString {}

## A child process started by `Command.spawn()`: its id, the pipes to the
## streams that were piped, and its exit status once it ends.
##
## Wait for every child with `wait()` (or until `try_wait()` returns a
## status): on POSIX a child that ended but was never waited for stays in
## the process table until the parent ends. Releasing the last reference to
## a Child neither waits for it nor kills it; the process runs on.
##
## @example
##     import process;
##
##     main(): int {
##         var child = process.Command("sleep").argument("10").spawn().value();
##         child.kill();
##         var status = child.wait().value();
##         assert(!status.success(), "killed");
##         return 0;
##     }
[NotCopyable("owns a child process handle and cannot be copied")]
export struct Child {
    # The process: its id on POSIX, its `HANDLE` on Windows.
    var _handle: _ProcessHandle;
    # The process id.
    var _id: ulong;
    # The parent's ends of the pipes; closed Files for streams that were not
    # piped.
    var _stdin: io.File;
    var _stdout: io.File;
    var _stderr: io.File;
    # The exit status, once a wait has collected it.
    var _status: ExitStatus?;

    ## Creates a Child that stands for no process: `id()` is 0, its streams
    ## are closed, and `wait()`, `try_wait()` and `kill()` fail. Use
    ## `Command.spawn()` to start one.
    construct() {
        _stdin = io.File();
        _stdout = io.File();
        _stderr = io.File();
    }

    # Releases the Windows process handle; the process runs on.
    destruct {
        if (_id != 0) {
            _process_sys_release(_handle);
        }
    }

    ## Returns the child's process id, as the operating system knows it.
    ## After the child has been waited for, the system may give the id to a
    ## new process.
    ##
    ## @returns the process id
    id(): ulong {
        return _id;
    }

    ## Returns the pipe to the child's standard input, for writing. Close it
    ## when done (`close()`), so that a child reading to the end sees the
    ## end.
    ##
    ## @returns the pipe, or a closed File when standard input was not
    ##   `Stream.Pipe`
    stdin(): io.File {
        return _stdin;
    }

    ## Returns the pipe from the child's standard output, for reading. A read
    ## returns 0 once the child has ended (or closed its standard output) and
    ## everything it wrote has been read.
    ##
    ## @returns the pipe, or a closed File when standard output was not
    ##   `Stream.Pipe`
    stdout(): io.File {
        return _stdout;
    }

    ## Returns the pipe from the child's standard error, for reading.
    ##
    ## @returns the pipe, or a closed File when standard error was not
    ##   `Stream.Pipe`
    stderr(): io.File {
        return _stderr;
    }

    ## Waits for the child to end and returns how it ended. Standard input,
    ## when piped, is closed first, so a child reading it to the end can
    ## finish. Waiting again returns the same status.
    ##
    ## In a task, the wait parks the task (it runs on a `run_blocking`
    ## thread) rather than blocking its worker. Read piped output before
    ## waiting: a child stalls when a pipe it writes to is full.
    ##
    ## @returns the exit status, or an error from the system
    wait(): io.IoResult<ExitStatus> {
        if (_status.is_some()) {
            return io.IoResult<ExitStatus>.ok(_status.value());
        }
        if (_id == 0) {
            return io.IoResult<ExitStatus>.err(_process_no_process());
        }
        if (_stdin.is_open()) {
            _stdin.close();
        }
        var handle = _handle;
        var raw = async.run_blocking<long>(() => {
            return _process_sys_wait_raw(handle, true);
        });
        var result = _process_status_from_raw(raw);
        if (result.is_err()) {
            return io.IoResult<ExitStatus>.err(result.error());
        }
        _status = result.value();
        return io.IoResult<ExitStatus>.ok(_status.value());
    }

    ## Returns how the child ended if it has, without waiting.
    ##
    ## @returns the exit status, or none while the child runs; or an error
    ##   from the system
    try_wait(): io.IoResult<ExitStatus?> {
        if (_status.is_some()) {
            return io.IoResult<ExitStatus?>.ok(_status);
        }
        if (_id == 0) {
            return io.IoResult<ExitStatus?>.err(_process_no_process());
        }
        var result = _process_status_from_raw(_process_sys_wait_raw(_handle, false));
        if (result.is_ok()) {
            _status = result.value();
        }
        return result;
    }

    ## Ends the child at once: `SIGKILL` on POSIX, `TerminateProcess` (with
    ## exit code 1) on Windows. The child still has to be waited for. Killing
    ## a child that has already been waited for does nothing.
    ##
    ## @returns Ok, or an error from the system
    kill(): io.IoResult<void> {
        if (_status.is_some()) {
            return io.IoResult<void>.ok();
        }
        if (_id == 0) {
            return io.IoResult<void>.err(_process_no_process());
        }
        return _process_sys_kill(_handle);
    }

    # Reads the piped standard output and error to the end at once (standard
    # error on its own thread) and returns them in an Output whose status is
    # not set yet.
    _collect(): io.IoResult<Output> {
        # The reader thread hands back a malloc'd copy of the bytes, since a
        # String or Array is not thread-safe.
        var error_data = async.Atomic<__ptr<void>>(__null);
        var error_size = async.Atomic<ulong>(0);
        var error_code = async.Atomic<long>(0);
        var reader = Optional<async.Thread>.none();
        if (_stderr.is_open()) {
            var handle = _stderr._handle;
            reader = Optional<async.Thread>.some(async.Thread.spawn(() => {
                var file = _process_sys_borrowed_file(handle);
                var bytes = file.read_all();
                if (bytes.is_err()) {
                    error_code.store(bytes.error().code as long);
                    return;
                }
                var data = bytes.value();
                __ptr<u8> copy = _pep_malloc(data.count() + 1);
                memcpy(copy, data._data, data.count());
                error_size.store(data.count());
                error_data.store(copy);
            }));
        }
        var stdout = "";
        var failure = Optional<io.IoError>.none();
        if (_stdout.is_open()) {
            var bytes = _stdout.read_all();
            if (bytes.is_err()) {
                failure = Optional<io.IoError>.some(bytes.error());
            } else {
                stdout = String._from_bytes(bytes.value());
            }
            _stdout.close();
        }
        var stderr = "";
        if (reader.is_some()) {
            reader.value().join();
            _stderr.close();
            __ptr<u8> data = error_data.load();
            if (data != __null) {
                var bytes = Array<u8>(error_size.load());
                ulong index = 0;
                while (index < error_size.load()) {
                    bytes.append(data[index]);
                    index = index + 1;
                }
                _pep_free(data);
                stderr = String._from_bytes(bytes);
            }
            if (error_code.load() != 0 && failure.is_none()) {
                var code = error_code.load() as io.ErrorCode;
                failure = Optional<io.IoError>.some(io.IoError(code, _process_sys_error_message(code)));
            }
        }
        if (failure.is_some()) {
            return io.IoResult<Output>.err(failure.value());
        }
        return io.IoResult<Output>.ok(Output(ExitStatus(), stdout, stderr));
    }
}

# The error for a Child that stands for no process.
_process_no_process(): io.IoError {
    return io.IoError(0, "the Child has no process");
}

# A wait's result as `_process_sys_wait_raw` encodes it in one number (so a
# `run_blocking` thread can return it): -1 while the child runs, -2 minus
# the error code on failure, else the code in the low 32 bits and the
# signal in the next 8.
_process_status_from_raw(raw: long): io.IoResult<ExitStatus?> {
    if (raw == -1) {
        return io.IoResult<ExitStatus?>.ok(Optional<ExitStatus>.none());
    }
    if (raw < -1) {
        var code = (-2 - raw) as io.ErrorCode;
        return io.IoResult<ExitStatus?>.err(io.IoError(code, _process_sys_error_message(code)));
    }
    var low = (raw & 4294967295) as uint;
    var exit_code = low as int;
    var signal = ((raw >> 32) & 255) as int;
    return io.IoResult<ExitStatus?>.ok(Optional<ExitStatus>.some(ExitStatus(exit_code, signal)));
}

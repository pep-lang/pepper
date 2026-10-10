# POSIX (Linux, macOS) whole-file lock layer for io: `flock`. Every
# declaration carries [Target(OS(Linux) || OS(Mac))]; lock_windows.pep and
# lock_wasi.pep declare the same `_io_sys_*` lock functions with the same
# signatures for Windows and WASI. Like sys_posix.pep, these are exported to
# the other io files only.
#
# An `flock` lock belongs to the open file description: every File opened
# separately holds its own, even in one process, and closing the File (or
# the last copy of its descriptor) releases it.

import "sys_posix";
import "types";

[Target(OS(Linux) || OS(Mac))]
extern int flock(int fd, int operation);

# EWOULDBLOCK (the same value as EAGAIN): the lock is held elsewhere.
[Target(OS(Linux))]
_io_posix_code_would_block(): ErrorCode {
    return 11;
}

[Target(OS(Mac))]
_io_posix_code_would_block(): ErrorCode {
    return 35;
}

# Takes the lock on `h`: exclusive (LOCK_EX) or shared (LOCK_SH), waiting
# for it when `wait` and failing at once (LOCK_NB) otherwise. An interrupted
# wait (`EINTR`) is retried.
# Returns whether the lock was taken: false only without `wait`, when
# another holder has it.
[Target(OS(Linux) || OS(Mac))]
_io_sys_lock(h: FileHandle, exclusive: bool, wait: bool): IoResult<bool> {
    var operation = 1;  # LOCK_SH
    if (exclusive) {
        operation = 2;  # LOCK_EX
    }
    if (!wait) {
        operation = operation | 4;  # LOCK_NB
    }
    while (true) {
        if (flock(h, operation) == 0) {
            return IoResult<bool>.ok(true);
        }
        var code = _io_sys_last_error();
        if (code == 4) {  # EINTR
            continue;
        }
        if (!wait && code == _io_posix_code_would_block()) {
            return IoResult<bool>.ok(false);
        }
        return IoResult<bool>.err(IoError(code, _io_sys_error_message(code)));
    }
    return IoResult<bool>.ok(false);
}

# Releases the lock on `h` (LOCK_UN); releasing none is not an error.
[Target(OS(Linux) || OS(Mac))]
_io_sys_unlock(h: FileHandle): IoResult<void> {
    return _io_posix_check(flock(h, 8));
}

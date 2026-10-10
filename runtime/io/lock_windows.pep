# Windows whole-file lock layer for io: `LockFileEx` and `UnlockFile` over
# the whole range of offsets. Every declaration carries
# [Target(OS(Windows))]; lock_posix.pep and lock_wasi.pep declare the same
# `_io_sys_*` lock functions with the same signatures for POSIX and WASI.
#
# A Windows lock belongs to the handle: every File opened separately holds
# its own, even in one process, and closing the File releases it. Unlike
# POSIX's `flock`, the lock is mandatory for reads and writes through other
# handles while it is held.

import "sys_windows";
import "types";

[Target(OS(Windows))]
extern int LockFileEx(void* h, uint flags, uint reserved, uint low, uint high, void* overlapped);
[Target(OS(Windows))]
extern int UnlockFile(void* h, uint offset_low, uint offset_high, uint low, uint high);

# Takes the lock on `h`: exclusive (LOCKFILE_EXCLUSIVE_LOCK) or shared,
# waiting for it when `wait` and failing at once
# (LOCKFILE_FAIL_IMMEDIATELY) otherwise. The handle is synchronous, so
# LockFileEx returns only once it has the lock; its OVERLAPPED (32 bytes,
# zeroed) gives the range's start, offset 0.
# Returns whether the lock was taken: false only without `wait`, when
# another holder has it (ERROR_LOCK_VIOLATION, or ERROR_IO_PENDING).
[Target(OS(Windows))]
_io_sys_lock(h: FileHandle, exclusive: bool, wait: bool): IoResult<bool> {
    uint flags = 0;
    if (exclusive) {
        flags = flags | 2;  # LOCKFILE_EXCLUSIVE_LOCK
    }
    if (!wait) {
        flags = flags | 1;  # LOCKFILE_FAIL_IMMEDIATELY
    }
    var overlapped = _pep_malloc(32) as __ptr<ulong>;
    for (var i in 0..4) {
        overlapped[i] = 0;
    }
    var ok = LockFileEx(h, flags, 0, 4294967295, 4294967295, overlapped);
    var code = GetLastError();
    _pep_free(overlapped);
    if (ok != 0) {
        return IoResult<bool>.ok(true);
    }
    if (!wait && (code == 33 || code == 997)) {  # LOCK_VIOLATION, IO_PENDING
        return IoResult<bool>.ok(false);
    }
    return IoResult<bool>.err(IoError(code, _io_sys_error_message(code)));
}

# Releases the lock on `h`. Releasing none is not an error, as with POSIX's
# `flock`: ERROR_NOT_LOCKED is Ok.
[Target(OS(Windows))]
_io_sys_unlock(h: FileHandle): IoResult<void> {
    var ok = UnlockFile(h, 0, 0, 4294967295, 4294967295);
    if (ok != 0) {
        return _io_ok_void();
    }
    var code = GetLastError();
    if (code == 158) {  # NOT_LOCKED
        return _io_ok_void();
    }
    return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
}

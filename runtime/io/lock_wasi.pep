# WASI (WebAssembly) whole-file lock layer for io: the same `_io_sys_*`
# lock functions as lock_posix.pep and lock_windows.pep, each with
# [Target(OS(Wasi))]. WASI preview 1 has no file locks, so every call fails
# with ENOTSUP.

import "sys_posix";
import "types";

# What every lock call returns: file locks are not part of WASI preview 1.
[Target(OS(Wasi))]
_io_wasi_no_locks(): IoError {
    return IoError(58, "file locks are not supported on WASI");  # ENOTSUP
}

[Target(OS(Wasi))]
_io_sys_lock(h: FileHandle, exclusive: bool, wait: bool): IoResult<bool> {
    return IoResult<bool>.err(_io_wasi_no_locks());
}

[Target(OS(Wasi))]
_io_sys_unlock(h: FileHandle): IoResult<void> {
    return IoResult<void>.err(_io_wasi_no_locks());
}

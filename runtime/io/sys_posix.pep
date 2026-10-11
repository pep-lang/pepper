# POSIX (Linux, macOS, and WASI through wasi-libc) platform layer for io.
# Every declaration carries [Target(!OS(Windows))] or a narrower target;
# sys_windows.pep declares the same `_io_sys_*` functions with the same
# signatures for Windows. These are exported to the other io files only:
# module.pep does not re-export them.
#
# Linux, macOS and WASI differ in the errno accessor and values, O_* flag
# values, the stat call and layout, and the dirent layout. C structs are
# read from raw `_pep_malloc` buffers at the byte offsets the small [Target]
# functions below return. wasi-libc's `long` is 32 bits, so a C `off_t` is
# declared `i64`, and a `long` field is never read as a Pepper `long`.

import "directory";
import "file";
import "path";
import "types";

# ── C functions ──────────────────────────────────────────────────────────────

[Target(!OS(Windows))]
extern int pthread_key_create(void* key, void* destructor);
[Target(!OS(Windows))]
extern void* pthread_getspecific(ulong key);
[Target(!OS(Windows))]
extern int pthread_setspecific(ulong key, void* value);

[Target(!OS(Windows))]
extern int open(char* path, int flags, ...);
[Target(!OS(Windows))]
extern long read(int fd, void* buf, ulong n);
[Target(!OS(Windows))]
extern long write(int fd, void* buf, ulong n);
[Target(!OS(Windows))]
extern int close(int fd);
[Target(!OS(Windows))]
extern i64 lseek(int fd, i64 offset, int whence);
[Target(!OS(Windows))]
extern int ftruncate(int fd, i64 size);
[Target(!OS(Windows))]
extern int fsync(int fd);
[Target(!OS(Windows))]
extern int mkdir(char* path, uint mode);
[Target(!OS(Windows))]
extern int rmdir(char* path);
[Target(!OS(Windows))]
extern int unlink(char* path);
[Target(!OS(Windows))]
extern int rename(char* from, char* to);
[Target(!OS(Windows))]
extern char* getcwd(char* buf, ulong size);
[Target(!OS(Windows))]
extern int chdir(char* path);
[Target(!OS(Windows))]
extern char* realpath(char* path, char* resolved);
[Target(!OS(Windows))]
extern char* strerror(int code);
[Target(!OS(Windows))]
extern char* getenv(char* name);
[Target(!OS(Windows))]
extern int closedir(void* dir);
[Target(!OS(Windows))]
extern int utimensat(int dirfd, char* path, void* times, int flags);
[Target(!OS(Windows))]
extern int futimens(int fd, void* times);
[Target(!OS(Windows))]
extern int symlink(char* target, char* link);
[Target(!OS(Windows))]
extern long readlink(char* path, char* buf, ulong size);

# WASI preview 1 has no permission bits, and wasi-libc no chmod.
[Target(OS(Linux) || OS(Mac))]
extern int chmod(char* path, uint mode);
[Target(OS(Linux) || OS(Mac))]
extern int fchmod(int fd, uint mode);

# Linux: errno through glibc's accessor (bionic's on Android); statx for
# stat (one layout on x64 and aarch64, and present where glibc < 2.33 has no
# `stat` symbol; bionic has it from API level 30, the oldest Pepper targets).
[Target((OS(Linux) && !OS(Android)) || OS(Wasi))]
extern int* __errno_location();
[Target(OS(Android))]
extern int* __errno();
[Target(OS(Linux))]
extern int statx(int dirfd, char* path, int flags, uint mask, void* buf);
[Target(OS(Linux))]
extern void* opendir(char* path);
[Target(OS(Linux))]
extern void* readdir(void* dir);

# macOS: x64 binds the 64-bit-inode variants by their `$INODE64` symbols;
# aarch64 only has those layouts, under the plain names, and so does iOS on
# both (its simulator included), which never had 32-bit inodes.
[Target(OS(Mac))]
extern int* __error();
[Target(OS(Mac) && !OS(IOS) && Arch(x64))]
[Link(name = "stat$INODE64")]
extern int stat(char* path, void* buf);
[Target(OS(Mac) && !OS(IOS) && Arch(x64))]
[Link(name = "lstat$INODE64")]
extern int lstat(char* path, void* buf);
[Target(OS(Mac) && !OS(IOS) && Arch(x64))]
[Link(name = "fstat$INODE64")]
extern int fstat(int fd, void* buf);
[Target(OS(Mac) && !OS(IOS) && Arch(x64))]
[Link(name = "opendir$INODE64")]
extern void* opendir(char* path);
[Target(OS(Mac) && !OS(IOS) && Arch(x64))]
[Link(name = "readdir$INODE64")]
extern void* readdir(void* dir);
[Target(OS(Mac) && (Arch(aarch64) || OS(IOS)))]
extern int stat(char* path, void* buf);
[Target(OS(Mac) && (Arch(aarch64) || OS(IOS)))]
extern int lstat(char* path, void* buf);
[Target(OS(Mac) && (Arch(aarch64) || OS(IOS)))]
extern int fstat(int fd, void* buf);
[Target(OS(Mac) && (Arch(aarch64) || OS(IOS)))]
extern void* opendir(char* path);
[Target(OS(Mac) && (Arch(aarch64) || OS(IOS)))]
extern void* readdir(void* dir);

# WASI: wasi-libc's own stat and dirent layouts, under the plain names.
[Target(OS(Wasi))]
extern int stat(char* path, void* buf);
[Target(OS(Wasi))]
extern int lstat(char* path, void* buf);
[Target(OS(Wasi))]
extern int fstat(int fd, void* buf);
[Target(OS(Wasi))]
extern void* opendir(char* path);
[Target(OS(Wasi))]
extern void* readdir(void* dir);

# ── errno ────────────────────────────────────────────────────────────────────

[Target((OS(Linux) && !OS(Android)) || OS(Wasi))]
_io_errno(): __ptr<int> {
    return __errno_location();
}

[Target(OS(Android))]
_io_errno(): __ptr<int> {
    return __errno();
}

[Target(OS(Mac))]
_io_errno(): __ptr<int> {
    return __error();
}

[Target(!OS(Windows))]
_io_sys_last_error(): ErrorCode {
    return _io_errno()[0];
}

[Target(!OS(Windows))]
export _io_sys_error_message(code: ErrorCode): String {
    return String(strerror(code));
}

# The ErrorKind of an errno value. Linux and macOS share the file codes
# except ENOTEMPTY and ECANCELED; most socket codes differ.
[Target(OS(Linux))]
_io_sys_error_kind(code: ErrorCode): ErrorKind {
    return match (code) {
        2 => ErrorKind.NotFound,                    # ENOENT
        13, 1 => ErrorKind.PermissionDenied,        # EACCES, EPERM
        17 => ErrorKind.AlreadyExists,              # EEXIST
        20 => ErrorKind.NotADirectory,              # ENOTDIR
        21 => ErrorKind.IsADirectory,               # EISDIR
        39 => ErrorKind.DirectoryNotEmpty,          # ENOTEMPTY
        22 => ErrorKind.InvalidInput,               # EINVAL
        4 => ErrorKind.Interrupted,                 # EINTR
        111 => ErrorKind.ConnectionRefused,         # ECONNREFUSED
        104, 103, 32 => ErrorKind.ConnectionReset,  # ECONNRESET, ECONNABORTED, EPIPE
        98 => ErrorKind.AddressInUse,               # EADDRINUSE
        99 => ErrorKind.AddressNotAvailable,        # EADDRNOTAVAIL
        110 => ErrorKind.TimedOut,                  # ETIMEDOUT
        125 => ErrorKind.Cancelled,                 # ECANCELED
        else => ErrorKind.Other,
    };
}

[Target(OS(Mac))]
_io_sys_error_kind(code: ErrorCode): ErrorKind {
    return match (code) {
        2 => ErrorKind.NotFound,                  # ENOENT
        13, 1 => ErrorKind.PermissionDenied,      # EACCES, EPERM
        17 => ErrorKind.AlreadyExists,            # EEXIST
        20 => ErrorKind.NotADirectory,            # ENOTDIR
        21 => ErrorKind.IsADirectory,             # EISDIR
        66 => ErrorKind.DirectoryNotEmpty,        # ENOTEMPTY
        22 => ErrorKind.InvalidInput,             # EINVAL
        4 => ErrorKind.Interrupted,               # EINTR
        61 => ErrorKind.ConnectionRefused,        # ECONNREFUSED
        54, 53, 32 => ErrorKind.ConnectionReset,  # ECONNRESET, ECONNABORTED, EPIPE
        48 => ErrorKind.AddressInUse,             # EADDRINUSE
        49 => ErrorKind.AddressNotAvailable,      # EADDRNOTAVAIL
        60 => ErrorKind.TimedOut,                 # ETIMEDOUT
        89 => ErrorKind.Cancelled,                # ECANCELED
        else => ErrorKind.Other,
    };
}

# WASI numbers errno values its own way (wasi/api.h's __WASI_ERRNO_*).
[Target(OS(Wasi))]
_io_sys_error_kind(code: ErrorCode): ErrorKind {
    return match (code) {
        44 => ErrorKind.NotFound,                 # ENOENT
        2, 63 => ErrorKind.PermissionDenied,      # EACCES, EPERM
        20 => ErrorKind.AlreadyExists,            # EEXIST
        54 => ErrorKind.NotADirectory,            # ENOTDIR
        31 => ErrorKind.IsADirectory,             # EISDIR
        55 => ErrorKind.DirectoryNotEmpty,        # ENOTEMPTY
        28 => ErrorKind.InvalidInput,             # EINVAL
        27 => ErrorKind.Interrupted,              # EINTR
        14 => ErrorKind.ConnectionRefused,        # ECONNREFUSED
        15, 13, 64 => ErrorKind.ConnectionReset,  # ECONNRESET, ECONNABORTED, EPIPE
        3 => ErrorKind.AddressInUse,              # EADDRINUSE
        4 => ErrorKind.AddressNotAvailable,       # EADDRNOTAVAIL
        73 => ErrorKind.TimedOut,                 # ETIMEDOUT
        11 => ErrorKind.Cancelled,                # ECANCELED
        else => ErrorKind.Other,
    };
}

# Codes for errors Pepper raises itself.
[Target(OS(Linux) || OS(Mac))]
export _io_sys_code_invalid_input(): ErrorCode {
    return 22;
}  # EINVAL

[Target(OS(Linux) || OS(Mac))]
_io_sys_code_not_a_directory(): ErrorCode {
    return 20;
}  # ENOTDIR

[Target(OS(Linux) || OS(Mac))]
_io_sys_code_not_found(): ErrorCode {
    return 2;
}  # ENOENT

[Target(OS(Linux) || OS(Mac))]
_io_sys_code_bad_handle(): ErrorCode {
    return 9;
}  # EBADF

[Target(OS(Linux) || OS(Mac))]
export _io_sys_code_write_zero(): ErrorCode {
    return 5;
}  # EIO

[Target(OS(Wasi))]
export _io_sys_code_invalid_input(): ErrorCode {
    return 28;
}  # EINVAL

[Target(OS(Wasi))]
_io_sys_code_not_a_directory(): ErrorCode {
    return 54;
}  # ENOTDIR

[Target(OS(Wasi))]
_io_sys_code_not_found(): ErrorCode {
    return 44;
}  # ENOENT

[Target(OS(Wasi))]
_io_sys_code_bad_handle(): ErrorCode {
    return 8;
}  # EBADF

[Target(OS(Wasi))]
export _io_sys_code_write_zero(): ErrorCode {
    return 29;
}  # EIO

# ERANGE: a buffer was too small.
[Target(OS(Linux) || OS(Mac))]
_io_posix_code_range(): ErrorCode {
    return 34;
}

[Target(OS(Wasi))]
_io_posix_code_range(): ErrorCode {
    return 68;
}

[Target(OS(Linux))]
_io_sys_code_cancelled(): ErrorCode {
    return 125;
}  # ECANCELED

[Target(OS(Mac))]
_io_sys_code_cancelled(): ErrorCode {
    return 89;
}  # ECANCELED

[Target(OS(Wasi))]
_io_sys_code_cancelled(): ErrorCode {
    return 11;
}  # ECANCELED

[Target(!OS(Windows))]
_io_posix_err_none(): IoResult<void> {
    return IoResult<void>.err(IoError.last());
}

# 0 -> Ok, -1 -> the errno error.
[Target(!OS(Windows))]
_io_posix_check(rc: int): IoResult<void> {
    if (rc == 0) {
        return _io_ok_void();
    }
    return _io_posix_err_none();
}

# An empty path names nothing (and an empty String has no C string).
[Target(!OS(Windows))]
_io_posix_empty_path(): IoError {
    return IoError(_io_sys_code_not_found(), "empty path");
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(!OS(Windows))]
_io_sys_invalid_handle(): FileHandle {
    return -1;
}

[Target(!OS(Windows))]
_io_sys_handle_valid(h: FileHandle): bool {
    return h >= 0;
}

# `h` as a number, for a `FileTransfer`.
[Target(!OS(Windows))]
_io_sys_handle_bits(h: FileHandle): long {
    return h as long;
}

# The handle `_io_sys_handle_bits` gave `bits` for.
[Target(!OS(Windows))]
_io_sys_handle_from_bits(bits: long): FileHandle {
    return bits as FileHandle;
}

[Target(!OS(Windows))]
_io_sys_std_handle(stream: StdStream): FileHandle {
    return match (stream) {
        Input => 0,
        Output => 1,
        Error => 2,
    };
}

# ── O_* flags ────────────────────────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
_io_o_rdonly(): int { return 0; }

[Target(OS(Linux) || OS(Mac))]
_io_o_wronly(): int { return 1; }

[Target(OS(Linux) || OS(Mac))]
_io_o_rdwr(): int { return 2; }

[Target(OS(Linux))]
_io_o_creat(): int {
    return 64;
}  # 0x40

[Target(OS(Linux))]
_io_o_excl(): int {
    return 128;
}  # 0x80

[Target(OS(Linux))]
_io_o_trunc(): int {
    return 512;
}  # 0x200

[Target(OS(Linux))]
_io_o_append(): int {
    return 1024;
}  # 0x400

[Target(OS(Linux))]
_io_o_cloexec(): int {
    return 524288;
}  # 0x80000

[Target(OS(Mac))]
_io_o_creat(): int {
    return 512;
}  # 0x200

[Target(OS(Mac))]
_io_o_excl(): int {
    return 2048;
}  # 0x800

[Target(OS(Mac))]
_io_o_trunc(): int {
    return 1024;
}  # 0x400

[Target(OS(Mac))]
_io_o_append(): int {
    return 8;
}  # 0x8

[Target(OS(Mac))]
_io_o_cloexec(): int {
    return 16777216;
}  # 0x1000000

# WASI: the access mode is two rights bits, O_CREAT, O_EXCL and O_TRUNC are
# WASI's open flags shifted up 12, and there is no exec to close on.
[Target(OS(Wasi))]
_io_o_rdonly(): int {
    return 67108864;
}  # 0x4000000

[Target(OS(Wasi))]
_io_o_wronly(): int {
    return 268435456;
}  # 0x10000000

[Target(OS(Wasi))]
_io_o_rdwr(): int {
    return 335544320;
}  # 0x14000000

[Target(OS(Wasi))]
_io_o_creat(): int {
    return 4096;
}  # 0x1000

[Target(OS(Wasi))]
_io_o_excl(): int {
    return 16384;
}  # 0x4000

[Target(OS(Wasi))]
_io_o_trunc(): int {
    return 32768;
}  # 0x8000

[Target(OS(Wasi))]
_io_o_append(): int {
    return 1;
}

[Target(OS(Wasi))]
_io_o_cloexec(): int {
    return 0;
}

# ── File operations ──────────────────────────────────────────────────────────

[Target(!OS(Windows))]
_io_sys_open(path: Path, options: OpenOptions): IoResult<FileHandle> {
    if (path._value.size == 0) {
        return IoResult<FileHandle>.err(_io_posix_empty_path());
    }
    var writes = options._write || options._append;
    var flags = _io_o_rdonly();
    if (writes) {
        flags = _io_o_wronly();
        if (options._read) {
            flags = _io_o_rdwr();
        }
    }
    if (options._append) {
        flags = flags | _io_o_append();
    }
    if (options._truncate) {
        flags = flags | _io_o_trunc();
    }
    if (options._create) {
        flags = flags | _io_o_creat();
    }
    if (options._create_new) {
        flags = flags | _io_o_creat() | _io_o_excl();
    }
    flags = flags | _io_o_cloexec();
    while (true) {
        var fd = open(path._value.c_str(), flags, options._mode);  # less the umask
        if (fd >= 0) {
            return IoResult<FileHandle>.ok(fd);
        }
        var e = IoError.last();
        if (!e.is_interrupted()) {
            return IoResult<FileHandle>.err(e);
        }
    }
    return IoResult<FileHandle>.err(IoError(4, "interrupted"));
}

[Target(!OS(Windows))]
_io_sys_close(h: FileHandle): IoResult<void> {
    return _io_posix_check(close(h));
}

# One read/write call moves at most this many bytes (Linux caps at
# 0x7ffff000, macOS at INT_MAX).
[Target(!OS(Windows))]
_io_posix_max_rw(n: ulong): ulong {
    if (n > 2147479552) {
        return 2147479552;
    }
    return n;
}

[Target(!OS(Windows))]
_io_sys_read(h: FileHandle, dst: __ptr<u8>, n: ulong): IoResult<ulong> {
    while (true) {
        var r = read(h, dst, _io_posix_max_rw(n));
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var e = IoError.last();
        if (!e.is_interrupted()) {
            return IoResult<ulong>.err(e);
        }
    }
    return IoResult<ulong>.ok(0);
}

[Target(!OS(Windows))]
_io_sys_write(h: FileHandle, src: __ptr<u8>, n: ulong): IoResult<ulong> {
    while (true) {
        var r = write(h, src, _io_posix_max_rw(n));
        if (r >= 0) {
            return IoResult<ulong>.ok(r as ulong);
        }
        var e = IoError.last();
        if (!e.is_interrupted()) {
            return IoResult<ulong>.err(e);
        }
    }
    return IoResult<ulong>.ok(0);
}

# whence: 0 start, 1 current, 2 end (SEEK_SET/SEEK_CUR/SEEK_END).
[Target(!OS(Windows))]
_io_sys_seek(h: FileHandle, offset: Offset, whence: int): IoResult<Offset> {
    var r = lseek(h, offset, whence);
    if (r < 0) {
        return IoResult<Offset>.err(IoError.last());
    }
    return IoResult<Offset>.ok(r);
}

[Target(!OS(Windows))]
_io_sys_truncate(h: FileHandle, size: ulong): IoResult<void> {
    return _io_posix_check(ftruncate(h, size as long));
}

[Target(!OS(Windows))]
_io_sys_sync(h: FileHandle): IoResult<void> {
    return _io_posix_check(fsync(h));
}

# ── stat ─────────────────────────────────────────────────────────────────────
# Linux `struct statx` (x64 and aarch64 alike): stx_mask u32 @0,
# stx_mode u16 @28, stx_size u64 @40, then statx_timestamp {i64 sec;
# u32 nsec; i32 pad} for atime @64, btime @80, ctime @96, mtime @112; 256
# bytes in all.
# macOS `struct stat` (64-bit inode layout, x64 and aarch64 alike): st_mode
# u16 @4, timespec {i64 sec; i64 nsec} for atime @32, mtime @48, ctime @64,
# birthtime @80, st_size i64 @96; 144 bytes in all.
# wasi-libc `struct stat` (wasm32): st_mode u32 @24, st_size i64 @48,
# timespec {i64 sec; i32 nsec; pad} for atime @72, mtime @88, ctime @104;
# 144 bytes in all, and no birth time.

[Target(OS(Linux))]
_io_stat_buf_size(): ulong { return 256; }

[Target(OS(Linux))]
_io_stat_mode_offset(): ulong { return 28; }

[Target(OS(Linux))]
_io_stat_size_offset(): ulong { return 40; }

[Target(OS(Linux))]
_io_stat_atime_offset(): ulong { return 64; }

[Target(OS(Linux))]
_io_stat_btime_offset(): ulong { return 80; }

[Target(OS(Linux))]
_io_stat_mtime_offset(): ulong { return 112; }

[Target(OS(Mac))]
_io_stat_buf_size(): ulong { return 144; }

[Target(OS(Mac))]
_io_stat_mode_offset(): ulong { return 4; }

[Target(OS(Mac))]
_io_stat_size_offset(): ulong { return 96; }

[Target(OS(Mac))]
_io_stat_atime_offset(): ulong { return 32; }

[Target(OS(Mac))]
_io_stat_btime_offset(): ulong { return 80; }

[Target(OS(Mac))]
_io_stat_mtime_offset(): ulong { return 48; }

[Target(OS(Wasi))]
_io_stat_buf_size(): ulong { return 144; }

[Target(OS(Wasi))]
_io_stat_mode_offset(): ulong { return 24; }

[Target(OS(Wasi))]
_io_stat_size_offset(): ulong { return 48; }

[Target(OS(Wasi))]
_io_stat_atime_offset(): ulong { return 72; }

# Never read: `_io_stat_has_btime` is false.
[Target(OS(Wasi))]
_io_stat_btime_offset(): ulong { return 72; }

[Target(OS(Wasi))]
_io_stat_mtime_offset(): ulong { return 88; }

# statx reports a birth time only when the file system has one.
[Target(OS(Linux))]
_io_stat_has_btime(buf: __ptr<void>): bool {
    return ((buf as __ptr<uint>)[0] & 2048) != 0;  # STATX_BTIME
}

[Target(OS(Mac))]
_io_stat_has_btime(buf: __ptr<void>): bool {
    return true;
}

[Target(OS(Wasi))]
_io_stat_has_btime(buf: __ptr<void>): bool {
    return false;
}

# Whether st_mode carries permission bits: WASI preview 1 has none, and
# wasi-libc reports only the file type.
[Target(OS(Linux) || OS(Mac))]
_io_stat_has_permissions(): bool {
    return true;
}

[Target(OS(Wasi))]
_io_stat_has_permissions(): bool {
    return false;
}

# AT_FDCWD, AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS | STATX_BTIME.
[Target(OS(Linux))]
_io_stat_path(path: __ptr<char>, follow: bool, buf: __ptr<void>): int {
    var flags = 0;
    if (!follow) {
        flags = 256;
    }
    return statx(-100, path, flags, 4095, buf);
}

[Target(OS(Mac) || OS(Wasi))]
_io_stat_path(path: __ptr<char>, follow: bool, buf: __ptr<void>): int {
    if (follow) {
        return stat(path, buf);
    }
    return lstat(path, buf);
}

# statx on the descriptor itself: AT_EMPTY_PATH with "".
[Target(OS(Linux))]
_io_stat_fd(fd: int, buf: __ptr<void>): int {
    return statx(fd, "", 4096, 4095, buf);
}

[Target(OS(Mac) || OS(Wasi))]
_io_stat_fd(fd: int, buf: __ptr<void>): int {
    return fstat(fd, buf);
}

[Target(!OS(Windows))]
_io_read_u16(buf: __ptr<void>, offset: ulong): uint {
    return ((buf + offset) as __ptr<u16>)[0];
}

[Target(!OS(Windows))]
_io_read_i64(buf: __ptr<void>, offset: ulong): long {
    return ((buf + offset) as __ptr<long>)[0];
}

[Target(!OS(Windows))]
_io_read_u32(buf: __ptr<void>, offset: ulong): uint {
    return ((buf + offset) as __ptr<uint>)[0];
}

# A {seconds, nanoseconds} pair as ns since the epoch. The nanoseconds are
# read as 32 bits: statx stores a u32, macOS a long whose value (< 10^9) sits
# in its low half, and wasi-libc a 32-bit long.
[Target(!OS(Windows))]
_io_stat_time(buf: __ptr<void>, offset: ulong): long {
    var sec = _io_read_i64(buf, offset);
    var nsec = _io_read_u32(buf, offset + 8) as long;
    return sec * 1000000000 + nsec;
}

[Target(!OS(Windows))]
_io_metadata_from_stat(buf: __ptr<void>): Metadata {
    var m = Metadata();
    var mode = _io_read_u16(buf, _io_stat_mode_offset());
    var kind = mode & 61440;         # S_IFMT 0170000
    m.is_file = kind == 32768;       # S_IFREG 0100000
    m.is_directory = kind == 16384;  # S_IFDIR 0040000
    m.is_symlink = kind == 40960;    # S_IFLNK 0120000
    m.file_type = _io_file_type(m.is_file, m.is_directory, m.is_symlink);
    if (_io_stat_has_permissions()) {
        m.permissions = mode & 4095;      # 07777
        m.read_only = (mode & 146) == 0;  # no 0222 write bit
    }
    m.size = _io_read_i64(buf, _io_stat_size_offset()) as ulong;
    m.accessed = _io_stat_time(buf, _io_stat_atime_offset());
    m.modified = _io_stat_time(buf, _io_stat_mtime_offset());
    if (_io_stat_has_btime(buf)) {
        m.created = Optional<long>.Value(_io_stat_time(buf, _io_stat_btime_offset()));
    }
    return m;
}

[Target(!OS(Windows))]
_io_sys_stat(path: Path, follow: bool): IoResult<Metadata> {
    if (path._value.size == 0) {
        return IoResult<Metadata>.err(_io_posix_empty_path());
    }
    var buf = _IoBuffer(_io_stat_buf_size());
    return _io_posix_stat_result(_io_stat_path(path._value.c_str(), follow, buf._bytes), buf);
}

[Target(!OS(Windows))]
_io_sys_fstat(h: FileHandle): IoResult<Metadata> {
    var buf = _IoBuffer(_io_stat_buf_size());
    return _io_posix_stat_result(_io_stat_fd(h, buf._bytes), buf);
}

# The metadata a stat call that returned `rc` wrote into `buf`, or errno.
[Target(!OS(Windows))]
_io_posix_stat_result(rc: int, buf: _IoBuffer): IoResult<Metadata> {
    if (rc != 0) {
        return IoResult<Metadata>.err(IoError.last());
    }
    return IoResult<Metadata>.ok(_io_metadata_from_stat(buf._bytes));
}

# ── Directories ──────────────────────────────────────────────────────────────
# dirent: d_type u8 and d_name char[] at 18/19 (Linux dirent64), 20/21
# (macOS 64-bit inode dirent) or 8/9 (wasi-libc). d_type's values are
# DT_DIR 4, DT_REG 8 and DT_LNK 10, except on WASI, whose are its file
# types: 3, 4 and 7.

[Target(OS(Linux))]
_io_dirent_type_offset(): ulong { return 18; }

[Target(OS(Linux))]
_io_dirent_name_offset(): ulong { return 19; }

[Target(OS(Mac))]
_io_dirent_type_offset(): ulong { return 20; }

[Target(OS(Mac))]
_io_dirent_name_offset(): ulong { return 21; }

[Target(OS(Wasi))]
_io_dirent_type_offset(): ulong { return 8; }

[Target(OS(Wasi))]
_io_dirent_name_offset(): ulong { return 9; }

[Target(OS(Linux) || OS(Mac))]
_io_dirent_directory(): u8 { return 4; }

[Target(OS(Linux) || OS(Mac))]
_io_dirent_file(): u8 { return 8; }

[Target(OS(Linux) || OS(Mac))]
_io_dirent_symlink(): u8 { return 10; }

[Target(OS(Wasi))]
_io_dirent_directory(): u8 { return 3; }

[Target(OS(Wasi))]
_io_dirent_file(): u8 { return 4; }

[Target(OS(Wasi))]
_io_dirent_symlink(): u8 { return 7; }

# Opens the listing of `iterator._path` and reads its first entry into
# `iterator._entry`: false when there is none.
[Target(!OS(Windows))]
_io_sys_directory_first(iterator: DirectoryIterator): IoResult<bool> {
    if (iterator._path._value.size == 0) {
        return IoResult<bool>.err(_io_posix_empty_path());
    }
    iterator._handle = opendir(iterator._path._value.c_str());
    if (iterator._handle == __null) {
        return IoResult<bool>.err(IoError.last());
    }
    return _io_sys_directory_next(iterator);
}

# Reads the next entry of an open listing into `iterator._entry`, skipping
# `.` and `..`: false at the end.
[Target(!OS(Windows))]
_io_sys_directory_next(iterator: DirectoryIterator): IoResult<bool> {
    while (true) {
        # readdir returns null at the end and on error; only errno tells.
        _io_errno()[0] = 0;
        var ent: __ptr<u8> = readdir(iterator._handle);
        if (ent == __null) {
            var code = _io_sys_last_error();
            if (code != 0) {
                return IoResult<bool>.err(IoError(code, _io_sys_error_message(code)));
            }
            return IoResult<bool>.ok(false);
        }
        var name = String(unsafe_cast<__ptr<char>>(ent + _io_dirent_name_offset()));
        if (name == "." || name == "..") {
            continue;
        }
        var entry = DirEntry();
        entry.name = name;
        entry.path = iterator._path.join(Path(name));
        var kind = ent[_io_dirent_type_offset()];
        if (kind == 0) {
            # DT_UNKNOWN: the file system did not say; ask lstat.
            var m = _io_sys_stat(entry.path, false);
            if (m.is_ok()) {
                entry.is_file = m.value().is_file;
                entry.is_directory = m.value().is_directory;
                entry.is_symlink = m.value().is_symlink;
                entry.file_type = m.value().file_type;
            }
        } else {
            entry.is_directory = kind == _io_dirent_directory();
            entry.is_file = kind == _io_dirent_file();
            entry.is_symlink = kind == _io_dirent_symlink();
            entry.file_type = _io_file_type(entry.is_file, entry.is_directory, entry.is_symlink);
        }
        iterator._entry = entry;
        return IoResult<bool>.ok(true);
    }
}

# Closes an open listing.
[Target(!OS(Windows))]
_io_sys_directory_close(handle: __ptr<void>) {
    closedir(handle);
}

[Target(!OS(Windows))]
_io_sys_mkdir(path: Path, mode: Mode): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(mkdir(path._value.c_str(), mode));  # less the umask
}

[Target(!OS(Windows))]
_io_sys_rmdir(path: Path): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(rmdir(path._value.c_str()));
}

[Target(!OS(Windows))]
_io_sys_unlink(path: Path): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(unlink(path._value.c_str()));
}

# Remove a non-directory or a symlink (to anything); `unlink` handles both.
[Target(!OS(Windows))]
_io_sys_remove_link(path: Path, is_dir: bool): IoResult<void> {
    return _io_sys_unlink(path);
}

[Target(!OS(Windows))]
_io_sys_rename(from: Path, to: Path): IoResult<void> {
    if (from._value.size == 0 || to._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(rename(from._value.c_str(), to._value.c_str()));
}

[Target(!OS(Windows))]
_io_sys_getcwd(): IoResult<Path> {
    ulong size = 4096;
    while (true) {
        var buf = _IoBuffer(size);
        var r = getcwd(unsafe_cast<__ptr<char>>(buf._bytes), size);
        if (r != __null) {
            return IoResult<Path>.ok(Path(_io_string_from_c(r)));
        }
        var e = IoError.last();
        if (e.code != _io_posix_code_range()) {  # retry with a bigger buffer
            return IoResult<Path>.err(e);
        }
        size = size * 2;
    }
    return IoResult<Path>.err(IoError(_io_posix_code_range(), "path too long"));
}

[Target(!OS(Windows))]
_io_sys_chdir(path: Path): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(chdir(path._value.c_str()));
}

[Target(!OS(Windows))]
_io_sys_realpath(path: Path): IoResult<Path> {
    if (path._value.size == 0) {
        return IoResult<Path>.err(_io_posix_empty_path());
    }
    var buf = _IoBuffer(4096);  # PATH_MAX (Linux 4096, macOS 1024)
    var r = realpath(path._value.c_str(), unsafe_cast<__ptr<char>>(buf._bytes));
    if (r == __null) {
        return IoResult<Path>.err(IoError.last());
    }
    return IoResult<Path>.ok(Path(_io_string_from_c(r)));
}

# Android has no /tmp; /data/local/tmp is the one any process may write.
[Target(!OS(Windows) && !OS(Android))]
_io_default_temp_dir(): String { return "/tmp"; }

[Target(OS(Android))]
_io_default_temp_dir(): String { return "/data/local/tmp"; }

[Target(!OS(Windows))]
export _io_sys_temp_dir(): Path {
    var s = String(getenv("TMPDIR"));
    if (s.size == 0) {
        return Path(_io_default_temp_dir());
    }
    # macOS's TMPDIR ends in '/'.
    var p = unsafe_cast<__ptr<u8>>(s.c_str());
    var n = s.size;
    while (n > 1 && _io_byte(p, s.size, n - 1) == '/') {
        n = n - 1;
    }
    return Path(_io_slice(s, 0, n));
}

# ── Permissions, times and links ─────────────────────────────────────────────

[Target(OS(Linux) || OS(Mac))]
_io_sys_chmod(path: Path, mode: Mode): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(chmod(path._value.c_str(), mode));
}

[Target(OS(Linux) || OS(Mac))]
_io_sys_fchmod(h: FileHandle, mode: Mode): IoResult<void> {
    return _io_posix_check(fchmod(h, mode));
}

# WASI's ENOTSUP.
[Target(OS(Wasi))]
_io_wasi_no_permissions(): IoResult<void> {
    return IoResult<void>.err(IoError(58, "WASI has no permission bits"));
}

[Target(OS(Wasi))]
_io_sys_chmod(path: Path, mode: Mode): IoResult<void> {
    return _io_wasi_no_permissions();
}

[Target(OS(Wasi))]
_io_sys_fchmod(h: FileHandle, mode: Mode): IoResult<void> {
    return _io_wasi_no_permissions();
}

# `current` with every write bit (0222) cleared, or with the owner's (0200)
# set: making a file writable never opens it to group or others.
[Target(!OS(Windows))]
_io_sys_read_only_mode(current: Mode, read_only: bool): Mode {
    if (read_only) {
        return (current | 146) ^ 146;
    }
    return current | 128;
}

# `current` with an execute bit (0111) for each class that may read it
# (0444), as `chmod +x` gives, or with every execute bit cleared.
[Target(!OS(Windows))]
_io_sys_executable_mode(current: Mode, executable: bool): Mode {
    if (executable) {
        return current | ((current & 292) >> 2);
    }
    return (current | 73) ^ 73;
}

# AT_FDCWD.
[Target(OS(Linux))]
_io_at_fdcwd(): int { return -100; }

[Target(OS(Mac) || OS(Wasi))]
_io_at_fdcwd(): int { return -2; }

# UTIME_OMIT, for the time a `utimensat` leaves alone.
[Target(OS(Linux))]
_io_utime_omit(): long { return 1073741822; }

[Target(OS(Mac) || OS(Wasi))]
_io_utime_omit(): long { return -2; }

# Writes the two timespecs `utimensat` and `futimens` take (access, then
# modification) into a 32-byte buffer. The nanoseconds are written as 64
# bits: wasi-libc's 32-bit `long` takes the low half, and the rest is
# padding.
[Target(!OS(Windows))]
_io_posix_times(accessed: long?, modified: long?): _IoBuffer {
    var buf = _IoBuffer(32);
    _io_posix_timespec(buf._bytes, accessed);
    _io_posix_timespec(buf._bytes + 16, modified);
    return buf;
}

[Target(!OS(Windows))]
_io_posix_timespec(at: __ptr<u8>, time: long?) {
    var fields = unsafe_cast<__ptr<long>>(at);
    if (time.is_empty()) {
        fields[0] = 0;
        fields[1] = _io_utime_omit();
        return;
    }
    var ns = time.value();
    var seconds = ns / 1000000000;
    var rest = ns - seconds * 1000000000;
    if (rest < 0) {  # division truncates toward zero
        seconds = seconds - 1;
        rest = rest + 1000000000;
    }
    fields[0] = seconds;
    fields[1] = rest;
}

[Target(!OS(Windows))]
_io_sys_set_times(path: Path, accessed: long?, modified: long?): IoResult<void> {
    if (path._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    var times = _io_posix_times(accessed, modified);
    return _io_posix_check(utimensat(_io_at_fdcwd(), path._value.c_str(), times._bytes, 0));
}

[Target(!OS(Windows))]
_io_sys_fset_times(h: FileHandle, accessed: long?, modified: long?): IoResult<void> {
    var times = _io_posix_times(accessed, modified);
    return _io_posix_check(futimens(h, times._bytes));
}

# POSIX makes one kind of symlink, whatever it points to.
[Target(!OS(Windows))]
_io_sys_symlink(target: Path, link: Path, directory: bool): IoResult<void> {
    if (target._value.size == 0 || link._value.size == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(symlink(target._value.c_str(), link._value.c_str()));
}

# readlink does not say when the buffer was too small, only fills it: retry
# with a bigger one until the target fits with room to spare.
[Target(!OS(Windows))]
_io_sys_readlink(path: Path): IoResult<Path> {
    if (path._value.size == 0) {
        return IoResult<Path>.err(_io_posix_empty_path());
    }
    ulong size = 256;
    while (true) {
        var buf = _IoBuffer(size);
        var n = readlink(path._value.c_str(), unsafe_cast<__ptr<char>>(buf._bytes), size);
        if (n < 0) {
            return IoResult<Path>.err(IoError.last());
        }
        if ((n as ulong) < size) {
            return IoResult<Path>.ok(Path(_io_string_from(unsafe_cast<__ptr<char>>(buf._bytes), n as ulong)));
        }
        size = size * 2;
    }
    return IoResult<Path>.err(IoError(_io_posix_code_range(), "link target too long"));
}

# ── Thread-local keys ────────────────────────────────────────────────────────

# A new thread-local key (pthread_key_t is 4 bytes on Linux and WASI, 8 on
# macOS; the slot is zeroed first so either reads back whole).
[Target(!OS(Windows))]
_io_sys_key_create(): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    key[0] = 0;
    if (pthread_key_create(key, __null) != 0) {
        panic("io: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(!OS(Windows))]
_io_sys_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(!OS(Windows))]
_io_sys_key_set(key: ulong, value: __ptr<void>) {
    pthread_setspecific(key, value);
}

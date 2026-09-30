# POSIX (Linux, macOS) platform layer for io. Every declaration carries
# [Target(!OS(Windows))]; sys_windows.pep declares the same `_io_sys_*`
# functions with the same signatures for Windows. These are exported to the
# other io files only: module.pep does not re-export them.
#
# Linux and macOS differ in the errno accessor, O_* flag values, the stat
# call and layout, and the dirent layout. C structs are read from raw
# `_pep_malloc` buffers at the byte offsets the small [Target] functions
# below return.

import "types";
import "path";
import "file";
import "directory";

# ── C functions ──────────────────────────────────────────────────────────────

[Target(!OS(Windows))] extern int open(char* path, int flags, ...);
[Target(!OS(Windows))] extern long read(int fd, void* buf, ulong n);
[Target(!OS(Windows))] extern long write(int fd, void* buf, ulong n);
[Target(!OS(Windows))] extern int close(int fd);
[Target(!OS(Windows))] extern long lseek(int fd, long offset, int whence);
[Target(!OS(Windows))] extern int ftruncate(int fd, long size);
[Target(!OS(Windows))] extern int fsync(int fd);
[Target(!OS(Windows))] extern int mkdir(char* path, uint mode);
[Target(!OS(Windows))] extern int rmdir(char* path);
[Target(!OS(Windows))] extern int unlink(char* path);
[Target(!OS(Windows))] extern int rename(char* from, char* to);
[Target(!OS(Windows))] extern char* getcwd(char* buf, ulong size);
[Target(!OS(Windows))] extern int chdir(char* path);
[Target(!OS(Windows))] extern char* realpath(char* path, char* resolved);
[Target(!OS(Windows))] extern char* strerror(int code);
[Target(!OS(Windows))] extern char* getenv(char* name);
[Target(!OS(Windows))] extern int closedir(void* dir);

# Linux: errno through glibc's accessor; statx for stat (one layout on x64
# and aarch64, and present where glibc < 2.33 has no `stat` symbol).
[Target(OS(Linux))] extern int* __errno_location();
[Target(OS(Linux))] extern int statx(int dirfd, char* path, int flags, uint mask, void* buf);
[Target(OS(Linux))] extern void* opendir(char* path);
[Target(OS(Linux))] extern void* readdir(void* dir);

# macOS: x64 binds the 64-bit-inode variants by their `$INODE64` symbols;
# aarch64 only has those layouts, under the plain names.
[Target(OS(Mac))] extern int* __error();
[Target(OS(Mac) && Arch(x64))] [LinkName("stat$INODE64")] extern int stat(char* path, void* buf);
[Target(OS(Mac) && Arch(x64))] [LinkName("lstat$INODE64")] extern int lstat(char* path, void* buf);
[Target(OS(Mac) && Arch(x64))] [LinkName("fstat$INODE64")] extern int fstat(int fd, void* buf);
[Target(OS(Mac) && Arch(x64))] [LinkName("opendir$INODE64")] extern void* opendir(char* path);
[Target(OS(Mac) && Arch(x64))] [LinkName("readdir$INODE64")] extern void* readdir(void* dir);
[Target(OS(Mac) && Arch(aarch64))] extern int stat(char* path, void* buf);
[Target(OS(Mac) && Arch(aarch64))] extern int lstat(char* path, void* buf);
[Target(OS(Mac) && Arch(aarch64))] extern int fstat(int fd, void* buf);
[Target(OS(Mac) && Arch(aarch64))] extern void* opendir(char* path);
[Target(OS(Mac) && Arch(aarch64))] extern void* readdir(void* dir);

# ── errno ────────────────────────────────────────────────────────────────────

[Target(OS(Linux))] export _io_errno(): __ptr<int> {
    return __errno_location();
}
[Target(OS(Mac))] export _io_errno(): __ptr<int> {
    return __error();
}

[Target(!OS(Windows))] export _io_sys_last_error(): ErrorCode {
    return _io_errno()[0];
}

[Target(!OS(Windows))] export _io_sys_error_message(code: ErrorCode): String {
    return _io_string_from_c(strerror(code));
}

# errno values (identical on Linux and macOS except ENOTEMPTY).
[Target(!OS(Windows))] export _io_sys_is_not_found(code: ErrorCode): bool { return code == 2; }          # ENOENT
[Target(!OS(Windows))] export _io_sys_is_permission_denied(code: ErrorCode): bool {
    return code == 13 || code == 1;   # EACCES, EPERM
}
[Target(!OS(Windows))] export _io_sys_is_already_exists(code: ErrorCode): bool { return code == 17; }    # EEXIST
[Target(!OS(Windows))] export _io_sys_is_not_a_directory(code: ErrorCode): bool { return code == 20; }  # ENOTDIR
[Target(!OS(Windows))] export _io_sys_is_is_a_directory(code: ErrorCode): bool { return code == 21; }   # EISDIR
[Target(OS(Linux))] export _io_sys_is_directory_not_empty(code: ErrorCode): bool { return code == 39; } # ENOTEMPTY
[Target(OS(Mac))] export _io_sys_is_directory_not_empty(code: ErrorCode): bool { return code == 66; }   # ENOTEMPTY
[Target(!OS(Windows))] export _io_sys_is_invalid_input(code: ErrorCode): bool { return code == 22; }    # EINVAL
[Target(!OS(Windows))] export _io_sys_is_interrupted(code: ErrorCode): bool { return code == 4; }       # EINTR

# Codes for errors Pepper raises itself.
[Target(!OS(Windows))] export _io_sys_code_invalid_input(): ErrorCode { return 22; }    # EINVAL
[Target(!OS(Windows))] export _io_sys_code_not_a_directory(): ErrorCode { return 20; }  # ENOTDIR
[Target(!OS(Windows))] export _io_sys_code_not_found(): ErrorCode { return 2; }         # ENOENT
[Target(!OS(Windows))] export _io_sys_code_bad_handle(): ErrorCode { return 9; }        # EBADF
[Target(!OS(Windows))] export _io_sys_code_write_zero(): ErrorCode { return 5; }        # EIO

[Target(!OS(Windows))] export _io_posix_err_none(): IoResult<void> {
    return IoResult<void>.err(IoError.last());
}

# 0 -> Ok, -1 -> the errno error.
[Target(!OS(Windows))] export _io_posix_check(rc: int): IoResult<void> {
    if (rc == 0) {
        return _io_ok_void();
    }
    return _io_posix_err_none();
}

# An empty path names nothing (and an empty String has no C string).
[Target(!OS(Windows))] export _io_posix_empty_path(): IoError {
    return IoError(2, "empty path");
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(!OS(Windows))] export _io_sys_invalid_handle(): FileHandle {
    return -1;
}

[Target(!OS(Windows))] export _io_sys_handle_valid(h: FileHandle): bool {
    return h >= 0;
}

[Target(!OS(Windows))] export _io_sys_std_handle(which: int): FileHandle {
    return which;   # 0, 1, 2
}

# ── O_* flags ────────────────────────────────────────────────────────────────

[Target(!OS(Windows))] export _io_o_wronly(): int { return 1; }
[Target(!OS(Windows))] export _io_o_rdwr(): int { return 2; }
[Target(OS(Linux))] export _io_o_creat(): int { return 64; }        # 0x40
[Target(OS(Linux))] export _io_o_excl(): int { return 128; }        # 0x80
[Target(OS(Linux))] export _io_o_trunc(): int { return 512; }       # 0x200
[Target(OS(Linux))] export _io_o_append(): int { return 1024; }     # 0x400
[Target(OS(Linux))] export _io_o_cloexec(): int { return 524288; }  # 0x80000
[Target(OS(Mac))] export _io_o_creat(): int { return 512; }         # 0x200
[Target(OS(Mac))] export _io_o_excl(): int { return 2048; }         # 0x800
[Target(OS(Mac))] export _io_o_trunc(): int { return 1024; }        # 0x400
[Target(OS(Mac))] export _io_o_append(): int { return 8; }          # 0x8
[Target(OS(Mac))] export _io_o_cloexec(): int { return 16777216; }  # 0x1000000

# ── File operations ──────────────────────────────────────────────────────────

[Target(!OS(Windows))] export _io_sys_open(path: Path, options: OpenOptions): IoResult<FileHandle> {
    if (path._value.size() == 0) {
        return IoResult<FileHandle>.err(_io_posix_empty_path());
    }
    var writes = options._write || options._append;
    var flags = 0;   # O_RDONLY
    if (writes) {
        flags = _io_o_wronly();
        if (options._read) {
            flags = _io_o_rdwr();
        }
    }
    if (options._append) { flags = flags | _io_o_append(); }
    if (options._truncate) { flags = flags | _io_o_trunc(); }
    if (options._create) { flags = flags | _io_o_creat(); }
    if (options._create_new) { flags = flags | _io_o_creat() | _io_o_excl(); }
    flags = flags | _io_o_cloexec();
    while (true) {
        var fd = open(path._value.c_str(), flags, 438);   # 0666, less the umask
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

[Target(!OS(Windows))] export _io_sys_close(h: FileHandle): IoResult<void> {
    return _io_posix_check(close(h));
}

# One read/write call moves at most this many bytes (Linux caps at
# 0x7ffff000, macOS at INT_MAX).
[Target(!OS(Windows))] export _io_posix_max_rw(n: ulong): ulong {
    if (n > 2147479552) {
        return 2147479552;
    }
    return n;
}

[Target(!OS(Windows))] export _io_sys_read(h: FileHandle, dst: __ptr<u8>, n: ulong): IoResult<ulong> {
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

[Target(!OS(Windows))] export _io_sys_write(h: FileHandle, src: __ptr<u8>, n: ulong): IoResult<ulong> {
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
[Target(!OS(Windows))] export _io_sys_seek(h: FileHandle, offset: Offset, whence: int): IoResult<Offset> {
    var r = lseek(h, offset, whence);
    if (r < 0) {
        return IoResult<Offset>.err(IoError.last());
    }
    return IoResult<Offset>.ok(r);
}

[Target(!OS(Windows))] export _io_sys_truncate(h: FileHandle, size: ulong): IoResult<void> {
    return _io_posix_check(ftruncate(h, size as long));
}

[Target(!OS(Windows))] export _io_sys_sync(h: FileHandle): IoResult<void> {
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

[Target(OS(Linux))] export _io_stat_buf_size(): ulong { return 256; }
[Target(OS(Linux))] export _io_stat_mode_offset(): ulong { return 28; }
[Target(OS(Linux))] export _io_stat_size_offset(): ulong { return 40; }
[Target(OS(Linux))] export _io_stat_atime_offset(): ulong { return 64; }
[Target(OS(Linux))] export _io_stat_btime_offset(): ulong { return 80; }
[Target(OS(Linux))] export _io_stat_mtime_offset(): ulong { return 112; }
[Target(OS(Mac))] export _io_stat_buf_size(): ulong { return 144; }
[Target(OS(Mac))] export _io_stat_mode_offset(): ulong { return 4; }
[Target(OS(Mac))] export _io_stat_size_offset(): ulong { return 96; }
[Target(OS(Mac))] export _io_stat_atime_offset(): ulong { return 32; }
[Target(OS(Mac))] export _io_stat_btime_offset(): ulong { return 80; }
[Target(OS(Mac))] export _io_stat_mtime_offset(): ulong { return 48; }

# statx reports a birth time only when the file system has one.
[Target(OS(Linux))] export _io_stat_has_btime(buf: __ptr<void>): bool {
    return ((buf as __ptr<uint>)[0] & 2048) != 0;   # STATX_BTIME
}
[Target(OS(Mac))] export _io_stat_has_btime(buf: __ptr<void>): bool {
    return true;
}

# AT_FDCWD, AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS | STATX_BTIME.
[Target(OS(Linux))] export _io_stat_path(path: __ptr<char>, follow: bool, buf: __ptr<void>): int {
    var flags = 0;
    if (!follow) {
        flags = 256;
    }
    return statx(-100, path, flags, 4095, buf);
}
[Target(OS(Mac))] export _io_stat_path(path: __ptr<char>, follow: bool, buf: __ptr<void>): int {
    if (follow) {
        return stat(path, buf);
    }
    return lstat(path, buf);
}

# statx on the descriptor itself: AT_EMPTY_PATH with "".
[Target(OS(Linux))] export _io_stat_fd(fd: int, buf: __ptr<void>): int {
    return statx(fd, "", 4096, 4095, buf);
}
[Target(OS(Mac))] export _io_stat_fd(fd: int, buf: __ptr<void>): int {
    return fstat(fd, buf);
}

[Target(!OS(Windows))] export _io_read_u16(buf: __ptr<void>, offset: ulong): uint {
    return ((buf + offset) as __ptr<u16>)[0];
}

[Target(!OS(Windows))] export _io_read_i64(buf: __ptr<void>, offset: ulong): long {
    return ((buf + offset) as __ptr<long>)[0];
}

[Target(!OS(Windows))] export _io_read_u32(buf: __ptr<void>, offset: ulong): uint {
    return ((buf + offset) as __ptr<uint>)[0];
}

# A {seconds, nanoseconds} pair as ns since the epoch. The nanoseconds are
# read as 32 bits: statx stores a u32, macOS a long whose value (< 10^9) sits
# in its low half.
[Target(!OS(Windows))] export _io_stat_time(buf: __ptr<void>, offset: ulong): long {
    var sec = _io_read_i64(buf, offset);
    var nsec = _io_read_u32(buf, offset + 8) as long;
    return sec * 1000000000 + nsec;
}

[Target(!OS(Windows))] export _io_metadata_from_stat(buf: __ptr<void>): Metadata {
    var m = Metadata();
    var mode = _io_read_u16(buf, _io_stat_mode_offset());
    var kind = mode & 61440;           # S_IFMT 0170000
    m.is_file = kind == 32768;          # S_IFREG 0100000
    m.is_directory = kind == 16384;           # S_IFDIR 0040000
    m.is_symlink = kind == 40960;       # S_IFLNK 0120000
    m.permissions = mode & 4095;       # 07777
    m.read_only = (mode & 146) == 0;    # no 0222 write bit
    m.size = _io_read_i64(buf, _io_stat_size_offset()) as ulong;
    m.accessed = _io_stat_time(buf, _io_stat_atime_offset());
    m.modified = _io_stat_time(buf, _io_stat_mtime_offset());
    if (_io_stat_has_btime(buf)) {
        m.created = _io_stat_time(buf, _io_stat_btime_offset());
    }
    return m;
}

[Target(!OS(Windows))] export _io_sys_stat(path: Path, follow: bool): IoResult<Metadata> {
    if (path._value.size() == 0) {
        return IoResult<Metadata>.err(_io_posix_empty_path());
    }
    var buf = _pep_malloc(_io_stat_buf_size());
    var rc = _io_stat_path(path._value.c_str(), follow, buf);
    if (rc != 0) {
        var e = IoError.last();
        _pep_free(buf);
        return IoResult<Metadata>.err(e);
    }
    var m = _io_metadata_from_stat(buf);
    _pep_free(buf);
    return IoResult<Metadata>.ok(m);
}

[Target(!OS(Windows))] export _io_sys_fstat(h: FileHandle): IoResult<Metadata> {
    var buf = _pep_malloc(_io_stat_buf_size());
    var rc = _io_stat_fd(h, buf);
    if (rc != 0) {
        var e = IoError.last();
        _pep_free(buf);
        return IoResult<Metadata>.err(e);
    }
    var m = _io_metadata_from_stat(buf);
    _pep_free(buf);
    return IoResult<Metadata>.ok(m);
}

# ── Directories ──────────────────────────────────────────────────────────────
# dirent: d_type u8 and d_name char[] at 18/19 (Linux dirent64) or 20/21
# (macOS 64-bit inode dirent).

[Target(OS(Linux))] export _io_dirent_type_offset(): ulong { return 18; }
[Target(OS(Linux))] export _io_dirent_name_offset(): ulong { return 19; }
[Target(OS(Mac))] export _io_dirent_type_offset(): ulong { return 20; }
[Target(OS(Mac))] export _io_dirent_name_offset(): ulong { return 21; }

[Target(!OS(Windows))] export _io_sys_list(path: Path): IoResult<DirEntry[]> {
    if (path._value.size() == 0) {
        return IoResult<DirEntry[]>.err(_io_posix_empty_path());
    }
    var dir = opendir(path._value.c_str());
    if (dir == __null) {
        return IoResult<DirEntry[]>.err(IoError.last());
    }
    var out = Array<DirEntry>();
    while (true) {
        # readdir returns null at the end and on error; only errno tells.
        _io_errno()[0] = 0;
        var ent: __ptr<u8> = readdir(dir);
        if (ent == __null) {
            var code = _io_sys_last_error();
            if (code != 0) {
                var e = IoError(code, _io_sys_error_message(code));
                closedir(dir);
                return IoResult<DirEntry[]>.err(e);
            }
            break;
        }
        var name = _io_string_from_c((ent + _io_dirent_name_offset()) as __ptr<char>);
        if (_io_is_dot(name) || _io_is_dotdot(name)) {
            continue;
        }
        var entry = DirEntry();
        entry.name = name;
        entry.path = path.join(Path(name));
        var kind = ent[_io_dirent_type_offset()];
        if (kind == 0) {
            # DT_UNKNOWN: the file system did not say; ask lstat.
            var m = _io_sys_stat(entry.path, false);
            if (m.is_ok()) {
                entry.is_file = m._value.is_file;
                entry.is_directory = m._value.is_directory;
                entry.is_symlink = m._value.is_symlink;
            }
        } else {
            entry.is_directory = kind == 4;       # DT_DIR
            entry.is_file = kind == 8;      # DT_REG
            entry.is_symlink = kind == 10;  # DT_LNK
        }
        out.append(entry);
    }
    closedir(dir);
    return IoResult<DirEntry[]>.ok(out);
}

[Target(!OS(Windows))] export _io_sys_mkdir(path: Path): IoResult<void> {
    if (path._value.size() == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(mkdir(path._value.c_str(), 511));   # 0777, less the umask
}

[Target(!OS(Windows))] export _io_sys_rmdir(path: Path): IoResult<void> {
    if (path._value.size() == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(rmdir(path._value.c_str()));
}

[Target(!OS(Windows))] export _io_sys_unlink(path: Path): IoResult<void> {
    if (path._value.size() == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(unlink(path._value.c_str()));
}

# Remove a non-directory or a symlink (to anything); `unlink` handles both.
[Target(!OS(Windows))] export _io_sys_remove_link(path: Path, is_dir: bool): IoResult<void> {
    return _io_sys_unlink(path);
}

[Target(!OS(Windows))] export _io_sys_rename(from: Path, to: Path): IoResult<void> {
    if (from._value.size() == 0 || to._value.size() == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(rename(from._value.c_str(), to._value.c_str()));
}

[Target(!OS(Windows))] export _io_sys_getcwd(): IoResult<Path> {
    ulong size = 4096;
    while (true) {
        var buf = _pep_malloc(size);
        var r = getcwd(buf, size);
        if (r != __null) {
            var p = Path(_io_string_from_c(buf));
            _pep_free(buf);
            return IoResult<Path>.ok(p);
        }
        var e = IoError.last();
        _pep_free(buf);
        if (e.code != 34) {   # ERANGE: retry with a bigger buffer
            return IoResult<Path>.err(e);
        }
        size = size * 2;
    }
    return IoResult<Path>.err(IoError(34, "path too long"));
}

[Target(!OS(Windows))] export _io_sys_chdir(path: Path): IoResult<void> {
    if (path._value.size() == 0) {
        return IoResult<void>.err(_io_posix_empty_path());
    }
    return _io_posix_check(chdir(path._value.c_str()));
}

[Target(!OS(Windows))] export _io_sys_realpath(path: Path): IoResult<Path> {
    if (path._value.size() == 0) {
        return IoResult<Path>.err(_io_posix_empty_path());
    }
    var buf = _pep_malloc(4096);   # PATH_MAX (Linux 4096, macOS 1024)
    var r = realpath(path._value.c_str(), buf);
    if (r == __null) {
        var e = IoError.last();
        _pep_free(buf);
        return IoResult<Path>.err(e);
    }
    var p = Path(_io_string_from_c(buf));
    _pep_free(buf);
    return IoResult<Path>.ok(p);
}

[Target(!OS(Windows))] export _io_sys_temp_dir(): Path {
    var s = _io_string_from_c(getenv("TMPDIR"));
    if (s.size() == 0) {
        return Path("/tmp");
    }
    # macOS's TMPDIR ends in '/'.
    var p = s.c_str() as __ptr<u8>;
    var n = s.size();
    while (n > 1 && _io_byte(p, s.size(), n - 1) == 47) { n = n - 1; }
    return Path(_io_slice(s, 0, n));
}

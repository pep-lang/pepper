# Windows platform layer for io. Every declaration carries
# [Target(OS(Windows))]; sys_posix.pep declares the same `_io_sys_*`
# functions with the same signatures for Linux and macOS. These are exported
# to the other io files only: module.pep does not re-export them.
#
# Paths go through the UTF-16 *W APIs: UTF-8 Strings are converted with
# MultiByteToWideChar into NUL-terminated `__ptr<u16>` buffers (freed by the
# caller) and back with WideCharToMultiByte. Everything here is in kernel32,
# which is linked by default. C structs are read from raw `_pep_malloc`
# buffers at fixed byte offsets (identical on x64 and aarch64).

import "directory";
import "file";
import "path";
import "types";

# ── C functions (kernel32) ───────────────────────────────────────────────────

[Target(OS(Windows))]
extern void* CreateFileW(
    ushort* name, uint access, uint share, void* security, uint disposition, uint flags, void* template
);
[Target(OS(Windows))]
extern int ReadFile(void* h, void* buf, uint n, uint* done, void* overlapped);
[Target(OS(Windows))]
extern int WriteFile(void* h, void* buf, uint n, uint* done, void* overlapped);
[Target(OS(Windows))]
extern int CloseHandle(void* h);
[Target(OS(Windows))]
extern int SetFilePointerEx(void* h, long distance, long* position, uint method);
[Target(OS(Windows))]
extern int SetFileInformationByHandle(void* h, int info_class, void* info, uint size);
[Target(OS(Windows))]
extern int FlushFileBuffers(void* h);
[Target(OS(Windows))]
extern int SetFileTime(void* h, void* created, void* accessed, void* written);
[Target(OS(Windows))]
extern u8 CreateSymbolicLinkW(ushort* link, ushort* target, uint flags);
[Target(OS(Windows))]
extern int DeviceIoControl(
    void* h, uint code, void* input, uint input_size, void* output, uint output_size, uint* returned, void* overlapped
);
[Target(OS(Windows))]
extern int GetFileInformationByHandle(void* h, void* info);
[Target(OS(Windows))]
extern void* FindFirstFileW(ushort* pattern, void* data);
[Target(OS(Windows))]
extern int FindNextFileW(void* h, void* data);
[Target(OS(Windows))]
extern int FindClose(void* h);
[Target(OS(Windows))]
extern int CreateDirectoryW(ushort* path, void* security);
[Target(OS(Windows))]
extern int RemoveDirectoryW(ushort* path);
[Target(OS(Windows))]
extern int DeleteFileW(ushort* path);
[Target(OS(Windows))]
extern int MoveFileExW(ushort* from, ushort* to, uint flags);
[Target(OS(Windows))]
extern uint GetCurrentDirectoryW(uint size, ushort* buf);
[Target(OS(Windows))]
extern int SetCurrentDirectoryW(ushort* path);
[Target(OS(Windows))]
extern uint GetFinalPathNameByHandleW(void* h, ushort* buf, uint size, uint flags);
[Target(OS(Windows))]
extern uint GetTempPathW(uint size, ushort* buf);
[Target(OS(Windows))]
extern void* GetStdHandle(uint which);
[Target(OS(Windows))]
extern uint GetLastError();
[Target(OS(Windows))]
extern uint FormatMessageW(uint flags, void* source, uint id, uint language, ushort* buf, uint size, void* args);
[Target(OS(Windows))]
extern int MultiByteToWideChar(uint codepage, uint flags, char* src, int src_len, ushort* dst, int dst_len);
[Target(OS(Windows))]
extern uint TlsAlloc();
[Target(OS(Windows))]
extern void* TlsGetValue(uint index);
[Target(OS(Windows))]
extern int TlsSetValue(uint index, void* value);
[Target(OS(Windows))]
extern int WideCharToMultiByte(
    uint codepage, uint flags, ushort* src, int src_len, char* dst, int dst_len, void* default_char, int* used_default
);

# ── UTF-8 <-> UTF-16 ─────────────────────────────────────────────────────────

# A NUL-terminated UTF-16 copy of `s`; the caller frees it with _pep_free.
# One UTF-8 byte never yields more than one UTF-16 unit, so Size + 1 units
# always suffice.
[Target(OS(Windows))]
export _io_win_wide(s: String): __ptr<u16> {
    var units = s.size + 1;
    var w = _pep_malloc(units * 2) as __ptr<u16>;
    if (s.size > 0) {
        MultiByteToWideChar(65001, 0, s.c_str(), s.size as int, w, units as int);  # CP_UTF8
    }
    return w;
}

# Number of UTF-16 units before the terminating NUL.
[Target(OS(Windows))]
export _io_win_wide_len(w: __ptr<u16>): int {
    var n = 0;
    while (w[n] != 0) {
        n = n + 1;
    }
    return n;
}

# `n` UTF-16 units at `w` as a UTF-8 String.
[Target(OS(Windows))]
export _io_win_narrow(w: __ptr<u16>, n: int): String {
    if (n <= 0) {
        return String();
    }
    var size = WideCharToMultiByte(65001, 0, w, n, __null, 0, __null, __null);
    if (size <= 0) {
        return String();
    }
    var buf = _pep_malloc(size as ulong) as __ptr<char>;
    WideCharToMultiByte(65001, 0, w, n, buf, size, __null, __null);
    var s = _io_string_from(buf, size as ulong);
    _pep_free(buf);
    return s;
}

# ── Errors ───────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
_io_sys_last_error(): ErrorCode {
    return GetLastError();
}

# FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, trailing
# whitespace (the ". \r\n" tail) trimmed.
[Target(OS(Windows))]
export _io_sys_error_message(code: ErrorCode): String {
    var buf = _pep_malloc(1024) as __ptr<u16>;
    var n = FormatMessageW(4608, __null, code, 0, buf, 512, __null) as int;
    while (n > 0) {
        var c = buf[n - 1];
        if (c != '\n' && c != '\r' && c != ' ' && c != '.') {
            break;
        }
        n = n - 1;
    }
    var s = _io_win_narrow(buf, n);
    _pep_free(buf);
    if (s.size == 0) {
        return "unknown error";
    }
    return s;
}

# The ErrorKind of a GetLastError() / WSAGetLastError() code.
[Target(OS(Windows))]
_io_sys_error_kind(code: ErrorCode): ErrorKind {
    return match (code) {
        2, 3 => ErrorKind.NotFound,                    # FILE_NOT_FOUND, PATH_NOT_FOUND
        5, 1314 => ErrorKind.PermissionDenied,         # ACCESS_DENIED, PRIVILEGE_NOT_HELD
        80, 183 => ErrorKind.AlreadyExists,            # FILE_EXISTS, ALREADY_EXISTS
        267 => ErrorKind.NotADirectory,                # DIRECTORY (invalid directory name)
        336 => ErrorKind.IsADirectory,                 # DIRECTORY_NOT_SUPPORTED
        145 => ErrorKind.DirectoryNotEmpty,            # DIR_NOT_EMPTY
        87, 123, 131, 4390 => ErrorKind.InvalidInput,  # INVALID_PARAMETER, INVALID_NAME, NEGATIVE_SEEK, NOT_A_REPARSE_POINT
        10004 => ErrorKind.Interrupted,                # WSAEINTR
        10061 => ErrorKind.ConnectionRefused,          # WSAECONNREFUSED
        10054, 10053 => ErrorKind.ConnectionReset,     # WSAECONNRESET, WSAECONNABORTED
        10048 => ErrorKind.AddressInUse,               # WSAEADDRINUSE
        10049 => ErrorKind.AddressNotAvailable,        # WSAEADDRNOTAVAIL
        10060 => ErrorKind.TimedOut,                   # WSAETIMEDOUT
        995, 1223 => ErrorKind.Cancelled,              # OPERATION_ABORTED, CANCELLED
        else => ErrorKind.Other,
    };
}

# Codes for errors Pepper raises itself.
[Target(OS(Windows))]
export _io_sys_code_invalid_input(): ErrorCode {
    return 87;
}  # INVALID_PARAMETER

[Target(OS(Windows))]
_io_sys_code_not_a_directory(): ErrorCode {
    return 267;
}  # DIRECTORY

[Target(OS(Windows))]
_io_sys_code_not_found(): ErrorCode {
    return 2;
}  # FILE_NOT_FOUND

[Target(OS(Windows))]
_io_sys_code_bad_handle(): ErrorCode {
    return 6;
}  # INVALID_HANDLE

[Target(OS(Windows))]
export _io_sys_code_write_zero(): ErrorCode {
    return 29;
}  # WRITE_FAULT

[Target(OS(Windows))]
_io_sys_code_cancelled(): ErrorCode {
    return 995;
}  # OPERATION_ABORTED

# A BOOL result: nonzero -> Ok, 0 -> the GetLastError() error.
[Target(OS(Windows))]
_io_win_check(ok: int): IoResult<void> {
    if (ok != 0) {
        return _io_ok_void();
    }
    return IoResult<void>.err(IoError.last());
}

# A BOOL result `ok`, with `code`, the GetLastError() read right after the
# call (before freeing its arguments could change it): nonzero -> Ok, 0 ->
# that error.
[Target(OS(Windows))]
_io_win_check_code(ok: int, code: ErrorCode): IoResult<void> {
    if (ok != 0) {
        return _io_ok_void();
    }
    return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(OS(Windows))]
_io_sys_invalid_handle(): FileHandle {
    return __null;
}

# Neither null nor INVALID_HANDLE_VALUE (-1).
[Target(OS(Windows))]
_io_sys_handle_valid(h: FileHandle): bool {
    return h != __null && unsafe_cast<long>(h) != -1;
}

# `h` as a number, for a `FileTransfer`.
[Target(OS(Windows))]
_io_sys_handle_bits(h: FileHandle): long {
    return unsafe_cast<long>(h);
}

# The handle `_io_sys_handle_bits` gave `bits` for.
[Target(OS(Windows))]
_io_sys_handle_from_bits(bits: long): FileHandle {
    return unsafe_cast<FileHandle>(bits);
}

# STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE are (DWORD)-10,
# -11 and -12.
[Target(OS(Windows))]
_io_sys_std_handle(stream: StdStream): FileHandle {
    uint which = match (stream) {
        Input => 4294967286,   # STD_INPUT_HANDLE (-10)
        Output => 4294967285,  # STD_OUTPUT_HANDLE (-11)
        Error => 4294967284,   # STD_ERROR_HANDLE (-12)
    };
    return GetStdHandle(which);
}

# CreateFileW sharing everything (FILE_SHARE_READ | WRITE | DELETE) with
# FILE_FLAG_BACKUP_SEMANTICS, so directories open too.
[Target(OS(Windows))]
_io_win_create(path: Path, access: ulong, disposition: uint, extra_flags: ulong): IoResult<FileHandle> {
    var w = _io_win_wide(path._value);
    var flags = 33554560 | extra_flags;  # BACKUP_SEMANTICS | ATTRIBUTE_NORMAL
    var h = CreateFileW(w, access as uint, 7, __null, disposition, flags as uint, __null);
    var code = GetLastError();
    _pep_free(w);
    if (!_io_sys_handle_valid(h)) {
        return IoResult<FileHandle>.err(IoError(code, _io_sys_error_message(code)));
    }
    return IoResult<FileHandle>.ok(h);
}

# ── File operations ──────────────────────────────────────────────────────────

[Target(OS(Windows))]
_io_sys_open(path: Path, options: OpenOptions): IoResult<FileHandle> {
    ulong access = 0;
    if (options._read) {
        access = access | 2147483648;  # GENERIC_READ
    }
    if (options._append) {
        # FILE_GENERIC_WRITE without FILE_WRITE_DATA: writes only append.
        access = access | 1179924;
    } else {
        if (options._write) {
            access = access | 1073741824;  # GENERIC_WRITE
        }
    }
    uint disposition = 3;  # OPEN_EXISTING
    if (options._truncate) {
        disposition = 5;  # TRUNCATE_EXISTING
    }
    if (options._create) {
        disposition = 4;  # OPEN_ALWAYS
        if (options._truncate) {
            disposition = 2;  # CREATE_ALWAYS
        }
    }
    if (options._create_new) {
        disposition = 1;  # CREATE_NEW
    }
    return _io_win_create(path, access, disposition, 0);
}

[Target(OS(Windows))]
_io_sys_close(h: FileHandle): IoResult<void> {
    return _io_win_check(CloseHandle(h));
}

# One ReadFile/WriteFile call moves at most 1 GiB (the count is a DWORD);
# sockets use the same limit (their length is an int).
[Target(OS(Windows))]
_io_win_max_rw(n: ulong): uint {
    if (n > 1073741824) {
        return 1073741824;
    }
    return n as uint;
}

[Target(OS(Windows))]
_io_sys_read(h: FileHandle, dst: __ptr<u8>, n: ulong): IoResult<ulong> {
    var done = _pep_malloc(4) as __ptr<uint>;
    var ok = ReadFile(h, dst, _io_win_max_rw(n), done, __null);
    var count = done[0] as ulong;
    _pep_free(done);
    if (ok == 0) {
        var code = GetLastError();
        if (code == 109) {  # BROKEN_PIPE: the writer closed; EOF
            return IoResult<ulong>.ok(0);
        }
        if (code == 1) {
            # INVALID_FUNCTION is what ReadFile says about a directory handle
            # (opened with BACKUP_SEMANTICS); report it as POSIX's EISDIR does.
            var m = _io_sys_fstat(h);
            if (m.is_ok()) {
                if (m.value().is_directory) {
                    code = 336;  # DIRECTORY_NOT_SUPPORTED: is_is_a_directory
                }
            }
        }
        return IoResult<ulong>.err(IoError(code, _io_sys_error_message(code)));
    }
    return IoResult<ulong>.ok(count);
}

[Target(OS(Windows))]
_io_sys_write(h: FileHandle, src: __ptr<u8>, n: ulong): IoResult<ulong> {
    var done = _pep_malloc(4) as __ptr<uint>;
    var ok = WriteFile(h, src, _io_win_max_rw(n), done, __null);
    var count = done[0] as ulong;
    _pep_free(done);
    if (ok == 0) {
        return IoResult<ulong>.err(IoError.last());
    }
    return IoResult<ulong>.ok(count);
}

# whence: 0 FILE_BEGIN, 1 FILE_CURRENT, 2 FILE_END (the POSIX values).
[Target(OS(Windows))]
_io_sys_seek(h: FileHandle, offset: Offset, whence: int): IoResult<Offset> {
    var pos = _pep_malloc(8) as __ptr<long>;
    var ok = SetFilePointerEx(h, offset, pos, whence as uint);
    var at = pos[0];
    _pep_free(pos);
    if (ok == 0) {
        return IoResult<Offset>.err(IoError.last());
    }
    return IoResult<Offset>.ok(at);
}

# FILE_END_OF_FILE_INFO through SetFileInformationByHandle(FileEndOfFileInfo):
# unlike SetEndOfFile it leaves the file pointer where it is.
[Target(OS(Windows))]
_io_sys_truncate(h: FileHandle, size: ulong): IoResult<void> {
    var info = _pep_malloc(8) as __ptr<long>;
    info[0] = size as long;
    var ok = SetFileInformationByHandle(h, 6, info, 8);
    var code = GetLastError();
    _pep_free(info);
    return _io_win_check_code(ok, code);
}

[Target(OS(Windows))]
_io_sys_sync(h: FileHandle): IoResult<void> {
    return _io_win_check(FlushFileBuffers(h));
}

# ── Metadata ─────────────────────────────────────────────────────────────────
# BY_HANDLE_FILE_INFORMATION (52 bytes): dwFileAttributes u32 @0, FILETIMEs
# {u32 low; u32 high} for creation @4, last access @12, last write @20,
# nFileSizeHigh @32, nFileSizeLow @36.

[Target(OS(Windows))]
_io_win_u32(buf: __ptr<void>, offset: ulong): ulong {
    return ((buf + offset) as __ptr<uint>)[0] as ulong;
}

# A FILETIME (100 ns ticks since 1601) as ns since the Unix epoch; 0 stays 0.
[Target(OS(Windows))]
_io_win_time(buf: __ptr<void>, offset: ulong): long {
    var ticks = ((_io_win_u32(buf, offset + 4) << 32) | _io_win_u32(buf, offset)) as long;
    if (ticks == 0) {
        return 0;
    }
    return (ticks - 116444736000000000) * 100;
}

[Target(OS(Windows))]
_io_win_metadata(
    buf: __ptr<void>,
    attrs_offset: ulong,
    created: ulong,
    accessed: ulong,
    written: ulong,
    size_high: ulong,
    size_low: ulong
): Metadata {
    var m = Metadata();
    var attrs = _io_win_u32(buf, attrs_offset);
    m.is_directory = (attrs & 16) != 0;  # FILE_ATTRIBUTE_DIRECTORY
    m.is_symlink = (attrs & 1024) != 0;  # FILE_ATTRIBUTE_REPARSE_POINT
    m.is_file = !m.is_directory && !m.is_symlink;
    m.file_type = _io_file_type(m.is_file, m.is_directory, m.is_symlink);
    m.read_only = (attrs & 1) != 0;  # FILE_ATTRIBUTE_READONLY
    m.permissions = attrs as uint;
    m.size = (_io_win_u32(buf, size_high) << 32) | _io_win_u32(buf, size_low);
    var born = _io_win_time(buf, created);
    if (born != 0) {
        m.created = Optional<long>.Value(born);
    }
    m.accessed = _io_win_time(buf, accessed);
    m.modified = _io_win_time(buf, written);
    return m;
}

[Target(OS(Windows))]
_io_sys_fstat(h: FileHandle): IoResult<Metadata> {
    var info = _IoBuffer(52);
    if (GetFileInformationByHandle(h, info._bytes) == 0) {
        return IoResult<Metadata>.err(IoError.last());
    }
    return IoResult<Metadata>.ok(_io_win_metadata(info._bytes, 0, 4, 12, 20, 32, 36));
}

# Opens the path for no access (attributes only); without `follow`,
# FILE_FLAG_OPEN_REPARSE_POINT opens a symlink itself.
[Target(OS(Windows))]
_io_win_open_query(path: Path, follow: bool): IoResult<FileHandle> {
    ulong extra = 0;
    if (!follow) {
        extra = 2097152;  # FILE_FLAG_OPEN_REPARSE_POINT
    }
    return _io_win_create(path, 0, 3, extra);
}

[Target(OS(Windows))]
_io_sys_stat(path: Path, follow: bool): IoResult<Metadata> {
    var h = _io_win_open_query(path, follow);
    if (h.is_err()) {
        return IoResult<Metadata>.err(h.error());
    }
    var m = _io_sys_fstat(h.value());
    CloseHandle(h.value());
    return m;
}

# ── Directories ──────────────────────────────────────────────────────────────
# WIN32_FIND_DATAW (592 bytes): dwFileAttributes @0, FILETIMEs @4/@12/@20,
# nFileSizeHigh @28, nFileSizeLow @32, cFileName (NUL-terminated WCHAR[260])
# @44.

# Opens the listing of `iterator._path` and reads its first entry into
# `iterator._entry`: false when there is none.
[Target(OS(Windows))]
_io_sys_directory_first(iterator: DirectoryIterator): IoResult<bool> {
    var path = iterator._path;
    # An empty path would search `*`, the current directory; POSIX fails.
    if (path._value.size == 0) {
        return IoResult<bool>.err(IoError(_io_sys_code_not_found(), "empty path"));
    }
    var w = _io_win_wide(path.join(Path("*"))._value);
    iterator._data = _pep_malloc(592);
    var h = FindFirstFileW(w, iterator._data);
    _pep_free(w);
    if (!_io_sys_handle_valid(h)) {
        var e = IoError.last();
        # FILE_NOT_FOUND means nothing matched `*`: an empty directory with
        # no `.` or `..` entries, as a drive root is. A missing directory
        # says PATH_NOT_FOUND, but confirm it is a directory regardless.
        if (e.code == 2) {
            var m = _io_sys_stat(path, true);
            if (m.is_ok()) {
                if (m.value().is_directory) {
                    return IoResult<bool>.ok(false);
                }
            }
        }
        return IoResult<bool>.err(e);
    }
    iterator._handle = h;
    # FindFirstFileW already read the first entry into `_data`.
    iterator._pending = true;
    return _io_sys_directory_next(iterator);
}

# Reads the next entry of an open listing into `iterator._entry`, skipping
# `.` and `..`: false at the end.
[Target(OS(Windows))]
_io_sys_directory_next(iterator: DirectoryIterator): IoResult<bool> {
    var data = iterator._data;
    while (true) {
        if (iterator._pending) {
            iterator._pending = false;
        } else if (FindNextFileW(iterator._handle, data) == 0) {
            var code = GetLastError();
            if (code != 18) {  # NO_MORE_FILES
                return IoResult<bool>.err(IoError(code, _io_sys_error_message(code)));
            }
            return IoResult<bool>.ok(false);
        }
        var name_ptr = unsafe_cast<__ptr<u16>>(data + 44);
        var name = _io_win_narrow(name_ptr, _io_win_wide_len(name_ptr));
        if (name == "." || name == "..") {
            continue;
        }
        var m = _io_win_metadata(data, 0, 4, 12, 20, 28, 32);
        var entry = DirEntry();
        entry.name = name;
        entry.path = iterator._path.join(Path(name));
        entry.is_file = m.is_file;
        entry.is_directory = m.is_directory;
        entry.is_symlink = m.is_symlink;
        entry.file_type = m.file_type;
        iterator._entry = entry;
        return IoResult<bool>.ok(true);
    }
}

# Closes an open listing.
[Target(OS(Windows))]
_io_sys_directory_close(handle: __ptr<void>) {
    FindClose(handle);
}

[Target(OS(Windows))]
_io_sys_mkdir(path: Path, mode: Mode): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = CreateDirectoryW(w, __null);
    var code = GetLastError();
    _pep_free(w);
    return _io_win_check_code(ok, code);
}

[Target(OS(Windows))]
_io_sys_rmdir(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = RemoveDirectoryW(w);
    var code = GetLastError();
    _pep_free(w);
    return _io_win_check_code(ok, code);
}

[Target(OS(Windows))]
_io_sys_unlink(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = DeleteFileW(w);
    var code = GetLastError();
    _pep_free(w);
    return _io_win_check_code(ok, code);
}

# A directory symlink (junction) is removed with RemoveDirectoryW, anything
# else with DeleteFileW.
[Target(OS(Windows))]
_io_sys_remove_link(path: Path, is_dir: bool): IoResult<void> {
    if (is_dir) {
        return _io_sys_rmdir(path);
    }
    return _io_sys_unlink(path);
}

# MOVEFILE_REPLACE_EXISTING, as POSIX rename replaces.
[Target(OS(Windows))]
_io_sys_rename(from: Path, to: Path): IoResult<void> {
    var wf = _io_win_wide(from._value);
    var wt = _io_win_wide(to._value);
    var ok = MoveFileExW(wf, wt, 1);
    var code = GetLastError();
    _pep_free(wf);
    _pep_free(wt);
    return _io_win_check_code(ok, code);
}

[Target(OS(Windows))]
_io_sys_getcwd(): IoResult<Path> {
    var need = GetCurrentDirectoryW(0, __null);  # units, NUL included
    if (need == 0) {
        return IoResult<Path>.err(IoError.last());
    }
    var buffer = _IoBuffer((need as ulong) * 2);
    var buf = unsafe_cast<__ptr<u16>>(buffer._bytes);
    var n = GetCurrentDirectoryW(need, buf);
    if (n == 0) {
        return IoResult<Path>.err(IoError.last());
    }
    return IoResult<Path>.ok(Path(_io_win_narrow(buf, n as int)));
}

[Target(OS(Windows))]
_io_sys_chdir(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = SetCurrentDirectoryW(w);
    var code = GetLastError();
    _pep_free(w);
    return _io_win_check_code(ok, code);
}

# GetFinalPathNameByHandleW answers `\\?\C:\x` or `\\?\UNC\server\share`;
# drop the verbatim prefix (`\\?\UNC\` becomes `\\`).
[Target(OS(Windows))]
_io_sys_realpath(path: Path): IoResult<Path> {
    var h = _io_win_open_query(path, true);
    if (h.is_err()) {
        return IoResult<Path>.err(h.error());
    }
    var need = GetFinalPathNameByHandleW(h.value(), __null, 0, 0);
    if (need == 0) {
        var e = IoError.last();
        CloseHandle(h.value());
        return IoResult<Path>.err(e);
    }
    var buffer = _IoBuffer((need as ulong) * 2 + 2);
    var buf = unsafe_cast<__ptr<u16>>(buffer._bytes);
    var n = GetFinalPathNameByHandleW(h.value(), buf, need, 0);
    var code = GetLastError();
    CloseHandle(h.value());
    if (n == 0) {
        return IoResult<Path>.err(IoError(code, _io_sys_error_message(code)));
    }
    var s = _io_win_narrow(buf, n as int);
    # Drop the `\\?\` prefix, keeping a UNC path's `\\`.
    if (s.starts_with("\\\\?\\UNC\\")) {
        return IoResult<Path>.ok(Path("\\\\" + _io_slice(s, 8, s.size)));
    }
    if (s.starts_with("\\\\?\\")) {
        return IoResult<Path>.ok(Path(_io_slice(s, 4, s.size)));
    }
    return IoResult<Path>.ok(Path(s));
}

# GetTempPathW's answer ends in a separator; drop it unless it is the root.
[Target(OS(Windows))]
export _io_sys_temp_dir(): Path {
    var need = GetTempPathW(0, __null);
    if (need == 0) {
        return Path(".");
    }
    var buf = _pep_malloc((need as ulong) * 2 + 2) as __ptr<u16>;
    var n = GetTempPathW(need, buf) as int;
    var s = _io_win_narrow(buf, n);
    _pep_free(buf);
    return Path(_io_slice(s, 0, _io_path_trimmed_end(s)));
}

# ── Permissions, times and links ─────────────────────────────────────────────

# Only FILE_ATTRIBUTE_READONLY (1) of `mode` is applied, through
# FILE_BASIC_INFO (40 bytes: four LARGE_INTEGER times, 0 meaning unchanged,
# then FileAttributes u32 @32), where 0 attributes would also mean
# unchanged, so a file left with none gets FILE_ATTRIBUTE_NORMAL.
[Target(OS(Windows))]
_io_sys_fchmod(h: FileHandle, mode: Mode): IoResult<void> {
    var query = _IoBuffer(52);
    if (GetFileInformationByHandle(h, query._bytes) == 0) {
        return IoResult<void>.err(IoError.last());
    }
    var attributes = ((_io_win_u32(query._bytes, 0) | 1) ^ 1) | ((mode & 1) as ulong);
    if (attributes == 0) {
        attributes = 128;  # FILE_ATTRIBUTE_NORMAL
    }
    var info = _IoBuffer(40);
    var fields = unsafe_cast<__ptr<long>>(info._bytes);
    fields[0] = 0;
    fields[1] = 0;
    fields[2] = 0;
    fields[3] = 0;
    fields[4] = attributes as long;
    var ok = SetFileInformationByHandle(h, 0, info._bytes, 40);  # FileBasicInfo
    return _io_win_check(ok);
}

# Opens `path`, following links, to change its attributes or times
# (FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES).
[Target(OS(Windows))]
_io_win_open_attributes(path: Path): IoResult<FileHandle> {
    if (path._value.size == 0) {
        return IoResult<FileHandle>.err(IoError(_io_sys_code_not_found(), "empty path"));
    }
    return _io_win_create(path, 384, 3, 0);  # OPEN_EXISTING
}

[Target(OS(Windows))]
_io_sys_chmod(path: Path, mode: Mode): IoResult<void> {
    var h = _io_win_open_attributes(path);
    if (h.is_err()) {
        return IoResult<void>.err(h.error());
    }
    var r = _io_sys_fchmod(h.value(), mode);
    CloseHandle(h.value());
    return r;
}

[Target(OS(Windows))]
_io_sys_read_only_mode(current: Mode, read_only: bool): Mode {
    if (read_only) {
        return current | 1;
    }
    return (current | 1) ^ 1;
}

# Windows has no execute bit: whether a file runs depends on its extension.
[Target(OS(Windows))]
_io_sys_executable_mode(current: Mode, executable: bool): Mode {
    return current;
}

# A FILETIME (100 ns ticks since 1601) for ns since the Unix epoch, written
# at `at`; null for a time left alone.
[Target(OS(Windows))]
_io_win_filetime(at: __ptr<u8>, time: long?): __ptr<void> {
    if (time.is_empty()) {
        return __null;
    }
    var ns = time.value();
    var ticks = ns / 100;
    if (ticks * 100 > ns) {  # round toward the past, as POSIX truncates
        ticks = ticks - 1;
    }
    unsafe_cast<__ptr<long>>(at)[0] = ticks + 116444736000000000;
    return at;
}

[Target(OS(Windows))]
_io_sys_fset_times(h: FileHandle, accessed: long?, modified: long?): IoResult<void> {
    var buf = _IoBuffer(16);
    var a = _io_win_filetime(buf._bytes, accessed);
    var m = _io_win_filetime(buf._bytes + 8, modified);
    return _io_win_check(SetFileTime(h, __null, a, m));
}

[Target(OS(Windows))]
_io_sys_set_times(path: Path, accessed: long?, modified: long?): IoResult<void> {
    var h = _io_win_open_attributes(path);
    if (h.is_err()) {
        return IoResult<void>.err(h.error());
    }
    var r = _io_sys_fset_times(h.value(), accessed, modified);
    CloseHandle(h.value());
    return r;
}

# SYMBOLIC_LINK_FLAG_DIRECTORY (1) for a link to a directory, and
# SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE (2), which Developer Mode
# needs; Windows before 10 1703 rejects that flag, so try again without it.
[Target(OS(Windows))]
_io_sys_symlink(target: Path, link: Path, directory: bool): IoResult<void> {
    if (target._value.size == 0 || link._value.size == 0) {
        return IoResult<void>.err(IoError(_io_sys_code_not_found(), "empty path"));
    }
    uint flags = 2;
    if (directory) {
        flags = 3;
    }
    var wt = _io_win_wide(target._value);
    var wl = _io_win_wide(link._value);
    var ok = CreateSymbolicLinkW(wl, wt, flags);
    var code = GetLastError();
    if (ok == 0 && code == 87) {  # INVALID_PARAMETER
        ok = CreateSymbolicLinkW(wl, wt, flags ^ 2);
        code = GetLastError();
    }
    _pep_free(wt);
    _pep_free(wl);
    return _io_win_check_code(ok as int, code);
}

# FSCTL_GET_REPARSE_POINT fills a REPARSE_DATA_BUFFER: ReparseTag u32 @0,
# then SubstituteNameOffset and SubstituteNameLength u16 @8 and @10 (bytes
# into the path buffer), and the path buffer itself at @20 for a symlink
# (after its Flags u32 @16) or @16 for a junction. The substitute name of an
# absolute target starts `\??\`, dropped here (`\??\UNC\` becomes `\\`).
[Target(OS(Windows))]
_io_sys_readlink(path: Path): IoResult<Path> {
    if (path._value.size == 0) {
        return IoResult<Path>.err(IoError(_io_sys_code_not_found(), "empty path"));
    }
    var h = _io_win_open_query(path, false);
    if (h.is_err()) {
        return IoResult<Path>.err(h.error());
    }
    var size: uint = 16384;  # MAXIMUM_REPARSE_DATA_BUFFER_SIZE
    var buf = _IoBuffer(size as ulong);
    var returned = _IoBuffer(4);
    var ok = DeviceIoControl(
        h.value(), 589992, __null, 0, buf._bytes, size, unsafe_cast<__ptr<uint>>(returned._bytes), __null
    );
    var code = GetLastError();
    CloseHandle(h.value());
    if (ok == 0) {
        return IoResult<Path>.err(IoError(code, _io_sys_error_message(code)));
    }
    var tag = _io_win_u32(buf._bytes, 0);
    ulong names = 0;
    if (tag == 2684354572) {  # IO_REPARSE_TAG_SYMLINK
        names = 20;
    } else if (tag == 2684354563) {  # IO_REPARSE_TAG_MOUNT_POINT
        names = 16;
    } else {
        return IoResult<Path>.err(IoError(4390, _io_sys_error_message(4390)));  # NOT_A_REPARSE_POINT
    }
    var offset = _io_win_u16(buf._bytes, 8);
    var length = _io_win_u16(buf._bytes, 10);
    var name = unsafe_cast<__ptr<u16>>(buf._bytes + names + offset);
    var s = _io_win_narrow(name, (length / 2) as int);
    if (s.starts_with("\\??\\UNC\\")) {
        return IoResult<Path>.ok(Path("\\\\" + _io_slice(s, 8, s.size)));
    }
    if (s.starts_with("\\??\\")) {
        return IoResult<Path>.ok(Path(_io_slice(s, 4, s.size)));
    }
    return IoResult<Path>.ok(Path(s));
}

[Target(OS(Windows))]
_io_win_u16(buf: __ptr<void>, offset: ulong): ulong {
    return ((buf + offset) as __ptr<u16>)[0] as ulong;
}

# ── Thread-local keys ────────────────────────────────────────────────────────

# Thread local storage, not fiber local storage: every task on a thread
# shares the value.
[Target(OS(Windows))]
_io_sys_key_create(): ulong {
    var index = TlsAlloc();
    assert(index != 4294967295, "io: no thread-local keys left");  # TLS_OUT_OF_INDEXES
    return index as ulong;
}

[Target(OS(Windows))]
_io_sys_key_get(key: ulong): __ptr<void> {
    return TlsGetValue(key as uint);
}

[Target(OS(Windows))]
_io_sys_key_set(key: ulong, value: __ptr<void>) {
    TlsSetValue(key as uint, value);
}

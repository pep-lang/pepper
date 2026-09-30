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

import "types";
import "path";
import "file";
import "directory";

# ── C functions (kernel32) ───────────────────────────────────────────────────

[Target(OS(Windows))] extern void* CreateFileW(ushort* name, uint access, uint share, void* security, uint disposition, uint flags, void* template);
[Target(OS(Windows))] extern int ReadFile(void* h, void* buf, uint n, uint* done, void* overlapped);
[Target(OS(Windows))] extern int WriteFile(void* h, void* buf, uint n, uint* done, void* overlapped);
[Target(OS(Windows))] extern int CloseHandle(void* h);
[Target(OS(Windows))] extern int SetFilePointerEx(void* h, long distance, long* position, uint method);
[Target(OS(Windows))] extern int SetFileInformationByHandle(void* h, int info_class, void* info, uint size);
[Target(OS(Windows))] extern int FlushFileBuffers(void* h);
[Target(OS(Windows))] extern int GetFileInformationByHandle(void* h, void* info);
[Target(OS(Windows))] extern void* FindFirstFileW(ushort* pattern, void* data);
[Target(OS(Windows))] extern int FindNextFileW(void* h, void* data);
[Target(OS(Windows))] extern int FindClose(void* h);
[Target(OS(Windows))] extern int CreateDirectoryW(ushort* path, void* security);
[Target(OS(Windows))] extern int RemoveDirectoryW(ushort* path);
[Target(OS(Windows))] extern int DeleteFileW(ushort* path);
[Target(OS(Windows))] extern int MoveFileExW(ushort* from, ushort* to, uint flags);
[Target(OS(Windows))] extern uint GetCurrentDirectoryW(uint size, ushort* buf);
[Target(OS(Windows))] extern int SetCurrentDirectoryW(ushort* path);
[Target(OS(Windows))] extern uint GetFinalPathNameByHandleW(void* h, ushort* buf, uint size, uint flags);
[Target(OS(Windows))] extern uint GetTempPathW(uint size, ushort* buf);
[Target(OS(Windows))] extern void* GetStdHandle(uint which);
[Target(OS(Windows))] extern uint GetLastError();
[Target(OS(Windows))] extern uint FormatMessageW(uint flags, void* source, uint id, uint language, ushort* buf, uint size, void* args);
[Target(OS(Windows))] extern int MultiByteToWideChar(uint codepage, uint flags, char* src, int src_len, ushort* dst, int dst_len);
[Target(OS(Windows))] extern int WideCharToMultiByte(uint codepage, uint flags, ushort* src, int src_len, char* dst, int dst_len, void* default_char, int* used_default);

# ── UTF-8 <-> UTF-16 ─────────────────────────────────────────────────────────

# A NUL-terminated UTF-16 copy of `s`; the caller frees it with _pep_free.
# One UTF-8 byte never yields more than one UTF-16 unit, so Size + 1 units
# always suffice.
[Target(OS(Windows))] export _io_win_wide(s: String): __ptr<u16> {
    var units = s.size() + 1;
    var w = _pep_malloc(units * 2) as __ptr<u16>;
    if (s.size() > 0) {
        MultiByteToWideChar(65001, 0, s.c_str(), s.size() as int, w, units as int);   # CP_UTF8
    }
    return w;
}

# Number of UTF-16 units before the terminating NUL.
[Target(OS(Windows))] export _io_win_wide_len(w: __ptr<u16>): int {
    var n = 0;
    while (w[n] != 0) { n = n + 1; }
    return n;
}

# `n` UTF-16 units at `w` as a UTF-8 String.
[Target(OS(Windows))] export _io_win_narrow(w: __ptr<u16>, n: int): String {
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

[Target(OS(Windows))] export _io_sys_last_error(): ErrorCode {
    return GetLastError();
}

# FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, trailing
# whitespace (the ". \r\n" tail) trimmed.
[Target(OS(Windows))] export _io_sys_error_message(code: ErrorCode): String {
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
    if (s.size() == 0) {
        return "unknown error";
    }
    return s;
}

[Target(OS(Windows))] export _io_sys_is_not_found(code: ErrorCode): bool {
    return code == 2 || code == 3;       # FILE_NOT_FOUND, PATH_NOT_FOUND
}
[Target(OS(Windows))] export _io_sys_is_permission_denied(code: ErrorCode): bool {
    return code == 5;                    # ACCESS_DENIED
}
[Target(OS(Windows))] export _io_sys_is_already_exists(code: ErrorCode): bool {
    return code == 80 || code == 183;    # FILE_EXISTS, ALREADY_EXISTS
}
[Target(OS(Windows))] export _io_sys_is_not_a_directory(code: ErrorCode): bool {
    return code == 267;                  # DIRECTORY (invalid directory name)
}
[Target(OS(Windows))] export _io_sys_is_is_a_directory(code: ErrorCode): bool {
    return code == 336;                  # DIRECTORY_NOT_SUPPORTED
}
[Target(OS(Windows))] export _io_sys_is_directory_not_empty(code: ErrorCode): bool {
    return code == 145;                  # DIR_NOT_EMPTY
}
[Target(OS(Windows))] export _io_sys_is_invalid_input(code: ErrorCode): bool {
    return code == 87 || code == 123 || code == 131;   # INVALID_PARAMETER, INVALID_NAME, NEGATIVE_SEEK
}
[Target(OS(Windows))] export _io_sys_is_interrupted(code: ErrorCode): bool {
    return code == 995;                  # OPERATION_ABORTED
}

# Codes for errors Pepper raises itself.
[Target(OS(Windows))] export _io_sys_code_invalid_input(): ErrorCode { return 87; }     # INVALID_PARAMETER
[Target(OS(Windows))] export _io_sys_code_not_a_directory(): ErrorCode { return 267; }  # DIRECTORY
[Target(OS(Windows))] export _io_sys_code_not_found(): ErrorCode { return 2; }          # FILE_NOT_FOUND
[Target(OS(Windows))] export _io_sys_code_bad_handle(): ErrorCode { return 6; }         # INVALID_HANDLE
[Target(OS(Windows))] export _io_sys_code_write_zero(): ErrorCode { return 29; }        # WRITE_FAULT

# A BOOL result: nonzero -> Ok, 0 -> the GetLastError() error.
[Target(OS(Windows))] export _io_win_check(ok: int): IoResult<void> {
    if (ok != 0) {
        return _io_ok_void();
    }
    return IoResult<void>.err(IoError.last());
}

# ── Handles ──────────────────────────────────────────────────────────────────

[Target(OS(Windows))] export _io_sys_invalid_handle(): FileHandle {
    return __null;
}

# Neither null nor INVALID_HANDLE_VALUE (-1).
[Target(OS(Windows))] export _io_sys_handle_valid(h: FileHandle): bool {
    return h != __null && (h as long) != -1;
}

# STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE are (DWORD)-10,
# -11 and -12.
[Target(OS(Windows))] export _io_sys_std_handle(which: int): FileHandle {
    return GetStdHandle((4294967286 - which) as uint);
}

# CreateFileW sharing everything (FILE_SHARE_READ | WRITE | DELETE) with
# FILE_FLAG_BACKUP_SEMANTICS, so directories open too.
[Target(OS(Windows))] export _io_win_create(path: Path, access: ulong, disposition: uint, extra_flags: ulong): IoResult<FileHandle> {
    var w = _io_win_wide(path._value);
    var flags = 33554560 | extra_flags;   # BACKUP_SEMANTICS | ATTRIBUTE_NORMAL
    var h = CreateFileW(w, access as uint, 7, __null, disposition, flags as uint, __null);
    var code = GetLastError();
    _pep_free(w);
    if (!_io_sys_handle_valid(h)) {
        return IoResult<FileHandle>.err(IoError(code, _io_sys_error_message(code)));
    }
    return IoResult<FileHandle>.ok(h);
}

# ── File operations ──────────────────────────────────────────────────────────

[Target(OS(Windows))] export _io_sys_open(path: Path, options: OpenOptions): IoResult<FileHandle> {
    ulong access = 0;
    if (options._read) {
        access = access | 2147483648;    # GENERIC_READ
    }
    if (options._append) {
        # FILE_GENERIC_WRITE without FILE_WRITE_DATA: writes only append.
        access = access | 1179924;
    } else {
        if (options._write) {
            access = access | 1073741824;   # GENERIC_WRITE
        }
    }
    uint disposition = 3;                # OPEN_EXISTING
    if (options._truncate) {
        disposition = 5;                 # TRUNCATE_EXISTING
    }
    if (options._create) {
        disposition = 4;                 # OPEN_ALWAYS
        if (options._truncate) {
            disposition = 2;             # CREATE_ALWAYS
        }
    }
    if (options._create_new) {
        disposition = 1;                 # CREATE_NEW
    }
    return _io_win_create(path, access, disposition, 0);
}

[Target(OS(Windows))] export _io_sys_close(h: FileHandle): IoResult<void> {
    return _io_win_check(CloseHandle(h));
}

# One ReadFile/WriteFile call moves at most 1 GiB (the count is a DWORD).
[Target(OS(Windows))] export _io_win_max_rw(n: ulong): uint {
    if (n > 1073741824) {
        return 1073741824;
    }
    return n as uint;
}

[Target(OS(Windows))] export _io_sys_read(h: FileHandle, dst: __ptr<u8>, n: ulong): IoResult<ulong> {
    var done = _pep_malloc(4) as __ptr<uint>;
    var ok = ReadFile(h, dst, _io_win_max_rw(n), done, __null);
    var count = done[0] as ulong;
    _pep_free(done);
    if (ok == 0) {
        var code = GetLastError();
        if (code == 109) {               # BROKEN_PIPE: the writer closed; EOF
            return IoResult<ulong>.ok(0);
        }
        if (code == 1) {
            # INVALID_FUNCTION is what ReadFile says about a directory handle
            # (opened with BACKUP_SEMANTICS); report it as POSIX's EISDIR does.
            var m = _io_sys_fstat(h);
            if (m.is_ok()) {
                if (m._value.is_directory) {
                    code = 336;          # DIRECTORY_NOT_SUPPORTED: is_is_a_directory
                }
            }
        }
        return IoResult<ulong>.err(IoError(code, _io_sys_error_message(code)));
    }
    return IoResult<ulong>.ok(count);
}

[Target(OS(Windows))] export _io_sys_write(h: FileHandle, src: __ptr<u8>, n: ulong): IoResult<ulong> {
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
[Target(OS(Windows))] export _io_sys_seek(h: FileHandle, offset: Offset, whence: int): IoResult<Offset> {
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
[Target(OS(Windows))] export _io_sys_truncate(h: FileHandle, size: ulong): IoResult<void> {
    var info = _pep_malloc(8) as __ptr<long>;
    info[0] = size as long;
    var ok = SetFileInformationByHandle(h, 6, info, 8);
    var code = GetLastError();
    _pep_free(info);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

[Target(OS(Windows))] export _io_sys_sync(h: FileHandle): IoResult<void> {
    return _io_win_check(FlushFileBuffers(h));
}

# ── Metadata ─────────────────────────────────────────────────────────────────
# BY_HANDLE_FILE_INFORMATION (52 bytes): dwFileAttributes u32 @0, FILETIMEs
# {u32 low; u32 high} for creation @4, last access @12, last write @20,
# nFileSizeHigh @32, nFileSizeLow @36.

[Target(OS(Windows))] export _io_win_u32(buf: __ptr<void>, offset: ulong): ulong {
    return ((buf + offset) as __ptr<uint>)[0] as ulong;
}

# A FILETIME (100 ns ticks since 1601) as ns since the Unix epoch; 0 stays 0.
[Target(OS(Windows))] export _io_win_time(buf: __ptr<void>, offset: ulong): long {
    var ticks = ((_io_win_u32(buf, offset + 4) << 32) | _io_win_u32(buf, offset)) as long;
    if (ticks == 0) {
        return 0;
    }
    return (ticks - 116444736000000000) * 100;
}

[Target(OS(Windows))] export _io_win_metadata(buf: __ptr<void>, attrs_offset: ulong, created: ulong, accessed: ulong, written: ulong, size_high: ulong, size_low: ulong): Metadata {
    var m = Metadata();
    var attrs = _io_win_u32(buf, attrs_offset);
    m.is_directory = (attrs & 16) != 0;          # FILE_ATTRIBUTE_DIRECTORY
    m.is_symlink = (attrs & 1024) != 0;    # FILE_ATTRIBUTE_REPARSE_POINT
    m.is_file = !m.is_directory && !m.is_symlink;
    m.read_only = (attrs & 1) != 0;        # FILE_ATTRIBUTE_READONLY
    m.permissions = attrs as uint;
    m.size = (_io_win_u32(buf, size_high) << 32) | _io_win_u32(buf, size_low);
    m.created = _io_win_time(buf, created);
    m.accessed = _io_win_time(buf, accessed);
    m.modified = _io_win_time(buf, written);
    return m;
}

[Target(OS(Windows))] export _io_sys_fstat(h: FileHandle): IoResult<Metadata> {
    var info = _pep_malloc(52);
    var ok = GetFileInformationByHandle(h, info);
    if (ok == 0) {
        var e = IoError.last();
        _pep_free(info);
        return IoResult<Metadata>.err(e);
    }
    var m = _io_win_metadata(info, 0, 4, 12, 20, 32, 36);
    _pep_free(info);
    return IoResult<Metadata>.ok(m);
}

# Opens the path for no access (attributes only); without `follow`,
# FILE_FLAG_OPEN_REPARSE_POINT opens a symlink itself.
[Target(OS(Windows))] export _io_win_open_query(path: Path, follow: bool): IoResult<FileHandle> {
    ulong extra = 0;
    if (!follow) {
        extra = 2097152;                 # FILE_FLAG_OPEN_REPARSE_POINT
    }
    return _io_win_create(path, 0, 3, extra);
}

[Target(OS(Windows))] export _io_sys_stat(path: Path, follow: bool): IoResult<Metadata> {
    var h = _io_win_open_query(path, follow);
    if (h.is_err()) {
        return IoResult<Metadata>.err(h._error);
    }
    var m = _io_sys_fstat(h._value);
    CloseHandle(h._value);
    return m;
}

# ── Directories ──────────────────────────────────────────────────────────────
# WIN32_FIND_DATAW (592 bytes): dwFileAttributes @0, FILETIMEs @4/@12/@20,
# nFileSizeHigh @28, nFileSizeLow @32, cFileName (NUL-terminated WCHAR[260])
# @44.

[Target(OS(Windows))] export _io_sys_list(path: Path): IoResult<DirEntry[]> {
    # An empty path would search `*`, the current directory; POSIX fails.
    if (path._value.size() == 0) {
        return IoResult<DirEntry[]>.err(IoError(_io_sys_code_not_found(), "empty path"));
    }
    var w = _io_win_wide(path.join(Path("*"))._value);
    var data = _pep_malloc(592);
    var h = FindFirstFileW(w, data);
    _pep_free(w);
    var out = Array<DirEntry>();
    if (!_io_sys_handle_valid(h)) {
        var e = IoError.last();
        _pep_free(data);
        # FILE_NOT_FOUND means nothing matched `*`: an empty directory with
        # no `.` or `..` entries, as a drive root is. A missing directory
        # says PATH_NOT_FOUND, but confirm it is a directory regardless.
        if (e.code == 2) {
            var m = _io_sys_stat(path, true);
            if (m.is_ok()) {
                if (m._value.is_directory) {
                    return IoResult<DirEntry[]>.ok(out);
                }
            }
        }
        return IoResult<DirEntry[]>.err(e);
    }
    while (true) {
        var name_ptr = (data + 44) as __ptr<u16>;
        var name = _io_win_narrow(name_ptr, _io_win_wide_len(name_ptr));
        if (!_io_is_dot(name) && !_io_is_dotdot(name)) {
            var m = _io_win_metadata(data, 0, 4, 12, 20, 28, 32);
            var entry = DirEntry();
            entry.name = name;
            entry.path = path.join(Path(name));
            entry.is_file = m.is_file;
            entry.is_directory = m.is_directory;
            entry.is_symlink = m.is_symlink;
            out.append(entry);
        }
        if (FindNextFileW(h, data) == 0) {
            var code = GetLastError();
            if (code != 18) {            # NO_MORE_FILES
                FindClose(h);
                _pep_free(data);
                return IoResult<DirEntry[]>.err(IoError(code, _io_sys_error_message(code)));
            }
            break;
        }
    }
    FindClose(h);
    _pep_free(data);
    return IoResult<DirEntry[]>.ok(out);
}

[Target(OS(Windows))] export _io_sys_mkdir(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = CreateDirectoryW(w, __null);
    var code = GetLastError();
    _pep_free(w);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

[Target(OS(Windows))] export _io_sys_rmdir(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = RemoveDirectoryW(w);
    var code = GetLastError();
    _pep_free(w);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

[Target(OS(Windows))] export _io_sys_unlink(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = DeleteFileW(w);
    var code = GetLastError();
    _pep_free(w);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

# A directory symlink (junction) is removed with RemoveDirectoryW, anything
# else with DeleteFileW.
[Target(OS(Windows))] export _io_sys_remove_link(path: Path, is_dir: bool): IoResult<void> {
    if (is_dir) {
        return _io_sys_rmdir(path);
    }
    return _io_sys_unlink(path);
}

# MOVEFILE_REPLACE_EXISTING, as POSIX rename replaces.
[Target(OS(Windows))] export _io_sys_rename(from: Path, to: Path): IoResult<void> {
    var wf = _io_win_wide(from._value);
    var wt = _io_win_wide(to._value);
    var ok = MoveFileExW(wf, wt, 1);
    var code = GetLastError();
    _pep_free(wf);
    _pep_free(wt);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

[Target(OS(Windows))] export _io_sys_getcwd(): IoResult<Path> {
    var need = GetCurrentDirectoryW(0, __null);   # units, NUL included
    if (need == 0) {
        return IoResult<Path>.err(IoError.last());
    }
    var buf = _pep_malloc((need as ulong) * 2) as __ptr<u16>;
    var n = GetCurrentDirectoryW(need, buf);
    if (n == 0) {
        var e = IoError.last();
        _pep_free(buf);
        return IoResult<Path>.err(e);
    }
    var p = Path(_io_win_narrow(buf, n as int));
    _pep_free(buf);
    return IoResult<Path>.ok(p);
}

[Target(OS(Windows))] export _io_sys_chdir(path: Path): IoResult<void> {
    var w = _io_win_wide(path._value);
    var ok = SetCurrentDirectoryW(w);
    var code = GetLastError();
    _pep_free(w);
    if (ok == 0) {
        return IoResult<void>.err(IoError(code, _io_sys_error_message(code)));
    }
    return _io_ok_void();
}

# GetFinalPathNameByHandleW answers `\\?\C:\x` or `\\?\UNC\server\share`;
# drop the verbatim prefix (`\\?\UNC\` becomes `\\`).
[Target(OS(Windows))] export _io_sys_realpath(path: Path): IoResult<Path> {
    var h = _io_win_open_query(path, true);
    if (h.is_err()) {
        return IoResult<Path>.err(h._error);
    }
    var need = GetFinalPathNameByHandleW(h._value, __null, 0, 0);
    if (need == 0) {
        var e = IoError.last();
        CloseHandle(h._value);
        return IoResult<Path>.err(e);
    }
    var buf = _pep_malloc((need as ulong) * 2 + 2) as __ptr<u16>;
    var n = GetFinalPathNameByHandleW(h._value, buf, need, 0);
    var code = GetLastError();
    CloseHandle(h._value);
    if (n == 0) {
        _pep_free(buf);
        return IoResult<Path>.err(IoError(code, _io_sys_error_message(code)));
    }
    var s = _io_win_narrow(buf, n as int);
    _pep_free(buf);
    var p = s.c_str() as __ptr<u8>;
    var size = s.size();
    # "\\?\" is 92 92 63 92; "UNC\" is 85 78 67 92.
    if (_io_byte(p, size, 0) == '\\' && _io_byte(p, size, 1) == '\\' && _io_byte(p, size, 2) == '?' && _io_byte(p, size, 3) == '\\') {
        if (_io_byte(p, size, 4) == 'U' && _io_byte(p, size, 5) == 'N' && _io_byte(p, size, 6) == 'C' && _io_byte(p, size, 7) == '\\') {
            var unc = _io_string_from_byte(92);
            unc.append(_io_string_from_byte(92));
            unc.append(_io_slice(s, 8, s.size()));
            return IoResult<Path>.ok(Path(unc));
        }
        return IoResult<Path>.ok(Path(_io_slice(s, 4, s.size())));
    }
    return IoResult<Path>.ok(Path(s));
}

# GetTempPathW's answer ends in a separator; drop it unless it is the root.
[Target(OS(Windows))] export _io_sys_temp_dir(): Path {
    var need = GetTempPathW(0, __null);
    if (need == 0) {
        return Path(".");
    }
    var buf = _pep_malloc((need as ulong) * 2 + 2) as __ptr<u16>;
    var n = GetTempPathW(need, buf) as int;
    var s = _io_win_narrow(buf, n);
    _pep_free(buf);
    var p = s.c_str() as __ptr<u8>;
    var end = s.size();
    var root = _io_path_root_end(s);
    while (end > root && _io_path_is_sep(_io_byte(p, s.size(), end - 1))) { end = end - 1; }
    return Path(_io_slice(s, 0, end));
}

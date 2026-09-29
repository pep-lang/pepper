# Platform aliases and the io error type.
#
# The raw types differ per platform; everything above the `_io_sys_*` layer
# is written against these names only.

import "sys_posix";
import "sys_windows";

# POSIX
[Target(!OS(Windows))] export type FileHandle = int;     # file descriptor
[Target(!OS(Windows))] export type ErrorCode = int;      # errno
[Target(!OS(Windows))] export type Mode = uint;          # mode_t bits

# Windows
[Target(OS(Windows))] export type FileHandle = __ptr<void>;   # HANDLE
[Target(OS(Windows))] export type ErrorCode = uint;           # DWORD from GetLastError()
[Target(OS(Windows))] export type Mode = uint;                # FILE_ATTRIBUTE_* bits

export type Offset = long;   # off_t / LARGE_INTEGER (64-bit on all targets)

# An I/O failure: the raw platform code plus a message. There are no enums,
# so the kind is a set of predicates over the code. Pepper-side failures
# (bad UTF-8, a short write) use the platform's own code for the kind they
# are (EINVAL / ERROR_INVALID_PARAMETER, ...), so the predicates hold for
# them too.
export struct IoError {
    ErrorCode Code;
    String Message;

    new(ErrorCode code = 0, String message = "") {
        this.Code = code;
        this.Message = message;
    }

    # Capture errno / GetLastError() now.
    static IoError last() {
        var code = _io_sys_last_error();
        return IoError(code, _io_sys_error_message(code));
    }

    bool is_not_found() { return _io_sys_is_not_found(Code); }
    bool is_permission_denied() { return _io_sys_is_permission_denied(Code); }
    bool is_already_exists() { return _io_sys_is_already_exists(Code); }
    bool is_not_a_directory() { return _io_sys_is_not_a_directory(Code); }
    bool is_is_a_directory() { return _io_sys_is_is_a_directory(Code); }
    bool is_directory_not_empty() { return _io_sys_is_directory_not_empty(Code); }
    bool is_invalid_input() { return _io_sys_is_invalid_input(Code); }
    bool is_interrupted() { return _io_sys_is_interrupted(Code); }
}

export type IoResult<T> = Result<T, IoError>;

# ── Module-private helpers shared by the io files ───────────────────────────

# A String holding a copy of `n` bytes at `p`. The String constructor derives
# the character count only when it measures a C string itself, so compute it
# here; `n == 0` must not reach the constructor, which would read `p` as a
# NUL-terminated C string.
export _io_string_from(p: __ptr<char>, n: ulong): String {
    if (p == __null || n == 0) {
        return String();
    }
    return String(p, n, _pep_utf8_length(p, n));
}

# A one-character String holding the ASCII byte `b` (string literals have no
# escape sequences, so this is how "\" or a newline is spelled).
export _io_string_from_byte(b: int): String {
    var buf: __ptr<char> = _pep_malloc(1);
    buf[0] = b;
    var s = String(buf, 1, 1);
    _pep_free(buf);
    return s;
}

# A String from a NUL-terminated C string.
export _io_string_from_c(p: __ptr<char>): String {
    if (p == __null) {
        return String();
    }
    return _io_string_from(p, _pep_c_strlen(p));
}

# Byte `i` of the `n` bytes at `p`, or 0 past the end. `&&` and `||` evaluate
# both operands, so a guard such as `i < n && p[i] == 47` still reads
# `p[i]`; reading through this keeps that in bounds (an empty String has no
# buffer at all).
export _io_byte(p: __ptr<u8>, n: ulong, i: ulong): int {
    if (i >= n) {
        return 0;
    }
    return p[i];
}

# True when the bytes are valid UTF-8 (empty is valid).
# Strict (RFC 3629): no overlong forms, surrogates, or code points past
# U+10FFFF.
export _io_utf8_valid(p: __ptr<char>, n: ulong): bool {
    var b = p as __ptr<u8>;
    ulong i = 0;
    while (i < n) {
        var c = _io_byte(b, n, i);
        if (c < 128) {
            i = i + 1;
            continue;
        }
        ulong extra = 0;
        var lo = 128;    # allowed range of the first continuation byte
        var hi = 191;
        if (c >= 194 && c <= 223) {
            extra = 1;
        } else {
            if (c >= 224 && c <= 239) {
                extra = 2;
                if (c == 224) { lo = 160; }   # no overlong 3-byte forms
                if (c == 237) { hi = 159; }   # no surrogates
            } else {
                if (c >= 240 && c <= 244) {
                    extra = 3;
                    if (c == 240) { lo = 144; }   # no overlong 4-byte forms
                    if (c == 244) { hi = 143; }   # nothing past U+10FFFF
                } else {
                    return false;   # continuation byte, 0xC0/0xC1, >= 0xF5
                }
            }
        }
        if (i + extra >= n) {
            return false;   # truncated sequence
        }
        var first = _io_byte(b, n, i + 1);
        if (first < lo || first > hi) {
            return false;
        }
        ulong k = 2;
        while (k <= extra) {
            var cont = _io_byte(b, n, i + k);
            if (cont < 128 || cont > 191) {
                return false;
            }
            k = k + 1;
        }
        i = i + extra + 1;
    }
    return true;
}

export _io_ok_none(): IoResult<None> {
    return IoResult<None>.ok(None());
}

export _io_err_none(e: IoError): IoResult<None> {
    return IoResult<None>.err(e);
}

export _io_last_none(): IoResult<None> {
    return IoResult<None>.err(IoError.last());
}

# ── C ABI externs (identical signatures on MSVC CRT and libc) ───────────────
extern void* malloc(ulong size);
extern void free(void* p);
extern void* realloc(void* p, ulong size);
extern void memcpy(void* dest, void* src, ulong n);
extern void memset(void* p, int c, ulong n);
extern int memcmp(void* a, void* b, ulong n);
extern char* getenv(char* name);
extern int puts(char* s);
extern void abort();
extern int fflush(void* stream);

## Panics with `message` when `condition` is false; otherwise does nothing.
##
## The check always runs; there is no release mode that removes it. A
## string literal message costs nothing when the assertion holds: the
## compiler passes the literal's constant bytes to the runtime without
## building a `String`. Any other message is evaluated before the call.
##
## @param condition the condition that must hold
## @param message the text to print on failure; a null `String` prints a
##   generic message
## @panics if `condition` is false: prints `message` and aborts (see `panic`)
## @example
##     assert(count > 0, "count must be positive");
export assert(condition: bool, message: String): void {
    if (!condition) {
        panic(message);
    }
}

# The allocation-free form of `assert` that compiler-generated checks (index
# bounds, null function and trait values) and string-literal messages lower
# to: `message` is a NUL-terminated C string, or `__null`.
export _pep_assert(condition: bool, message: __ptr<char>): void {
    if (!condition) {
        _pep_panic(message);
    }
}

# ── Live-allocation counter (leak tests) and trace gate ─────────────────────
# The live-allocation count, updated atomically because threads allocate
# concurrently. It lives in a raw malloc'd slot: an Atomic<long> would
# allocate through _pep_malloc itself. The prelude's globals are initialized
# before any other file's, and this is the first of them, so the slot exists
# before anything allocates. Every JIT engine carries its own copy of this
# global, so tests that count allocations can run in parallel.
_pep_new_live_allocs_slot(): __ptr<long> {
    var slot = malloc(8);
    memset(slot, 0, 8);
    return slot;
}
const _pep_live_allocs_slot: __ptr<long> = _pep_new_live_allocs_slot();

# `getenv` needs a NUL-terminated C string; a Pepper `String` buffer is not
# guaranteed to be, so build the name in a helper (its c_str() is safe).
_pep_trace_enabled(): bool {
    var name = "PEP_TRACE";
    return getenv(name.c_str()) != __null;
}
const _pep_trace_on = _pep_trace_enabled();

export _pep_malloc(size: ulong): __ptr<void> {
    var p = malloc(size);
    # Zero the payload: refcount machinery reads old slot values from fresh
    # buffers (index_refcount_ops), so uninitialized bytes are wild pointers.
    memset(p, 0, size);
    __atomic_fetch_add<long>(_pep_live_allocs_slot, 1);
    return p;
}

export _pep_free(p: __ptr<void>) {
    if (p != __null) {
        free(p);
        __atomic_fetch_sub<long>(_pep_live_allocs_slot, 1);
    }
}

export _pep_realloc(p: __ptr<void>, prev_size: ulong, new_size: ulong): __ptr<void> {
    # C realloc preserves contents up to min(prev,new); net-zero on the
    # counter. The extension region is uninitialized — zero it so fresh
    var np = realloc(p, new_size);
    if (np != __null) {
        # realloc(null, n) is a fresh allocation; the counter must see it.
        if (p == __null && new_size > 0) {
            __atomic_fetch_add<long>(_pep_live_allocs_slot, 1);
        }
        if (new_size > prev_size) {
            memset(np + prev_size, 0, new_size - prev_size);
        }
    }
    return np;
}
export _pep_live_allocs(): long {
    return __atomic_load<long>(_pep_live_allocs_slot);
}

## Prints `message` and aborts the program. It never returns.
##
## Writes `message` and a newline to standard output, or "Assertion failed
## with no additional information" when `message` is null. Then it flushes
## every C output stream, so the message is not lost when stdout is a pipe,
## and calls C `abort()`. No destructors or releases run, and the process
## ends abnormally (SIGABRT on POSIX).
##
## @param message the text to print
## @panics always
## @example
##     panic("unreachable");
export panic(message: String) {
    if (message === __null) {
        _pep_panic(__null);
    }
    _pep_panic(message.c_str());
}

# `panic` on a NUL-terminated C string (`__null` prints a generic message).
# String-literal messages and compiler-generated checks lower to this, so a
# panic never has to allocate.
export _pep_panic(message: __ptr<char>) {
    if (message == __null) {
        puts("Assertion failed with no additional information");
    } else {
        puts(message);
    }
    # stdout is fully buffered when it is a pipe: flush it, or abort() drops
    # the message just printed.
    fflush(__null);
    abort();
}

# ── Formatting helpers (fixed-width, so no string-length measurement needed) ─
hex(v: ulong): __ptr<char> {
    var buf = _pep_malloc(17);
    var i = 0;
    while (i < 16) {
        var d = (v >> ((15 - i) * 4)) & 0xF;
        buf[i] = (d < 10 ? (48 + d) : (55 + d));
        i = i + 1;
    }
    buf[16] = 0;
    return buf;
}

dec(v: long): __ptr<char> {
    var buf = _pep_malloc(24);
    var n = 0;
    var neg = 0;
    if (v < 0) { neg = 1; v = -v; }
    if (v == 0) { buf[n] = 48; n = n + 1; }
    while (v > 0) {
        buf[n] = (48 + (v % 10));
        n = n + 1;
        v = v / 10;
    }
    if (neg == 1) { buf[n] = 45; n = n + 1; }
    # Digits were produced least-significant first: reverse in place by
    # swapping pairs (copying buf[n-1-i] over buf[i] for every i mirrors the
    # second half onto the first instead).
    var i = 0;
    while (i < n / 2) {
        var t = buf[i];
        buf[i] = buf[n - 1 - i];
        buf[n - 1 - i] = t;
        i = i + 1;
    }
    buf[n] = 0;
    return buf;
}

# `v` with six fraction digits, rounded to nearest (`0.5` → "0.500000").
floatstr(v: double): __ptr<char> {
    var buf = _pep_malloc(64);
    var n = 0;
    if (v != v) {
        buf[0] = 110; buf[1] = 97; buf[2] = 110; buf[3] = 0;   # "nan"
        return buf;
    }
    if (v < 0.0) {
        buf[n] = 45;   # '-'
        n = n + 1;
        v = -v;
    }
    if (v > 9.0e18) {
        buf[n] = 105; buf[n + 1] = 110; buf[n + 2] = 102; buf[n + 3] = 0;   # "inf" (or too large for long)
        return buf;
    }
    var ip = v as long;
    var digits = ((v - (ip as double)) * 1000000.0 + 0.5) as long;
    # Rounding can carry into the integer part (0.9999996 → 1.000000).
    if (digits >= 1000000) {
        ip = ip + 1;
        digits = digits - 1000000;
    }
    var s = dec(ip);
    var i = 0;
    while (s[i] != 0) { buf[n] = s[i]; n = n + 1; i = i + 1; }
    _pep_free(s);
    buf[n] = 46;   # '.'
    n = n + 1;
    # Least-significant digit first, filling the six places from the right.
    var k = 5;
    while (k >= 0) {
        buf[n + k] = (48 + (digits % 10));
        digits = digits / 10;
        k = k - 1;
    }
    buf[n + 6] = 0;
    return buf;
}

# ── Trace (gated by PEP_TRACE) ───────────────────────────────────────────────
# Each line is "name: value" in a zeroed 512-byte buffer (so it stays
# NUL-terminated); the name is capped to leave room for the value.

# Write "name: " at the start of `buf`; returns the length written.
_pep_trace_prefix(buf: __ptr<char>, name: __ptr<char>): ulong {
    var n = 0;
    if (name != __null) {
        var nl = _pep_c_strlen(name);
        if (nl > 400) { nl = 400; }
        memcpy(buf, name, nl);
        n = nl;
    }
    buf[n] = 58;   # ':'
    buf[n + 1] = 32;   # ' '
    return n + 2;
}

# Copy the NUL-terminated `text` to `buf` at `n`, then free `text`; returns
# the new length.
_pep_trace_append(buf: __ptr<char>, n: ulong, text: __ptr<char>): ulong {
    var i = 0;
    while (text[i] != 0) { buf[n + i] = text[i]; i = i + 1; }
    _pep_free(text);
    return n + i;
}

_pep_trace_emit(buf: __ptr<char>) {
    puts(buf);
    _pep_free(buf);
}

# Debugging aid for compiler work: prints `name: ` and the address `ptr` as
# 16 hex digits when `PEP_TRACE` is set (read once at program start). The
# synthesized constructor, `__acquire` and `__release` call it; it is not
# part of the language's API.
export _pep_trace_ptr(ptr: __ptr<void>, name: __ptr<char>) {
    if (_pep_trace_on) {
        var buf = _pep_malloc(512);
        var n = _pep_trace_prefix(buf, name);
        var address = hex(ptr as ulong);
        _pep_trace_append(buf, n, address);
        _pep_trace_emit(buf);
    }
}

# Debugging aid for compiler work: prints `name: ` and `value` in decimal
# when `PEP_TRACE` is set. The synthesized `__acquire` and `__release` call
# it with the new reference count.
export _pep_trace_int(value: long, name: __ptr<char>) {
    if (_pep_trace_on) {
        var buf = _pep_malloc(512);
        var n = _pep_trace_prefix(buf, name);
        var text = dec(value);
        _pep_trace_append(buf, n, text);
        _pep_trace_emit(buf);
    }
}

# ── Swap two `stride`-byte slots of a buffer (a struct reference is one
# pointer, a trait value an object and a vtable pointer) ─────────────────────
export _pep_swap_refs(p: __ptr<void>, stride: ulong, i: ulong, j: ulong) {
    if (i != j) {
        var a: __ptr<void> = p + (i * stride);
        var b: __ptr<void> = p + (j * stride);
        var len = stride;
        var tmp = _pep_malloc(len);
        memcpy(tmp, a, len);
        memcpy(a, b, len);
        memcpy(b, tmp, len);
        _pep_free(tmp);
    }
}
# ── Move one `stride`-byte slot into another (raw reference transfer, no
# refcount change) and zero the source so it releases nothing later: a
# shifted slot must not keep a stale copy of the reference. ───────────────────
export _pep_move_ref(p: __ptr<void>, stride: ulong, i: ulong, j: ulong) {
    if (i != j) {
        var a: __ptr<void> = p + (i * stride);
        var b: __ptr<void> = p + (j * stride);
        var len = stride;
        memcpy(b, a, len);
        memset(a, 0, len);
    }
}

# ── FNV-1a 64-bit (same constants as the compiler's __address lowering) ─────
export _pep_hash_bytes(data: __ptr<void>, length: ulong): u64 {
    if (data == __null || length == 0) { return -3750763034362895579; }
    var h = -3750763034362895579;
    var i = 0;
    while (i < length) {
        h = (h ^ data[i]) * 1099511628211;
        i = i + 1;
    }
    return h;
}

# ── UTF-8 helpers (length-based; no NUL assumptions on language data) ───────
# C strings from getenv are NUL-terminated by the C standard; a byte walk is
# the only way to measure them (never used for language string data).
export _pep_c_strlen(s: __ptr<char>): ulong {
    var i = 0;
    while (s[i] != 0) { i = i + 1; }
    return i;
}

export _pep_utf8_length(s: __ptr<char>, size: ulong): ulong {
    if (s == __null || size == 0) { return 0; }
    var i = 0;
    var count = 0;
    while (i < size) {
        # Byte reads are signed; mask to the unsigned value.
        var b = s[i] & 0xFF;
        var n = 1;
        if (b >= 240 && b < 248) {
            if (i + 4 > size || (s[i+1] & 0xC0) != 0x80 || (s[i+2] & 0xC0) != 0x80 || (s[i+3] & 0xC0) != 0x80) { return 0; }
            n = 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (s[i+1] & 0xC0) != 0x80 || (s[i+2] & 0xC0) != 0x80) { return 0; }
            n = 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (s[i+1] & 0xC0) != 0x80) { return 0; }
            n = 2;
        }
        if (b >= 128 && b < 192) {
            return 0;
        }
        count = count + 1;
        i = i + n;
    }
    return count;
}

export _pep_utf8_size(s: __ptr<char>, size: ulong, chars: ulong): ulong {
    if (s == __null) { return 0; }
    if (chars == 0) { return size; }
    if (!_pep_utf8_valid(s, size)) { return 0; }
    return _pep_utf8_char_offset(s, size, chars);
}

export _pep_utf8_compare(a: __ptr<char>, a_size: ulong, b: __ptr<char>, b_size: ulong, size: ulong): bool {
    if (size == 0) {
        return a_size == b_size && memcmp(a, b, a_size) == 0;
    }
    return a_size >= size && b_size >= size && memcmp(a, b, size) == 0;
}
_pep_utf8_valid(data: __ptr<void>, size: ulong): bool {
    if (data == __null || size == 0) { return true; }
    var i = 0;
    while (i < size) {
        # Byte reads are signed; mask to the unsigned value.
        var b = data[i] & 0xFF;
        if (b >= 240 && b < 248) {
            if (i + 4 > size || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80 || (data[i+3] & 0xC0) != 0x80) { return false; }
            i = i + 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80) { return false; }
            i = i + 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (data[i+1] & 0xC0) != 0x80) { return false; }
            i = i + 2;
        }
        if (b >= 128 && b < 192) {
            return false;
        }
        if (b < 128) {
            i = i + 1;
        }
    }
    return true;
}
export _pep_utf8_find(haystack: __ptr<void>, haystack_size: ulong, needle: __ptr<void>, needle_size: ulong): long {
    if (haystack == __null || haystack_size == 0) { return -1; }
    if (needle_size == 0) { return 0; }
    if (needle == __null) { return -1; }
    # Both spans must be valid UTF-8 (the Rust original returns -1 otherwise).
    if (!_pep_utf8_valid(haystack, haystack_size)) { return -1; }
    if (!_pep_utf8_valid(needle, needle_size)) { return -1; }
    var i = 0;
    while (i + needle_size <= haystack_size) {
        var j = 0;
        while (j < needle_size) {
            if (haystack[i + j] != needle[j]) { break; }
            j = j + 1;
        }
        if (j == needle_size) { return i; }
        i = i + 1;
    }
    return -1;
}

export _pep_utf8_char_offset(data: __ptr<void>, size: ulong, chars: ulong): ulong {
    if (data == __null || size == 0) { return 0; }
    var i = 0;
    var count = 0;
    while (i < size && count < chars) {
        # Byte reads are signed; mask to the unsigned value.
        var b = data[i] & 0xFF;
        var n = 1;
        if (b >= 240 && b < 248) {
            if (i + 4 > size || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80 || (data[i+3] & 0xC0) != 0x80) { return size; }
            n = 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80) { return size; }
            n = 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (data[i+1] & 0xC0) != 0x80) { return size; }
            n = 2;
        }
        if (b >= 128 && b < 192) {
            return size;
        }
        count = count + 1;
        i = i + n;
    }
    return i;
}

# ── print backing (the `print` builtin lowers to these by name) ─────────────
# Exported so they keep their names: a private name is mangled per file.
export _pep_print(s: __ptr<char>) {
    if (s != __null) { puts(s); }
}

export _pep_print_int(v: long) {
    var s = dec(v);
    puts(s);
    _pep_free(s);
}

export _pep_print_float(v: double) {
    var s = floatstr(v);
    puts(s);
    _pep_free(s);
}

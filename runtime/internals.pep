# ── C ABI externs (identical signatures on MSVC CRT and libc) ───────────────
extern void* malloc(ulong size);
extern void free(void* p);
extern void* realloc(void* p, ulong size);
export extern void memcpy(void* dest, void* src, ulong n);
extern void memset(void* p, int c, ulong n);
extern int memcmp(void* a, void* b, ulong n);
extern char* getenv(char* name);
extern int puts(char* s);
extern void abort();

# The message is a raw `__ptr<char>` (C `char*`), not a `String`: codegen passes string
# literals as their global pointers (no temporary allocation), so hot paths
# like array index bounds checks stay allocation-free. Non-literal messages
# are lowered to `msg.c_str()` at the call site.
export assert(condition: bool, msg: __ptr<char>): void {
    if (!condition) {
        panic(msg);
    }
}

# ── Live-allocation counter (leak tests) and trace gate ─────────────────────
var _pep_live_allocs_count = 0;
# `getenv` needs a NUL-terminated C string; a Pepper `String` buffer is not
# guaranteed to be, so build the name in a helper (its c_str() is safe).
_pep_trace_enabled(): bool {
    var name = "PEP_TRACE";
    return getenv(name.c_str()) != __null;
}
var _pep_trace_on = _pep_trace_enabled();

export _pep_malloc(size: ulong): __ptr<void> {
    var p = malloc(size);
    # Zero the payload: refcount machinery reads old slot values from fresh
    # buffers (index_refcount_ops), so uninitialized bytes are wild pointers.
    memset(p, 0, size);
    _pep_live_allocs_count = _pep_live_allocs_count + 1;
    return p;
}

export _pep_free(p: __ptr<void>) {
    if (p != __null) {
        free(p);
        _pep_live_allocs_count = _pep_live_allocs_count - 1;
    }
}

export _pep_realloc(p: __ptr<void>, prevSize: ulong, newSize: ulong): __ptr<void> {
    # C realloc preserves contents up to min(prev,new); net-zero on the
    # counter. The extension region is uninitialized — zero it so fresh
    var np = realloc(p, newSize);
    if (np != __null) {
        # realloc(null, n) is a fresh allocation; the counter must see it.
        if (p == __null && newSize > 0) {
            _pep_live_allocs_count = _pep_live_allocs_count + 1;
        }
        if (newSize > prevSize) {
            memset(np + prevSize, 0, newSize - prevSize);
        }
    }
    return np;
}
export _pep_live_allocs(): long {
    return _pep_live_allocs_count;
}

export panic(msg: __ptr<char>) {
    if (msg == __null) {
        puts("Assertion failed with no additional information");
    } else {
        puts(msg);
    }
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
    var i = 0;
    while (i < n) {
        buf[i] = buf[n - 1 - i];
        i = i + 1;
    }
    buf[n] = 0;
    return buf;
}

floatstr(v: double): __ptr<char> {
    var ip = v as long;
    var fp = (v - (ip as double)) * 1000000.0;
    var digits = fp as long;
    var buf = _pep_malloc(64);
    var n = 0;
    var s = dec(ip);
    while (s[n] != 0) { buf[n] = s[n]; n = n + 1; }
    buf[n] = 46;
    n = n + 1;
    var k = 5;
    while (k >= 0) {
        buf[n] = (48 + (digits % 10));
        digits = digits / 10;
        n = n + 1;
        k = k - 1;
    }
    buf[n] = 0;
    return buf;
}

# ── Trace (gated by PEP_TRACE) ───────────────────────────────────────────────
export trace_region(ptr: __ptr<void>, size: ulong, name: __ptr<char>) {
    if (_pep_trace_on) {
        var buf = _pep_malloc(512);
        var n = 0;
        if (name != __null) {
            var nl = _pep_c_strlen(name);
            memcpy(buf, name, nl);
            n = nl;
        }
        buf[n] = 58;   # ':'
        n = n + 1;
        buf[n] = 32;   # ' '
        n = n + 1;
        var ah = hex(ptr as ulong);
        var i = 0;
        while (i < 16) { buf[n + i] = ah[i]; i = i + 1; }
        n = n + 16;
        if (ptr != __null && size >= 8) {
            # Build the word at ulong width: each byte zero-extends (u8 →
            # u64), so bytes >= 0x80 stay positive and the full 64-bit word
            # is defined. An i32-wide chain would sign-extend to all-F when
            # hex() takes it as ulong.
            var w = hex((ptr[0] as ulong) | ((ptr[1] as ulong) << 8) | ((ptr[2] as ulong) << 16)
                        | ((ptr[3] as ulong) << 24) | ((ptr[4] as ulong) << 32)
                        | ((ptr[5] as ulong) << 40) | ((ptr[6] as ulong) << 48)
                        | ((ptr[7] as ulong) << 56));
            var j = 0;
            while (j < 16) { buf[n + j] = w[j]; j = j + 1; }
        }
        puts(buf);
    }
}

export trace_ptr(ptr: __ptr<void>, name: __ptr<char>) {
    if (_pep_trace_on) {
        var buf = _pep_malloc(512);
        var n = 0;
        if (name != __null) {
            var nl = _pep_c_strlen(name);
            memcpy(buf, name, nl);
            n = nl;
        }
        buf[n] = 58;
        n = n + 1;
        buf[n] = 32;
        n = n + 1;
        var ah = hex(ptr as ulong);
        var i = 0;
        while (i < 16) { buf[n + i] = ah[i]; i = i + 1; }
        puts(buf);
    }
}

export trace_int(value: long, name: __ptr<char>) {
    if (_pep_trace_on) {
        var buf = _pep_malloc(512);
        var n = 0;
        if (name != __null) {
            var nl = _pep_c_strlen(name);
            memcpy(buf, name, nl);
            n = nl;
        }
        buf[n] = 58;
        n = n + 1;
        buf[n] = 32;
        n = n + 1;
        var s = dec(value);
        var i = 0;
        while (s[i] != 0) { buf[n + i] = s[i]; i = i + 1; }
        puts(buf);
    }
}

# ── Swap the first pointer-sized bytes of two slots in a struct buffer ──────
export _pep_swap_refs(p: __ptr<void>, stride: ulong, i: ulong, j: ulong) {
    if (i != j) {
        var a: __ptr<void> = p + (i * stride);
        var b: __ptr<void> = p + (j * stride);
        var len = stride;
        if (len > 8) { len = 8; }
        var tmp = _pep_malloc(len);
        memcpy(tmp, a, len);
        memcpy(a, b, len);
        memcpy(b, tmp, len);
        _pep_free(tmp);
    }
}
# ── Move the first pointer-sized bytes of one slot into another (raw
# reference transfer, no refcount change) and null the source so it releases
# nothing later: a shifted slot must not keep a stale copy of the reference.
export _pep_move_ref(p: __ptr<void>, stride: ulong, i: ulong, j: ulong) {
    if (i != j) {
        var a: __ptr<void> = p + (i * stride);
        var b: __ptr<void> = p + (j * stride);
        var len = stride;
        if (len > 8) { len = 8; }
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
export _pep_utf8_find(haystack: __ptr<void>, haystackSize: ulong, needle: __ptr<void>, needleSize: ulong): long {
    if (haystack == __null || haystackSize == 0) { return -1; }
    if (needleSize == 0) { return 0; }
    if (needle == __null) { return -1; }
    # Both spans must be valid UTF-8 (the Rust original returns -1 otherwise).
    if (!_pep_utf8_valid(haystack, haystackSize)) { return -1; }
    if (!_pep_utf8_valid(needle, needleSize)) { return -1; }
    var i = 0;
    while (i + needleSize <= haystackSize) {
        var j = 0;
        while (j < needleSize) {
            if (haystack[i + j] != needle[j]) { break; }
            j = j + 1;
        }
        if (j == needleSize) { return i; }
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
_pep_print(s: __ptr<char>) {
    if (s != __null) { puts(s); }
}

_pep_print_int(v: long) {
    puts(dec(v));
}

_pep_print_float(v: double) {
    puts(floatstr(v));
}

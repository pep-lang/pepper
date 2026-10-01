# ── C ABI externs (identical signatures on MSVC CRT and libc) ───────────────
extern void* malloc(ulong size);
extern void* calloc(ulong count, ulong size);
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
## string literal message picks the `__ptr<char>` overload instead, which
## builds no `String`. Any other message is evaluated before the call.
##
## @param condition the condition that must hold
## @param message the text to print on failure; a null `String` prints a
##   generic message
## @panics if `condition` is false: prints `message` and aborts (see `panic`)
## @example
##     assert(count > 0, "count must be positive");
export assert(condition: bool, message: String) {
    if (!condition) {
        panic(message);
    }
}

## Checks that `condition` holds; if not, panics with `message`, a
## NUL-terminated C string. A string literal message picks this overload,
## so an assertion that holds builds no `String`.
##
## @param condition the condition that must hold
## @param message the text to print on failure, or `__null` for a generic
##   message
## @panics if `condition` is false: prints `message` and aborts (see `panic`)
## @example
##     assert(count > 0, "count must be positive");
export assert(condition: bool, message: __ptr<char>) {
    if (!condition) {
        _pep_panic(message);
    }
}

# The allocation-free form of `assert` that compiler-generated checks (index
# bounds, null function and trait values) lower to: `message` is a
# NUL-terminated C string, or `__null`.
export _pep_assert(condition: bool, message: __ptr<char>) {
    if (!condition) {
        _pep_panic(message);
    }
}

# ── Live-allocation counter (leak tests) and trace gate ─────────────────────
# The live-allocation count, updated atomically because threads allocate
# concurrently. It is split into `_PEP_ALLOC_SHARDS` counters, each on its
# own 64-byte cache line, and a thread steps the one its thread id picks
# (`_pep_live_allocs_shard`). With a single counter, every allocation on
# every thread fought over one cache line: removing that cut the user CPU
# of the 4-worker echo benchmark by 18%. A block freed on another thread
# steps that thread's shard, so one shard can go negative; only the sum
# means anything. The shards live in a raw malloc'd block: an Atomic<long>
# would allocate through _pep_malloc itself. The prelude's globals are
# initialized before any other file's, and this is the first of them, so
# the block exists before anything allocates. Every JIT engine carries its
# own copy of this global, so tests that count allocations can run in
# parallel.
# Prime, so that thread ids a fixed stride apart spread over every shard.
const _PEP_ALLOC_SHARDS: ulong = 61;
# Longs per shard: one 64-byte cache line.
const _PEP_ALLOC_SHARD_STRIDE: ulong = 8;

[Target(!OS(Windows))]
extern ulong pthread_self();
[Target(OS(Windows))]
extern uint GetCurrentThreadId();

_pep_new_live_allocs_slot(): __ptr<long> {
    var size = _PEP_ALLOC_SHARDS * _PEP_ALLOC_SHARD_STRIDE * 8;
    __ptr<u8> block = malloc(size + 64);
    memset(block, 0, size + 64);
    # Start at a cache line boundary.
    __ptr<long> shards = block + (64 - (block as ulong) % 64) % 64;
    return shards;
}

const _pep_live_allocs_slot: __ptr<long> = _pep_new_live_allocs_slot();

# The calling thread's counter. glibc and macOS place each thread's
# pthread_t in its own stack mapping, so the page number tells threads
# apart (consecutive threads' stacks lie one stack size apart); Windows
# thread ids are multiples of 4.
[Target(!OS(Windows))]
_pep_live_allocs_shard(): __ptr<long> {
    var index = (pthread_self() >> 12) % _PEP_ALLOC_SHARDS;
    return _pep_live_allocs_slot + index * _PEP_ALLOC_SHARD_STRIDE;
}

[Target(OS(Windows))]
_pep_live_allocs_shard(): __ptr<long> {
    var index = ((GetCurrentThreadId() as ulong) >> 2) % _PEP_ALLOC_SHARDS;
    return _pep_live_allocs_slot + index * _PEP_ALLOC_SHARD_STRIDE;
}

# `PEP_CHECK_SYNC`, a debug switch read once at start: when it is set, a
# Mutex checks at each unlock that nothing outside the locked value refers
# into it (`_pep_check_sync` in copy.pep). It lives here because module
# constants initialize file by file, and this file's allocation counter must
# exist before any String is built.
_pep_check_sync_enabled(): bool {
    var name = "PEP_CHECK_SYNC";
    return getenv(name.c_str()) != __null;
}

export const _PEP_CHECK_SYNC_ON = _pep_check_sync_enabled();

export _pep_malloc(size: ulong): __ptr<void> {
    # Zero the payload: refcount machinery reads old slot values from fresh
    # buffers (index_refcount_ops), so uninitialized bytes are wild pointers.
    # calloc skips the clearing for fresh pages the OS already zeroed.
    var p = calloc(1, size);
    __atomic_fetch_add<long>(_pep_live_allocs_shard(), 1);
    return p;
}

export _pep_free(p: __ptr<void>) {
    if (p != __null) {
        free(p);
        __atomic_fetch_sub<long>(_pep_live_allocs_shard(), 1);
    }
}

export _pep_realloc(p: __ptr<void>, prev_size: ulong, new_size: ulong): __ptr<void> {
    # C realloc preserves contents up to min(prev,new); net-zero on the
    # counter. The extension region is uninitialized — zero it so fresh
    var np = realloc(p, new_size);
    if (np != __null) {
        # realloc(null, n) is a fresh allocation; the counter must see it.
        if (p == __null && new_size > 0) {
            __atomic_fetch_add<long>(_pep_live_allocs_shard(), 1);
        }
        if (new_size > prev_size) {
            memset(np + prev_size, 0, new_size - prev_size);
        }
    }
    return np;
}

export _pep_live_allocs(): long {
    long total = 0;
    ulong index = 0;
    while (index < _PEP_ALLOC_SHARDS) {
        total = total + __atomic_load<long>(_pep_live_allocs_slot + index * _PEP_ALLOC_SHARD_STRIDE);
        index = index + 1;
    }
    return total;
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

## Writes `message`, a NUL-terminated C string, and a newline to standard
## output (a generic message when it is `__null`), flushes every C output
## stream, and aborts, as `panic(String)` does. A string literal message
## picks this overload, so it allocates nothing.
##
## @param message the text to print, or `__null`
## @panics always
## @example
##     panic("unreachable");
export panic(message: __ptr<char>) {
    _pep_panic(message);
}

# `panic` on a NUL-terminated C string (`__null` prints a generic message).
# Compiler-generated checks lower to this, so a panic never has to allocate.
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

# ── Byte hash: 8 bytes per step, then a final avalanche ──────────────────────
# Each 8-byte word is xored in and multiplied by an odd constant, with the
# high half folded down so later words reach the low bits; the tail's 1-7
# bytes form one more word. The finish is MurmurHash3's fmix64, so every
# input bit reaches the low bits a power-of-two table masks with. Words are
# assembled from single bytes (LLVM merges them into one unaligned load), so
# `data` needs no alignment. An empty or null buffer hashes to the FNV-1a
# offset basis, the seed `hash<T>` also uses.
export _pep_hash_bytes(data: __ptr<void>, length: ulong): u64 {
    if (data == __null || length == 0) { return -3750763034362895579; }
    __ptr<u8> bytes = data as __ptr<u8>;
    ulong h = (-3750763034362895579 as ulong) ^ length;
    ulong i = 0;
    while (i + 8 <= length) {
        h = _pep_hash_step(h, _pep_hash_word(bytes, i, 8));
        i = i + 8;
    }
    if (i < length) {
        h = _pep_hash_step(h, _pep_hash_word(bytes, i, length - i));
    }
    h = (h ^ (h >> 33)) * 0xff51afd7ed558ccd;
    h = (h ^ (h >> 33)) * 0xc4ceb9fe1a85ec53;
    return h ^ (h >> 33);
}

# The `count` (1-8) bytes at `bytes[start]` as a little-endian word.
_pep_hash_word(bytes: __ptr<u8>, start: ulong, count: ulong): ulong {
    ulong word = 0;
    ulong k = 0;
    while (k < count) {
        word = word | ((bytes[start + k] as ulong) << (k * 8));
        k = k + 1;
    }
    return word;
}

# One step of `_pep_hash_bytes`: mixes `word` into `h`.
_pep_hash_step(h: ulong, word: ulong): ulong {
    var mixed = (h ^ word) * 0x9e3779b97f4a7c15;
    return mixed ^ (mixed >> 32);
}

# ── UTF-8 helpers (length-based; no NUL assumptions on language data) ───────
# C strings from getenv are NUL-terminated by the C standard; a byte walk is
# the only way to measure them (never used for language string data).
# The value of the hexadecimal digit `c` (`0`-`9`, `a`-`f` or `A`-`F`), or
# -1 when `c` is not one. Shared by the URI, HTTP and address parsers.
export _pep_hex_digit(c: int): int {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

export _pep_c_strlen(s: __ptr<char>): ulong {
    var i = 0;
    while (s[i] != 0) {
        i = i + 1;
    }
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
            if (i + 4 > size || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80 || (s[i + 3] & 0xC0) != 0x80) {
                return 0;
            }
            n = 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (s[i + 1] & 0xC0) != 0x80 || (s[i + 2] & 0xC0) != 0x80) { return 0; }
            n = 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (s[i + 1] & 0xC0) != 0x80) { return 0; }
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
            if (i + 4 > size
                || (data[i + 1] & 0xC0) != 0x80
                || (data[i + 2] & 0xC0) != 0x80
                || (data[i + 3] & 0xC0) != 0x80) { return false; }
            i = i + 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (data[i + 1] & 0xC0) != 0x80 || (data[i + 2] & 0xC0) != 0x80) { return false; }
            i = i + 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (data[i + 1] & 0xC0) != 0x80) { return false; }
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
            if (i + 4 > size
                || (data[i + 1] & 0xC0) != 0x80
                || (data[i + 2] & 0xC0) != 0x80
                || (data[i + 3] & 0xC0) != 0x80) { return size; }
            n = 4;
        }
        if (b >= 224 && b < 240) {
            if (i + 3 > size || (data[i + 1] & 0xC0) != 0x80 || (data[i + 2] & 0xC0) != 0x80) { return size; }
            n = 3;
        }
        if (b >= 192 && b < 224) {
            if (i + 2 > size || (data[i + 1] & 0xC0) != 0x80) { return size; }
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

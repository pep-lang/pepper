## `assert` and `panic`, which every program can call without an import.

# A panic prints its backtrace through the debug module.
import debug;

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
## @panics if `condition` is false: prints the location and `message`, and
##   aborts (see `panic`)
## @example
##     assert(count > 0, "count must be positive");
export assert(condition: bool, message: String, location: __ptr<char> = __caller_location()) {
    if (!condition) {
        panic(message, location);
    }
}

## Checks that `condition` holds; if not, panics with `message`, a
## NUL-terminated C string. A string literal message picks this overload,
## so an assertion that holds builds no `String`.
##
## @param condition the condition that must hold
## @param message the text to print on failure, or `__null` for a generic
##   message
## @panics if `condition` is false: prints the location and `message`, and
##   aborts (see `panic`)
## @example
##     assert(count > 0, "count must be positive");
export assert(condition: bool, message: __ptr<char>, location: __ptr<char> = __caller_location()) {
    if (!condition) {
        _pep_panic(message, location);
    }
}

# The allocation-free form of `assert` that compiler-generated null checks
# (function and trait values, `match` subjects) lower to: `message` is a
# NUL-terminated C string, or `__null`. A build with
# `--no-runtime-checks=null` drops them.
export _pep_assert(condition: bool, message: __ptr<char>, location: __ptr<char> = __caller_location()) {
    if (!condition) {
        _pep_panic(message, location);
    }
}

# The index check of `Array` and `String` indexing: `_pep_assert`, except
# that the compiler drops each call, condition and all, from a build with
# `--no-runtime-checks=bounds`, and that it passes when `location` starts
# with byte 1: the mark of a location passed from a function marked
# `[Unsafe("bounds")]` (`UNCHECKED_BOUNDS_MARK` in the compiler).
export _pep_check_bounds(condition: bool, message: __ptr<char>, location: __ptr<char> = __caller_location()) {
    if (!condition && (location == __null || location[0] != 1)) {
        _pep_panic(message, location);
    }
}

# ── Small block allocator ───────────────────────────────────────────────────
# The small block allocator behind `_pep_malloc` (#600).
#
# A block of up to `_pep_small_limit` bytes comes from a size class instead
# of from C's calloc. The limit is 128 bytes unless the environment variable
# PEPPER_SMALL_BLOCK_LIMIT, read once at start, sets it: 0 turns the
# allocator off, and values above 4096 count as 4096. A block's size is
# rounded up to its class: multiples of 16 up to 128, then four classes per
# power of two (160, 192, 224, 256, 320, ... 4096).
#
# The blocks live in one reserved stretch of address space (`_SMALL_REGION`
# bytes), so `_pep_free` tells a small block from a C one with one range
# check. The region is cut into 64 KiB spans, each holding blocks of one
# class, named in the span's first word; pages are committed a span at a
# time, and spans are never returned to the operating system.
#
# Each span has one owner, a thread's cache (a `[ThreadLocal]` pointer), and
# its own free list (#634). A thread allocates a class's blocks from one
# current span, from its free list and then from its never-used end, so
# blocks handed out one after another lie close together, and a free on the
# owner's thread pushes the block onto its span's list: neither takes a lock
# or an atomic read-modify-write. A block freed on any other thread goes onto
# the span's second list, an atomic stack, which the owner takes over when
# the span's own list runs dry. Per class the cache keeps its current span,
# a stack of spans with free blocks, and a ring of all its full spans. The
# first block another thread frees into a full span also puts the span on
# its owner's stack of spans to look at again (as mimalloc's delayed free
# does), so an owner never searches its full spans. When the current span
# runs dry the owner tries, in order, the blocks other threads freed into
# it, a span from the stack, a full span from the stack of spans to look at
# again, a span an exited thread left, and a new span. Caches are never
# freed, only handed to a new thread, so another thread can always reach a
# span's owner. A thread that `async.Thread.spawn` started gives its spans up when
# its body ends (`_pep_small_thread_exit`): they go to their class's pool,
# for any thread to adopt.
#
# Each cache counts its live blocks for `_pep_live_allocs`; a block freed on
# another thread makes that thread's count go down, so only the sum means
# anything. A cache's count moves to `_SMALL_RETIRED` when its thread exits.
#
# Recycled blocks are zeroed when they are handed out; fresh spans are
# already zero. WebAssembly has no way to reserve address space, so there
# the limit is always 0 and every block comes from calloc.
#
# This runs before the prelude's other globals exist, so it uses raw memory
# and C calls only: no `String`, `Array` or struct.

# Bytes per span.
const _SMALL_SPAN: ulong = 65536;
# Bytes at the start of a span before its first block: its header.
const _SMALL_SPAN_HEADER: ulong = 96;
# Bytes of address space reserved for small blocks (4 GiB). Only spans in
# use are committed; past the end, small requests fall back to calloc.
const _SMALL_REGION: ulong = 4294967296;
# The largest limit, and the default.
const _SMALL_MAX_LIMIT: ulong = 4096;
const _SMALL_DEFAULT_LIMIT: ulong = 128;
# Size classes: 8 multiples of 16, then 4 per power of two up to 4096.
const _SMALL_CLASSES: ulong = 28;
# The bit of a span's remote list that asks the next thread that frees into
# it to put the span on its owner's stack of spans to look at again: set
# while the span is full. Blocks are 16-byte aligned, so it is free.
const _SMALL_NOTIFY: ulong = 1;

# The state block, in ulong words.
# The region's base and size (0 when the allocator is off).
const _SMALL_BASE: ulong = 0;
const _SMALL_SIZE: ulong = 1;
# The next unused span (atomic).
const _SMALL_NEXT_SPAN: ulong = 2;
const _SMALL_LIMIT: ulong = 3;
# The caches of exited threads, for new threads to take (under the lock of
# the list of caches).
const _SMALL_SPARE_CACHES: ulong = 4;
# The lock of the list of caches, and its head.
const _SMALL_CACHES_LOCK: ulong = 5;
const _SMALL_CACHES: ulong = 6;
# The live blocks of the caches of threads that have exited (atomic).
const _SMALL_RETIRED: ulong = 7;
# Each class's block size.
const _SMALL_CLASS_SIZES: ulong = 8;
# A byte table from `(size + 15) >> 4` to the class.
const _SMALL_CLASS_TABLE: ulong = 40;
# Per class, a cache line: the lock and the pool of spans exited threads
# left.
const _SMALL_CENTRAL: ulong = 80;
const _SMALL_CENTRAL_WORDS: ulong = 8;
const _SMALL_STATE_WORDS: ulong = 304;

# A thread's cache, in ulong words: the next cache, the live count, then per
# class its current span, its stack of spans with free blocks, and the head
# and tail of its ring of full spans; on a cache line of its own, the stack
# of full spans other threads have freed into (atomic).
const _SMALL_CACHE_NEXT: ulong = 0;
const _SMALL_CACHE_LIVE: ulong = 1;
const _SMALL_CACHE_LISTS: ulong = 4;
const _SMALL_CACHE_FREED_INTO: ulong = 120;
const _SMALL_CACHE_WORDS: ulong = 128;
const _SMALL_CURRENT: ulong = 0;
const _SMALL_PARTIAL: ulong = 1;
const _SMALL_FULL_HEAD: ulong = 2;
const _SMALL_FULL_TAIL: ulong = 3;

# A span's header, in ulong words. The words its owner uses come first; the
# list other threads free into sits on the next cache line.
const _SMALL_HEADER_CLASS: ulong = 0;
const _SMALL_HEADER_FREE: ulong = 1;
# The never-used end of the span: its next block and its end.
const _SMALL_HEADER_BUMP: ulong = 2;
const _SMALL_HEADER_END: ulong = 3;
# The next span in the list or ring it is on, and the previous one in the
# ring of full spans.
const _SMALL_HEADER_NEXT: ulong = 4;
const _SMALL_HEADER_PREVIOUS: ulong = 5;
const _SMALL_HEADER_STATE: ulong = 6;
# The owner's cache, or 0 while the span is in its class's pool (atomic).
const _SMALL_HEADER_OWNER: ulong = 7;
# The blocks other threads freed (an atomic stack, with `_SMALL_NOTIFY`).
const _SMALL_HEADER_REMOTE: ulong = 8;
# The next span on its owner's stack of spans to look at again, and whether
# the span is on it (atomic), so it is never there twice.
const _SMALL_HEADER_FREED_INTO: ulong = 9;
const _SMALL_HEADER_QUEUED: ulong = 10;

# A span's state: its owner's current span, on its stack of spans with free
# blocks, on its ring of full spans, or in its class's pool.
const _SMALL_STATE_CURRENT: ulong = 0;
const _SMALL_STATE_PARTIAL: ulong = 1;
const _SMALL_STATE_FULL: ulong = 2;
const _SMALL_STATE_POOLED: ulong = 3;

[Target(!OS(Windows) && !OS(Wasi))]
extern void* mmap(void* address, ulong length, int protection, int flags, int descriptor, long offset);
[Target(!OS(Windows) && !OS(Wasi))]
extern int mprotect(void* address, ulong length, int protection);
[Target(!OS(Windows) && !OS(Wasi))]
extern int sched_yield();
[Target(OS(Windows))]
extern void* VirtualAlloc(void* address, ulong size, uint allocation_type, uint protect);
[Target(OS(Windows))]
extern int SwitchToThread();

# MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE.
[Target(OS(Linux))]
const _SMALL_MAP_FLAGS = 16418;
# MAP_PRIVATE | MAP_ANON.
[Target(OS(Mac))]
const _SMALL_MAP_FLAGS = 4098;

# Reserves `size` bytes of address space with no access, or returns null.
[Target(!OS(Windows) && !OS(Wasi))]
[Unsafe("overflow")]
_pep_small_reserve(size: ulong): __ptr<u8> {
    var p = mmap(__null, size, 0, _SMALL_MAP_FLAGS, -1, 0);
    # MAP_FAILED is -1.
    if (unsafe_cast<long>(p) == -1) {
        return __null;
    }
    return p;
}

[Target(OS(Windows))]
[Unsafe("overflow")]
_pep_small_reserve(size: ulong): __ptr<u8> {
    # MEM_RESERVE, PAGE_NOACCESS.
    return VirtualAlloc(__null, size, 0x2000, 1);
}

[Target(OS(Wasi))]
[Unsafe("overflow")]
_pep_small_reserve(size: ulong): __ptr<u8> {
    return __null;
}

# Makes a reserved span readable and writable; false if the system refuses.
[Target(!OS(Windows) && !OS(Wasi))]
[Unsafe("overflow")]
_pep_small_commit(span: __ptr<u8>): bool {
    # PROT_READ | PROT_WRITE.
    return mprotect(span, _SMALL_SPAN, 3) == 0;
}

[Target(OS(Windows))]
[Unsafe("overflow")]
_pep_small_commit(span: __ptr<u8>): bool {
    # MEM_COMMIT, PAGE_READWRITE.
    return VirtualAlloc(span, _SMALL_SPAN, 0x1000, 4) != __null;
}

[Target(OS(Wasi))]
[Unsafe("overflow")]
_pep_small_commit(span: __ptr<u8>): bool {
    return false;
}

# Lets another thread run while a lock is contended.
[Target(!OS(Windows) && !OS(Wasi))]
[Unsafe("overflow")]
_pep_small_yield() {
    sched_yield();
}

[Target(OS(Windows))]
[Unsafe("overflow")]
_pep_small_yield() {
    SwitchToThread();
}

[Target(OS(Wasi))]
[Unsafe("overflow")]
_pep_small_yield() {}

# The calling thread's cache, or null if it has none yet. It is a native
# thread-local with no exit hook: a JIT engine's code is gone by the time the
# thread that ran it exits, so a thread Pepper spawned hands its cache back
# itself (`_pep_small_thread_exit`), and any other thread keeps its cache. On
# Windows it is a thread (not fiber) local, so fibers that run on one thread
# share its cache.
[ThreadLocal]
var _pep_small_cache: __ptr<ulong>;

# The limit PEPPER_SMALL_BLOCK_LIMIT sets: a decimal number of bytes, or the
# default when it is unset or not a number. No `String` exists yet, so this
# reads the C string itself.
[Target(!OS(Wasi))]
_pep_small_read_limit(): ulong {
    __ptr<u8> text = getenv("PEPPER_SMALL_BLOCK_LIMIT");
    if (text == __null || text[0] == 0) {
        return _SMALL_DEFAULT_LIMIT;
    }
    ulong limit = 0;
    ulong index = 0;
    while (text[index] != 0) {
        var digit = text[index];
        if (digit < 48 || digit > 57) {
            return _SMALL_DEFAULT_LIMIT;
        }
        if (limit < _SMALL_MAX_LIMIT) {
            limit = limit * 10 + ((digit - 48) as ulong);
        }
        index = index + 1;
    }
    return limit < _SMALL_MAX_LIMIT ? limit : _SMALL_MAX_LIMIT;
}

[Target(OS(Wasi))]
_pep_small_read_limit(): ulong {
    return 0;
}

# The bytes a block of class `index` takes.
_pep_small_class_size(index: ulong): ulong {
    if (index < 8) {
        return (index + 1) * 16;
    }
    # Class 8 + 4 * group + step is 128 << group, plus (step + 1) quarters
    # of that.
    var group = (index - 8) / 4;
    var step = (index - 8) % 4;
    var base: ulong = 128 << group;
    return base + (step + 1) * (base / 4);
}

# Builds the state block: the limit, the class tables and the reserved
# region. When the limit is 0, or the reservation cannot be had, the region's size stays 0 and every block
# comes from calloc.
_pep_small_new_state(): __ptr<ulong> {
    var bytes = _SMALL_STATE_WORDS * 8 + 64;
    __ptr<u8> block = malloc(bytes);
    memset(block, 0, bytes);
    # Start at a cache line boundary, so each class's pool has a line of its
    # own.
    __ptr<ulong> state = block + (64 - unsafe_cast<ulong>(block) % 64) % 64;
    var limit = _pep_small_read_limit();
    if (limit == 0) {
        return state;
    }
    ulong index = 0;
    while (index < _SMALL_CLASSES) {
        var size = _pep_small_class_size(index);
        state[_SMALL_CLASS_SIZES + index] = size;
        index = index + 1;
    }
    # Sizes 0 to 4096 in steps of 16, each mapped to the smallest class that
    # holds it.
    __ptr<u8> table = state + _SMALL_CLASS_TABLE;
    ulong class_index = 0;
    ulong slot = 0;
    while (slot <= _SMALL_MAX_LIMIT / 16) {
        while (state[_SMALL_CLASS_SIZES + class_index] < slot * 16) {
            class_index = class_index + 1;
        }
        table[slot] = class_index as u8;
        slot = slot + 1;
    }
    __ptr<u8> reserved = _pep_small_reserve(_SMALL_REGION + _SMALL_SPAN);
    if (reserved == __null) {
        return state;
    }
    # Spans are aligned, so a block's span is its address rounded down.
    var base = unsafe_cast<ulong>(reserved);
    base = base + (_SMALL_SPAN - base % _SMALL_SPAN) % _SMALL_SPAN;
    state[_SMALL_BASE] = base;
    state[_SMALL_NEXT_SPAN] = base;
    state[_SMALL_SIZE] = _SMALL_REGION;
    state[_SMALL_LIMIT] = limit;
    return state;
}

[Unsafe("overflow")]
_pep_small_lock(lock: __ptr<ulong>) {
    while (!__atomic_cmpxchg<ulong>(lock, 0, 1)) {
        ulong spins = 0;
        while (__atomic_load<ulong>(lock) != 0) {
            spins = spins + 1;
            if (spins % 64 == 0) {
                _pep_small_yield();
            }
        }
    }
}

[Unsafe("overflow")]
_pep_small_unlock(lock: __ptr<ulong>) {
    __atomic_store<ulong>(lock, 0);
}

# Adds `delta` to a count only its own thread changes: a plain load and
# store, atomic only so `_pep_small_live` can read it from another thread.
[Unsafe("overflow")]
_pep_small_count(count: __ptr<ulong>, delta: long) {
    __ptr<long> value = count;
    __atomic_store<long>(value, __atomic_load<long>(value) + delta);
}

# A new, empty cache for the calling thread, on the list of caches: an exited
# thread's, or a new one; null when the C allocator has no room for it.
[Unsafe("overflow")]
_pep_small_new_cache(): __ptr<ulong> {
    _pep_small_lock(_pep_small_state + _SMALL_CACHES_LOCK);
    __ptr<ulong> cache = unsafe_cast<__ptr<ulong>>(_pep_small_state[_SMALL_SPARE_CACHES]);
    if (cache != __null) {
        _pep_small_state[_SMALL_SPARE_CACHES] = cache[_SMALL_CACHE_NEXT];
        # Its stack of spans to look at again may still gain a span, which
        # this thread does not own and passes over.
        memset(cache, 0, _SMALL_CACHE_FREED_INTO * 8);
    } else {
        cache = malloc(_SMALL_CACHE_WORDS * 8);
        if (cache == __null) {
            _pep_small_unlock(_pep_small_state + _SMALL_CACHES_LOCK);
            return __null;
        }
        memset(cache, 0, _SMALL_CACHE_WORDS * 8);
    }
    cache[_SMALL_CACHE_NEXT] = _pep_small_state[_SMALL_CACHES];
    _pep_small_state[_SMALL_CACHES] = unsafe_cast<ulong>(cache);
    _pep_small_unlock(_pep_small_state + _SMALL_CACHES_LOCK);
    _pep_small_cache = cache;
    return cache;
}

# Takes the blocks other threads freed into `header`'s span as its free
# list, which must be empty, and clears its `_SMALL_NOTIFY`; false if there
# are none.
[Unsafe("overflow")]
_pep_small_take_remote(header: __ptr<ulong>): bool {
    __ptr<ulong> remote = header + _SMALL_HEADER_REMOTE;
    while (true) {
        var head = __atomic_load<ulong>(remote);
        if ((head & ~_SMALL_NOTIFY) == 0) {
            return false;
        }
        if (__atomic_cmpxchg<ulong>(remote, head, 0)) {
            header[_SMALL_HEADER_FREE] = head & ~_SMALL_NOTIFY;
            return true;
        }
    }
    return false;
}

# Sets `header`'s span's `_SMALL_NOTIFY`, as it goes on the ring of full
# spans; false when other threads have freed into it meanwhile.
[Unsafe("overflow")]
_pep_small_ask_to_notify(header: __ptr<ulong>): bool {
    __ptr<ulong> remote = header + _SMALL_HEADER_REMOTE;
    while (true) {
        var head = __atomic_load<ulong>(remote);
        if (head == _SMALL_NOTIFY) {
            return true;
        }
        if (head != 0) {
            return false;
        }
        if (__atomic_cmpxchg<ulong>(remote, 0, _SMALL_NOTIFY)) {
            return true;
        }
    }
    return false;
}

# Appends `span` to the ring of full spans in `lists`.
[Unsafe("overflow")]
_pep_small_push_full(lists: __ptr<ulong>, span: ulong) {
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    header[_SMALL_HEADER_STATE] = _SMALL_STATE_FULL;
    header[_SMALL_HEADER_NEXT] = 0;
    var tail = lists[_SMALL_FULL_TAIL];
    header[_SMALL_HEADER_PREVIOUS] = tail;
    if (tail == 0) {
        lists[_SMALL_FULL_HEAD] = span;
    } else {
        unsafe_cast<__ptr<ulong>>(tail)[_SMALL_HEADER_NEXT] = span;
    }
    lists[_SMALL_FULL_TAIL] = span;
}

# Takes `span` off the ring of full spans in `lists`.
[Unsafe("overflow")]
_pep_small_unlink_full(lists: __ptr<ulong>, span: ulong) {
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    var next = header[_SMALL_HEADER_NEXT];
    var previous = header[_SMALL_HEADER_PREVIOUS];
    if (previous == 0) {
        lists[_SMALL_FULL_HEAD] = next;
    } else {
        unsafe_cast<__ptr<ulong>>(previous)[_SMALL_HEADER_NEXT] = next;
    }
    if (next == 0) {
        lists[_SMALL_FULL_TAIL] = previous;
    } else {
        unsafe_cast<__ptr<ulong>>(next)[_SMALL_HEADER_PREVIOUS] = previous;
    }
}

# Makes `span` the current span of `lists`.
[Unsafe("overflow")]
_pep_small_make_current(lists: __ptr<ulong>, span: ulong) {
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    header[_SMALL_HEADER_STATE] = _SMALL_STATE_CURRENT;
    lists[_SMALL_CURRENT] = span;
}

# Takes the stack of full spans other threads have freed into: spans this
# cache still owns and that are still full go back to their stacks of spans
# with free blocks, and those of class `class_index` become `lists`'s
# current span (the first) or join its stack. False if none of that class
# was there.
[Unsafe("overflow")]
_pep_small_freed_into(cache: __ptr<ulong>, lists: __ptr<ulong>, class_index: ulong): bool {
    __ptr<ulong> stack = cache + _SMALL_CACHE_FREED_INTO;
    if (__atomic_load<ulong>(stack) == 0) {
        return false;
    }
    var span = 0 as ulong;
    while (true) {
        span = __atomic_load<ulong>(stack);
        ulong empty = 0;
        if (__atomic_cmpxchg<ulong>(stack, span, empty)) {
            break;
        }
    }
    var found = false;
    while (span != 0) {
        __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
        var next = header[_SMALL_HEADER_FREED_INTO];
        ulong idle = 0;
        __atomic_store<ulong>(header + _SMALL_HEADER_QUEUED, idle);
        if (__atomic_load<ulong>(header + _SMALL_HEADER_OWNER) == unsafe_cast<ulong>(cache)
            && header[_SMALL_HEADER_STATE] == _SMALL_STATE_FULL) {
            var class_of_span = header[_SMALL_HEADER_CLASS];
            __ptr<ulong> span_lists = cache + _SMALL_CACHE_LISTS + class_of_span * 4;
            _pep_small_unlink_full(span_lists, span);
            if (class_of_span == class_index && !found) {
                _pep_small_make_current(lists, span);
                found = true;
            } else {
                header[_SMALL_HEADER_STATE] = _SMALL_STATE_PARTIAL;
                header[_SMALL_HEADER_NEXT] = span_lists[_SMALL_PARTIAL];
                span_lists[_SMALL_PARTIAL] = span;
            }
        }
        span = next;
    }
    return found;
}

# Finds class `class_index` a new current span for `cache` once the current
# one (if any) has no block left: a span with free blocks, a full span other
# threads have freed into, a span an exited thread left, or a new span. The
# current span, set aside, goes on the ring of full spans. False
# when the region is used up or the system will not commit more memory.
[Unsafe("overflow")]
_pep_small_refill(cache: __ptr<ulong>, lists: __ptr<ulong>, class_index: ulong): bool {
    var current = lists[_SMALL_CURRENT];
    if (current != 0) {
        __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(current);
        if (!_pep_small_ask_to_notify(header)) {
            # Blocks came back while it was being set aside.
            return _pep_small_take_remote(header);
        }
        lists[_SMALL_CURRENT] = 0;
        _pep_small_push_full(lists, current);
    }
    var partial = lists[_SMALL_PARTIAL];
    if (partial != 0) {
        lists[_SMALL_PARTIAL] = unsafe_cast<__ptr<ulong>>(partial)[_SMALL_HEADER_NEXT];
        _pep_small_make_current(lists, partial);
        return true;
    }
    if (_pep_small_freed_into(cache, lists, class_index)) {
        return true;
    }
    __ptr<ulong> central = _pep_small_state + _SMALL_CENTRAL + class_index * _SMALL_CENTRAL_WORDS;
    _pep_small_lock(central);
    var pooled = central[1];
    if (pooled != 0) {
        __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(pooled);
        central[1] = header[_SMALL_HEADER_NEXT];
        _pep_small_unlock(central);
        __atomic_store<ulong>(header + _SMALL_HEADER_OWNER, unsafe_cast<ulong>(cache));
        _pep_small_make_current(lists, pooled);
        return true;
    }
    _pep_small_unlock(central);
    var span = __atomic_fetch_add<ulong>(_pep_small_state + _SMALL_NEXT_SPAN, _SMALL_SPAN);
    if (span + _SMALL_SPAN > _pep_small_end || !_pep_small_commit(unsafe_cast<__ptr<u8>>(span))) {
        return false;
    }
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    var size = _pep_small_state[_SMALL_CLASS_SIZES + class_index];
    var count = (_SMALL_SPAN - _SMALL_SPAN_HEADER) / size;
    header[_SMALL_HEADER_CLASS] = class_index;
    header[_SMALL_HEADER_BUMP] = span + _SMALL_SPAN_HEADER;
    header[_SMALL_HEADER_END] = span + _SMALL_SPAN_HEADER + count * size;
    __atomic_store<ulong>(header + _SMALL_HEADER_OWNER, unsafe_cast<ulong>(cache));
    _pep_small_make_current(lists, span);
    return true;
}

# A zeroed block of at least `size` bytes, 1 to the limit, or null when no
# span is left (the caller then uses calloc). The fast path pops the current
# span's free list or bumps into its untouched tail; the rest is out of line.
[Unsafe("overflow")]
_pep_small_alloc(size: ulong): __ptr<void> {
    var cache = _pep_small_cache;
    if (cache != __null) {
        __ptr<u8> table = _pep_small_state + _SMALL_CLASS_TABLE;
        var class_index = table[(size + 15) >> 4] as ulong;
        __ptr<ulong> lists = cache + _SMALL_CACHE_LISTS + class_index * 4;
        var span = lists[_SMALL_CURRENT];
        if (span != 0) {
            __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
            var head = header[_SMALL_HEADER_FREE];
            if (head != 0) {
                __ptr<ulong> block = unsafe_cast<__ptr<ulong>>(head);
                header[_SMALL_HEADER_FREE] = block[0];
                _pep_small_count(cache + _SMALL_CACHE_LIVE, 1);
                memset(block, 0, size);
                return block;
            }
            var fresh = header[_SMALL_HEADER_BUMP];
            if (fresh != header[_SMALL_HEADER_END]) {
                # Never used, so still zero.
                header[_SMALL_HEADER_BUMP] = fresh + _pep_small_state[_SMALL_CLASS_SIZES + class_index];
                _pep_small_count(cache + _SMALL_CACHE_LIVE, 1);
                return unsafe_cast<__ptr<void>>(fresh);
            }
        }
    }
    return _pep_small_alloc_slow(size);
}

# `_pep_small_alloc` when the current span has nothing at hand: makes the
# cache, takes the blocks other threads freed or moves to another span, then
# tries again.
[Cold]
[Unsafe("overflow")]
_pep_small_alloc_slow(size: ulong): __ptr<void> {
    var cache = _pep_small_cache;
    if (cache == __null) {
        cache = _pep_small_new_cache();
        if (cache == __null) {
            return __null;
        }
        return _pep_small_alloc(size);
    }
    __ptr<u8> table = _pep_small_state + _SMALL_CLASS_TABLE;
    var class_index = table[(size + 15) >> 4] as ulong;
    __ptr<ulong> lists = cache + _SMALL_CACHE_LISTS + class_index * 4;
    var span = lists[_SMALL_CURRENT];
    if (span != 0 && _pep_small_take_remote(unsafe_cast<__ptr<ulong>>(span))) {
        return _pep_small_alloc(size);
    }
    if (!_pep_small_refill(cache, lists, class_index)) {
        return __null;
    }
    return _pep_small_alloc(size);
}

# Whether `p` is a small block.
[Unsafe("overflow")]
_pep_small_owns(p: __ptr<void>): bool {
    var address = unsafe_cast<ulong>(p);
    return address >= _pep_small_base && address < _pep_small_end;
}

# The class of small block `p`, from its span's first word.
[Unsafe("overflow")]
_pep_small_class(p: __ptr<void>): ulong {
    var address = unsafe_cast<ulong>(p);
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(address - address % _SMALL_SPAN);
    return header[0];
}

# The bytes small block `p` can hold.
[Unsafe("overflow")]
_pep_small_capacity(p: __ptr<void>): ulong {
    return _pep_small_state[_SMALL_CLASS_SIZES + _pep_small_class(p)];
}

# Returns small block `p` to its span: onto the span's own list on the
# owner's thread, else onto the list other threads free into.
[Unsafe("overflow")]
_pep_small_free(p: __ptr<void>) {
    var address = unsafe_cast<ulong>(p);
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(address - address % _SMALL_SPAN);
    var cache = _pep_small_cache;
    if (cache != __null
        && __atomic_load<ulong>(header + _SMALL_HEADER_OWNER) == unsafe_cast<ulong>(cache)
        && header[_SMALL_HEADER_STATE] != _SMALL_STATE_FULL) {
        __ptr<ulong> block = p;
        block[0] = header[_SMALL_HEADER_FREE];
        header[_SMALL_HEADER_FREE] = address;
        _pep_small_count(cache + _SMALL_CACHE_LIVE, -1);
        return;
    }
    _pep_small_free_slow(p);
}

# `_pep_small_free` for a full span of the calling thread's, which goes back
# among its partial spans, or a span another thread owns or none does.
[Cold]
[Unsafe("overflow")]
_pep_small_free_slow(p: __ptr<void>) {
    var address = unsafe_cast<ulong>(p);
    var span = address - address % _SMALL_SPAN;
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    __ptr<ulong> block = p;
    var cache = _pep_small_cache;
    if (cache != __null && __atomic_load<ulong>(header + _SMALL_HEADER_OWNER) == unsafe_cast<ulong>(cache)) {
        block[0] = header[_SMALL_HEADER_FREE];
        header[_SMALL_HEADER_FREE] = address;
        _pep_small_count(cache + _SMALL_CACHE_LIVE, -1);
        # It has room again.
        __ptr<ulong> lists = cache + _SMALL_CACHE_LISTS + header[_SMALL_HEADER_CLASS] * 4;
        _pep_small_unlink_full(lists, span);
        header[_SMALL_HEADER_STATE] = _SMALL_STATE_PARTIAL;
        header[_SMALL_HEADER_NEXT] = lists[_SMALL_PARTIAL];
        lists[_SMALL_PARTIAL] = span;
        return;
    }
    __ptr<ulong> remote = header + _SMALL_HEADER_REMOTE;
    while (true) {
        var head = __atomic_load<ulong>(remote);
        block[0] = head & ~_SMALL_NOTIFY;
        if (!__atomic_cmpxchg<ulong>(remote, head, address)) {
            continue;
        }
        if ((head & _SMALL_NOTIFY) != 0) {
            # The span was full: tell its owner, if it has one.
            __ptr<ulong> owner = unsafe_cast<__ptr<ulong>>(__atomic_load<ulong>(header + _SMALL_HEADER_OWNER));
            ulong idle = 0;
            ulong queued = 1;
            if (owner != __null && __atomic_cmpxchg<ulong>(header + _SMALL_HEADER_QUEUED, idle, queued)) {
                __ptr<ulong> stack = owner + _SMALL_CACHE_FREED_INTO;
                while (true) {
                    var top = __atomic_load<ulong>(stack);
                    header[_SMALL_HEADER_FREED_INTO] = top;
                    if (__atomic_cmpxchg<ulong>(stack, top, span)) {
                        break;
                    }
                }
            }
        }
        break;
    }
    if (cache == __null) {
        # A thread whose cache is gone (its exit has begun) or never made.
        __atomic_fetch_sub<long>(unsafe_cast<__ptr<long>>(_pep_small_state + _SMALL_RETIRED), 1);
    } else {
        _pep_small_count(cache + _SMALL_CACHE_LIVE, -1);
    }
}

# Puts `span` in its class's pool, ownerless.
[Unsafe("overflow")]
_pep_small_pool(span: ulong) {
    __ptr<ulong> header = unsafe_cast<__ptr<ulong>>(span);
    __ptr<ulong> central = _pep_small_state + _SMALL_CENTRAL + header[_SMALL_HEADER_CLASS] * _SMALL_CENTRAL_WORDS;
    header[_SMALL_HEADER_STATE] = _SMALL_STATE_POOLED;
    __atomic_store<ulong>(header + _SMALL_HEADER_OWNER, 0);
    _pep_small_lock(central);
    header[_SMALL_HEADER_NEXT] = central[1];
    central[1] = span;
    _pep_small_unlock(central);
}

# Hands the calling thread's cache back, as its last act (a thread that
# `async.Thread.spawn` started calls it): puts each of its spans in its
# class's pool, folds its live count into the retired count, and keeps the
# cache for the next new thread.
# A block the thread frees after this goes onto its span's list for other
# threads.
[Unsafe("overflow")]
export _pep_small_thread_exit() {
    if (_pep_small_end == 0) {
        return;
    }
    __ptr<ulong> cache = _pep_small_cache;
    if (cache == __null) {
        return;
    }
    _pep_small_cache = __null;
    ulong class_index = 0;
    while (class_index < _SMALL_CLASSES) {
        __ptr<ulong> lists = cache + _SMALL_CACHE_LISTS + class_index * 4;
        if (lists[_SMALL_CURRENT] != 0) {
            _pep_small_pool(lists[_SMALL_CURRENT]);
        }
        var span = lists[_SMALL_PARTIAL];
        while (span != 0) {
            var next = unsafe_cast<__ptr<ulong>>(span)[_SMALL_HEADER_NEXT];
            _pep_small_pool(span);
            span = next;
        }
        span = lists[_SMALL_FULL_HEAD];
        while (span != 0) {
            var next = unsafe_cast<__ptr<ulong>>(span)[_SMALL_HEADER_NEXT];
            _pep_small_pool(span);
            span = next;
        }
        class_index = class_index + 1;
    }
    _pep_small_lock(_pep_small_state + _SMALL_CACHES_LOCK);
    __ptr<ulong> link = _pep_small_state + _SMALL_CACHES;
    while (link[0] != unsafe_cast<ulong>(cache)) {
        link = unsafe_cast<__ptr<ulong>>(link[0]) + _SMALL_CACHE_NEXT;
    }
    link[0] = cache[_SMALL_CACHE_NEXT];
    __ptr<long> live = cache + _SMALL_CACHE_LIVE;
    __atomic_fetch_add<long>(unsafe_cast<__ptr<long>>(_pep_small_state + _SMALL_RETIRED), live[0]);
    cache[_SMALL_CACHE_NEXT] = _pep_small_state[_SMALL_SPARE_CACHES];
    _pep_small_state[_SMALL_SPARE_CACHES] = unsafe_cast<ulong>(cache);
    _pep_small_unlock(_pep_small_state + _SMALL_CACHES_LOCK);
}

# Whether `p` came from the small block allocator, and the limit in force:
# for the runtime's own tests.
export _pep_is_small_block(p: __ptr<void>): bool {
    return _pep_small_owns(p);
}

export _pep_small_block_limit(): ulong {
    return _pep_small_limit;
}

# The small blocks live now: every cache's count plus the retired count.
[Unsafe("overflow")]
_pep_small_live(): long {
    _pep_small_lock(_pep_small_state + _SMALL_CACHES_LOCK);
    var total = __atomic_load<long>(unsafe_cast<__ptr<long>>(_pep_small_state + _SMALL_RETIRED));
    var cache = _pep_small_state[_SMALL_CACHES];
    while (cache != 0) {
        __ptr<long> words = unsafe_cast<__ptr<long>>(cache);
        total = total + __atomic_load<long>(words + _SMALL_CACHE_LIVE);
        cache = unsafe_cast<ulong>(words[_SMALL_CACHE_NEXT]);
    }
    _pep_small_unlock(_pep_small_state + _SMALL_CACHES_LOCK);
    return total;
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
    __ptr<long> shards = block + (64 - unsafe_cast<ulong>(block) % 64) % 64;
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

# The small block allocator's state, and copies of the words every
# allocation and free reads (see the small block allocator above). Like the counter, it
# must exist before anything allocates.
const _pep_small_state: __ptr<ulong> = _pep_small_new_state();
const _pep_small_base: ulong = _pep_small_state[_SMALL_BASE];
const _pep_small_end: ulong = _pep_small_base + _pep_small_state[_SMALL_SIZE];
const _pep_small_limit: ulong = _pep_small_state[_SMALL_LIMIT];

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

[Unsafe("overflow")]
export _pep_malloc(size: ulong): __ptr<void> {
    # A small block, unless the limit is 0. A 0-byte request goes to calloc.
    if (size <= _pep_small_limit && size != 0) {
        var block = _pep_small_alloc(size);
        if (block != __null) {
            return block;
        }
    }
    # Zero the payload: refcount machinery reads old slot values from fresh
    # buffers (index_refcount_ops), so uninitialized bytes are wild pointers.
    # calloc skips the clearing for fresh pages the OS already zeroed.
    var p = calloc(1, size);
    __atomic_fetch_add<long>(_pep_live_allocs_shard(), 1);
    return p;
}

[Unsafe("overflow")]
export _pep_free(p: __ptr<void>) {
    if (_pep_small_owns(p)) {
        _pep_small_free(p);
    } else if (p != __null) {
        free(p);
        __atomic_fetch_sub<long>(_pep_live_allocs_shard(), 1);
    }
}

[Unsafe("overflow")]
export _pep_realloc(p: __ptr<void>, prev_size: ulong, new_size: ulong): __ptr<void> {
    if (_pep_small_owns(p) || (p == __null && new_size <= _pep_small_limit && new_size != 0)) {
        if (p != __null && new_size <= _pep_small_capacity(p)) {
            # It still fits its class.
            if (new_size > prev_size) {
                memset(p + prev_size, 0, new_size - prev_size);
            }
            return p;
        }
        # Move it: to another class, or to calloc past the limit.
        var moved = _pep_malloc(new_size);
        if (p != __null) {
            memcpy(moved, p, prev_size < new_size ? prev_size : new_size);
            _pep_free(p);
        }
        return moved;
    }
    # C realloc preserves contents up to min(prev,new); net-zero on the
    # counter. The extension region is uninitialized — zero it so fresh
    # Never ask for 0 bytes (an Array of a zero-size type): realloc(p, 0)
    # may free `p` and return null, which the counter would not see.
    var np = realloc(p, new_size > 0 ? new_size : 1);
    if (np != __null) {
        # realloc(null, n) is a fresh allocation; the counter must see it.
        if (p == __null) {
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
    return total + _pep_small_live();
}

## Prints `message` and aborts the program. It never returns.
##
## Flushes every C output stream, so output printed so far is not lost,
## then writes `location: panic: message` and a newline to standard error
## ("Assertion failed with no additional information" when `message` is
## null), followed in a build without `-O` by a backtrace of the calls
## that led there (`PEPPER_BACKTRACE` overrides the build; see the `debug`
## module's `print_backtrace`), and calls C `abort()`. No destructors or
## releases run, and the process ends abnormally (SIGABRT on POSIX).
##
## The location is the call's `file:line:col`, which the compiler passes
## in a hidden parameter, the way a C++ `std::source_location` default
## argument works. A function that panics on its caller's behalf, as the
## runtime's indexers do, declares that parameter itself and passes it on,
## so the panic names its caller's line:
##
##     check_positive(value: int, location: __ptr<char> = __caller_location()) {
##         if (value <= 0) {
##             panic("expected a positive value", location);
##         }
##     }
##
## @param message the text to print
## @panics always
## @example
##     panic("unreachable");
export panic(message: String, location: __ptr<char> = __caller_location()) {
    if (message === __null) {
        _pep_panic(__null, location);
    }
    _pep_panic(message.c_str(), location);
}

## Reports `message`, a NUL-terminated C string (a generic message when it
## is `__null`), as a panic and aborts, as `panic(String)` does. A string
## literal message picks this overload, so it allocates nothing.
##
## @param message the text to print, or `__null`
## @panics always
## @example
##     panic("unreachable");
export panic(message: __ptr<char>, location: __ptr<char> = __caller_location()) {
    _pep_panic(message, location);
}

[Target(!OS(Windows))]
extern long write(int fd, void* buf, ulong n);
[Target(OS(Windows))]
extern int _write(int fd, void* buf, uint n);
extern ulong strlen(char* s);

# Write the C string `text` to standard error, unbuffered.
[Target(!OS(Windows))]
export _pep_write_error(text: __ptr<char>) {
    write(2, text, strlen(text));
}

[Target(OS(Windows))]
export _pep_write_error(text: __ptr<char>) {
    _write(2, text, strlen(text) as uint);
}

# `panic` on NUL-terminated C strings: `message` (`__null` prints a generic
# message) and `location` (`__null` for none). Compiler-generated checks
# lower to this, so a panic never has to allocate.
export _pep_panic(message: __ptr<char>, location: __ptr<char>) {
    # stdout is fully buffered when it is a pipe: flush it, or abort() drops
    # what the program printed before the panic.
    fflush(__null);
    if (location != __null) {
        # Without the mark of an `[Unsafe("bounds")]` caller.
        _pep_write_error(location[0] == 1 ? location + 1 : location);
        _pep_write_error(": ");
    }
    _pep_write_error("panic: ");
    if (message == __null) {
        _pep_write_error("Assertion failed with no additional information");
    } else {
        _pep_write_error(message);
    }
    _pep_write_error("\n");
    debug._debug_panic_backtrace();
    abort();
}

# The panic backtrace's state: [0] is 1 when the build asks for a backtrace
# on panic (a build without `-O`: the compiler calls
# `_pep_set_backtrace_default` first thing in `main`), [1] is 1 once a
# panic has started printing one.
const _pep_backtrace_state: __ptr<int> = _pep_new_backtrace_state();

_pep_new_backtrace_state(): __ptr<int> {
    __ptr<int> state = _pep_malloc(8);
    state[0] = 0;
    state[1] = 0;
    return state;
}

# Called by the compiler at the start of `main` in a build without `-O`.
export _pep_set_backtrace_default() {
    if (_pep_backtrace_state == __null) {
        return;
    }
    __atomic_store<int>(_pep_backtrace_state, 1);
}

# Whether the build asks for a backtrace on panic when PEPPER_BACKTRACE is
# not set.
export _pep_backtrace_default(): bool {
    # Null when a module-scope initializer panics before this one ran.
    if (_pep_backtrace_state == __null) {
        return false;
    }
    return __atomic_load<int>(_pep_backtrace_state) == 1;
}

# Claims the one panic backtrace a process prints: false when another
# panic (a second thread, or a panic inside the symbolizer) already has.
export _pep_enter_backtrace(): bool {
    if (_pep_backtrace_state == __null) {
        return false;
    }
    return __atomic_cmpxchg<int>(_pep_backtrace_state + 1, 0, 1);
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
    ulong h = 0xcbf29ce484222325 ^ length;
    ulong i = 0;
    while (i + 8 <= length) {
        h = _pep_hash_step(h, _pep_hash_word(bytes, i, 8));
        i = i + 8;
    }
    if (i < length) {
        h = _pep_hash_step(h, _pep_hash_word(bytes, i, length - i));
    }
    h = __wrapping_mul(h ^ (h >> 33), 0xff51afd7ed558ccd);
    h = __wrapping_mul(h ^ (h >> 33), 0xc4ceb9fe1a85ec53);
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
    var mixed = __wrapping_mul(h ^ word, 0x9e3779b97f4a7c15);
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
    var (end, count) = _pep_utf8_scan(s, size, size);
    if (end != size) {
        return 0;
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

# The offset of the first byte from `i` up to (not including) `end` at `data`
# that is not ASCII (has its high bit set), or `end` when there is none.
# It tests sixteen bytes per step with a vector compare, whose bit mask's
# `trailing_zeros` is the first such byte (#517). It calls the intrinsics
# under `simd.Vector` directly: at `-O0` the vector's methods, even inlined,
# leave the loop several times slower than these few instructions.
_pep_ascii_end(data: __ptr<void>, i: ulong, end: ulong): ulong {
    __ptr<byte> bytes = unsafe_cast<__ptr<byte>>(data);
    var high_bit = __simd_splat<__simd<byte, 16>>(0x80 as byte);
    while (i + 16 <= end) {
        var chunk = __simd_load<__simd<byte, 16>>(bytes + i);
        var high = __simd_to_bits<__simd<bool, 16>>(__simd_greater_equal<__simd<byte, 16>>(chunk, high_bit));
        if (high != 0) {
            return i + high.trailing_zeros();
        }
        i = i + 16;
    }
    while (i < end) {
        if ((data[i] & 0x80) != 0) {
            return i;
        }
        i = i + 1;
    }
    return end;
}

# Reads UTF-8 from the start of the `size` bytes at `data` until it has
# counted `chars` code points, reached `size`, or met bytes that are not a
# whole valid sequence, and returns the byte offset it stopped at and the
# code points before it. So the bytes are valid UTF-8 exactly when the offset
# is `size` (with `chars` at least `size`). Every UTF-8 count and check goes
# through this one loop, with the decoding written out in it: a call per
# code point made CJK text about half again slower (#522). A run of eight
# ASCII bytes or more is handed to `_pep_ascii_end`, which skips it sixteen
# bytes at a time; shorter runs stay in the loop.
export _pep_utf8_scan(data: __ptr<void>, size: ulong, chars: ulong): (ulong, ulong) {
    ulong i = 0;
    ulong count = 0;
    ulong ascii_run = 0;
    while (i < size && count < chars) {
        # Byte reads are signed; mask to the unsigned value.
        var b = data[i] & 0xFF;
        if (b < 128) {
            i = i + 1;
            count = count + 1;
            ascii_run = ascii_run + 1;
            if (ascii_run == 8) {
                var end = size;
                if (chars - count < size - i) {
                    end = i + (chars - count);
                }
                var stop = _pep_ascii_end(data, i, end);
                count = count + (stop - i);
                i = stop;
                ascii_run = 0;
            }
            continue;
        }
        ascii_run = 0;
        # Each read is guarded by its own `if`, so none reads past `size`.
        if (b < 192) {
            break;
        }
        if (b < 224) {
            if (i + 2 > size) { break; }
            if ((data[i + 1] & 0xC0) != 0x80) { break; }
            i = i + 2;
        } else if (b < 240) {
            if (i + 3 > size) { break; }
            if ((data[i + 1] & 0xC0) != 0x80) { break; }
            if ((data[i + 2] & 0xC0) != 0x80) { break; }
            i = i + 3;
        } else if (b < 248) {
            if (i + 4 > size) { break; }
            if ((data[i + 1] & 0xC0) != 0x80) { break; }
            if ((data[i + 2] & 0xC0) != 0x80) { break; }
            if ((data[i + 3] & 0xC0) != 0x80) { break; }
            i = i + 4;
        } else {
            break;
        }
        count = count + 1;
    }
    return (i, count);
}

export _pep_utf8_valid(data: __ptr<void>, size: ulong): bool {
    if (data == __null || size == 0) { return true; }
    var (end, count) = _pep_utf8_scan(data, size, size);
    return end == size;
}

[Target(!OS(Windows))]
extern void* memmem(void* haystack, ulong haystack_size, void* needle, ulong needle_size);

# The first `needle` in the haystack, or `__null`. libc's `memmem` scans
# many bytes per step where it can.
[Target(!OS(Windows))]
_pep_memmem(haystack: __ptr<void>, haystack_size: ulong, needle: __ptr<void>, needle_size: ulong): __ptr<void> {
    return memmem(haystack, haystack_size, needle, needle_size);
}

extern void* memchr(void* p, int c, ulong n);

# The first `needle` in the haystack, or `__null`. The Windows C runtime has
# no `memmem`, so this jumps to candidates with `memchr`. When `memchr`'s hit
# comes within a few bytes, the first byte is common here, so it checks the
# next 32 bytes itself rather than pay a call per byte; when hits are sparse
# it stays with `memchr`. It compares the needle's last byte before calling
# `memcmp`.
[Target(OS(Windows))]
_pep_memmem(haystack: __ptr<void>, haystack_size: ulong, needle: __ptr<void>, needle_size: ulong): __ptr<void> {
    if (needle_size > haystack_size) {
        return __null;
    }
    # Byte reads are signed; mask to the unsigned value.
    var first = (needle[0] & 0xFF) as int;
    var tail = needle_size - 1;
    var final = (needle[tail] & 0xFF) as int;
    var last = haystack_size - needle_size;
    ulong i = 0;
    while (i <= last) {
        __ptr<void> found = memchr(haystack + i, first, last + 1 - i);
        if (found == __null) {
            return __null;
        }
        var at = unsafe_cast<ulong>(found) - unsafe_cast<ulong>(haystack);
        var window = at + 1;
        if (at - i < 8) {
            window = at + 32;
            if (window > last + 1) {
                window = last + 1;
            }
        }
        i = at;
        while (i < window) {
            if (((haystack[i] & 0xFF) as int) == first) {
                if (((haystack[i + tail] & 0xFF) as int) == final) {
                    if (memcmp(haystack + i, needle, needle_size) == 0) {
                        return haystack + i;
                    }
                }
            }
            i = i + 1;
        }
    }
    return __null;
}

# The byte offset of the first `needle` in the haystack, or -1, checking no
# UTF-8: callers that need the bytes before it checked check them themselves,
# as `_pep_utf8_find` does and as split and replace do while counting each
# piece's code points.
export _pep_utf8_search(haystack: __ptr<void>, haystack_size: ulong, needle: __ptr<void>, needle_size: ulong): long {
    if (haystack == __null || haystack_size == 0) { return -1; }
    if (needle_size == 0) { return 0; }
    if (needle == __null) { return -1; }
    __ptr<void> found = _pep_memmem(haystack, haystack_size, needle, needle_size);
    if (found == __null) {
        return -1;
    }
    return (unsafe_cast<ulong>(found) - unsafe_cast<ulong>(haystack)) as long;
}

# The byte offset of the first `needle` in the haystack, or -1. The needle
# must be valid UTF-8, and so must the haystack before the match. Only the
# bytes before the match are checked, once each, so repeated searches from
# successive offsets stay linear (#511); and a valid prefix ends on a code
# point boundary, so a match is only ever found at one.
export _pep_utf8_find(haystack: __ptr<void>, haystack_size: ulong, needle: __ptr<void>, needle_size: ulong): long {
    if (needle_size > 0 && !_pep_utf8_valid(needle, needle_size)) { return -1; }
    var at = _pep_utf8_search(haystack, haystack_size, needle, needle_size);
    if (at <= 0) {
        return at;
    }
    if (!_pep_utf8_valid(haystack, at as ulong)) {
        return -1;
    }
    return at;
}

export _pep_utf8_char_offset(data: __ptr<void>, size: ulong, chars: ulong): ulong {
    if (data == __null || size == 0) { return 0; }
    var (end, count) = _pep_utf8_scan(data, size, chars);
    if (end < size && count < chars) {
        # Stopped at bytes that are not valid UTF-8.
        return size;
    }
    return end;
}

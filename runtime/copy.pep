## Deep copies: `copy(value)` makes a copy that shares no object that is
## not thread-safe with the original, so it can be handed to another thread;
## `Copyable<T>` lets a type say how it is copied.

# `_Copies.copy<T>` is the `__copy<T>` intrinsic, which the compiler lowers
# once `T` is known (passes/copies.rs): to the value itself for a
# thread-safe `T`, and for a struct to `_copy_object<T>`, which calls the
# struct's `__copy()` method. The compiler synthesizes `__copy()`: it forwards
# to the struct's own `copy()` when it implements `Copyable<T>`, and
# otherwise copies field by field without running a constructor. A trait
# value goes to `_copy_trait<T>`, which calls the struct's
# `_pep_copy_trait` through the vtable. Anything else (a struct with a
# destructor or a raw pointer field, a plain function value) is a compile
# error at the code that asked for the copy.
#
# One `_Copies` is the context of the outermost `copy` call on a thread: the
# thread-local key `_copy_key()` points at its `_self` slot while it runs, so
# a `copy(x)` nested inside it (in a `Copyable<T>.copy()` implementation) and
# each synthesized `__copy()` find it with one thread-local read.
#
# `_made` maps each original object's address to its copy's. Every copy stays
# alive until `copy` returns: it is referenced from the copy of the object
# that contains it, and all of those from the copy being returned.

import "array";
import "hash";

extern void* malloc(ulong size);
[Target(!OS(Windows))]
extern int pthread_key_create(void* key, void* destructor);
[Target(!OS(Windows))]
extern void* pthread_getspecific(ulong key);
[Target(!OS(Windows))]
extern int pthread_setspecific(ulong key, void* value);
[Target(OS(Windows))]
extern uint TlsAlloc();
[Target(OS(Windows))]
extern void* TlsGetValue(uint index);
[Target(OS(Windows))]
extern int TlsSetValue(uint index, void* value);

# The thread-local key plus one, 0 until the first `copy` creates it. Made on
# first use, not at start: every program (and every JIT engine in a test
# run) loads this file, and the operating system has few keys.
const _copy_key_cell: __ptr<ulong> = _copy_new_key_cell();

# Plain `malloc`, not `_pep_malloc`: module constants may initialize before
# the allocation counter, and the cell lives as long as the program.
_copy_new_key_cell(): __ptr<ulong> {
    __ptr<ulong> cell = malloc(sizeof<ulong>());
    cell[0] = 0;
    return cell;
}

[Target(!OS(Windows))]
_copy_key_create(): ulong {
    __ptr<ulong> key = _pep_malloc(8);
    key[0] = 0;
    if (pthread_key_create(key, __null) != 0) {
        panic("copy: the operating system has no thread-local keys left");
    }
    ulong created = key[0];
    _pep_free(key);
    return created;
}

[Target(OS(Windows))]
_copy_key_create(): ulong {
    var index = TlsAlloc();
    # TLS_OUT_OF_INDEXES
    assert(index != 4294967295, "copy: the operating system has no thread-local keys left");
    return index as ulong;
}

[Target(!OS(Windows))]
_copy_key_get(key: ulong): __ptr<void> {
    return pthread_getspecific(key);
}

[Target(OS(Windows))]
_copy_key_get(key: ulong): __ptr<void> {
    return TlsGetValue(key as uint);
}

[Target(!OS(Windows))]
_copy_key_set(key: ulong, value: __ptr<void>) {
    pthread_setspecific(key, value);
}

[Target(OS(Windows))]
_copy_key_set(key: ulong, value: __ptr<void>) {
    TlsSetValue(key as uint, value);
}

# The thread-local key that points at the running copy's context. Two
# threads may race to make it; the loser's key is left unused.
_copy_key(): ulong {
    var key = __atomic_load<ulong>(_copy_key_cell);
    if (key != 0) {
        return key - 1;
    }
    ulong none = 0;
    __atomic_cmpxchg<ulong>(_copy_key_cell, none, _copy_key_create() + 1);
    return __atomic_load<ulong>(_copy_key_cell) - 1;
}

# The context of the copy running on this thread, or null when none is.
export _pep_copies(): _Copies {
    __ptr<void> raw = _copy_key_get(_copy_key());
    if (raw == __null) {
        return __default<_Copies>();
    }
    # The slot holds the context's address: reading it acquires a reference.
    __ptr<_Copies> slot = raw;
    return slot[0];
}

# Makes `copies` the context of this thread's copy and returns the one it
# replaces (null outside any copy), for `_copy_leave`.
_copy_enter(copies: _Copies): __ptr<void> {
    var key = _copy_key();
    var previous = _copy_key_get(key);
    copies._self[0] = copies._address<_Copies>(copies);
    _copy_key_set(key, copies._self);
    return previous;
}

# Points every copy's weak fields at copies, then restores the context
# `_copy_enter` replaced.
_copy_leave(copies: _Copies, previous: __ptr<void>) {
    copies._finish();
    _copy_key_set(_copy_key(), previous);
    copies._self[0] = 0;
}

## Returns a copy of `value` that shares no non-thread-safe object with it,
## so the copy can be handed to another thread.
##
## Every struct reachable from `value` whose type is not thread-safe is
## copied once. Objects referenced twice stay shared inside the copy, and
## cycles are preserved. Thread-safe objects (`[Shared]` structs, `shared`
## function values) are not copied: the copy references the same ones. A
## weak reference to a copied object points at its copy; a weak reference to
## an object outside the copied value becomes null.
##
## A struct is copied field by field, without running its constructor,
## unless it implements `Copyable<T>`. A struct with a destructor or a raw
## pointer field must implement `Copyable<T>` to be copied, since copying
## its fields would share what it owns; `String`, `Array`, `HashMap` and
## `HashSet` do. Copying such a struct that does not, or a plain function
## value, is a compile error.
##
## Called inside a `Copyable<T>.copy()` implementation while a copy is
## running, `copy` continues that copy: an object it already copied is not
## copied again.
##
## A trait value is copied by copying the struct behind it, which is known
## only at run time: when that struct cannot be copied, `copy` panics.
##
## Runs in O(size of the value) and allocates each copied object.
##
## @typeParam T the type of the value
## @param value the value to copy
## @returns a copy that shares no non-thread-safe object with `value`; `value` itself when `T` is thread-safe
## @panics if `value` reaches a trait value holding a struct that cannot be copied
## @example
##     var names = Array<String>();
##     names.append("ada");
##     var copied = copy(names);
##     copied[0].append(" lovelace");   # names[0] is still "ada"
export copy<T>(value: T): T {
    var running = _pep_copies();
    if (running !== __null) {
        return running.copy<T>(value);
    }
    var copies = _Copies();
    var previous = _copy_enter(copies);
    var result = copies.copy<T>(value);
    _copy_leave(copies, previous);
    return result;
}

## Records `made` as the copy of `original` in the running copy, so that
## copying `original` again returns `made`. A `Copyable<T>.copy()`
## implementation calls it before copying the values it holds when one of
## them may lead back to it; outside a copy it does nothing.
##
## @typeParam T the type of the value, a struct
## @param original the object being copied
## @param made its copy
## @example
##     copy(): Node {
##         var made = Node(value);
##         register_copy(this, made);   # a cycle back to this finds made
##         made.next = copy(next);
##         return made;
##     }
export register_copy<T>(original: T, made: T) {
    var running = _pep_copies();
    if (running !== __null) {
        running.register<T>(original, made);
    }
}

## Hands over the reference `value` holds and leaves it null, with no copy
## and no change to any count: the result is the same object.
##
## `value` must be a local variable (or a `[Move]` parameter) that holds
## the only reference to its value: nothing else may refer to it or to
## anything it reaches. The compiler checks that, and that the variable is
## not used again until it is assigned a new value. Use it to pass a value
## you built to a parameter that takes a new value, such as `Channel.send`
## or `Mutex.replace`, without the cost of `copy`.
##
## @typeParam T the type of the value
## @param value the variable to move from
## @returns the value `value` held, which nothing else references
## @example
##     var lines = Array<String>();
##     lines.append("first");
##     var log = async.Mutex<Array<String>>(move(lines));   # lines is null now
export move<T>([MoveSource] value: T): T {
    return value;
}

## A type that says how `copy` copies it, for a struct that `copy` cannot
## copy field by field: one with a destructor or a raw pointer field, such as
## a container that owns a buffer.
##
## Declare it with `extend Buffer with Copyable<Buffer>;` and give the
## struct a `copy(): Buffer` method. The method builds the copy and copies
## each struct value it holds with `copy(value)`, which, called while a copy
## is running, reuses a copy already made, so objects referenced twice stay
## shared.
##
## @typeParam T the implementing type
## @example
##     struct Buffer {
##         __ptr<u8> data;
##         ulong size;
##
##         construct(ulong size = 0) {
##             data = _pep_malloc(size);
##             this.size = size;
##         }
##
##         destruct {
##             _pep_free(data);
##         }
##
##         copy(): Buffer {
##             var made = Buffer(size);
##             var i: ulong = 0;
##             while (i < size) {
##                 made.data[i] = data[i];
##                 i = i + 1;
##             }
##             return made;
##         }
##     }
##
##     extend Buffer with Copyable<Buffer>;
export trait Copyable<T> {
    ## Returns a copy of this value, for `copy`.
    ##
    ## Copy each struct value this one holds with `copy(value)`. A value
    ## that can hold a reference back to itself calls
    ## `register_copy(this, made)` before copying what it holds, so the
    ## cycle leads back to the copy. Call `copy(x)`, not `x.copy()`, to copy
    ## a `Copyable` value: `copy(x)` keeps objects shared inside one copy.
    ##
    ## @returns the copy
    copy(): T;
}

## Deprecated: implement `Copyable<T>` as `copy(): T`, which copies what it
## holds with `copy(value)` and `register_copy(original, made)`.
##
## The context of a running copy, which a `Copyable<T>` implementation once
## took as `copy(copies: Copies): T`. Such an implementation still works
## for this release.
[Deprecated("implement 'Copyable<T>' as 'copy(): T', which copies what it holds with 'copy(value)'")]
export type Copies = _Copies;

# The objects one `copy` call has copied so far, so each is copied once:
# objects referenced twice stay shared inside the copy, and cycles end. The
# outermost `copy(value)` on a thread makes one and installs it as the
# thread's context (`_copy_enter`); `_pep_copies()` finds it.
export struct _Copies {
    # Maps the address of each object copied so far to its copy's address.
    HashMap<ulong, ulong> _made;

    # The copies whose weak fields to point at copies once everything is
    # copied.
    Array<DeferredFix> _later;

    # Scratch space for turning an address back into a reference.
    __ptr<ulong> _cell;

    # Holds this context's address while it is the thread's context: the
    # thread-local key points here.
    __ptr<ulong> _self;

    # For a `PEP_CHECK_SYNC` census (`_pep_check_sync`): how many of the
    # references the copy passed through lead to each original object, by
    # address. Null for an ordinary copy.
    HashMap<ulong, ulong> _edges;

    construct() {
        _made = HashMap<ulong, ulong>();
        _later = Array<DeferredFix>();
        _cell = _pep_malloc(sizeof<ulong>());
        _self = _pep_malloc(sizeof<ulong>());
        _self[0] = 0;
    }

    destruct {
        _pep_free(_cell);
        _pep_free(_self);
    }

    # The copy of `value`: `value` itself when `T` is thread-safe, the copy
    # already made when the same object was copied before, and a new copy
    # otherwise. (A deprecated `copy(copies: Copies)` implementation calls
    # it as `copies.copy(value)`.)
    copy<T>(value: T): T {
        return __copy<T>(value, this);
    }

    # Records `made` as the copy of `original`, so that copying `original`
    # again returns `made` (`register_copy`).
    register<T>(original: T, made: T) {
        _made.insert(this._address<T>(original), this._address<T>(made));
    }
    # The address of struct object `value`.
    _address<T>(value: T): ulong {
        __ptr<void> raw = value;
        return unsafe_cast<ulong>(raw);
    }

    # The copy of struct `value`: null for null, the copy already made of
    # the same object, or a new one from its `__copy()` method.
    _copy_object<T>(value: T): T {
        if (value === __null) {
            return value;
        }
        if (_edges !== __null) {
            var address = this._address<T>(value);
            # `get` gives 0 for an address not seen yet.
            _edges[address] = _edges.get(address) + 1;
        }
        var made = this._find<T>(value);
        if (made !== __null) {
            return made;
        }
        # `__copy_object<T>(value)` is `value.__copy()`, the method the
        # compiler synthesizes (passes/copies.rs).
        made = __copy_object<T>(value);
        this.register<T>(value, made);
        return made;
    }

    # The copy already made of `original`, or null.
    _find<T>(original: T): T {
        # One lookup: `get` gives 0, never an object's address, when
        # `original` was not copied.
        var made = _made.get(this._address<T>(original));
        if (made == 0) {
            return __default<T>();
        }
        # Read the address back as a reference: the read acquires it.
        _cell[0] = made;
        __ptr<void> raw = _cell;
        __ptr<T> slot = raw;
        T found = slot[0];
        _cell[0] = 0;
        return found;
    }

    # The copy of trait value `value`: null for null, else the copy of the
    # struct behind it, made by that struct's `_pep_copy_trait` method (which
    # the compiler adds to the trait and to each struct that declares it).
    _copy_trait<T>(value: T): T {
        if (value === __null) {
            return value;
        }
        return value._pep_copy_trait(this);
    }

    # A weak reference to the copy of `original`'s target, or a null one
    # when the target is gone or was not copied.
    _weak<T>(original: __weak<T>): __weak<T> {
        var target = __weak_upgrade<T>(original);
        if (target === __null) {
            return __default<__weak<T>>();
        }
        var made = this._find<T>(target);
        if (made === __null) {
            return __default<__weak<T>>();
        }
        return __weak_from<T>(made);
    }

    # Runs `fix` with these copies once everything is copied.
    _defer(fix: (_Copies) => void) {
        _later.append(DeferredFix(fix));
    }

    # Points every copy's weak fields at copies.
    _finish() {
        for (var deferred in _later) {
            deferred.run(this);
        }
        _later.clear();
    }
}

# A fix `_Copies._finish` runs. (An `Array` of a struct rather than of the
# function type itself: a program that declares a struct named `T` cannot
# specialize `Array<T>` with a function type yet.)
struct DeferredFix {
    (_Copies) => void run;

    construct(this.run = (copies: _Copies) => {}) {}
}

# What `__census<T>(slot, waiting)` lowers to in `MutexGuard.exit` for a `T` that can
# be copied (passes/copies.rs; for any other `T` it lowers to nothing). With
# `PEP_CHECK_SYNC` set (`_PEP_CHECK_SYNC_ON`), it copies the value in `slot`
# with a census that counts, for each original object, the references the copy passes through:
# each field and element that holds it, and the slot itself for the root.
# Once the copy is dropped, those are the only references the locked value
# may have, so an object whose strong count (the `u32` every struct object
# starts with) is higher is still referenced from outside it: a hole in the
# confinement checks, or a promise raw memory or extern code broke.
export _pep_check_sync<T>(slot: __ptr<T>, waiting: ulong, locked: __ptr<char>) {
    if (!_PEP_CHECK_SYNC_ON) {
        return;
    }
    var copies = _Copies();
    copies._edges = HashMap<ulong, ulong>();
    # Its own context, even inside a running copy: a `Copyable` method that
    # locks a Mutex runs this census in the middle of that copy.
    var previous = _copy_enter(copies);
    copies.copy<T>(slot[0]);
    _copy_leave(copies, previous);
    # Each holder sleeping in `Condition.wait` keeps its `with` binding, one
    # more reference to the root.
    var root = copies._address<T>(slot[0]);
    if (waiting != 0 && copies._edges.contains(root)) {
        copies._edges[root] = copies._edges.get(root) + waiting;
    }
    for (var (address, edges) in copies._edges) {
        copies._cell[0] = address;
        __ptr<void> raw = copies._cell;
        __ptr<__ptr<uint>> object = raw;
        var count = object[0][0];
        if (count as ulong != edges) {
            panic(
                "PEP_CHECK_SYNC: an object in the value locked by a '"
                    + String(locked)
                    + "' is still referenced from outside it"
            );
        }
    }
    copies._cell[0] = 0;
}

# What `__copy<T>` lowers to where `T` cannot be copied and nothing the
# program asks for copies one (a `Copyable` container of such values that is
# never copied): reaching it is a bug in the compiler's check.
export _pep_copy_failed<T>(message: __ptr<char>): T {
    _pep_panic(message, __null);
    return __default<T>();
}

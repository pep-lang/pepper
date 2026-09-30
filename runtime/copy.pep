## Deep copies: `copy(value)` makes a copy that shares no object that is
## not thread-safe with the original, so it can be handed to another thread;
## `Copyable<T>` lets a type say how it is copied.

# `Copies.copy<T>` is the `__copy<T>` intrinsic, which the compiler lowers
# once `T` is known (passes/copies.rs): to the value itself for a
# thread-safe `T`, and for a struct to `_copy_object<T>`, which calls the
# struct's `_pep_copy` method. The compiler synthesizes `_pep_copy`: it forwards to
# the struct's own `copy(Copies)` when it implements `Copyable<T>`, and
# otherwise copies field by field without running a constructor. Anything
# else (a struct with a destructor or a raw pointer field, a plain function
# value, a trait value) is a compile error at the code that asked for the
# copy.
#
# `_made` maps each original object's address to its copy's. Every copy stays
# alive until `copy` returns: it is referenced from the copy of the object
# that contains it, and all of those from the copy being returned.

import "array";
import "hash";

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
## `HashSet` do. Copying such a struct that does not, a plain function value
## or a trait value is a compile error.
##
## Runs in O(size of the value) and allocates each copied object.
##
## @typeParam T the type of the value
## @param value the value to copy
## @returns a copy that shares no non-thread-safe object with `value`; `value` itself when `T` is thread-safe
## @example
##     var names = Array<String>();
##     names.append("ada");
##     var copied = copy(names);
##     copied[0].append(" lovelace");   # names[0] is still "ada"
export copy<T>(value: T): T {
    var copies = Copies();
    var result = copies.copy<T>(value);
    copies._finish();
    return result;
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
## Declare it with `extend Buffer with Copyable<Buffer> {}` and give the
## struct a `copy(Copies copies)` method. The method builds the copy and
## copies each value it holds with `copies.copy(value)`, which reuses a copy
## already made, so objects referenced twice stay shared.
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
##         Buffer copy(Copies copies) {
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
##     extend Buffer with Copyable<Buffer> {}
export trait Copyable<T> {
    ## Returns a copy of this value, for `copy`.
    ##
    ## Copy each struct value this one holds with `copies.copy(value)`. A
    ## value that can hold a reference back to itself calls
    ## `copies.register(this, made)` before copying what it holds, so the
    ## cycle leads back to the copy.
    ##
    ## @param copies the objects copied so far
    ## @returns the copy
    copy(copies: Copies): T;
}

## The objects one `copy` call has copied so far, so each is copied once:
## objects referenced twice stay shared inside the copy, and cycles end.
##
## `copy(value)` makes one and passes it to every `Copyable<T>`
## implementation it calls; programs do not create their own.
export struct Copies {
    ## Maps the address of each object copied so far to its copy's address.
    HashMap<ulong, ulong> _made;

    ## The copies whose weak fields to point at copies once everything is
    ## copied.
    Array<DeferredFix> _later;

    ## Scratch space for turning an address back into a reference.
    __ptr<ulong> _cell;

    ## For a `PEP_CHECK_SYNC` census (`_pep_check_sync`): how many of the
    ## references the copy passed through lead to each original object, by
    ## address. Null for an ordinary copy.
    HashMap<ulong, ulong> _edges;

    ## Creates an empty set of copies.
    construct() {
        _made = HashMap<ulong, ulong>();
        _later = Array<DeferredFix>();
        _cell = _pep_malloc(sizeof<ulong>());
    }

    destruct {
        _pep_free(_cell);
    }

    ## Returns the copy of `value`: `value` itself when `T` is thread-safe,
    ## the copy already made when the same object was copied before, and a
    ## new copy otherwise.
    ##
    ## @typeParam T the type of the value
    ## @param value the value to copy
    ## @returns the copy
    ## @example
    ##     Pair copy(Copies copies) {
    ##         return Pair(copies.copy(first), copies.copy(second));
    ##     }
    copy<T>(value: T): T {
        return __copy<T>(value, this);
    }

    ## Records `made` as the copy of `original`, so that copying `original`
    ## again returns `made`. A `Copyable<T>` implementation calls it before
    ## copying the values it holds when one of them may lead back to it.
    ##
    ## @typeParam T the type of the value, a struct
    ## @param original the object being copied
    ## @param made its copy
    register<T>(original: T, made: T) {
        _made.insert(this._address<T>(original), this._address<T>(made));
    }

    # The address of struct object `value`.
    _address<T>(value: T): ulong {
        __ptr<void> raw = value;
        return raw as ulong;
    }

    # The copy of struct `value`: null for null, the copy already made of
    # the same object, or a new one from its `_pep_copy` method.
    _copy_object<T>(value: T): T {
        if (value === __null) {
            return value;
        }
        if (_edges !== __null) {
            var address = this._address<T>(value);
            _edges[address] = (_edges.contains(address) ? _edges.get(address) : 0) + 1;
        }
        var made = this._find<T>(value);
        if (made !== __null) {
            return made;
        }
        made = value._pep_copy(this);
        this.register<T>(value, made);
        return made;
    }

    # The copy already made of `original`, or null.
    _find<T>(original: T): T {
        var address = this._address<T>(original);
        if (!_made.contains(address)) {
            return __default<T>();
        }
        # Read the address back as a reference: the read acquires it.
        _cell[0] = _made.get(address);
        __ptr<void> raw = _cell;
        __ptr<T> slot = raw;
        T found = slot[0];
        _cell[0] = 0;
        return found;
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
    _defer(fix: (Copies) => void) {
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

# A fix `Copies._finish` runs. (An `Array` of a struct rather than of the
# function type itself: a program that declares a struct named `T` cannot
# specialize `Array<T>` with a function type yet.)
struct DeferredFix {
    (Copies) => void run;

    construct(this.run = (copies: Copies) => {}) {}
}

# What `__census<T>(slot)` lowers to in `MutexGuard.exit` for a `T` that can
# be copied (passes/copies.rs; for any other `T` it lowers to nothing). With
# `PEP_CHECK_SYNC` set (`_PEP_CHECK_SYNC_ON`), it copies the value in `slot`
# with a census that counts, for each original object, the references the copy passes through:
# each field and element that holds it, and the slot itself for the root.
# Once the copy is dropped, those are the only references the locked value
# may have, so an object whose strong count (the `u32` every struct object
# starts with) is higher is still referenced from outside it: a hole in the
# confinement checks, or a promise raw memory or extern code broke.
export _pep_check_sync<T>(slot: __ptr<T>, locked: __ptr<char>) {
    if (!_PEP_CHECK_SYNC_ON) {
        return;
    }
    var copies = Copies();
    copies._edges = HashMap<ulong, ulong>();
    copies.copy<T>(slot[0]);
    copies._finish();
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
    _pep_panic(message);
    return __default<T>();
}

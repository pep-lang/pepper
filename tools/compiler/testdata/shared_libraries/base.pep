# A Pepper shared library that `top` and the program import: a global
# set by a call, a struct the others fill, and a thread-local whose
# release counts.

import async;

export const released = async.Atomic<int>(0);
export const START: int = _compute();

_compute(): int {
    return 40;
}

## A list of names, which each image appends to.
export struct Box {
    var items: String[];

    construct() {
        items = Array<String>();
    }

    add(name: String) {
        items.append(name);
    }
}

[Shared]
struct Badge {
    const number: int;

    construct(number: int) {
        this.number = number;
    }

    destruct {
        released.fetch_add(1);
    }
}

[ThreadLocal]
var _badge: Badge;

[ThreadLocal]
var _calls: int = 0;

export make_box(): Box {
    var box = Box();
    box.add("base");
    return box;
}

export set_badge(number: int) {
    _badge = Badge(number);
}

export allocations(): long {
    return _pep_live_allocs();
}

## Counts two calls on this thread: a generic, so the program compiles it,
## and reaches `_calls` across the libraries (on Windows, through the
## accessor `base` exports).
export count_twice<T>(): int {
    _calls += 2;
    return _calls;
}

export count_call(): int {
    _calls += 1;
    return _calls;
}

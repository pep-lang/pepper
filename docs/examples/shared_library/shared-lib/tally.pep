## A count kept by a Pepper shared library: a global the program reads,
## and a struct the library makes, fills and hands over.

import async;

## How many names were added, on every thread.
export const total = async.Atomic<int>(0);

## The names added so far.
export struct Tally {
    var names: String[];

    construct() {
        names = Array<String>();
    }

    ## Adds `name`, and counts it in `total`.
    add(name: String) {
        names.append(name);
        total.fetch_add(1);
    }
}

## Returns a tally that already holds `first`.
export starting(first: String): Tally {
    var tally = Tally();
    tally.add(first);
    return tally;
}

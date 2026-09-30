# An iterator: next() advances, current() returns the element.
struct Countdown {
    int remaining;
    int now;

    construct(this.remaining = 0) {}

    bool next() {
        if (remaining == 0) {
            return false;
        }
        now = remaining;
        remaining = remaining - 1;
        return true;
    }

    int current() {
        return now;
    }
}

# Declaring the trait documents the intent; the loop goes by the methods.
extend Countdown with Iterator<int> {}

# An iterable: iterate() hands out a fresh iterator for each loop.
struct Evens {
    int limit;

    construct(this.limit = 0) {}

    EvensIterator iterate() {
        var it = EvensIterator();
        it.limit = limit;
        it.now = -2;
        return it;
    }
}

struct EvensIterator {
    int limit;
    int now;

    bool next() {
        now = now + 2;
        return now < limit;
    }

    int current() {
        return now;
    }
}

extend EvensIterator with Iterator<int> {}
extend Evens with Iterable<int> {}

# A generic function can loop over any type that supports the protocol.
sum<C>(C values): int {
    var total = 0;
    for (var v in values) {
        total = total + v;
    }
    return total;
}

main(): int {
    var total = 0;
    for (var n in Countdown(3)) {
        total = total + n;
    }
    assert(total == 6, "3 + 2 + 1");

    # A loop over an iterator in a variable uses that object up.
    var c = Countdown(2);
    for (var n in c) {
        total = total + n;
    }
    assert(!c.next(), "the countdown is exhausted");

    # An iterable starts a new pass every time.
    var evens = Evens(10);
    assert(sum<Evens>(evens) == 20, "0 + 2 + 4 + 6 + 8");
    assert(sum<Evens>(evens) == 20, "a second pass sees the same elements");

    var nums = Array<int>();
    nums.append(30);
    nums.append(12);
    assert(sum<Array<int>>(nums) == 42, "arrays work too");
    return 0;
}

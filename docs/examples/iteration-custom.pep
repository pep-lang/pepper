# An iterator: next() advances, current() returns the element.
struct Countdown {
    int Remaining;
    int Now;

    construct(this.Remaining = 0) {}

    bool next() {
        if (Remaining == 0) {
            return false;
        }
        Now = Remaining;
        Remaining = Remaining - 1;
        return true;
    }

    int current() {
        return Now;
    }
}

# Declaring the trait documents the intent; the loop goes by the methods.
extend Countdown with Iterator<int> {}

# An iterable: iterate() hands out a fresh iterator for each loop.
struct Evens {
    int Limit;

    construct(this.Limit = 0) {}

    EvensIterator iterate() {
        var it = EvensIterator();
        it.Limit = Limit;
        it.Now = -2;
        return it;
    }
}

struct EvensIterator {
    int Limit;
    int Now;

    bool next() {
        Now = Now + 2;
        return Now < Limit;
    }

    int current() {
        return Now;
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

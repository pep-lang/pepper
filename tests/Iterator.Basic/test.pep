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

extend Countdown with Iterator<int> {}

main(): int {
    # Array<T> is Iterable<T>.
    var nums = Array<int>();
    nums.append(1);
    nums.append(2);
    nums.append(3);
    var total = 0;
    for (var x in nums) {
        total = total + x;
    }
    if (total != 6) { return 1; }

    # A type with next()/current() is its own iterator.
    for (int n in Countdown(3)) {
        total = total + n;
    }
    if (total != 12) { return 2; }

    # String is Iterable<String>, one code point at a time.
    var count = 0;
    for (var c in "añb") {
        count = count + 1;
    }
    if (count != 3) { return 3; }
    return 0;
}

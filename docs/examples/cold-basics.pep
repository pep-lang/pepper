# A hot method with its rare work split out into a [Cold] one.
struct Counter {
    var count: int;
    var wraps: int;

    construct() {
        count = 0;
        wraps = 0;
    }

    # Called on every event: small enough to inline.
    add() {
        if (count == 1000) {
            _wrap();
        }
        count += 1;
    }

    # Called once per thousand events: kept out of line.
    [Cold]
    _wrap() {
        count = 0;
        wraps += 1;
    }
}

main(): int {
    var counter = Counter();
    for (var index in 0..2500) {
        counter.add();
    }
    assert(counter.wraps == 2 && counter.count == 500, "[Cold] changes nothing the program computes");
    return 0;
}

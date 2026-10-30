# A bare `return;` leaves a constructor early with the object as set so
# far: its fields keep their defaults past the return (#306). It works in
# a nested block, a loop, a value struct, and a constructor of several.

struct Counter {
    var count: int;
    var name: String = "none";

    construct(start: int) {
        if (start < 0) {
            return;
        }
        count = start;
        name = "set";
    }

    construct(start: int, limit: int) {
        while (count < limit) {
            if (count == start) {
                return;
            }
            count += 1;
        }
        name = "full";
    }
}

[Value]
struct Pair {
    var a: int;
    var b: int = 7;

    construct(a: int) {
        this.a = a;
        if (a == 0) {
            return;
        }
        b = a * 2;
    }
}

run(): int {
    var set = Counter(3);
    if (set.count != 3 or set.name != "set") {
        return 1;
    }
    var early = Counter(-1);
    if (early.count != 0 or early.name != "none") {
        return 2;
    }
    var looped = Counter(2, 5);
    if (looped.count != 2 or looped.name != "none") {
        return 3;
    }
    if (Counter(9, 4).name != "full") {
        return 4;
    }
    var zero = Pair(0);
    if (zero.a != 0 or zero.b != 7 or Pair(3).b != 6) {
        return 5;
    }
    return 0;
}

main(): int {
    var before = _pep_live_allocs();
    var result = run();
    if (result == 0 and _pep_live_allocs() != before) {
        return 6;
    }
    return result;
}

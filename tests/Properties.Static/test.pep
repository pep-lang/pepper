# Static properties (#406): S.P reads the getter, S.P = v, += and ++ the
# setter; in an extension; a bare P in the struct's own code.

import async;

const _count = async.Atomic<int>(0);

struct Counter {
    var x: int;

    static var total: int {
        get { return _count.load(); }
        set {
            _count.store(value);
        }
    }

    static var label: String {
        get { return "counter"; }
    }

    # A bare name in the struct's own code.
    describe(): String {
        return $"{label} {total}";
    }
}

struct Color {
    var r: int;

    construct(this.r = 0) {}
}

extend Color {
    static var red: Color {
        get { return Color(255); }
    }
}

main(): int {
    assert(Counter.label == "counter", "read");
    Counter.total = 5;
    assert(Counter.total == 5, "write");
    Counter.total += 2;
    assert(Counter.total == 7, "compound");
    Counter.total++;
    assert(Counter.total == 8, "increment");
    assert(Color.red.r == 255, "extension");
    assert(Counter().describe() == "counter 8", "bare name");
    return 0;
}

# A Pepper library a program imports (`pepper_library_test.pep`, #220):
# a trait with a default method, a value struct, a struct that conforms in
# an extension, a shared struct, an exported extension of a runtime type,
# a generic the library instantiates too, a global set by a call, and a
# deprecated function.

import async;

export trait Shape {
    area(): int;

    describe(): String {
        return $"area {area()}";
    }
}

[Value]
export struct Point {
    var x: int;
    var y: int;

    construct(x: int, y: int) {
        this.x = x;
        this.y = y;
    }
}

export struct Square {
    var side: int;

    construct(side: int) {
        this.side = side;
    }
}

extend Square with Shape {
    area(): int {
        return side * side;
    }
}

[Shared]
export struct Counter {
    const hits: async.Atomic<int> = async.Atomic<int>(0);
}

export extend String {
    shout(): String {
        return this + "!";
    }
}

export pair<T>(value: T): T[] {
    return [value, value];
}

export sum(points: Point[]): int {
    var total = 0;
    for (var p in points) {
        total += p.x + p.y;
    }
    return total;
}

[Deprecated("use 'sum' instead", "sum")]
export old_sum(points: Point[]): int {
    return sum(points);
}

const ANSWER: int = _answer();

_answer(): int {
    return pair("hi").count * 21;
}

export answer(): int {
    return ANSWER;
}

main(): int {
    return 1;
}

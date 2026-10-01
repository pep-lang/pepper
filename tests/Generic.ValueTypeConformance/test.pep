# Numbers, `bool` and enums whose cases carry no values conform to traits
# through `extend`, dispatched statically: instance and static methods,
# trait defaults, calls through a constrained `T`, overloads beside a
# non-generic member, and conditional conformance of a generic struct.

trait Doubled {
    doubled(): int;
    static zero(): this;
    twice(): int { return doubled() * 2; }
}

extend int with Doubled {
    doubled(): int { return this * 2; }
    static zero(): int { return 0; }
}

trait Flag {
    flag(): int;
}

extend bool with Flag {
    flag(): int { return this ? 1 : 0; }
}

extend byte {
    high(): bool { return this > 127; }
}

enum Light {
    Red,
    Green,
}

extend Light with Flag {
    flag(): int { return this == Light.Green ? 1 : 0; }
}

total<T: Doubled>(items: Array<T>): int {
    var sum = 0;
    for (var item in items) {
        sum += item.doubled();
    }
    return sum + T.zero().doubled();
}

flags<T: Flag>(a: T, b: T): int { return a.flag() + b.flag(); }

pick<T: Doubled>(x: T): int { return 1; }
pick(x: long): int { return 2; }

trait Unused {
    unused(): int;
}

# int does not conform to Unused, so only the long overload is viable.
choose<T: Unused>(x: T): int { return 1; }
choose(x: long): int { return 2; }

struct Box<T> {
    var item: T;
    construct(item: T) { this.item = item; }
}

extend Box<T: Doubled> with Flag {
    flag(): int { return item.twice(); }
}

main(): int {
    var x = 3;
    if (x.doubled() != 6 or x.twice() != 12 or int.zero() != 0) {
        return 1;
    }
    var items = Array<int>();
    items.append(1);
    items.append(2);
    if (total(items) != 6) {
        return 2;
    }
    if (flags(true, false) != 1 or flags(Light.Green, Light.Green) != 2) {
        return 3;
    }
    var b: byte = 200;
    if (!b.high()) {
        return 4;
    }
    # int conforms, so the generic's exact match beats widening to long.
    if (pick(x) != 1) {
        return 5;
    }
    if (choose(x) != 2) {
        return 7;
    }
    if (flags(Box<int>(1), Box<int>(2)) != 12) {
        return 6;
    }
    return 0;
}

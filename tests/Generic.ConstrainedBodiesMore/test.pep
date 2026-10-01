# More constrained bodies that must compile: a `for` over a value
# constrained `Iterable<X>`, a method used as a value, a generic trait
# method, a trait with two parameters, an `[Implicit]` conversion of a
# number, and a static call through a constrained struct's parameter.

trait Num {
    value(): int;
    static zero(): this;
}

struct N {
    var v: int = 0;
    construct(this.v = 0) {}
    value(): int { return v; }
    static zero(): N { return N(0); }
}

extend N with Num {}

struct Bag {
    var items = Array<int>();
    iterate(): ArrayIterator<int> { return items.iterate(); }
}

extend Bag with Iterable<int> {}

sum_all<C: Iterable<int>>(bag: C): int {
    var total = 0;
    for (var v in bag) {
        total += v;
    }
    return total;
}

reader<T: Num>(x: T): int {
    var g: () => int = x.value;
    return g();
}

trait Sink {
    put<U>(value: U): int { return 1; }
}

struct Basin {
}

extend Basin with Sink {}

pour<S: Sink>(s: S): int { return s.put<int>(5) + s.put(7); }

trait Pair<T, U> {
    put(t: T): int;
}

struct Holder {
    put(t: String): int { return 3; }
}

extend Holder with Pair<String, int> {}

store<U, X: Pair<U, int>>(x: X, u: U): int { return x.put(u); }

struct Big {
    var v: long = 0;
    [Implicit]
    construct(v: long) { this.v = v; }
}

trait Taker {
    take(b: Big): int;
}

struct Hand {
    take(b: Big): int { return b.v as int; }
}

extend Hand with Taker {}

give<T: Taker>(t: T): int { return t.take(5); }

struct Shelf<T: Num> {
    var count: int = 2;
    first(): int { return T.zero().value() + count; }
}

main(): int {
    var bag = Bag();
    bag.items.append(2);
    bag.items.append(3);
    if (sum_all(bag) != 5) {
        return 1;
    }
    if (reader(N(4)) != 4) {
        return 2;
    }
    if (pour(Basin()) != 2) {
        return 3;
    }
    if (store<String, Holder>(Holder(), "x") != 3) {
        return 4;
    }
    if (give(Hand()) != 5) {
        return 5;
    }
    if (Shelf<N>().first() != 2) {
        return 6;
    }
    return 0;
}

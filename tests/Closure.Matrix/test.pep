# Closures that return a struct (an ArrayIterator) where the slot's function
# type returns a trait (`Iterator<U>`), in every combination of
#   kind: uses its parameter, ignores it, captures a local;
#   slot: plain function, generic function, generic method, struct field,
#         constructor argument;
# with the generic function also given an array literal beside the closure
#.

# How many elements `make` gives for each of `items`, in total.
count_all(items: Array<int>, make: (int) => Iterator<int>): int {
    var total = 0;
    for (var item in items) {
        var inner = make(item);
        while (inner.next()) {
            total = total + inner.current();
        }
    }
    return total;
}

count_generic<T, U>(items: T[], make: (T) => Iterator<U>, value: (U) => int): int {
    var total = 0;
    for (var item in items) {
        var inner = make(item);
        while (inner.next()) {
            total = total + value(inner.current());
        }
    }
    return total;
}

struct Items {
    Array<int> items;

    construct(items: Array<int>) {
        this.items = items;
    }

    count_method<U>(make: (int) => Iterator<U>, value: (U) => int): int {
        return count_generic(items, make, value);
    }
}

struct Holder<T, U> {
    (T) => Iterator<U> make;

    construct(make: (T) => Iterator<U>) {
        this.make = make;
    }

    count(items: T[], value: (U) => int): int {
        return count_generic(items, make, value);
    }
}

main(): int {
    var items = [1, 2];
    var extra = [10, 20];

    # Plain function: uses, ignores, captures.
    if (count_all(items, (n) => [n, n].iterate()) != 6) { return 1; }
    if (count_all(items, (n) => [5].iterate()) != 10) { return 2; }
    if (count_all(items, (n) => extra.iterate()) != 60) { return 3; }

    # Generic function, with an array variable and with an array literal.
    if (count_generic(items, (n) => [n, n].iterate(), (u) => u) != 6) { return 4; }
    if (count_generic(items, (n) => [5].iterate(), (u) => u) != 10) { return 5; }
    if (count_generic(items, (n) => extra.iterate(), (u) => u) != 60) { return 6; }
    if (count_generic([1, 2], (n) => [n, n].iterate(), (u) => u) != 6) { return 7; }
    if (count_generic([1, 2], (n) => [5].iterate(), (u) => u) != 10) { return 8; }
    if (count_generic([1, 2], (n) => extra.iterate(), (u) => u) != 60) { return 9; }

    # Generic method.
    var box = Items(items);
    if (box.count_method((n) => [n, n].iterate(), (u) => u) != 6) { return 10; }
    if (box.count_method((n) => [5].iterate(), (u) => u) != 10) { return 11; }
    if (box.count_method((n) => extra.iterate(), (u) => u) != 60) { return 12; }

    # Constructor argument.
    if (Holder<int, int>((n) => [n, n].iterate()).count(items, (u) => u) != 6) { return 13; }
    if (Holder<int, int>((n) => [5].iterate()).count(items, (u) => u) != 10) { return 14; }
    if (Holder<int, int>((n) => extra.iterate()).count(items, (u) => u) != 60) { return 15; }

    # Struct field, assigned after construction.
    var holder = Holder<int, int>((n) => [0].iterate());
    holder.make = (n) => [n, n].iterate();
    if (holder.count(items, (u) => u) != 6) { return 16; }
    holder.make = (n) => [5].iterate();
    if (holder.count(items, (u) => u) != 10) { return 17; }
    holder.make = (n) => extra.iterate();
    if (holder.count(items, (u) => u) != 60) { return 18; }

    # A struct of another element type: `U` is String.
    if (count_generic(["ab", "c"], (s) => [s, s].iterate(), (u) => u.size as int) != 6) { return 19; }
    return 0;
}

# A closure whose body returns a struct is accepted where the function type
# returns a trait the struct declares, also when the trait's type arguments
# are inferred from that struct (#992).

struct Numbers {
    Array<int> items;
    ulong at;

    construct(items: Array<int>) {
        this.items = items;
    }

    next(): bool {
        if (at >= items.count) {
            return false;
        }
        at = at + 1;
        return true;
    }

    current(): int {
        return items[at - 1];
    }

    # Sums every element of the iterator `make` returns for each element.
    sum_inner<U>(make: (int) => Iterator<U>, value: (U) => int): int {
        var total = 0;
        while (next()) {
            var inner = make(current());
            while (inner.next()) {
                total = total + value(inner.current());
            }
        }
        return total;
    }
}

extend Numbers with Iterator<int> {}

count_inner<T, U>(items: Array<T>, make: (T) => Iterator<U>): int {
    var count = 0;
    for (var item in items) {
        var inner = make(item);
        while (inner.next()) {
            count = count + 1;
        }
    }
    return count;
}

count_all(items: Array<int>, make: (int) => Iterator<int>): int {
    return count_inner<int, int>(items, make);
}

main(): int {
    # A non-generic slot.
    if (count_all([1, 2], (n) => [n, n].iterate()) != 4) {
        return 1;
    }
    # A generic function: `U` is bound by the struct the closure returns.
    var items = [1, 2, 3];
    if (count_inner(items, (n) => [n].iterate()) != 3) {
        return 2;
    }
    # A generic method.
    if (Numbers([1, 2]).sum_inner((n) => [n, n].iterate(), (u) => u) != 6) {
        return 3;
    }
    return 0;
}

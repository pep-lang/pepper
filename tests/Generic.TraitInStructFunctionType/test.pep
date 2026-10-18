# A generic struct whose members name its parameters inside a function
# type that returns a trait (`(T) => Iterator<U>`) compiles, also when
# unused, and a closure whose body names no parameter, so its struct result
# is known first, still returns the slot's trait (#949).

# Never used: its members alone used to fail with "unknown type name 'U'".
struct Unused<T, U> {
    () => Iterator<U> make;

    run(make: (T) => Iterator<U>): int {
        return 0;
    }
}

struct Counter<T, U> {
    (T) => Iterator<U> make;

    construct(make: (T) => Iterator<U>) {
        this.make = make;
    }

    count(item: T): int {
        var inner = make(item);
        var total = 0;
        while (inner.next()) {
            total = total + 1;
        }
        return total;
    }
}

count_inner<T, U>(item: T, make: (T) => Iterator<U>): int {
    return Counter<T, U>(make).count(item);
}

main(): int {
    if (Counter<String, String>((w) => w.iterate()).count("abc") != 3) {
        return 1;
    }
    # The bodies name no parameter.
    var items = [1, 2];
    if (Counter<String, int>((w) => items.iterate()).count("x") != 2) {
        return 2;
    }
    if (count_inner("x", (w) => items.iterate()) != 2) {
        return 3;
    }
    if (count_inner("x", (w) => (1..>3)) != 3) {
        return 4;
    }
    return 0;
}

# A tuple literal in a generic body whose element calls an overload set
# that `T` decides between (pepper#75): the base cannot spell the tuple's
# type, each specialization does.
enum Value {
    Null,
    Text(value: String),
}

wrap(value: String): Value {
    return Value.Text(value);
}

wrap(value: Value): Value {
    return value;
}

pair_of<T>(value: T): (int, Value) {
    return (1, wrap(value));
}

labeled_of<T>(value: T): (count: int, item: Value) {
    return (count: 2, item: wrap(value));
}

same<T>(value: T): T {
    return value;
}

# An argument, and an element calling a generic function.
entries_of<T>(value: T): Array<(int, Value)> {
    var entries = Array<(int, Value)>();
    entries.append((4, wrap(same(value))));
    return entries;
}

struct Wrapper {
    pair_of<T>(value: T): (int, Value) {
        return (3, wrap(value));
    }
}

main(): int {
    if (pair_of("a").0 != 1 or !(pair_of(Value.Null).1 is Null)) {
        return 1;
    }
    var labeled = labeled_of("b");
    if (labeled.count != 2 or !(labeled.item is Text(_))) {
        return 2;
    }
    if (Wrapper().pair_of("c").0 != 3) {
        return 3;
    }
    if (entries_of("d")[0].0 != 4) {
        return 4;
    }
    return 0;
}

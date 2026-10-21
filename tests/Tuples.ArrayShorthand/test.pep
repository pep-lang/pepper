# The `T[]` shorthand after a tuple type (pepper#117): `(String, int)[]` is
# `Array<(String, int)>`, as a return type, a parameter, a local and a field.
pairs(): (String, int)[] {
    return [("a", 1)];
}

total(entries: (name: String, count: int)[]): int {
    var sum = 0;
    for (var entry in entries) {
        sum += entry.count;
    }
    return sum;
}

struct Table {
    var rows: (int, int)[][] = [];
}

main(): int {
    if (pairs().count != 1 or pairs()[0].1 != 1) {
        return 1;
    }
    var local: (String, int)[] = [("b", 2)];
    if (local[0].0 != "b" or total([("c", 3), ("d", 4)]) != 7) {
        return 2;
    }
    var table = Table();
    table.rows.append([(1, 2)]);
    if (table.rows[0][0].1 != 2) {
        return 3;
    }
    var maybe: (int, int)[]? = Optional<(int, int)[]>.Value([(4, 5)]);
    if (maybe.value()[0].0 != 4) {
        return 4;
    }
    return 0;
}

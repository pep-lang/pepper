# Labels name a tuple's elements.
position(): (line: int, column: int) {
    return (line: 3, column: 7);
}

# A generic function hands back the labels of its type argument.
first_of<T>(items: Array<T>): T {
    return items[0];
}

struct Token {
    var text: String = "";
    var at: (line: int, column: int);
}

main(): int {
    var p = position();
    assert(p.line == 3 && p.column == 7, "read by label");
    assert(p.0 == 3, "positions still work");

    # Labeled and unlabeled tuples convert to each other.
    var plain: (int, int) = p;
    assert(plain.1 == 7, "same elements");

    # A labeled value carries its labels into the variable's type.
    var end = (line: 4, column: 1);
    assert(end.line == p.line + 1, "labeled literal");

    var t = Token();
    t.at = (5, 6);
    assert(t.at.column == 6, "a labeled field");

    # Labels pass through a type argument.
    var counts = Array<(word: String, count: int)>();
    counts.append((word: "tuple", count: 2));
    assert(counts[0].count == 2, "a labeled element");
    var found = Optional<(line: int, column: int)>.Value(p);
    assert(found.value().column == 7, "through an enum case");
    assert(first_of(counts).count == 2, "through a generic function");
    return 0;
}

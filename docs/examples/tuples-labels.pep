# Labels name a tuple's elements.
position(): (line: int, column: int) {
    return (3, 7);
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

    var t = Token();
    t.at = (5, 6);
    assert(t.at.column == 6, "a labeled field");
    return 0;
}

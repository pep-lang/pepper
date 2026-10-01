# A value struct compares and hashes by its fields with no code at all.
[Value]
struct Cell {
    int row;
    int column;

    construct(this.row = 0, this.column = 0) {}
}

# A value struct may still declare its own pair, here to ignore case.
[Value]
struct Tag {
    String text;

    construct(this.text = "") {}

    ==(other: Tag): bool {
        return text.lower() == other.text.lower();
    }
}

hash<Tag>(value: Tag): u64 {
    return hash<String>(value.text.lower());
}

main(): int {
    var board = HashMap<Cell, String>();
    board[Cell(0, 0)] = "rook";
    assert(board[Cell(0, 0)] == "rook", "fields decide");

    var tags = HashSet<Tag>();
    tags.insert(Tag("Pepper"));
    assert(tags.contains(Tag("PEPPER")), "case is ignored");
    return 0;
}

import "inventory";

main(): int {
    var s = Stock(2);
    assert(s.low(), "two is below the restock level");
    assert(s.missing() == 3, "three more reach it");
    # `needs_restock(...)` here would be an error: it is internal to the
    # module 'inventory'.
    return 0;
}

# A `var` initialized from `?:` or `match` with numeric arms of different
# types gets their common type, not the first arm's: `c ? 0 : big` is a
# ulong.
enum Size {
    Small,
    Large,
}

main(): int {
    ulong big = 14345035776;
    long pages = 5;
    var bytes = pages < 1 ? 0 : big;
    if (bytes != 14345035776) {
        return -1;
    }
    bytes = big * 2;
    if (bytes != 28690071552) {
        return -2;
    }
    var mixed = pages > 1 ? 1.5 : 2;
    if (mixed != 1.5) {
        return -3;
    }
    var size = Size.Large;
    var matched = match (size) { Small => 0, Large => big };
    if (matched != 14345035776) {
        return -4;
    }
    var three = match (size) { Small => 0, Large => pages > 1 ? big : 1 };
    if (three != 14345035776) {
        return -5;
    }
    return 0;
}

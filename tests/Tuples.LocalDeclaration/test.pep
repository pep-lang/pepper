# A local declared `Type name = ...` may start with a tuple type
# (pepper#130), and a statement starting with `(` that declares nothing
# stays an expression: a swap, a parenthesized callee.
twice(x: int): int {
    return x * 2;
}

main(): int {
    (String, int)[] pairs = Array<(String, int)>();
    pairs.append(("a", 1));
    (int, String)? maybe = Optional<(int, String)>.Value((2, "b"));
    (line: int, column: int) at = (3, 4);
    (int) => int double_it = twice;
    (int, int)[][] grid = [[(5, 6)]];
    if (pairs[0].1 != 1 or maybe.value().0 != 2 or at.column != 4 or grid[0][0].1 != 6) {
        return 1;
    }
    var x = 1;
    var y = 2;
    (x, y) = (y, x);
    if (x != 2 or y != 1) {
        return 2;
    }
    if ((double_it)(x) != 4 or (twice)(y) != 2) {
        return 3;
    }
    (double_it)(x);
    return 0;
}

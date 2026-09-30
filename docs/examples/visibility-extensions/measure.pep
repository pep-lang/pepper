import "point";

# An exported extension: files that import measure.pep can call these.
export extend Point {
    manhattan(): int {
        return abs(x) + abs(y);
    }
}

# Private to this file.
abs(v: int): int {
    if (v < 0) { return -v; }
    return v;
}

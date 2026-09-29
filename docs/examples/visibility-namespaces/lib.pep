# lib.pep's private helpers: no other file can see them, and no other
# file's names can clash with them.
struct Counter { var n: int; }

make(): Counter {
    var c = Counter();
    c.n = 10;
    return c;
}

export lib_total(): int {
    return make().n;
}

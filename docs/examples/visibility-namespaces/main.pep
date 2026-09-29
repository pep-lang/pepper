import "lib";

# main.pep has its own private Counter and make(), unrelated to lib.pep's.
struct Counter { var n: int; var step: int; }

make(): Counter {
    var c = Counter();
    c.n = 1;
    c.step = 2;
    return c;
}

main(): int {
    var c = make();                    # main.pep's make()
    assert(c.n + c.step == 3, "main's own Counter");
    assert(lib_total() == 10, "lib's make() is its own");
    return 0;
}

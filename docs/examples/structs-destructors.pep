# A module-scope counter: const, and changed through an Atomic.
const closed = Atomic<int>(0);

struct Connection {
    var name: String;

    construct(this.name = "") {}

    # The destructor runs once, when the last reference to the object goes
    # away. Use it to release whatever the object holds.
    destruct {
        closed.fetch_add(1);
    }
}

main(): int {
    {
        var c = Connection("db");
        assert(closed.load() == 0, "still in use");
    }
    # `c` went out of scope at the closing brace.
    assert(closed.load() == 1, "the destructor ran at the end of the block");
    return 0;
}

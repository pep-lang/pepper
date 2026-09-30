import async;

# A module-scope counter: const, and changed through an Atomic.
const destroyed = async.Atomic<int>(0);

struct Tracked {
    var name: String;
    construct(this.name = "") {}
    destruct {
        destroyed.fetch_add(1);
    }
}

struct Holder {
    var item: Tracked;
}

make(name: String): Tracked {
    var t = Tracked(name);
    return t;                   # the caller receives the object
}

main(): int {
    # 1. A local is released when its scope ends.
    {
        var a = Tracked("a");
    }
    assert(destroyed.load() == 1, "a was destroyed at the end of its block");

    # 2. While another reference exists, the object stays alive.
    var b = Tracked("b");
    var also_b = b;
    b = Tracked("b2");          # b lets go of the first object...
    assert(destroyed.load() == 1, "...but also_b still holds it");
    also_b = b;                 # the last reference moves away
    assert(destroyed.load() == 2, "the first object is destroyed now");

    # 3. Fields and containers hold references too.
    var holder = Holder();
    {
        var c = Tracked("c");
        holder.item = c;
    }
    assert(destroyed.load() == 2, "holder.item keeps c alive after its scope");
    holder = Holder();          # the old Holder dies and releases c
    assert(destroyed.load() == 3, "releasing the holder released its field");

    var list = Array<Tracked>();
    list.append(Tracked("d"));
    assert(destroyed.load() == 3, "the array holds d");
    list.clear();
    assert(destroyed.load() == 4, "clearing the array released d");

    # 4. Returned objects belong to the caller; unused results are
    #    destroyed right away.
    var e = make("e");
    assert(destroyed.load() == 4, "e is alive in main");
    make("temporary");
    assert(destroyed.load() == 5, "a result nobody keeps is destroyed immediately");
    return 0;
}

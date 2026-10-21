import async;

const destroyed = async.Atomic<int>(0);

struct Link {
    var next: Link;
    destruct {
        destroyed.fetch_add(1);
    }
}

main(): int {
    # A million links, each holding the next one.
    var head = Link();
    var node = head;
    for (var i in 0..999999) {
        node.next = Link();
        node = node.next;
    }
    node = Link();
    # Releasing the head destroys the whole chain, without one stack frame
    # per link.
    head = Link();
    assert(destroyed.load() == 1000000, "every link was destroyed");
    return 0;
}

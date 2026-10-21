import async;

const destroyed = async.Atomic<int>(0);

struct Link {
    var next: Link;
    destruct {
        destroyed.fetch_add(1);
    }
}

# A node of a tree, holding its children in an array.
struct Tree {
    var children: Array<Tree> = Array<Tree>();
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

    # A tree a hundred thousand levels deep, through its children arrays.
    var root = Tree();
    var branch = root;
    for (var i in 0..99999) {
        var child = Tree();
        branch.children.append(child);
        branch = child;
    }
    branch = Tree();
    root = Tree();
    assert(destroyed.load() == 1100000, "every node was destroyed");
    return 0;
}

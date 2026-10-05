struct Node {
    String name;
    # Most nodes never get children, and an empty Array costs nothing.
    Array<Node> children = Array<Node>();
    construct(name: String) {
        this.name = name;
    }
}

main(): int {
    var a = Array<int>();           # no allocation
    assert(a.count == 0 && a.is_empty, "reading allocates nothing");
    for (var x in a) {
        assert(false, "an empty Array has no elements");
    }
    var b = a;                      # allocates the Array: a and b share it
    b.append(1);                    # allocates its buffer
    assert(a.count == 1, "both names see the append");

    var leaf = Node("leaf");
    var root = Node("root");
    root.children.append(leaf);
    assert(leaf.children.is_empty && root.children.count == 1, "only root's children were allocated");
    return 0;
}

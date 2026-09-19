struct Widget {
    int tag;

    new(this.tag = 0) {}
};

main(): int {
    var a = array<int>();
    assert(a.empty(), "fresh array is empty");
    a.append(1);
    a.append(2);
    a.append(3);
    assert(a.count() == 3, "append grows count");
    assert(a[0] == 1 && a[1] == 2 && a[2] == 3, "index reads appended values");
    a.insert(1, 9);
    assert(a.count() == 4 && a[1] == 9 && a[2] == 2, "insert shifts the tail");
    var removed = a.remove_at(0);
    assert(removed == 1 && a.count() == 3 && a[0] == 9, "remove_at returns and shifts");
    var popped = a.pop();
    assert(popped == 3 && a.count() == 2, "pop drops the last element");
    assert(a.find(9) >= 0, "find locates an element");
    assert(a.contains(9), "contains reports membership");
    assert(!a.contains(42), "contains rejects missing elements");
    var b = a.clone();
    b.append(7);
    assert(b.count() == 3 && a.count() == 2, "clone is independent of the source");
    assert(a[1] == 2 && b[1] == 2, "clone copies element values");
    var c = array<int>();
    c.append(9);
    c.append(2);
    assert(c == a, "element-wise equality holds");
    assert(c != b, "differing sizes are not equal");
    c.reverse();
    assert(c[0] == 2 && c[1] == 9, "reverse flips the order");
    # Struct elements are references: stores into a slot acquire the new value
    # and release the old occupant, so refcounts track external refs plus live
    # slots.
    var s = array<Widget>();
    var w = Widget(5);
    s.append(w);
    assert(__refcount<Widget>(w) == 2, "append acquires the element");
    s.insert(0, Widget());
    assert(__refcount<Widget>(w) == 2, "insert shifts without refcount churn");
    assert(s[1].tag == 5, "shifted element is intact");
    var gone = s.remove_at(1);
    assert(gone.tag == 5 && __refcount<Widget>(w) == 1, "remove_at transfers the reference");
    s.clear();
    assert(__refcount<Widget>(w) == 1, "clear releases the array's reference");
    return 0;
}

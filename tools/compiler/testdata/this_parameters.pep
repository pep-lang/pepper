# A constructor's `this.x` parameter without a default is required and
# takes its field's type (#325): mixed with defaulted ones, passed by
# name, chosen between overloads, replacing a field's initializer, in a
# generic struct, a `[Value]` struct, an `[Implicit]` constructor and an
# attribute.

struct Point {
    var x: int;
    var y: int;

    construct(this.x, this.y) {}
}

struct Label {
    var name: String;
    var size: int = 7;
    var tag: String;

    construct(this.name, this.size = 3, this.tag = "t") {}
    construct(this.size, this.name) {}
}

struct Box<T> {
    var value: T;

    construct(this.value) {}
}

struct Pair<T> {
    var first: T;
    var second: T;

    construct(this.first, second: T) {
        this.second = second;
    }
}

struct Counter {
    var n: int = 5;

    construct(this.n) {}
    construct() {}
}

struct Meters {
    var m: double;

    [Implicit]
    construct(this.m) {}
}

[Value]
struct Size {
    var w: int;
    var h: int;

    construct(this.w, this.h = 2) {}
}

[Attribute]
struct Weight {
    var w: int;

    construct(this.w) {}
}

[Weight(4)]
struct Weighed {
    var q: int;
}

length(m: Meters): double {
    return m.m;
}

main(): int {
    var p = Point(1, 2);
    assert(p.x == 1 and p.y == 2, "positional");
    var q = Point(y = 4, x = 3);
    assert(q.x == 3 and q.y == 4, "by name");
    var a = Label("a");
    assert(a.name == "a" and a.size == 3 and a.tag == "t", "defaults after the required one");
    var b = Label(9, "b");
    assert(b.size == 9 and b.name == "b", "the other overload");
    var c = Label("c", tag = "z");
    assert(c.size == 3 and c.tag == "z", "a defaulted one by name");
    assert(Box<String>("hi").value == "hi", "generic");
    var pair = Pair<int>(1, 2);
    assert(pair.first == 1 and pair.second == 2, "generic, with an ordinary parameter");
    assert(Counter(8).n == 8, "the argument replaces the initializer");
    assert(Counter().n == 5, "the initializer without it");
    assert(length(2.5) == 2.5, "implicit");
    var size = Size(1);
    assert(size.w == 1 and size.h == 2, "value struct");
    static {
        reflect.assert(reflect.attribute<Weighed, Weight>().w == 4, "attribute");
    }
    print("ok");
    return 0;
}

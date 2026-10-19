# Calls to a struct's own methods: by their bare names, a generic method
# called with explicit type arguments (`make<String>(n)`) from a method, a
# static method and a closure, as `this.make<String>(n)` would call it;
# and overloads mixing plain and generic members.

struct Labeled<T> {
    var label = "";
}

struct LabelMaker {
    var prefix = "p:";

    make(text: String): Labeled<String> {
        return make<String>(text);
    }

    make<T>(text: String): Labeled<T> {
        var labeled = Labeled<T>();
        labeled.label = prefix + text;
        return labeled;
    }

    later(text: String): () => String {
        return () => make<int>(text).label;
    }

    static plain(text: String): Labeled<String> {
        return plain_of<String>(text);
    }

    static plain_of<T>(text: String): Labeled<T> {
        var labeled = Labeled<T>();
        labeled.label = text;
        return labeled;
    }
}

struct TagOf<U> {
    var tag = "tag";

    name(): String {
        return tag_of<U>();
    }

    tag_of<T>(): String {
        return tag;
    }
}

[Test]
calls_a_generic_method_by_its_bare_name() {
    var maker = LabelMaker();
    expect_equal(maker.make("a").label, "p:a");
    expect_equal(maker.later("b")(), "p:b");
    expect_equal(LabelMaker.plain("c").label, "c");
    expect_equal(TagOf<int>().name(), "tag");
}

# A method overloaded by plain and generic members, picked by the argument's
# type: `bool` goes to the plain member, `T?` and `T[]` to their generic
# members ahead of the plain `T` one.
struct Describer<U> {
    var tag = "d";

    describe(value: bool): String {
        return tag + ":bool";
    }

    describe<T>(value: T): String {
        return tag + ":one";
    }

    describe<T>(value: T?): String {
        return tag + ":maybe";
    }

    describe<T>(value: Array<T>): String {
        return tag + ":many";
    }

    all(u: U): String {
        return describe(true) + " " + describe(u) + " " + describe([u]) + " " + describe<U>(u);
    }

    kind<T>(value: T): String {
        return "one";
    }

    kind<T>(value: Array<T>): String {
        return "many";
    }

    static make<T>(value: T): String {
        return "one";
    }

    static make<T>(value: T?): String {
        return "maybe";
    }
}

[Test]
picks_between_plain_and_generic_overloads() {
    var describer = Describer<int>();
    expect_equal(describer.all(3), "d:bool d:one d:many d:one");
    expect_equal(describer.describe(false), "d:bool");
    expect_equal(describer.describe(Optional<int>.Value(1)), "d:maybe");
    expect_equal(describer.describe<String>("a"), "d:one");
    expect_equal(describer.kind([1, 2]), "many");
    expect_equal(describer.kind(1), "one");
    expect_equal(Describer<int>.make(1), "one");
    expect_equal(Describer<int>.make(Optional<int>.Value(1)), "maybe");
}

# Calls to a struct's own methods by their bare names: a generic method
# called with explicit type arguments (`make<String>(n)`) from a method, a
# static method and a closure, as `this.make<String>(n)` would call it (#672).

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

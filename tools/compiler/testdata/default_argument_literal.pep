# String literals inside default arguments, which each call that omits the
# argument evaluates: in a call, through an `[Implicit]` conversion, in a
# constructor and a method, and from another module.
import d;

struct Label {
    var text: String;

    [Implicit]
    construct(text: String) {
        this.text = text;
    }
}

size_of(text: String): int {
    return text.length as int;
}

counted(n: int = size_of("abc")): int {
    return n;
}

labeled(label: Label = "default"): String {
    return label.text;
}

struct Box {
    var n: int;

    construct(n: int = size_of("abcd")) {
        this.n = n;
    }

    get(n: int = size_of("abcde")): int {
        return n;
    }
}

main(): int {
    print($"{counted()} {labeled()} {Box().n} {Box().get()}");
    var sized = d.Sized();
    print($"{d.count_default()} {sized.n} {sized.label.text}");
    return 0;
}

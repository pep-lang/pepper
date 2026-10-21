# String literals inside default arguments, which each call that omits the
# argument evaluates: in a call, through an `[Implicit]` conversion, in a
# constructor and a method, as a C string, as a struct in a trait slot, and
# from another module.
import d;

extern ulong strlen(char* s);

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

c_length(text: __ptr<char> = "abcdefg"): int {
    return strlen(text) as int;
}

trait Named {
    name(): String;
}

struct Dog {
    var name_text: String;

    construct(name_text: String = "rex") {
        this.name_text = name_text;
    }

    name(): String {
        return name_text;
    }
}

extend Dog with Named;

named(n: Named = Dog()): String {
    return n.name();
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
    print($"{c_length()} {named()}");
    var sized = d.Sized();
    print($"{d.count_default()} {sized.n} {sized.label.text}");
    return 0;
}

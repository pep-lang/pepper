_count(text: String): int {
    return text.length as int;
}

export struct Label {
    var text: String;

    [Implicit]
    construct(text: String) {
        this.text = text;
    }
}

export struct Sized {
    var n: int;
    var label: Label;

    construct(n: int = _count("abcdef"), label: Label = "module") {
        this.n = n;
        this.label = label;
    }
}

export count_default(n: int = _count("ab")): int {
    return n;
}

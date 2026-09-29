struct Box<T> {
    T value;
    construct(T v) { value = v; }

    # A method with a type parameter of its own: `U` is chosen per call.
    map<U>(f: (T) => U): Box<U> {
        return Box<U>(f(value));
    }
}

main(): int {
    var b = Box<int>(4);

    # `U` comes from what the closure returns...
    var tens = b.map((x) => x * 10);
    assert(tens.value == 40, "tens");

    var text = tens.map((x) => "forty");
    assert(text.value == "forty", "text");

    # ...or is written after the method name.
    var wide = b.map<long>((x: int): long => x + 1);
    assert(wide.value == 5, "wide");
    return 0;
}

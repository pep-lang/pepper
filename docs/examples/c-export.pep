# A library C code calls: build it with `pepper build counter.pep --lib
# static` (or `--lib shared`), which also writes `counter.h`.
#
# `main` is not needed in a library; this one calls the exported functions
# from Pepper, so the example runs as a program too.

[Export]
add(a: int, b: int): int {
    return a + b;
}

# A struct crosses to C as an opaque handle, `Counter*`.
struct Counter {
    var count: int;

    construct(this.count = 0) {}
}

# The C name can differ from the Pepper name.
[Export(name = "counter_new")]
make_counter(start: int): Counter {
    return Counter(start);
}

[Export]
counter_increment(counter: Counter): int {
    counter.count += 1;
    return counter.count;
}

# A C function pointer, called back.
[Export]
apply(f: extern (int) => int, x: int): int {
    return f(x);
}

# A String arrives as UTF-8 bytes and their size, and leaves as a
# NUL-terminated copy that C frees with `pepper_string_free`.
[Export]
greet(name: String): String {
    return "hello, " + name;
}

main(): int {
    var counter = make_counter(41);
    assert(counter_increment(counter) == 42, "the counter counts");
    assert(add(2, 3) == 5, "add adds");
    assert(greet("C") == "hello, C", "greet greets");
    return 0;
}

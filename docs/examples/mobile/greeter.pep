# The Pepper half of the prototype iOS and Android apps: a library their
# Swift and Java code calls through the bindings the compiler generates.
# The iOS app builds it with `--lib static --bindings swift`, the iOS
# package with `--lib swift-package` and the Android app with `--lib aar`
# (see docs/src/language/mobile.md).

# A String crosses as UTF-8, a Swift or Java String on the other side.
[Export]
greet(name: String): String {
    return $"Hello, {name}, from Pepper";
}

[Export]
fibonacci(n: int): long {
    long previous = 0;
    long current = 1;
    for (var i in 0..n) {
        var next = previous + current;
        previous = current;
        current = next;
    }
    return previous;
}

[Export]
count_words(text: String): int {
    var count = 0;
    for (var word in text.split(" ")) {
        if (!word.is_empty) {
            count += 1;
        }
    }
    return count;
}

[Export]
is_even(n: long): bool {
    return n % 2 == 0;
}

[Export]
half(x: double): double {
    return x / 2;
}

# A struct crosses as a handle: Swift and Java hold it as an object that
# owns one reference, released by Swift's `deinit` or Java's `close()`.
struct Tally {
    var total: long = 0;

    construct() {}
}

[Export]
tally_new(): Tally {
    return Tally();
}

[Export]
tally_add(tally: Tally, n: int): long {
    tally.total += n;
    return tally.total;
}

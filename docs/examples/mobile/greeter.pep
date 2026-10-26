# The Pepper half of the prototype iOS and Android apps: a library their
# Swift and Java code calls through the bindings the compiler generates.
# The iOS app builds it with `--lib static --bindings swift`, the iOS
# package with `--lib swift-package` and the Android app with `--lib aar`
# (see docs/src/language/mobile.md).

import io;

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

# Writes `text` to a file in the temporary folder, inside the app's
# container (on Android, the cache folder the app passed to
# `pepperSetAppDirectories`), and returns what reading it back gives.
# What it prints reaches Xcode's console, or logcat in an Android app.
[Export]
save_note(text: String): String {
    var path = io.Directory.temp().join("note.txt");
    var written = io.File.write_text(path, text);
    if (written.is_err()) {
        return $"cannot write {path}: {written.error().message}";
    }
    print($"saved a note in {path}");
    return io.File.read_to_string(path).value();
}

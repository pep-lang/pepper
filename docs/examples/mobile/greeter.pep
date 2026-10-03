# The Pepper half of the prototype iOS and Android apps: a library their
# Swift and Java code calls through C. Each app builds it with `--lib
# static` for its platform (see docs/src/language/mobile.md).

# A String arrives as UTF-8 bytes and leaves as a copy the caller frees
# with `pepper_string_free`.
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

# `I`'s constraint names `T`: the argument's type gives `I`, and the
# `Iterator<T>` it declares gives `T`.
count_all<T, I: Iterator<T>>(source: I): int {
    var count = 0;
    while (source.next()) {
        count += 1;
    }
    return count;
}

first<T, I: Iterator<T>>(source: I): T {
    source.next();
    return source.current();
}

main(): int {
    var words = Array<String>();
    words.append("pepper");
    words.append("salt");

    # Both inferred: I = ArrayIterator<String>, T = String.
    assert(count_all(words.iterate()) == 2, "count");
    assert(first(words.iterate()) == "pepper", "first");

    # Written type arguments may stop early; the rest are inferred.
    assert(count_all<String>(words.iterate()) == 2, "partial");
    return 0;
}

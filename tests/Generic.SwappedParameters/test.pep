# Generic code that names a generic function or struct with its own type
# parameters swapped (`first_of<V, K>` inside `f<K, V>`) types the result
# as the swapped parameter (#189).

first_of<K, V>(key: K, value: V): K {
    return key;
}

struct Pair<K, V> {
    var key: K;
    var value: V;

    construct(key: K, value: V) {
        this.key = key;
        this.value = value;
    }

    first(): K {
        return key;
    }
}

called<K, V>(key: K, value: V): String {
    var x = first_of<V, K>(value, key);
    return $"{x}";
}

method<K, V>(key: K, value: V): String {
    var p = Pair<V, K>(value, key);
    var x = p.first();
    var y = p.value;
    return $"{x}{y}";
}

main(): int {
    if (called(1, "one") != "one") {
        return 1;
    }
    if (method(1, "one") != "one1") {
        return 2;
    }
    return 0;
}

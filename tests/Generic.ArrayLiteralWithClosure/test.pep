# A generic call taking an array literal, or another generic call's result,
# and a closure infers its type arguments from the elements, as it does
# from an array variable.

apply<T, U>(items: T[], f: (T) => U): U[] {
    var out = Array<U>();
    for (var item in items) {
        out.append(f(item));
    }
    return out;
}

twice<T>(item: T): T[] {
    return [item, item];
}

main(): int {
    var next = apply([1, 2], (x) => x + 1);
    if (next.count != 2 or next[0] != 2 or next[1] != 3) {
        return 1;
    }
    var sizes = apply(["a", "bc"], (s) => s.size);
    if (sizes[1] != 2) {
        return 2;
    }
    var counts = apply([[1, 2], [3]], (xs) => xs.count);
    if (counts[0] != 2 or counts[1] != 1) {
        return 3;
    }
    var doubled = apply(twice(4), (x) => x * 2);
    if (doubled.count != 2 or doubled[1] != 8) {
        return 4;
    }
    return 0;
}

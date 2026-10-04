# `[Unsafe("...")]` removes runtime checks from one function's body.

# A hash that wraps on purpose: without the overflow check, `*` and `+`
# wrap around instead of panicking.
[Unsafe("overflow")]
hash(values: Array<int>): uint {
    uint result = 2166136261;
    for (var value in values) {
        result = (result ^ (value as uint)) * 16777619;
    }
    return result;
}

# A loop that already checked its range: the index checks of `a[i]`, made by
# `Array`'s indexer for this caller, are removed too.
[Unsafe("bounds")]
sum(values: Array<int>): long {
    long total = 0;
    ulong i = 0;
    while (i < values.count) {
        total = total + values[i];
        i = i + 1;
    }
    return total;
}

main(): int {
    var values = Array<int>();
    for (var i in 0..100) {
        values.append(i);
    }
    assert(hash(values) != 0, "a hash");
    assert(sum(values) == 4950, "0 + 1 + ... + 99");
    # Outside those functions every check stays: 2147483647 + 1 here would
    # still panic.
    return 0;
}

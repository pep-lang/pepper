# `extern (P...) => R` is a C function pointer type: qsort calls `compare`
# with pointers to two elements.
extern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);

ascending(a: __ptr<void>, b: __ptr<void>): int {
    __ptr<int> x = a;
    __ptr<int> y = b;
    return x[0] - y[0];
}

main(): int {
    __ptr<int> numbers = _pep_malloc(4 * sizeof<int>());
    numbers[0] = 30;
    numbers[1] = 10;
    numbers[2] = 40;
    numbers[3] = 20;

    # A named function converts to the C function pointer type.
    qsort(numbers, 4, sizeof<int>(), ascending);
    assert(numbers[0] == 10 && numbers[3] == 40, "ascending");

    # So does a closure that captures nothing; its parameter types come
    # from the C function pointer type.
    qsort(numbers, 4, sizeof<int>(), (a, b) => {
        __ptr<int> x = a;
        __ptr<int> y = b;
        return y[0] - x[0];
    });
    assert(numbers[0] == 40 && numbers[3] == 10, "descending");

    # A C function pointer is a value like a number: store it, call it.
    var compare: extern (__ptr<void>, __ptr<void>) => int = ascending;
    assert(compare(numbers, numbers + 1) > 0, "40 sorts after 30");

    _pep_free(numbers);
    return 0;
}

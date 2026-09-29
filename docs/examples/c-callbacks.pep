extern void qsort(void* base, ulong count, ulong size, void* compare);

# C calls this with pointers to two elements: a C-compatible signature.
compare_ints(a: __ptr<void>, b: __ptr<void>): int {
    __ptr<int> x = a;
    __ptr<int> y = b;
    if (x[0] < y[0]) { return -1; }
    if (x[0] > y[0]) { return 1; }
    return 0;
}

main(): int {
    __ptr<int> numbers = _pep_malloc(4 * sizeof<int>());
    numbers[0] = 30;
    numbers[1] = 10;
    numbers[2] = 40;
    numbers[3] = 20;
    qsort(numbers, 4, sizeof<int>(), __function_pointer(compare_ints));
    assert(numbers[0] == 10 && numbers[3] == 40, "sorted");
    _pep_free(numbers);
    return 0;
}

# A C function pointer holds no captured values, so a callback that needs
# state reads it from somewhere C does not have to carry: here, a
# thread-local the caller sets before handing the callback to C.
extern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);

# The value to sort around, for the calling thread.
[ThreadLocal]
var pivot: int = 0;

distance(x: int): int {
    var d = x - pivot;
    return d < 0 ? -d : d;
}

closest_first(a: __ptr<void>, b: __ptr<void>): int {
    __ptr<int> x = a;
    __ptr<int> y = b;
    return distance(x[0]) - distance(y[0]);
}

main(): int {
    __ptr<int> numbers = _pep_malloc(4 * sizeof<int>());
    numbers[0] = 10;
    numbers[1] = 40;
    numbers[2] = 22;
    numbers[3] = 31;

    pivot = 30;
    qsort(numbers, 4, sizeof<int>(), closest_first);
    assert(numbers[0] == 31 && numbers[3] == 10, "closest to 30 first");

    _pep_free(numbers);
    return 0;
}

# Raw pointers: __ptr<T> in Pepper code, T* in extern prototypes.

extern void* malloc(ulong size);
extern void free(void* p);
extern void* memset(void* p, int value, ulong size);

struct Buffer {
    var data: __ptr<u8> = __null;
    var size: ulong = 0;
}

make_buffer(size: ulong): Buffer {
    var b = Buffer();
    b.data = malloc(size) as __ptr<u8>;
    b.size = size;
    memset(b.data, 0, size);
    return b;
}

sum(values: __ptr<int>, count: int): int {
    var total = 0;
    var i = 0;
    while (i < count) {
        total = total + values[i];
        i = i + 1;
    }
    return total;
}

# `var` takes the element type from the pointer: `big` is a ulong, so a value
# above 2^32 reads back whole.
first(values: __ptr<ulong>): ulong {
    var big = values[0];
    return big;
}

main(): int {
    # Indexing reads and writes elements of T.
    var numbers = malloc(4 * sizeof<int>()) as __ptr<int>;
    numbers[0] = 10;
    numbers[1] = 20;
    numbers[2] = 30;
    numbers[3] = 40;
    assert(sum(numbers, 4) == 100, "indexing reads what was written");

    var wide = malloc(sizeof<ulong>()) as __ptr<ulong>;
    wide[0] = 5000000000;
    assert(first(wide) == 5000000000, "var v = p[i] has the pointee's type");
    free(wide);

    # p + n moves by n elements, not n bytes.
    var third = numbers + 2;
    assert(third[0] == 30, "numbers + 2 points at the third element");
    assert((third as ulong) - (numbers as ulong) == 8, "two ints are eight bytes");

    # __ptr<void> strides by bytes; cast to see the memory another way.
    var raw = numbers as __ptr<void>;
    var bytes = raw as __ptr<u8>;
    assert(bytes[4] == 20, "the second int starts at byte 4 (little-endian)");
    free(raw);

    # Pointers can live in struct fields, and compare with __null.
    var b = make_buffer(16);
    assert(b.data != __null, "malloc returned memory");
    assert(b.data[15] == 0, "memset cleared it");
    free(b.data);
    b.data = __null;

    # A pointer to pointers: indexing yields the inner pointer, and indexing
    # again reads or writes through it.
    var rows = malloc(2 * sizeof<__ptr<int>>()) as __ptr<__ptr<int>>;
    var row = malloc(sizeof<int>()) as __ptr<int>;
    rows[1] = row;
    rows[1][0] = 7;
    assert(rows[1][0] == 7, "rows[1][0] reads through the row pointer");
    assert(row[0] == 7, "rows[1] is the row pointer");
    free(row);
    free(rows);
    return 0;
}

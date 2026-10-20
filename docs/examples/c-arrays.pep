# Passing an Array's elements to C, and filling an Array from a C buffer.

extern void* memset(void* s, int c, ulong n);
extern void* malloc(ulong size);
extern void free(void* p);

main(): int {
    # data() points at the elements, so C can read or write them in place.
    var bytes = Array<u8>();
    bytes.append(1);
    bytes.append(2);
    bytes.append(3);
    memset(bytes.data() as __ptr<void>, 7, bytes.count);
    assert(bytes[2] == 7, "C wrote through data()");

    # An empty Array has no elements to point at: data() is __null.
    var none = Array<u8>();
    assert(unsafe_cast<__ptr<u8>>(none.data()) == __null, "empty is __null");

    # append_from copies count elements out of a C buffer, which you still own.
    __ptr<u8> buffer = unsafe_cast<__ptr<u8>>(malloc(4));
    memset(buffer as __ptr<void>, 9, 4);
    var copy = Array<u8>();
    copy.append_from(buffer, 4);
    free(buffer as __ptr<void>);
    assert(copy.count == 4 && copy[3] == 9, "append_from copied the buffer");
    return 0;
}

# `as` converts values; `unsafe_cast<T>(value)` reinterprets bits.

extern void* malloc(ulong size);
extern void free(void* p);

main(): int {
    # A float's bits, and back: the same 32 bits seen as a uint.
    var one = 1.0 as float;
    var bits = unsafe_cast<uint>(one);
    assert(bits == 0x3F800000, "1.0 is 0x3F800000");
    assert(unsafe_cast<float>(bits) == one, "the bits convert back");

    # A double's sign bit is its top bit.
    var negative = unsafe_cast<ulong>(-2.0);
    assert((negative >> 63) == 1, "the sign bit is set");

    # `as` converts a pointer to and from `__ptr<void>`.
    var memory = malloc(8);
    var words = memory as __ptr<uint>;
    words[0] = 0x01020304;
    words[1] = 0;

    # Reading the same memory as bytes reinterprets it.
    var bytes = unsafe_cast<__ptr<u8>>(words);
    assert(bytes[0] == 4 || bytes[0] == 1, "the first byte is the low or the high one");

    # An address is an integer, and an integer is an address.
    var address = unsafe_cast<ulong>(words);
    assert(unsafe_cast<__ptr<uint>>(address + 4)[0] == 0, "the address four bytes on is the second word");

    free(memory as __ptr<void>);
    return 0;
}

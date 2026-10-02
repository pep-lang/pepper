# A C resource owned by a Handle: `free` runs when the last reference to
# the handle goes away.

extern void* malloc(ulong size);
extern void free(void* p);
extern void* memset(void* p, int value, ulong size);

# A buffer from C, freed with the struct that holds it.
struct Buffer {
    var _memory: Handle<__ptr<void>>;
    var size: ulong { get; }

    construct(size: ulong) {
        _memory = Handle<__ptr<void>>(malloc(size), (p) => free(p));
        this.size = size;
    }

    fill(value: u8) {
        memset(_memory.value, value as int, size);
    }

    at(index: ulong): u8 {
        return (_memory.value as __ptr<u8>)[index];
    }
}

main(): int {
    var buffer = Buffer(16);
    buffer.fill(7);
    if (buffer.at(15) != 7) {
        return 1;
    }

    # release() frees early; the handle then no longer owns the memory.
    var scratch = Handle<__ptr<void>>(malloc(8), (p) => free(p));
    scratch.release();
    return scratch.is_owned() ? 2 : 0;
}

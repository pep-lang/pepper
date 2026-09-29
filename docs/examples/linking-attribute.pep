# [Link("name")] on an extern links the library that defines it.

# gdi32 is not one of the libraries Windows programs link by default.
[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int kind);

# pthread_self is in libpthread on older Linux systems, in libc on newer
# ones, and in libSystem on macOS; linking pthread works on all of them.
[Target(!OS(Windows))] [Link("pthread")] extern ulong pthread_self();

# The math library is separate from the C library on Linux.
[Target(OS(Linux))] [Link("m")] extern double pow(double base, double exponent);
[Target(!OS(Linux))] extern double pow(double base, double exponent);

main(): int {
    [Target(OS(Windows))] {
        # 5 is NULL_BRUSH, a stock object that always exists.
        assert(GetStockObject(5) != 0, "gdi32 was linked");
    }
    [Target(!OS(Windows))] {
        assert(pthread_self() != 0, "pthread was linked");
    }
    assert(pow(2.0, 10.0) == 1024.0, "the math library was linked");
    return 0;
}

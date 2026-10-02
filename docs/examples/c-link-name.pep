# [Link(name = "symbol")] binds a Pepper name to a C symbol with a different name.

# llabs takes a 64-bit long long on every platform: `i64` in an extern is
# 64 bits everywhere, where `long` follows the size of a pointer.
[Link(name = "llabs")]
extern i64 absolute(i64 value);

# C's long is 64 bits on Linux and macOS but 32 bits on Windows and
# WebAssembly, so the 64-bit labs is only right on the first two.
[Target(OS(Windows) || OS(Wasi))]
[Link(name = "llabs")]
extern i64 abs64(i64 value);
[Target(OS(Linux) || OS(Mac))]
[Link(name = "labs")]
extern long abs64(long value);

# `lib` names the library that defines the symbol, as [Link("m")] does.
[Target(OS(Linux))]
[Link(lib = "m", name = "cbrt")]
extern double cube_root(double value);

main(): int {
    assert(absolute(-7) == 7, "absolute calls llabs");
    assert(abs64(-5000000000) == 5000000000, "abs64 calls a 64-bit abs");
    [Target(OS(Linux))]
    {
        var root = cube_root(27.0);
        assert(root > 2.999 && root < 3.001, "cube_root calls cbrt from libm");
    }
    return 0;
}

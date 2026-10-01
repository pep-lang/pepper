# [Link(name = "symbol")] binds a Pepper name to a C symbol with a different name.

# llabs takes a 64-bit long long on every platform.
[Link(name = "llabs")]
extern long absolute(long value);

# C's long is 64 bits on Linux and macOS but 32 bits on Windows, so
# the 64-bit labs is only right away from Windows.
[Target(OS(Windows))]
[Link(name = "llabs")]
extern long abs64(long value);
[Target(!OS(Windows))]
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

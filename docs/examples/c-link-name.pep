# [LinkName] binds a Pepper name to a C symbol with a different name.

# llabs takes a 64-bit long long on every platform.
[LinkName("llabs")] extern long absolute(long value);

# C's long is 64 bits on Linux and macOS but 32 bits on Windows, so
# the 64-bit labs is only right away from Windows.
[Target(OS(Windows))] [LinkName("llabs")] extern long abs64(long value);
[Target(!OS(Windows))] [LinkName("labs")] extern long abs64(long value);

main(): int {
    assert(absolute(-7) == 7, "absolute calls llabs");
    assert(abs64(-5000000000) == 5000000000, "abs64 calls a 64-bit abs");
    return 0;
}

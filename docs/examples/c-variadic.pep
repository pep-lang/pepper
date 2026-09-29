# Calling a C function that takes a variable argument list.

extern void* malloc(ulong size);
extern void free(void* p);

# On Windows, snprintf lives in legacy_stdio_definitions.
[Target(OS(Windows))] [Link("legacy_stdio_definitions")]
extern int snprintf(char* buffer, ulong size, char* format, ...);
[Target(!OS(Windows))]
extern int snprintf(char* buffer, ulong size, char* format, ...);

main(): int {
    var buffer = malloc(64) as __ptr<char>;
    u8 small = 200;     # widened to int
    float half = 0.5;   # widened to double
    long big = 5000000000;
    var written = snprintf(buffer, 64, "%d %.1f %lld %s", small, half, big, "ok");
    var text = String(buffer, written as ulong, String.length_of(buffer, written as ulong));
    free(buffer);
    assert(text == "200 0.5 5000000000 ok", "snprintf formatted every argument");
    return 0;
}

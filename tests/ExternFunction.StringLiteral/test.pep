# A string literal passed through a C function pointer reaches C as a
# C string, as it does in a direct call.
measure(text: __ptr<char>): ulong {
    var length: ulong = 0;
    while (text[length] != 0) {
        length += 1;
    }
    return length;
}

main(): int {
    var length: extern (__ptr<char>) => ulong = measure;
    assert(length("hello") == 5, "literal through a C function pointer");
    return 0;
}

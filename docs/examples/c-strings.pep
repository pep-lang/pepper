# Passing strings to C, and turning C strings back into Strings.

extern ulong strlen(char* s);
extern int strcmp(char* a, char* b);
extern char* strchr(char* s, int c);

main(): int {
    # A string literal passed to an extern is a NUL-terminated C string.
    assert(strlen("hello") == 5, "a literal is passed as a C string");
    assert(strcmp("abc", "abc") == 0, "equal C strings compare as 0");

    # A String value goes through c_str().
    var name = "Pepper";
    name += " and C";
    assert(strlen(name.c_str()) == name.size(), "c_str() is the String's bytes");

    # A char* result is a __ptr<char>. Copy it into a String with the
    # constructor: the byte size and the number of code points.
    var rest = strchr(name.c_str(), 32);   # 32 is ' '
    assert(rest != __null, "strchr found a space");
    var size = strlen(rest);
    var copy = String(rest, size, String.length_of(rest, size));
    assert(copy == " and C", "the copy holds the tail of the C string");
    return 0;
}

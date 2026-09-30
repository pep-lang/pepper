# Numbers to text, byte-level access, ordering, and building text in pieces.
main(): int {
    # to_string turns any integer into its decimal text.
    var line = 3;
    var where = to_string(line) + ":" + to_string(-7);
    assert(where == "3:-7", "to_string");

    # byte_at and substr_bytes count bytes, so they work with find's offsets.
    var setting = "indent=4";
    var eq = setting.find("=") as ulong;
    assert(setting.byte_at(eq) == '=', "byte_at compares with a character literal");
    assert(setting.substr_bytes(0, eq) == "indent", "the bytes before '='");

    # compare, <, <=, > and >= order strings byte by byte.
    assert("apple" < "banana", "ordering");
    assert("b".compare("a") > 0, "compare is negative, 0 or positive");

    # lines() splits on "\n" or "\r\n"; trim_end() drops trailing whitespace.
    var lines = "one  \r\ntwo\n".lines();
    assert(lines.count() == 2, "no empty line after the final newline");
    assert(lines[0].trim_end() == "one", "trim_end");

    # repeat joins copies; StringBuilder appends without recopying the text.
    var out = StringBuilder();
    for (var text in lines) {
        out.append(" ".repeat(4)).append(text.trim_end()).append("\n");
    }
    assert(out.to_string() == "    one\n    two\n", "StringBuilder");
    return 0;
}

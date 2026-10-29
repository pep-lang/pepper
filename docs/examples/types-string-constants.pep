# A string literal's own type is StringConstant: its constant bytes, with no
# allocation and no reference count.
extern ulong strlen(char* text);

# A `const` initialized from a literal is a StringConstant.
const GREETING = "hello";

# `\x80` to `\xFF` write raw bytes, which only a StringConstant holds: a
# byte table kept in static data.
const TABLE = "\x01\x80\xFF";

shout(text: String): String {
    return text.upper() + "!";
}

main(): int {
    StringConstant name = "pepper";
    assert(name.length == 6, "the read API of String");
    assert(name.starts_with("pep") && name.find("p", 1) == 2, "find counts bytes");

    # Always NUL-terminated: c_str() goes to C with no copy.
    assert(strlen(GREETING.c_str()) == 5, "C reads the literal's bytes");

    # A StringConstant converts to a String wherever one is expected.
    String copy = name;
    copy.append("!");
    assert(copy == "pepper!" && name == "pepper", "the copy has its own bytes");
    print(shout(GREETING));

    # Compared with a String either way round, with no copy.
    String typed = "pepper";
    assert(name == typed && typed == name && GREETING < typed, "mixed comparisons");

    assert(TABLE.size == 3 && TABLE.byte_at(2) == 0xFF, "raw bytes");

    # Copying a StringConstant copies a pointer.
    var also = name;
    assert(also == name, "same text");
    return 0;
}

# Output:
# HELLO!

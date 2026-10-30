# String literals are String values.
main(): int {
    var language = "Pepper";
    assert(language.length == 6, "6 code points");

    # + makes a new String; == compares contents.
    var message = "Hello, " + language;
    assert(message == "Hello, Pepper", "concatenation");
    assert(message != language, "different contents");

    # Strings are UTF-8. `length` counts code points, `size` counts bytes.
    var word = "héllo";
    assert(word.length == 5, "5 code points");
    assert(word.size == 6, "6 bytes: 'é' takes 2");
    assert(word[1] == "é", "indexing yields a one-code-point String");

    # A literal may span lines, and each line break in it is "\n",
    # whether the file ends its lines "\n" or "\r\n".
    var lines = "one
two";
    assert(lines == "one\ntwo", "a line break is a newline");

    # A String is a reference: both names see an append.
    var alias = message;
    message.append("!");
    assert(alias == "Hello, Pepper!", "one object, two references");

    print(message);
    return 0;
}

# Output:
# Hello, Pepper!

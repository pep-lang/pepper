# Searching, splitting, joining and replacing text.

main(): int {
    # find takes a byte offset to start from; rfind finds the last match.
    var path = "src/lib/main.pep";
    var first = path.find("/");
    assert(path.find("/", (first as ulong) + 1) == 7, "the second slash");
    assert(path.rfind("/") == 7, "the last slash");

    # split cuts at every separator; split_once at the first, if any.
    var fields = "name,,age".split(",");
    assert(fields.count == 3 && fields[1] == "", "an empty field");
    var header = "Content-Type: text/plain".split_once(": ");
    if (header.is_value()) {
        var (name, value) = header.value();
        assert(name == "Content-Type" && value == "text/plain", "both halves");
    }

    # join puts the separator between the parts; replace swaps every match.
    assert(" | ".join(fields) == "name |  | age", "joined");
    assert("a\r\nb\r\n".replace("\r\n", "\n") == "a\nb\n", "line endings");
    return 0;
}

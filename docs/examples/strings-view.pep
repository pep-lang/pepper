main(): int {
    var line = "name = pepper, version = 0.12";
    var names = Array<String>();
    # Each piece is a view of `line`: nothing is copied until `to_string`.
    for (var field in line.view(0, line.size).split(",")) {
        var (key, value) = field.split_once("=").value();
        if (key.trim() == "name") {
            names.append(value.trim().to_string());
        }
    }
    assert(names.count == 1 && names[0] == "pepper", "one name");

    # `s[i..j]` counts code points, as `s[i]` does.
    var word = "héllo";
    assert(word[1..4] == "éll", "code points 1 to 3");
    return 0;
}

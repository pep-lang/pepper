# Interpolated strings: `$"..."` with expressions in braces.
main(): int {
    var name = "Pepper";
    var count = 3;
    var ready = true;

    # Each {name} is replaced by that variable's text.
    var line = $"{name} has {count} items, ready: {ready}";
    assert(line == "Pepper has 3 items, ready: true", "integers, bool and String");

    # Any expression fits between the braces, strings included.
    var sizes = [2, 5];
    assert($"total {sizes[0] + sizes[1]}" == "total 7", "arithmetic and index");
    assert($"{name.size()} letters" == "6 letters", "call");
    assert($"{count > 1 ? "many" : "one"}" == "many", "ternary with strings");

    # Doubled braces are literal braces; escapes work as in any string.
    assert($"{{count}} = {count}" == "{count} = 3", "literal braces");
    assert($"tab\t{count}\n" == "tab\t3\n", "escapes");
    return 0;
}

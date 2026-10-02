struct Settings {
    var width: int;
    [Deprecated("use 'width' instead", "width")]
    var size: int;
}

# Lists the deprecated fields of `T` with what replaces each, read from the
# built-in `Deprecated` attribute like any `[Attribute]` struct.
deprecated_fields<T>(): String {
    var out = "";
    static (out) {
        for (var field in reflect.properties<T>()) {
            if (field.has_attribute<Deprecated>()) {
                out = out + $"{field.name} -> {field.attribute<Deprecated>().replacement};";
            }
        }
    }
    return out;
}

main(): int {
    assert(deprecated_fields<Settings>() == "size -> width;", "one deprecated field");
    return 0;
}

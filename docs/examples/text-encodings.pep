# Text in other encodings: encode a String to bytes, decode bytes back.
import text;

main(): int {
    var greeting = "héllo 🙂";

    # UTF-8 is what a String holds; decode checks the bytes.
    var utf8 = text.Utf8.encode(greeting);
    assert(utf8.count == 11, "é takes two bytes, 🙂 four");
    assert(text.Utf8.decode(utf8).value() == greeting, "round trip");

    # UTF-16: two bytes per unit, little-endian unless asked otherwise.
    var utf16 = text.Utf16.encode(greeting);
    assert(utf16.count == 16, "🙂 takes a surrogate pair");
    assert(text.Utf16.decode(utf16).value() == greeting, "round trip");

    # ASCII has no é: strict gives none, lossy writes '?'.
    assert(text.Ascii.encode(greeting).is_none(), "not ASCII");
    assert(text.Ascii.encode_lossy("é").count == 1, "one '?'");

    # Strict decoding rejects invalid bytes; lossy decoding replaces them.
    var bad = Array<u8>();
    bad.append(104);
    bad.append(255);
    assert(text.Utf8.decode(bad).is_none(), "0xFF is never UTF-8");
    assert(text.Utf8.decode_lossy(bad) == "h\u{FFFD}", "replaced");
    return 0;
}

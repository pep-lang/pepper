<!-- Generated from runtime/text/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The text module

Converting text to and from bytes in a given encoding.

Bring it in with `import text`. A `String` always holds UTF-8; these
types encode one into the bytes of an encoding (`u8[]`) and decode bytes
back. Each `decode` is strict and gives none when the bytes are not valid
in the encoding (code page 437's always succeeds, since every byte is a
character); each `decode_lossy` replaces what is invalid with U+FFFD
and always succeeds.

- [UTF-8](text-utf8.md): `Utf8`
- [UTF-16](text-utf16.md): `Utf16`
- [ASCII](text-ascii.md): `Ascii`
- [Code page 437](text-code_page_437.md): `CodePage437`

**Example**
```pepper
import text;

main(): int {
    var bytes = text.Utf8.encode("héllo");
    assert(bytes.count == 6, "é takes two bytes");
    assert(text.Utf8.decode(bytes).value() == "héllo", "round trip");
    return 0;
}
```

Source: `runtime/text/module.pep`

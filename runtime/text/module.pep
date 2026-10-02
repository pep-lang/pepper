## Converting text to and from bytes in a given encoding.
##
## Bring it in with `import text`. A `String` always holds UTF-8; these
## types encode one into the bytes of an encoding (`u8[]`) and decode bytes
## back. Each `decode` is strict and gives none when the bytes are not valid
## in the encoding; each `decode_lossy` replaces what is invalid with U+FFFD
## and always succeeds.
##
## - [UTF-8](text-utf8.md): `Utf8`
## - [UTF-16](text-utf16.md): `Utf16`
## - [ASCII](text-ascii.md): `Ascii`
##
## @example
##     import text;
##
##     main(): int {
##         var bytes = text.Utf8.encode("héllo");
##         assert(bytes.count == 6, "é takes two bytes");
##         assert(text.Utf8.decode(bytes).value() == "héllo", "round trip");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "ascii";
import "utf16";
import "utf8";

export Ascii;
export Utf16;
export Utf8;

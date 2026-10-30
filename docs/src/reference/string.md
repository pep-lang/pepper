<!-- Generated from runtime/string.pep by `pep-doc reference`. Do not edit. -->

# String

Source: `runtime/string.pep`

## String

```pepper
struct String
```

A mutable, reference-counted string of UTF-8 text. A string literal
(`"text"`) is a `String` wherever a `String` is expected; its own type is
`StringConstant`.

Two measures describe a String, and each API says which one it uses:

- **Code points** (Unicode characters): `length`, `is_empty`,
  the indexer `s[i]`, `substr`, and iteration.
- **Bytes** of UTF-8: `size`, `find`, `starts_with`, and
  `ends_with`. The byte size is the authoritative length, so the data may
  contain NUL bytes. It is never derived from a terminator.

A String's bytes are not guaranteed to be followed by a NUL. Only
`c_str()` guarantees one, so call it to hand the text to C; anything else
that reads the bytes must stop at `size`.

A String is a reference type: `var b = a;` shares one object, so
`append`, `+=`, and `grow` are visible through every reference. Use
`copy()` or `+` for an independent copy. Equality (`==`) compares
content.

A `StringIterator` panics when the String has been changed by `append`,
`+=`, or `grow` since the iterator was created, so modifying a String
while a `for` loop iterates it panics.

To build text from values, use an interpolated string
(`$"{name}: {count:>4}"`) or `String.format("{0}: {1:>4}", name, count)`,
a compiler intrinsic whose braces name its arguments by position (see
the String interpolation chapter).

**Example**
```pepper
var s = "héllo";
assert(s.length == 5, "5 code points");
assert(s.size == 6, "6 bytes: 'é' is 2");
s.append(" world");
assert(s.find("world") == 7, "find returns a byte offset");
assert(s[1] == "é", "the indexer counts code points");
for (var c in s) {
    print(c);   # one code point per line
}
```

### Properties

#### length

```pepper
var length: ulong { get; }
```

The number of Unicode code points. O(1).

**See also**
- `size`

#### size

```pepper
var size: ulong { get; }
```

The number of bytes of UTF-8. O(1).

**See also**
- `length`

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the String has no code points. O(1).

### Constructor

#### String()

```pepper
construct(data: __ptr<char> = __null, size: ulong = 0, length: ulong = 0)
```

Creates a String by copying `size` bytes of `data` into a new
NUL-terminated buffer. With no arguments, it creates an empty String
with no buffer; its `c_str()` is still a valid empty C string.

When `data` is not `__null` and `size` is 0, `data` is treated as a
NUL-terminated C string:

- with `length` nonzero, `size` becomes the byte length of its first
  `length` code points (0 if the C string is not valid UTF-8);
- with `length` 0, `size` becomes the C string's whole byte length.

When `length` is 0, it is counted from the bytes. A nonzero `length` is
trusted, not checked against the data. Runs in O(size).

**Parameters**
- `data` — the bytes to copy; `__null` for an empty String (then pass no sizes, because they are stored as given)
- `size` — the number of bytes to copy from `data`; 0 treats `data` as a NUL-terminated C string
- `length` — the number of code points in those bytes

**Example**
```pepper
var empty = String();
var s = "abc";
var copy = String(s.c_str(), s.size, s.length);
```

### Static methods

#### length_of

```pepper
static length_of(data: __ptr<char>, size: ulong): ulong
```

Returns the number of Unicode code points in the first `size` bytes at
`data`. Runs in O(size).

Returns 0 when `data` is `__null`, when `size` is 0, or when the bytes
are not valid UTF-8: any malformed or truncated sequence makes the
whole count 0.

**Parameters**
- `data` — the UTF-8 bytes to measure
- `size` — the number of bytes to measure

**Returns**
- the number of code points, or 0 for invalid UTF-8

### Methods

#### bytes

```pepper
bytes(): u8[]
```

Returns a new array holding the String's UTF-8 bytes, without a
terminating NUL. Runs in O(size).

**Returns**
- a new array of `size` bytes

**Example**
```pepper
var data = "hi".bytes();
assert(data.count == 2 && data[0] == 104, "the bytes of 'h' and 'i'");
```

#### grow

```pepper
grow(new_size: ulong)
```

Extends the byte buffer to `new_size` bytes and fills the new bytes
with zeros. Does nothing when `new_size` is not greater than `size`.

A low-level primitive for `append`. It updates `size` but not `length`,
so the zero bytes it adds are not counted as code points until the
caller overwrites them and fixes the length. When it grows the buffer,
it invalidates running iterators and may reallocate the buffer, which invalidates
pointers from `c_str()`. Runs in O(new_size).

**Parameters**
- `new_size` — the new byte length

#### append

```pepper
append(rhs: String)
```

Appends the content of `rhs` to this String in place, updating `size`
and `length`.

Always invalidates running iterators, even when `rhs` is empty, so
appending during iteration panics. It may reallocate the buffer. Every reference to
this String sees the change. Runs in O(size + rhs.size).

**Parameters**
- `rhs` — the String to append; it is not modified

**Example**
```pepper
var s = "TEST";
s.append("ING");   # s == "TESTING"
```

#### operator []

```pepper
[](idx: int): String
```

Returns the code point at code-point index `idx` as a new
one-code-point String.

A negative `idx` counts from the end (`s[-1]` is the last code point).
`length` is added until the index is non-negative, so any negative
index wraps, and `s[-7]` of a 3-code-point String is `s[2]`. Runs in
O(idx) because it walks the UTF-8 bytes. Use `for (var c in s)` to
visit every code point in O(size).

**Parameters**
- `idx` — the code-point index; negative counts from the end

**Returns**
- a new String that holds the one code point

**Panics**
- if `idx` is not less than `length` after the negative index is normalized, which includes any index into an empty String

**Example**
```pepper
var s = "TEST";
assert(s[0] == "T", "first");
assert(s[-1] == "T", "last");
```

#### operator ==

```pepper
==(rhs: String): bool
```

Returns whether this String and `rhs` have the same content, compared
byte by byte. Strings with different `length` are unequal without
comparing bytes. Runs in O(size).

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when both hold the same bytes

#### operator ==

```pepper
==(rhs: StringConstant): bool
```

Returns whether this String holds the same bytes as the
`StringConstant` `rhs`, a literal included. Runs in O(size) and
copies nothing.

**Parameters**
- `rhs` — the text to compare with

**Returns**
- true when both hold the same bytes

#### operator +=

```pepper
+=(rhs: String): String
```

Appends `rhs` in place, like `append`, and returns this same String,
not a copy. `s += t` modifies the object that every reference to `s`
shares, and invalidates running iterators.

**Parameters**
- `rhs` — the String to append

**Returns**
- this String, after appending

**Example**
```pepper
var s = "a";
s += "b";   # s == "ab"
```

#### iterate

```pepper
iterate(): StringIterator
```

Returns an iterator over the String's code points, which makes String
`Iterable<String>`: `for (var c in s)` visits each code point as a
one-code-point String, the same value `s[i]` gives.

The iterator holds a reference to this String. The whole loop runs in
O(size). Modifying the String during iteration makes the iterator
panic.

**Returns**
- a new iterator, positioned before the first code point

**Example**
```pepper
var n = 0;
for (var c in "héllo") {
    n = n + 1;   # 5 iterations
}
```

#### c_str

```pepper
c_str(): __ptr<char>
```

Returns the String's buffer as a NUL-terminated C string.

This is the one API that guarantees a NUL after the content: a String
is not otherwise guaranteed to be NUL-terminated, so code that needs
the terminator calls `c_str()` rather than relying on the buffer.

The pointer is owned by the String. It is valid until the String is
destroyed or `append`, `+=`, or `grow` reallocates it. It is never
`__null`: a String built with no data (`String()`) returns a constant
empty C string, so it can go to C as it is. C functions stop at the
first NUL byte in the content.

**Returns**
- the String's NUL-terminated byte buffer

#### copy

```pepper
copy(): String
```

Returns a new String with the same content and its own buffer, so
later changes to either String do not affect the other. Runs in O(size).

This is also how `copy(value)` copies a String (the `Copyable<String>`
implementation).

**Returns**
- an independent copy of this String

**Example**
```pepper
var a = "abc";
var b = a.copy();
b.append("d");   # a is still "abc"
```

#### clone

```pepper
[Deprecated("use 'copy' instead", "copy")] clone(): String
```

Deprecated: use `copy` instead. Returns a new String with the same
content and its own buffer.

**Returns**
- an independent copy of this String

#### find

```pepper
find(needle: String, from: ulong = 0): long
```

Returns the **byte offset** of the first occurrence of `needle`, or -1
when it does not occur.

The offset counts bytes, not code points. To use it with `s[i]` or
`substr`, convert it with `String.length_of(s.c_str(), offset)`.
An empty `needle` is found at 0 unless this String is empty, in which
case the result is -1. The result is also -1 when `needle` is not valid
UTF-8, or when this String holds invalid UTF-8 before the first match.
Bytes past the match are not checked, so searching on from each match
(as `split` and `replace` do) reads the String once in all. The
search is the C library's `memmem`, which compares many bytes per step
(Windows, which has none, jumps between matches of the first byte with
`memchr`).

With `from`, the search starts at that byte offset, which must be a
code point boundary (an offset `find` returned, plus a match's size,
is one); an offset past the end, or inside a code point, finds
nothing. The result still counts from the start of the String.

**Parameters**
- `needle` — the text to search for
- `from` — the byte offset to start searching at; 0 by default

**Returns**
- the byte offset of the first match at or after `from`, or -1 when there is none

**Example**
```pepper
var s = "TESTING";
assert(s.find("STI") == 2, "byte offset");
assert(s.find("xyz") == -1, "absent");
assert("a,b,c".find(",", 2) == 3, "the second comma");
```

#### rfind

```pepper
rfind(needle: String): long
```

Returns the byte offset of the last place `needle` occurs in this
String, or -1 when it does not occur. An empty `needle` is found at
`size`. Runs in O(size * needle.size).

**Parameters**
- `needle` — the text to search for

**Returns**
- the byte offset of the last match, or -1 when there is none

**Example**
```pepper
assert("a/b/c".rfind("/") == 3, "the last slash");
assert("abc".rfind("x") == -1, "absent");
```

#### split

```pepper
split(separator: String): String[]
```

Splits the String at every occurrence of `separator` and returns the
pieces between them, in order. Adjacent separators give an empty
piece, and so does a separator at either end: `"a,,b".split(",")` is
`["a", "", "b"]` and `",a".split(",")` is `["", "a"]`. A String
without `separator`, the empty String included, gives one piece: the
whole String. Runs in O(size * separator.size).

**Parameters**
- `separator` — the text to split at

**Returns**
- a new Array with one new String per piece

**Panics**
- if `separator` is empty

**Example**
```pepper
var parts = "a,b,,c".split(",");
assert(parts.count == 4, "four pieces");
assert(parts[2] == "", "an empty piece");
```

#### split_once

```pepper
split_once(separator: String): (String, String)?
```

Splits the String at the first occurrence of `separator`: the text
before it and the text after it, or none when it does not occur.
Runs in O(size * separator.size).

**Parameters**
- `separator` — the text to split at

**Returns**
- the pieces before and after the first `separator`, or none

**Panics**
- if `separator` is empty

**Example**
```pepper
var header = "Host: example.com".split_once(": ");
assert(header.is_value(), "has a colon");
var (name, value) = header.value();
assert(name == "Host" && value == "example.com", "split");
```

#### join

```pepper
join(parts: String[]): String
```

Returns the pieces of `parts` joined into one String, with this String
between each two of them: `", ".join(names)`. No parts give an empty
String, and one part gives a copy of it. Runs in O(total size).

**Parameters**
- `parts` — the pieces to join

**Returns**
- a new String

**Example**
```pepper
var parts = Array<String>();
parts.append("a");
parts.append("b");
assert(", ".join(parts) == "a, b", "joined");
```

#### replace

```pepper
replace(from: String, to: String): String
```

Returns a copy of this String with every occurrence of `from` replaced
by `to`, scanning left to right without overlaps: `"aaa".replace("aa",
"b")` is `"ba"`. Runs in O(size * from.size) plus the result's
size.

**Parameters**
- `from` — the text to replace
- `to` — the text to put in its place

**Returns**
- a new String

**Panics**
- if `from` is empty

**Example**
```pepper
assert("a\r\nb".replace("\r\n", "\n") == "a\nb", "line endings");
```

#### contains

```pepper
contains(needle: String): bool
```

Returns whether `needle` occurs in this String (`find(needle) >= 0`).
Because of that, an empty String contains nothing, not even `""`.
Runs in O(size * needle.size).

**Parameters**
- `needle` — the text to search for

**Returns**
- true when `needle` occurs

#### starts_with

```pepper
starts_with(prefix: String): bool
```

Returns whether this String begins with the bytes of `prefix`. An
empty `prefix` always matches. Runs in O(prefix.size).

**Parameters**
- `prefix` — the text to test for

**Returns**
- true when the first `prefix.size` bytes equal `prefix`

#### ends_with

```pepper
ends_with(suffix: String): bool
```

Returns whether this String ends with the bytes of `suffix`. An empty
`suffix` always matches. Runs in O(suffix.size).

**Parameters**
- `suffix` — the text to test for

**Returns**
- true when the last `suffix.size` bytes equal `suffix`

#### substr

```pepper
substr(start: ulong, count: ulong): String
```

Returns a new String of up to `count` code points starting at
code-point index `start`. Both arguments count code points, not bytes.

`count` is clamped to the code points that remain. When `start` is at
or past `length`, the result is an empty String. Runs in O(size).

**Parameters**
- `start` — the code-point index of the first code point to copy
- `count` — the maximum number of code points to copy

**Returns**
- a new String that holds the selected code points

**Example**
```pepper
var s = "TEST";
assert(s.substr(1, 2) == "ES", "middle");
assert(s.substr(0, 99) == "TEST", "count is clamped");
assert(s.substr(4, 5) == "", "start past the end");
```

#### operator !=

```pepper
!=(rhs: String): bool
```

Returns whether this String and `rhs` differ in content, the negation
of `==`. Runs in O(size).

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when the contents differ

#### operator !=

```pepper
!=(rhs: StringConstant): bool
```

Returns whether this String differs from the `StringConstant` `rhs`.

**Parameters**
- `rhs` — the text to compare with

**Returns**
- true when the contents differ

#### operator +

```pepper
+(rhs: String): String
```

Returns a new String that holds this String followed by `rhs`. Neither
operand is modified. Runs in O(size + rhs.size).

**Parameters**
- `rhs` — the String to append to the copy

**Returns**
- a new concatenated String

**Example**
```pepper
var greeting = "Hello, " + "world";
```

#### to_string

```pepper
to_string(): String
```

Returns this String, so a String is `ToString` and can be
interpolated (`$"name: {name}"`). The result is the same object, not
a copy. O(1).

**Returns**
- this String

#### byte_at

```pepper
byte_at(index: ulong): byte
```

Returns the byte at byte offset `index` of the UTF-8 data. O(1).

The offset counts bytes, not code points, so a byte inside a
multi-byte code point is returned as it is. Compare the result with a
character literal (`s.byte_at(0) == '#'`).

**Parameters**
- `index` — the byte offset, less than `size`

**Returns**
- the byte at `index`

**Panics**
- if `index` is not less than `size` ("String byte_at index out of bounds")

**Example**
```pepper
var s = "a=b";
assert(s.byte_at(1) == '=', "second byte");
```

#### substr_bytes

```pepper
substr_bytes(start: ulong, size: ulong): String
```

Returns a new String of the `size` bytes starting at byte offset
`start`. Both arguments count bytes, not code points, so offsets from
`find` can be used directly. Runs in O(size).

**Parameters**
- `start` — the byte offset of the first byte to copy
- `size` — the number of bytes to copy

**Returns**
- a new String that holds those bytes

**Panics**
- if `start + size` is greater than `size` ("String substr_bytes range out of bounds")
- if `start` or `start + size` falls inside a multi-byte code point ("String substr_bytes splits a code point")

**Example**
```pepper
var s = "key=value";
var eq = s.find("=") as ulong;
assert(s.substr_bytes(0, eq) == "key", "before '='");
assert(s.substr_bytes(eq + 1, s.size - eq - 1) == "value", "after '='");
```

#### compare

```pepper
compare(other: String): int
```

Compares this String with `other` byte by byte, for sorting. For
valid UTF-8 this is code-point order; a String that is a prefix of the
other orders first. Runs in O(min(size, other.size)).

**Parameters**
- `other` — the String to compare with

**Returns**
- a negative number when this String orders before `other`, 0 when both hold the same bytes, and a positive number when it orders after

**Example**
```pepper
assert("apple".compare("banana") < 0, "a before b");
assert("ab".compare("abc") < 0, "a prefix orders first");
assert("x".compare("x") == 0, "equal");
```

#### operator <

```pepper
<(other: String): bool
```

Returns whether this String orders before `other`, as `compare` does.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when `compare(other) < 0`

#### operator <

```pepper
<(other: StringConstant): bool
```

Returns whether this String orders before the `StringConstant` `other`,
byte by byte, a literal included. Copies nothing.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is negative

#### operator <=

```pepper
<=(other: String): bool
```

Returns whether this String orders before `other` or equals it, as
`compare` does.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when `compare(other) <= 0`

#### operator <=

```pepper
<=(other: StringConstant): bool
```

Returns whether this String orders before or equals the `StringConstant` `other`,
byte by byte, a literal included. Copies nothing.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is not positive

#### operator >

```pepper
>(other: String): bool
```

Returns whether this String orders after `other`, as `compare` does.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when `compare(other) > 0`

#### operator >

```pepper
>(other: StringConstant): bool
```

Returns whether this String orders after the `StringConstant` `other`,
byte by byte, a literal included. Copies nothing.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is positive

#### operator >=

```pepper
>=(other: String): bool
```

Returns whether this String orders after `other` or equals it, as
`compare` does.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when `compare(other) >= 0`

#### operator >=

```pepper
>=(other: StringConstant): bool
```

Returns whether this String orders after or equals the `StringConstant` `other`,
byte by byte, a literal included. Copies nothing.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is not negative

#### trim_end

```pepper
trim_end(): String
```

Returns a new String without the whitespace at the end: spaces, tabs,
carriage returns, line feeds, vertical tabs and form feeds (ASCII
only). Runs in O(size).

**Returns**
- a new String with the trailing whitespace removed

**Example**
```pepper
assert("code;  \r\n".trim_end() == "code;", "trailing whitespace");
assert("  indented".trim_end() == "  indented", "leading kept");
```

#### trim_start

```pepper
trim_start(): String
```

Returns a new String without the whitespace at the start: spaces,
tabs, carriage returns, line feeds, vertical tabs and form feeds
(ASCII only). Runs in O(size).

**Returns**
- a new String with the leading whitespace removed

**Example**
```pepper
assert("  \tcode".trim_start() == "code", "leading whitespace");
```

#### trim

```pepper
trim(): String
```

Returns a new String without the whitespace at either end, as
`trim_start` and `trim_end` do. Runs in O(size).

**Returns**
- a new String with the leading and trailing whitespace removed

**Example**
```pepper
assert(" \t value \r\n".trim() == "value", "both ends");
```

#### lower

```pepper
lower(): String
```

Returns a new String with the ASCII letters `A` to `Z` changed to `a`
to `z`. Every other character, including non-ASCII letters, is kept
as it is, so the result is valid UTF-8 of the same size. Runs in
O(size).

**Returns**
- a new String in lowercase

**Example**
```pepper
assert("Content-Type".lower() == "content-type", "ASCII lowered");
assert("Ärger".lower() == "Ärger", "non-ASCII kept");
```

#### upper

```pepper
upper(): String
```

Returns a new String with the ASCII letters `a` to `z` changed to `A`
to `Z`. Every other character, including non-ASCII letters, is kept
as it is, so the result is valid UTF-8 of the same size. Runs in
O(size).

**Returns**
- a new String in uppercase

**Example**
```pepper
assert("get".upper() == "GET", "ASCII raised");
```

#### lines

```pepper
lines(): String[]
```

Splits the String into lines and returns them without their line
endings. A line ends at `"\n"` or `"\r\n"`. A final line with no
ending is included, but the end of the String after a final line
ending does not start another line, so `"a\nb\n"` and `"a\nb"` both
give `["a", "b"]`, and `""` gives no lines. Runs in O(size).

**Returns**
- a new Array with one new String per line

**Example**
```pepper
var lines = "first\r\nsecond\n\nfourth".lines();
assert(lines.count == 4, "four lines");
assert(lines[1] == "second", "\\r\\n removed");
assert(lines[2] == "", "an empty line");
```

#### repeat

```pepper
repeat(count: ulong): String
```

Returns a new String that holds this String `count` times in a row.
`count` 0, or an empty String, gives an empty String. Runs in
O(size * count).

**Parameters**
- `count` — how many copies to join

**Returns**
- a new String of `size * count` bytes

**Example**
```pepper
assert("ab".repeat(3) == "ababab", "three copies");
var indent = " ".repeat(8);   # eight spaces
```

## StringConstant

```pepper
[Value] struct StringConstant
```

The text of a string literal: a pointer to its bytes, which never change
and are never freed, with their byte size and code-point length. A string
literal's type is `StringConstant`, and so is a `const` with no written
type initialized from one (`const NAME = "pepper";`); where a `String` is
expected, the literal is a `String` (see the Strings chapter of the
book).

A `StringConstant` is a `[Value]` type: copying one copies the pointer
and steps no reference count, and any thread may read it. Its bytes
always end in a NUL byte, so `c_str()` goes to C as it is. It has
`String`'s read API, measured the same way (`length` in code points,
`size` and offsets in bytes); the methods that make new text return a
`String`. A `StringConstant` converts to a `String` wherever a `String`
is expected, as if `String` had an `[Implicit]` constructor from it: the
conversion, like `String(text)`, copies the bytes. Where C expects a
`char*`, it passes its own bytes, as `c_str()` does.

Unlike a `String`, a `StringConstant` may hold bytes that are not UTF-8:
a literal's `\x80` to `\xFF` escapes write raw bytes, so a static byte
table can be a string constant. Read such bytes with `size` and
`byte_at`; `length` is 0 for them, and the code-point API (the indexer,
iteration) and a conversion to `String` need UTF-8.

**Example**
```pepper
StringConstant name = "pepper";
assert(name.length == 6, "6 code points");
assert(name.starts_with("pep"), "the read API of String");
String copy = name;   # a new String with its own bytes
copy.append("!");
```

### Properties

#### length

```pepper
var length: ulong { get; }
```

The number of Unicode code points, or 0 when the bytes are not UTF-8. O(1).

**See also**
- `size`

#### size

```pepper
var size: ulong { get; }
```

The number of bytes, not counting the NUL terminator. O(1).

**See also**
- `length`

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the text has no bytes, and so no code points. O(1).

### Constructor

#### StringConstant()

```pepper
construct(data: __ptr<char> = __null, size: ulong = 0, length: ulong = 0)
```

Creates a `StringConstant` over the `size` bytes at `data`. The
compiler calls it for each string literal. The bytes must be followed
by a NUL byte and must never change or be freed while the program
runs; no other bytes meet that, so code outside the runtime has no
reason to call it with arguments. With no arguments, it is the empty
text.

**Parameters**
- `data` — the constant NUL-terminated bytes
- `size` — the number of bytes before the NUL terminator
- `length` — the number of code points in those bytes

### Methods

#### c_str

```pepper
c_str(): __ptr<char>
```

Returns the text as a NUL-terminated C string, with no copy. It is
never `__null`, and it stays valid for the whole run of the program.

**Returns**
- the constant NUL-terminated bytes

#### to_string

```pepper
to_string(): String
```

Returns a new String with a copy of the text. Converting a
`StringConstant` to a `String`, or calling `String(text)`, calls it.
Runs in O(size).

**Returns**
- a new String with the same content

#### bytes

```pepper
bytes(): u8[]
```

Returns a copy of the UTF-8 bytes in a new array, as `String.bytes`
does. Runs in O(size).

**Returns**
- a new array of `size` bytes

#### operator []

```pepper
[](idx: int): String
```

Returns the code point at code-point index `idx` as a new
one-code-point String, as `String`'s indexer does. A negative `idx`
counts from the end. Runs in O(idx).

**Parameters**
- `idx` — the code-point index; negative counts from the end

**Returns**
- a new String that holds the one code point

**Panics**
- if `idx` is not less than `length` after the negative index is normalized

#### operator ==

```pepper
==(rhs: StringConstant): bool
```

Returns whether two texts hold the same bytes, a literal `rhs`
included. Runs in O(size).

**Parameters**
- `rhs` — the text to compare with

**Returns**
- true when both hold the same bytes

#### operator !=

```pepper
!=(rhs: StringConstant): bool
```

Returns whether two texts differ.

**Parameters**
- `rhs` — the text to compare with

**Returns**
- true when the bytes differ

#### operator ==

```pepper
==(rhs: String): bool
```

Returns whether this text holds the same bytes as the String `rhs`.
Runs in O(size) and copies nothing.

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when both hold the same bytes

#### operator !=

```pepper
!=(rhs: String): bool
```

Returns whether this text differs from the String `rhs`.

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when the bytes differ

#### operator +

```pepper
+(rhs: String): String
```

Returns a new String: this text followed by `rhs`.

**Parameters**
- `rhs` — the text to append

**Returns**
- a new String

#### find

```pepper
find(needle: String, from: ulong = 0): long
```

Returns the byte offset of the first occurrence of `needle` at or
after byte offset `from`, or -1, as `String.find` does.

**Parameters**
- `needle` — the text to search for
- `from` — the byte offset to start searching at; 0 by default

**Returns**
- the byte offset of the first match, or -1 when there is none

#### rfind

```pepper
rfind(needle: String): long
```

Returns the byte offset of the last occurrence of `needle`, or -1, as
`String.rfind` does.

**Parameters**
- `needle` — the text to search for

**Returns**
- the byte offset of the last match, or -1 when there is none

#### contains

```pepper
contains(needle: String): bool
```

Returns whether `needle` occurs in the text.

**Parameters**
- `needle` — the text to search for

**Returns**
- true when `find(needle)` is not -1

#### starts_with

```pepper
starts_with(prefix: String): bool
```

Returns whether the text starts with `prefix`. An empty prefix always
matches.

**Parameters**
- `prefix` — the text to look for at the start

**Returns**
- true when the first bytes are `prefix`'s

#### ends_with

```pepper
ends_with(suffix: String): bool
```

Returns whether the text ends with `suffix`. An empty suffix always
matches.

**Parameters**
- `suffix` — the text to look for at the end

**Returns**
- true when the last bytes are `suffix`'s

#### substr

```pepper
substr(start: ulong, count: ulong): String
```

Returns up to `count` code points starting at code-point index
`start`, as a new String, as `String.substr` does.

**Parameters**
- `start` — the code-point index of the first code point
- `count` — the most code points to take

**Returns**
- a new String; empty when `start` is past the end

#### byte_at

```pepper
byte_at(index: ulong): byte
```

Returns the byte at byte offset `index`.

**Parameters**
- `index` — the byte offset

**Returns**
- the byte at `index`

**Panics**
- if `index` is not less than `size`

#### substr_bytes

```pepper
substr_bytes(start: ulong, size: ulong): String
```

Returns the `size` bytes from byte offset `start` as a new String, as
`String.substr_bytes` does.

**Parameters**
- `start` — the byte offset of the first byte
- `size` — the number of bytes

**Returns**
- a new String

**Panics**
- if the range is not inside the text
- if `start` or `start + size` falls inside a code point

#### compare

```pepper
compare(other: String): int
```

Compares this text with `other` byte by byte, for sorting, as
`String.compare` does.

**Parameters**
- `other` — the text to compare with

**Returns**
- a negative number, 0, or a positive number when this text sorts before, the same as, or after `other`

#### operator <

```pepper
<(other: StringConstant): bool
```

Returns whether this text sorts before `other`, byte by byte.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is negative

#### operator <

```pepper
<(other: String): bool
```

Returns whether this text sorts before the String `other`, byte by byte.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when the byte-by-byte order is negative

#### operator <=

```pepper
<=(other: StringConstant): bool
```

Returns whether this text sorts before or the same as `other`, byte by byte.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is not positive

#### operator <=

```pepper
<=(other: String): bool
```

Returns whether this text sorts before or the same as the String `other`, byte by byte.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when the byte-by-byte order is not positive

#### operator >

```pepper
>(other: StringConstant): bool
```

Returns whether this text sorts after `other`, byte by byte.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is positive

#### operator >

```pepper
>(other: String): bool
```

Returns whether this text sorts after the String `other`, byte by byte.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when the byte-by-byte order is positive

#### operator >=

```pepper
>=(other: StringConstant): bool
```

Returns whether this text sorts after or the same as `other`, byte by byte.

**Parameters**
- `other` — the text to compare with

**Returns**
- true when the byte-by-byte order is not negative

#### operator >=

```pepper
>=(other: String): bool
```

Returns whether this text sorts after or the same as the String `other`, byte by byte.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when the byte-by-byte order is not negative

#### trim_end

```pepper
trim_end(): String
```

Returns a new String without the whitespace at the end.

**Returns**
- a new String with the trailing whitespace removed

#### trim_start

```pepper
trim_start(): String
```

Returns a new String without the whitespace at the start.

**Returns**
- a new String with the leading whitespace removed

#### trim

```pepper
trim(): String
```

Returns a new String without the whitespace at either end.

**Returns**
- a new String with the leading and trailing whitespace removed

#### lower

```pepper
lower(): String
```

Returns a new String with the ASCII letters in lowercase.

**Returns**
- a new String

#### upper

```pepper
upper(): String
```

Returns a new String with the ASCII letters in uppercase.

**Returns**
- a new String

#### lines

```pepper
lines(): String[]
```

Returns the lines of the text, split at `"\n"` or `"\r\n"`, as
`String.lines` does.

**Returns**
- a new array of Strings, without the line breaks

#### repeat

```pepper
repeat(count: ulong): String
```

Returns a new String of `count` copies of the text.

**Parameters**
- `count` — the number of copies

**Returns**
- a new String; empty when `count` is 0

#### split

```pepper
split(separator: String): String[]
```

Returns the pieces of the text between each `separator`, as
`String.split` does.

**Parameters**
- `separator` — the text to split at

**Returns**
- a new array of Strings

**Panics**
- if `separator` is empty

#### split_once

```pepper
split_once(separator: String): (String, String)?
```

Returns the text before and after the first `separator`, or `Empty`
when it does not occur, as `String.split_once` does.

**Parameters**
- `separator` — the text to split at

**Returns**
- the two pieces, or `Empty`

**Panics**
- if `separator` is empty

#### join

```pepper
join(parts: String[]): String
```

Returns `parts` joined into a new String with this text between each
two.

**Parameters**
- `parts` — the Strings to join

**Returns**
- a new String

#### replace

```pepper
replace(from: String, to: String): String
```

Returns a new String with every occurrence of `from` replaced by
`to`, as `String.replace` does.

**Parameters**
- `from` — the text to replace
- `to` — the text to put in its place

**Returns**
- a new String

**Panics**
- if `from` is empty

#### iterate

```pepper
iterate(): StringIterator
```

Returns an iterator over the code points, so `for (var c in text)`
visits each one as a one-code-point String.

**Returns**
- a new iterator, positioned before the first code point

## to_string

```pepper
to_string(value: long): String
```

Returns the decimal text of `value`, with a leading `-` when it is
negative.

`to_string` is overloaded for every integer type, so a call with any
integer picks its own overload.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"-42"`

**Example**
```pepper
assert(to_string(-42) == "-42", "negative");
var where = to_string(line) + ":" + to_string(column);
```

## to_string

```pepper
to_string(value: ulong): String
```

Returns the decimal text of `value`.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"18446744073709551615"`

## to_string

```pepper
to_string(value: int): String
```

Returns the decimal text of `value`, with a leading `-` when it is
negative.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"7"`

## to_string

```pepper
to_string(value: uint): String
```

Returns the decimal text of `value`.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"7"`

## to_string

```pepper
to_string(value: short): String
```

Returns the decimal text of `value`, with a leading `-` when it is
negative.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"-7"`

## to_string

```pepper
to_string(value: ushort): String
```

Returns the decimal text of `value`.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"7"`

## to_string

```pepper
to_string(value: char): String
```

Returns the decimal text of `value`, with a leading `-` when it is
negative.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"-7"`

## to_string

```pepper
to_string(value: byte): String
```

Returns the decimal text of `value`.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"7"`

## to_string

```pepper
to_string(value: bool): String
```

Returns `"true"` or `"false"`.

**Parameters**
- `value` — the value to convert

**Returns**
- a new String, `"true"` or `"false"`

## to_string

```pepper
to_string(value: double): String
```

Returns the shortest decimal text that reads back as exactly `value`,
as Swift prints a `Double`.

A whole number keeps a `.0` (`"3.0"`), so the text always reads as a
floating-point number. Values from 1e-4 up to 1e16 print in decimal;
others use an exponent (`"1e+16"`, `"1.5e-05"`). The special values are
`"nan"`, `"inf"` and `"-inf"`. For a fixed number of fraction digits,
interpolate with a precision instead: `$"{value:.2}"`.

The digits come from the Ryu algorithm, which takes a fixed, small
number of steps per value.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"0.1"` or `"-2.5"`

**Example**
```pepper
assert(to_string(0.1) == "0.1", "shortest");
assert(to_string(3.0) == "3.0", "keeps the point");
assert(to_string(1.0e20) == "1e+20", "exponent");
```

## to_string

```pepper
to_string(value: float): String
```

Returns the shortest decimal text that reads back as exactly `value` as
a `float`, laid out as `to_string(double)` lays it out.

**Parameters**
- `value` — the number to convert

**Returns**
- a new String such as `"0.1"`

**Example**
```pepper
float third = 1.0 / 3.0;
assert(to_string(third) == "0.33333334", "a float's digits");
```

## to_string

```pepper
to_string<A, B>(value: (A, B)): String
```

Returns the text of a pair, `"(1, x)"`: each element's `to_string`
text, separated by `", "`, in parentheses. A String element is its text
without quotes. Tuples of up to eight elements convert this way.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, two)"`

**Example**
```pepper
assert(to_string((1, "two")) == "(1, two)", "a pair");
var nested = (1, (2.5, true));
assert($"{nested}" == "(1, (2.5, true))", "nested");
```

## to_string

```pepper
to_string<A, B, C>(value: (A, B, C)): String
```

Returns the text of a three-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3)"`

## to_string

```pepper
to_string<A, B, C, D>(value: (A, B, C, D)): String
```

Returns the text of a four-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element
- `D` — the type of the fourth element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3, 4)"`

## to_string

```pepper
to_string<A, B, C, D, E>(value: (A, B, C, D, E)): String
```

Returns the text of a five-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element
- `D` — the type of the fourth element
- `E` — the type of the fifth element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3, 4, 5)"`

## to_string

```pepper
to_string<A, B, C, D, E, F>(value: (A, B, C, D, E, F)): String
```

Returns the text of a six-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element
- `D` — the type of the fourth element
- `E` — the type of the fifth element
- `F` — the type of the sixth element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3, 4, 5, 6)"`

## to_string

```pepper
to_string<A, B, C, D, E, F, G>(value: (A, B, C, D, E, F, G)): String
```

Returns the text of a seven-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element
- `D` — the type of the fourth element
- `E` — the type of the fifth element
- `F` — the type of the sixth element
- `G` — the type of the seventh element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3, 4, 5, 6, 7)"`

## to_string

```pepper
to_string<A, B, C, D, E, F, G, H>(value: (A, B, C, D, E, F, G, H)): String
```

Returns the text of an eight-element tuple, as the pair overload does.

**Type parameters**
- `A` — the type of the first element
- `B` — the type of the second element
- `C` — the type of the third element
- `D` — the type of the fourth element
- `E` — the type of the fifth element
- `F` — the type of the sixth element
- `G` — the type of the seventh element
- `H` — the type of the eighth element

**Parameters**
- `value` — the tuple to convert

**Returns**
- a new String such as `"(1, 2, 3, 4, 5, 6, 7, 8)"`

## print

```pepper
print(text: String)
```

Writes `text` and a line break to standard output.

Any other value prints through `print(value)`, which writes its
`to_string` text. To combine values, interpolate them
(`print($"total: {n}")`), or pass a format string and arguments, which
prints what `String.format` makes of them (`print("{0} of {1}", a, b)`).
A string with no arguments after it is printed as written, braces
included.

Each line is flushed as it is printed, as Rust's `println!` does, so the
output appears as the program runs even when standard output is a pipe
or a file (where C would buffer it until the program exits).

**Parameters**
- `text` — the text to print

**Example**
```pepper
print("hello");
var n = 3;
print($"n = {n}");
print("{0} + {1} = {2}", 1, 2, 1 + 2);   # 1 + 2 = 3
```

## print

```pepper
print<T>(value: T)
```

Writes the text of `value` and a line break to standard output: what
`$"{value}"` would make of it, through `to_string`. That covers numbers,
`bool` (`true` or `false`), tuples, and any type with a `to_string()`
method or a `to_string<T>` override; another type is a compile error at
the argument.

**Type parameters**
- `T` — the type of `value`

**Parameters**
- `value` — the value to print

**Example**
```pepper
print(42);          # 42
print(0.5);         # 0.5
print((1, "two"));  # (1, two)
```

## to_string

```pepper
to_string<T>(value: T): String
```

Returns the text of `value` by calling its `to_string()` method: the
overload for any type that is `ToString`.

Declare a concrete override for a type that has no `to_string()` method
of its own, or whose interpolated text should differ from it; like
`hash<Point>`, an override is used by the whole program, including
interpolated strings.

**Type parameters**
- `T` — the type of `value`; it must have a `to_string()` method unless an override `to_string<T>` exists

**Parameters**
- `value` — the value to convert

**Returns**
- the String that `value.to_string()` returns

**Example**
```pepper
struct Point {
    var x: int = 0;
    var y: int = 0;
    construct(this.x = 0, this.y = 0) {}
}

to_string<Point>(value: Point): String {
    var x = value.x;
    var y = value.y;
    return $"({x}, {y})";
}
```

## ToString

```pepper
trait ToString
```

Something with a text form: a `to_string()` method returning a String.

An interpolated string (`$"total: {a + b}"`) converts each value it holds
with `to_string(value)`, so a struct that implements `ToString` can be
interpolated, as can the integers, `bool`, and `String`, which have
`to_string` overloads. `String`, `StringBuilder` and `io.Path` implement
it.

**Example**
```pepper
struct Point {
    var x: int = 0;
    var y: int = 0;
    construct(this.x = 0, this.y = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"({x}, {y})";
    }
}

var p = Point(1, 2);
assert($"p = {p}" == "p = (1, 2)", "interpolated");
```

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the text of this value.

**Returns**
- a String

## StringBuilder

```pepper
struct StringBuilder
```

Builds a String from many pieces without copying the text built so far
on every append.

`String.append` grows its buffer to the exact new size, so a long run of
appends can copy the text repeatedly. A StringBuilder doubles its buffer
when it is full, so appending is amortized O(piece size). Call
`to_string()` for the result; the builder can keep appending afterward.

**Example**
```pepper
var out = StringBuilder();
out.append("line ").append(to_string(3)).append("\n");
var text = out.to_string();   # "line 3\n"
```

### Properties

#### size

```pepper
var size: ulong { get; }
```

The number of bytes of UTF-8 appended so far. O(1).

#### length

```pepper
var length: ulong { get; }
```

The number of code points appended so far. O(1).

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether nothing has been appended since the builder was
created or last cleared. O(1).

### Constructor

#### StringBuilder()

```pepper
construct(capacity: ulong = 0)
```

Creates an empty StringBuilder, optionally with room for `capacity`
bytes before it has to grow.

**Parameters**
- `capacity` — the number of bytes to allocate up front

### Methods

#### append

```pepper
append(text: String): StringBuilder
```

Appends the text of `text` and returns this builder, so calls can be
chained. Runs in amortized O(text.size).

**Parameters**
- `text` — the String to append; it is not modified

**Returns**
- this StringBuilder

**Example**
```pepper
var b = StringBuilder();
b.append("a").append("b");   # b.to_string() == "ab"
```

#### clear

```pepper
clear()
```

Removes all the text and keeps the buffer for reuse. O(1).

#### to_string

```pepper
to_string(): String
```

Returns a new String holding the text appended so far. The builder
is unchanged. Runs in O(size).

**Returns**
- a new String

## StringIterator

```pepper
[Value] struct StringIterator
```

An `Iterator<String>` over a String's code points, returned by
`String.iterate()` and used by `for (var c in s)`.

Call `next()` to advance, then `current()` for the code point it moved
to. Both methods panic if the String has been modified since the
iterator was created. Create it with `String.iterate()`: a
default-constructed `StringIterator()` has no String to walk.

**Example**
```pepper
var it = "ab".iterate();
while (it.next()) {
    print(it.current());   # "a", then "b"
}
```

### Methods

#### next

```pepper
next(): bool
```

Advances to the next code point. Runs in O(1) per code point.

Returns false once it passes the end, and on every call after that.
A malformed UTF-8 sequence is yielded, together with the rest of the
bytes, as one final "code point".

**Returns**
- true when positioned on a code point, false at the end

**Panics**
- if the String was modified since the iterator was created

#### next

```pepper
next(location: __ptr<char>): bool
```

`next()` for a `for` loop, which passes its own location so that
the panic names the loop.

**Parameters**
- `location` — the loop's location, which a panic reports

**Returns**
- true when positioned on a code point, false at the end

**Panics**
- if the String was modified since the

#### current

```pepper
current(): String
```

Returns the code point that the last successful `next()` moved to, as
a new one-code-point String.

**Returns**
- a new String that holds the current code point

**Panics**
- if the String was modified since the iterator was created
- if `next()` has not been called yet
- if `next()` has returned false (the iterator is past the end)

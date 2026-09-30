<!-- Generated from runtime/string.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# String

Source: `runtime/string.pep`

## String

```pepper
struct String
```

A mutable, reference-counted string of UTF-8 text. String literals
(`"text"`) are `String` values.

Two measures describe a String, and each API says which one it uses:

- **Code points** (Unicode characters): `length()`, `empty()`,
  the indexer `s[i]`, `substr`, and iteration.
- **Bytes** of UTF-8: `size()`, `find`, `starts_with`, and
  `ends_with`. The byte size is the authoritative length, so the data may
  contain NUL bytes. It is never derived from a terminator.

A String is a reference type: `var b = a;` shares one object, so
`append`, `+=`, and `grow` are visible through every reference. Use
`copy()` or `+` for an independent copy. Equality (`==`) compares
content.

A `StringIterator` panics when the String has been changed by `append`,
`+=`, or `grow` since the iterator was created, so modifying a String
while a `for` loop iterates it panics.

**Example**
```pepper
    var s = "héllo";
    assert(s.length() == 5, "5 code points");
    assert(s.size() == 6, "6 bytes: 'é' is 2");
    s.append(" world");
    assert(s.find("world") == 7, "find returns a byte offset");
    assert(s[1] == "é", "the indexer counts code points");
    for (var c in s) {
        print(c);   # one code point per line
    }
```

### Constructor

#### String()

```pepper
construct(data: __ptr<char> = __null, size: ulong = 0, length: ulong = 0)
```

Creates a String by copying `size` bytes of `data` into a new
NUL-terminated buffer. With no arguments, it creates an empty String
whose `c_str()` is `__null`.

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
    var copy = String(s.c_str(), s.size(), s.length());
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

#### length

```pepper
length(): ulong
```

Returns the number of Unicode code points. O(1).

**Returns**
- the length in code points, not bytes

**See also**
- `size`

#### grow

```pepper
grow(new_size: ulong)
```

Extends the byte buffer to `new_size` bytes and fills the new bytes
with zeros. Does nothing when `new_size` is not greater than `size()`.

A low-level primitive for `append`. It updates `size()` but not `length()`,
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

Appends the content of `rhs` to this String in place, updating `size()`
and `length()`.

Always invalidates running iterators, even when `rhs` is empty, so
appending during iteration panics. It may reallocate the buffer. Every reference to
this String sees the change. Runs in O(size() + rhs.size()).

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
`length()` is added until the index is non-negative, so any negative
index wraps, and `s[-7]` of a 3-code-point String is `s[2]`. Runs in
O(idx) because it walks the UTF-8 bytes. Use `for (var c in s)` to
visit every code point in O(size).

**Parameters**
- `idx` — the code-point index; negative counts from the end

**Returns**
- a new String that holds the one code point

**Panics**
- if `idx` is not less than `length()` after the negative index is normalized, which includes any index into an empty String

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
byte by byte. Strings with different `length()` are unequal without
comparing bytes. Runs in O(size()).

**Parameters**
- `rhs` — the String to compare with

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

#### size

```pepper
size(): ulong
```

Returns the number of bytes of UTF-8, not counting the NUL
terminator. O(1).

**Returns**
- the length in bytes, not code points

**See also**
- `length`

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

#### empty

```pepper
empty(): bool
```

Returns whether the String has no code points. O(1).

**Returns**
- true when `length()` is 0

#### c_str

```pepper
c_str(): __ptr<char>
```

Returns the String's buffer as a NUL-terminated C string.

The pointer is owned by the String. It is valid until the String is
destroyed or `append`, `+=`, or `grow` reallocates it. It is `__null`
for a String built with no data (`String()`), so check it before you
pass it to C. C functions stop at the first NUL byte in the content.

**Returns**
- the String's NUL-terminated byte buffer, or `__null`

#### copy

```pepper
copy(copies: Copies = __null): String
```

Returns a new String with the same content and its own buffer, so
later changes to either String do not affect the other. Runs in O(size()).

This is also how `copy(value)` copies a String (the `Copyable<String>`
implementation), which passes `copies`.

**Parameters**
- `copies` — the objects copied so far, when `copy(value)` calls it; a String holds no other objects, so it is not used

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
find(needle: String): long
```

Returns the **byte offset** of the first occurrence of `needle`, or -1
when it does not occur.

The offset counts bytes, not code points. To use it with `s[i]` or
`substr`, convert it with `String.length_of(s.c_str(), offset)`.
An empty `needle` is found at 0 unless this String is empty, in which
case the result is -1. The result is also -1 when either String is not
valid UTF-8. Runs in O(size() * needle.size()).

**Parameters**
- `needle` — the text to search for

**Returns**
- the byte offset of the first match, or -1 when there is none

**Example**
```pepper
    var s = "TESTING";
    assert(s.find("STI") == 2, "byte offset");
    assert(s.find("xyz") == -1, "absent");
```

#### contains

```pepper
contains(needle: String): bool
```

Returns whether `needle` occurs in this String (`find(needle) >= 0`).
Because of that, an empty String contains nothing, not even `""`.
Runs in O(size() * needle.size()).

**Parameters**
- `needle` — the text to search for

**Returns**
- true when `needle` occurs

#### starts_with

```pepper
starts_with(prefix: String): bool
```

Returns whether this String begins with the bytes of `prefix`. An
empty `prefix` always matches. Runs in O(prefix.size()).

**Parameters**
- `prefix` — the text to test for

**Returns**
- true when the first `prefix.size()` bytes equal `prefix`

#### ends_with

```pepper
ends_with(suffix: String): bool
```

Returns whether this String ends with the bytes of `suffix`. An empty
`suffix` always matches. Runs in O(suffix.size()).

**Parameters**
- `suffix` — the text to test for

**Returns**
- true when the last `suffix.size()` bytes equal `suffix`

#### substr

```pepper
substr(start: ulong, count: ulong): String
```

Returns a new String of up to `count` code points starting at
code-point index `start`. Both arguments count code points, not bytes.

`count` is clamped to the code points that remain. When `start` is at
or past `length()`, the result is an empty String. Runs in O(size()).

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
of `==`. Runs in O(size()).

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when the contents differ

#### operator +

```pepper
+(rhs: String): String
```

Returns a new String that holds this String followed by `rhs`. Neither
operand is modified. Runs in O(size() + rhs.size()).

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
- `index` — the byte offset, less than `size()`

**Returns**
- the byte at `index`

**Panics**
- if `index` is not less than `size()` ("String byte_at index out of bounds")

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
- if `start + size` is greater than `size()` ("String substr_bytes range out of bounds")
- if `start` or `start + size` falls inside a multi-byte code point ("String substr_bytes splits a code point")

**Example**
```pepper
    var s = "key=value";
    var eq = s.find("=") as ulong;
    assert(s.substr_bytes(0, eq) == "key", "before '='");
    assert(s.substr_bytes(eq + 1, s.size() - eq - 1) == "value", "after '='");
```

#### compare

```pepper
compare(other: String): int
```

Compares this String with `other` byte by byte, for sorting. For
valid UTF-8 this is code-point order; a String that is a prefix of the
other orders first. Runs in O(min(size(), other.size())).

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

#### operator >

```pepper
>(other: String): bool
```

Returns whether this String orders after `other`, as `compare` does.

**Parameters**
- `other` — the String to compare with

**Returns**
- true when `compare(other) > 0`

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

#### trim_end

```pepper
trim_end(): String
```

Returns a new String without the whitespace at the end: spaces, tabs,
carriage returns, line feeds, vertical tabs and form feeds (ASCII
only). Runs in O(size()).

**Returns**
- a new String with the trailing whitespace removed

**Example**
```pepper
    assert("code;  \r\n".trim_end() == "code;", "trailing whitespace");
    assert("  indented".trim_end() == "  indented", "leading kept");
```

#### lines

```pepper
lines(): String[]
```

Splits the String into lines and returns them without their line
endings. A line ends at `"\n"` or `"\r\n"`. A final line with no
ending is included, but the end of the String after a final line
ending does not start another line, so `"a\nb\n"` and `"a\nb"` both
give `["a", "b"]`, and `""` gives no lines. Runs in O(size()).

**Returns**
- a new Array with one new String per line

**Example**
```pepper
    var lines = "first\r\nsecond\n\nfourth".lines();
    assert(lines.count() == 4, "four lines");
    assert(lines[1] == "second", "\\r\\n removed");
    assert(lines[2] == "", "an empty line");
```

#### repeat

```pepper
repeat(count: ulong): String
```

Returns a new String that holds this String `count` times in a row.
`count` 0, or an empty String, gives an empty String. Runs in
O(size() * count).

**Parameters**
- `count` — how many copies to join

**Returns**
- a new String of `size() * count` bytes

**Example**
```pepper
    assert("ab".repeat(3) == "ababab", "three copies");
    var indent = " ".repeat(8);   # eight spaces
```

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

An interpolated string (`$"total: {total}"`) converts each value it names
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
chained. Runs in amortized O(text.size()).

**Parameters**
- `text` — the String to append; it is not modified

**Returns**
- this StringBuilder

**Example**
```pepper
    var b = StringBuilder();
    b.append("a").append("b");   # b.to_string() == "ab"
```

#### size

```pepper
size(): ulong
```

Returns the number of bytes of UTF-8 appended so far. O(1).

**Returns**
- the size in bytes

#### length

```pepper
length(): ulong
```

Returns the number of code points appended so far. O(1).

**Returns**
- the length in code points

#### empty

```pepper
empty(): bool
```

Returns whether nothing has been appended since the builder was
created or last cleared. O(1).

**Returns**
- true when `size()` is 0

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
is unchanged. Runs in O(size()).

**Returns**
- a new String

## StringIterator

```pepper
struct StringIterator
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

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

- **Code points** (Unicode characters): `Length`, `length()`, `empty()`,
  the indexer `s[i]`, `substr`, and iteration.
- **Bytes** of UTF-8: `Size`, `size()`, `find`, `starts_with`, and
  `ends_with`. `Size` is the authoritative length, so the data may
  contain NUL bytes. It is never derived from a terminator.

A String is a reference type: `var b = a;` shares one object, so
`append`, `+=`, and `grow` are visible through every reference. Use
`clone()` or `+` for an independent copy. Equality (`==`) compares
content.

`append`, `+=`, and `grow` increment `Version`. A `StringIterator`
panics when it sees a `Version` other than the one it started with, so
modifying a String while a `for` loop iterates it panics.

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

### Fields

#### Data

```pepper
__ptr<char> Data
```

The heap buffer: `Size` bytes of UTF-8 followed by a NUL terminator,
or `__null` for a String built with no data (`String()`). The String
owns it and frees it on destruction. `append` and `grow` may move it.

#### Length

```pepper
ulong Length
```

The number of Unicode code points. The constructor and `append` keep
it current; `grow` does not update it.

#### Size

```pepper
ulong Size
```

The number of bytes of UTF-8 in `Data`, not counting the NUL terminator.

#### Version

```pepper
ulong Version
```

A modification counter, incremented by `append` and `grow`. A
`StringIterator` compares it to detect modification during iteration.
`clone()` starts the copy at 0.

### Constructor

#### String()

```pepper
construct(__ptr<char> data = __null, this.Size = 0, this.Length = 0)
```

Creates a String by copying `Size` bytes of `data` into a new
NUL-terminated buffer. With no arguments, it creates an empty String
whose `Data` is `__null`.

When `data` is not `__null` and `Size` is 0, `data` is treated as a
NUL-terminated C string:

- with `Length` nonzero, `Size` becomes the byte length of its first
  `Length` code points (0 if the C string is not valid UTF-8);
- with `Length` 0, `Size` becomes the C string's whole byte length.

When `Length` is 0, it is counted from the bytes. A nonzero `Length` is
trusted, not checked against the data. Runs in O(Size).

**Parameters**
- `data` — the bytes to copy; `__null` for an empty String (then pass no sizes, because they are stored as given)
- `this.Size` — the number of bytes to copy from `data`; 0 treats `data` as a NUL-terminated C string
- `this.Length` — the number of code points in those bytes

**Example**
```pepper
    var empty = String();
    var s = "abc";
    var copy = String(s.c_str(), s.size(), s.length());
```

### Static methods

#### length_of

```pepper
static ulong length_of(__ptr<char> data, ulong size)
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
ulong length()
```

Returns the number of Unicode code points (`Length`). O(1).

**Returns**
- the length in code points, not bytes

**See also**
- `size`

#### grow

```pepper
void grow(ulong newSize)
```

Extends the byte buffer to `newSize` bytes and fills the new bytes
with zeros. Does nothing when `newSize` is not greater than `Size`.

A low-level primitive for `append`. It sets `Size` but not `Length`,
so the zero bytes it adds are not counted as code points until the
caller overwrites them and fixes `Length`. When it grows the buffer,
it increments `Version` and may reallocate `Data`, which invalidates
pointers from `c_str()`. Runs in O(newSize).

**Parameters**
- `newSize` — the new byte length

#### append

```pepper
void append(String rhs)
```

Appends the content of `rhs` to this String in place, updating `Size`
and `Length`.

Always increments `Version`, even when `rhs` is empty, so appending
during iteration panics. It may reallocate `Data`. Every reference to
this String sees the change. Runs in O(Size + rhs.Size).

**Parameters**
- `rhs` — the String to append; it is not modified

**Example**
```pepper
    var s = "TEST";
    s.append("ING");   # s == "TESTING"
```

#### operator []

```pepper
String [](int idx)
```

Returns the code point at code-point index `idx` as a new
one-code-point String.

A negative `idx` counts from the end (`s[-1]` is the last code point).
`Length` is added until the index is non-negative, so any negative
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
bool ==(String rhs)
```

Returns whether this String and `rhs` have the same content, compared
byte by byte. Strings with different `Length` are unequal without
comparing bytes. Runs in O(Size).

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when both hold the same bytes

#### operator +=

```pepper
String +=(String rhs)
```

Appends `rhs` in place, like `append`, and returns this same String,
not a copy. `s += t` modifies the object that every reference to `s`
shares, and increments `Version`.

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
ulong size()
```

Returns the number of bytes of UTF-8 (`Size`), not counting the NUL
terminator. O(1).

**Returns**
- the length in bytes, not code points

**See also**
- `length`

#### iterate

```pepper
StringIterator iterate()
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
bool empty()
```

Returns whether the String has no code points (`Length` is 0). O(1).

**Returns**
- true when `length()` is 0

#### c_str

```pepper
__ptr<char> c_str()
```

Returns the String's buffer as a NUL-terminated C string (`Data`).

The pointer is owned by the String. It is valid until the String is
destroyed or `append`, `+=`, or `grow` reallocates it. It is `__null`
for a String built with no data (`String()`), so check it before you
pass it to C. C functions stop at the first NUL byte in the content.

**Returns**
- the String's NUL-terminated byte buffer, or `__null`

#### clone

```pepper
String clone()
```

Returns a new String with the same content and its own buffer, so
later changes to either String do not affect the other. The copy's
`Version` starts at 0. Runs in O(Size).

**Returns**
- an independent copy of this String

#### find

```pepper
long find(String needle)
```

Returns the **byte offset** of the first occurrence of `needle`, or -1
when it does not occur.

The offset counts bytes, not code points. To use it with `s[i]` or
`substr`, convert it with `String.length_of(s.c_str(), offset)`.
An empty `needle` is found at 0 unless this String is empty, in which
case the result is -1. The result is also -1 when either String is not
valid UTF-8. Runs in O(Size * needle.Size).

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
bool contains(String needle)
```

Returns whether `needle` occurs in this String (`find(needle) >= 0`).
Because of that, an empty String contains nothing, not even `""`.
Runs in O(Size * needle.Size).

**Parameters**
- `needle` — the text to search for

**Returns**
- true when `needle` occurs

#### starts_with

```pepper
bool starts_with(String prefix)
```

Returns whether this String begins with the bytes of `prefix`. An
empty `prefix` always matches. Runs in O(prefix.Size).

**Parameters**
- `prefix` — the text to test for

**Returns**
- true when the first `prefix.size()` bytes equal `prefix`

#### ends_with

```pepper
bool ends_with(String suffix)
```

Returns whether this String ends with the bytes of `suffix`. An empty
`suffix` always matches. Runs in O(suffix.Size).

**Parameters**
- `suffix` — the text to test for

**Returns**
- true when the last `suffix.size()` bytes equal `suffix`

#### substr

```pepper
String substr(ulong start, ulong count)
```

Returns a new String of up to `count` code points starting at
code-point index `start`. Both arguments count code points, not bytes.

`count` is clamped to the code points that remain. When `start` is at
or past `length()`, the result is an empty String. Runs in O(Size).

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
bool !=(String rhs)
```

Returns whether this String and `rhs` differ in content, the negation
of `==`. Runs in O(Size).

**Parameters**
- `rhs` — the String to compare with

**Returns**
- true when the contents differ

#### operator +

```pepper
String +(String rhs)
```

Returns a new String that holds this String followed by `rhs`. Neither
operand is modified. Runs in O(Size + rhs.Size).

**Parameters**
- `rhs` — the String to append to the copy

**Returns**
- a new concatenated String

**Example**
```pepper
    var greeting = "Hello, " + "world";
```

## StringIterator

```pepper
struct StringIterator
```

An `Iterator<String>` over a String's code points, returned by
`String.iterate()` and used by `for (var c in s)`.

Call `next()` to advance, then `current()` for the code point it moved
to. The iterator records the String's `Version` when it is created, and
both methods panic if the String has been modified since. Create it with
`String.iterate()`: a default-constructed `StringIterator()` has a null
`Source`.

**Example**
```pepper
    var it = "ab".iterate();
    while (it.next()) {
        print(it.current());   # "a", then "b"
    }
```

### Fields

#### Source

```pepper
String Source
```

The String being iterated. The iterator holds a reference to it.

#### Offset

```pepper
ulong Offset
```

The byte offset in `Source` of the current code point.

#### NextOffset

```pepper
ulong NextOffset
```

The byte offset in `Source` of the code point after the current one,
or `Source.Size` at the end.

#### Version

```pepper
ulong Version
```

`Source.Version` when iteration began; a mismatch means modification.

#### Started

```pepper
bool Started
```

Whether `next()` has been called at least once.

### Methods

#### next

```pepper
bool next()
```

Advances to the next code point. Runs in O(1) per code point.

Returns false once it passes the end, and on every call after that.
A malformed UTF-8 sequence is yielded, together with the rest of the
bytes, as one final "code point".

**Returns**
- true when positioned on a code point, false at the end

**Panics**
- if `Source` was modified (its `Version` changed) since the iterator was created

#### current

```pepper
String current()
```

Returns the code point that the last successful `next()` moved to, as
a new one-code-point String.

**Returns**
- a new String that holds the current code point

**Panics**
- if `Source` was modified since the iterator was created
- if `next()` has not been called yet
- if `next()` has returned false (the iterator is past the end)

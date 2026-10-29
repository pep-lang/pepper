# Types and variables

This chapter covers the values every Pepper program is built from: numbers,
booleans and strings, the variables that hold them, and the operators that
combine them.

## Built-in types

### Integers

Pepper has signed and unsigned integers of 8, 16, 32 and 64 bits. Each width has
a short name (`i32`) and a descriptive alias (`int`). The two names are the same
type, so you can use whichever reads better and assign freely between them.

| Bits | Signed | Unsigned |
|---|---|---|
| 8 | `i8`, `char` | `u8`, `byte` |
| 16 | `i16`, `short` | `u16`, `ushort` |
| 32 | `i32`, `int` | `u32`, `uint` |
| 64 | `i64`, `long` | `u64`, `ulong` |

`int` is 32 bits and `long` is 64 bits on every platform. `sizeof<T>()` gives the
size of a type in bytes.

Integer literals are written in decimal (`42`) or hexadecimal (`0xFF`). A literal
on its own is an `int` when its value fits in an `int`, and a `long` otherwise, so
`var big = 3000000000;` is a `long`. It takes another type when you store it in a
variable of that type (`u64 huge = 9000000000000000000;`). A hexadecimal literal
is a 64-bit bit pattern: `u64 all = 0xFFFFFFFFFFFFFFFF;` sets every bit.

A decimal literal larger than the largest `long` (9223372036854775807), up to
the largest `ulong` (18446744073709551615), is a `ulong`: it is the same value as
its hexadecimal spelling, and it fits only where a `ulong` (or a floating-point
type) takes it. `long`'s minimum is written with its sign,
`-9223372036854775808`.

```pepper
{{#include ../../examples/types-integers.pep}}
```

Storing a value that does not fit in the destination keeps its low bits, as in
C: a `u16` holding 65535 becomes 0 when you add 1 and store the result, and
`70000 as u16` is 4464. Arithmetic that overflows `int` or a wider type
panics instead (see [Integer overflow](#integer-overflow)).

A decimal literal larger than the largest `ulong`, or a hexadecimal literal with
more than 64 bits, is an error:

```text
main.pep:2:13: error: integer literal is too large to be represented in a 64-bit integer
    2 |     var f = 99999999999999999999;
      |             ^~~~~~~~~~~~~~~~~~~~
```

So is a decimal literal past `long`'s range stored in an integer type other than
`ulong`:

```text
main.pep:2:14: error: integer literal is too large for type 'long'
    2 |     long g = 9223372036854775808;
      |              ^~~~~~~~~~~~~~~~~~~
```

### Floating point

`float` is a 32-bit and `double` a 64-bit IEEE 754 number (`f32` and `f64` are
aliases). A literal with a decimal point or an exponent, such as `0.25` or `1e3`,
is a `double`.

Comparisons follow IEEE 754, as in C: against NaN (`0.0 / 0.0`), `==`, `<`,
`<=`, `>` and `>=` are false and `!=` is true, so `x != x` is true only for a
NaN. As a condition, a float is true unless it equals zero, NaN included.

### Reading numbers from text

Every number type has a static `parse` that reads one from a `String`:
`int.parse("42")` gives an `int?` (see [optionals](optionals.md)), empty when
the text is not a number of that type: not digits, or too big or too small for
it. The integer types take a base from 2 to 36 as a second argument (`"ff"` in
base 16 is 255), and `float` and `double` read decimal notation (`"2.5"`,
`".5"`, `"1e-3"`). Neither accepts spaces, a `0x` prefix, `inf` or `nan`. Each
spelling of a type is the same type, so `i32.parse` is `int.parse`:

```pepper
{{#include ../../examples/types-numbers-parse.pep}}
```

### Booleans

`bool` holds `true` or `false`. Comparisons and the logical operators produce a
`bool`. In arithmetic a `bool` counts as 0 or 1, and its text is `true` or
`false` (`$"{flag}"`).

### Characters

A character literal is one ASCII character between single quotes: `'a'`, `'"'`,
`'#'`. Its value is the character's code, and its type is `byte` (`u8`), the type
of one byte of a UTF-8 string. Like any `byte` it widens to the other integer
types, so it compares with, and stores into, an `int` or a `char` as well:

```pepper
{{#include ../../examples/types-characters.pep}}
```

The escapes are the same as a string's (see the table under
[Strings](#strings)), plus `\xHH` for any byte, `'\xFF'` included. A
character literal holds exactly one ASCII character; for anything else use a
string:

```text
main.pep:2:13: error: character literal may only contain one character; use a string for more
    2 |     var x = 'ab';
      |             ^~~~
main.pep:2:14: error: character literal must be a single ASCII character; use a string for other characters
    2 |     var x = 'é';
      |              ^
```

`char` is an 8-bit **signed** integer, the same type as `i8`, used mostly for C
strings (`__ptr<char>`). The ASCII characters have the same value as a `char`
and as a `byte`; `'\xFF'` is 255 as a `byte` but -1 read through a `char`.
Text is a `String`, and a single character of it is a one-code-point `String`.

`byte` and `char` classify ASCII characters as C's `ctype.h` does in the "C"
locale: `is_digit`, `is_hex_digit`, `is_alphabetic`, `is_alphanumeric`,
`is_upper`, `is_lower`, `is_whitespace`, `is_blank`, `is_punctuation`,
`is_graphic`, `is_printable`, `is_control` and `is_ascii`, plus `to_upper`,
`to_lower` and `digit_value(base)`. The names are spelled out (`is_punctuation`
for C's `ispunct`). A byte above 127, which is a negative `char`, is never a
letter, digit, space or punctuation. Unicode classification is not covered.

```pepper
{{#include ../../examples/types-characters-classify.pep}}
```

### Strings

`String` is a UTF-8 string. A string literal such as `"hello"` is a `String`
value wherever a `String` is expected, and wherever nothing asks for another
type (`var s = "hello";` declares a `String`). Where it is stored or passed as
a `__ptr<char>`, it is the literal's NUL-terminated bytes (see
[Passing strings](c-interop.md#passing-strings)), and where a
[`StringConstant`](#string-constants) is expected, it is one. `+` joins two strings into a new one, `==` and `!=` compare contents,
the `length` property counts code points, `size` counts bytes, and `s[i]` gives the code
point at index `i` as a one-code-point `String`.

```pepper
{{#include ../../examples/types-strings.pep}}
```

A `String` is a reference type: `var alias = message;` makes a second reference
to the same object rather than a copy, so a change made with `append` shows
through both names. [Memory and reference counting](memory.md) explains how
references work, and the [`String`](../reference/string.md) reference lists every
method.

Every place a literal is stored (a variable, a field, an array element, a
function's result) gets a new `String`, so changing it never changes the
literal: after `var s = "a"; s.append("b");` the next `"a"` is still `"a"`.
Where a literal is only read, passed to a parameter that the function
neither keeps nor changes (`builder.append("x")`, `name.contains("x")`), every
evaluation shares one constant object and allocates nothing.

#### String constants

A literal's own type is [`StringConstant`](../reference/string.md): a pointer
to the literal's bytes, which never change and are never freed, with their
size and length. It is a [`[Value]`](value-structs.md) type, so copying one
steps no reference count, any thread may read it, and a literal stored as one
allocates nothing. Its bytes always end in a NUL byte, so `c_str()` passes it
to C as it is (a `String`'s `c_str()` does too, but a `String` built with no
data has none).

A `StringConstant` has `String`'s read API (`length`, `size`, `find`,
`split`, `trim`, `==`, `<`, the indexer, `for` loops and so on); the methods
that make new text return a `String`. It converts to a `String` wherever a
`String` is expected, as if `String` had an [`[Implicit]`
constructor](structs.md#implicit-conversions) taking it: the conversion (and
`String(text)`) copies the bytes, so an API that takes a `String` takes a
`StringConstant` too. Where C expects a `char*`, it passes its own bytes, as
`c_str()` does. Among [overloads](overloading.md), a literal picks a
`StringConstant` parameter over a `String` one, and a `StringConstant` value
picks a `String` parameter last, as an implicit conversion.

```pepper
{{#include ../../examples/types-string-constants.pep}}
```

- **Where a literal is a `StringConstant`**: a variable, field, parameter or
  return value of type `StringConstant`, a `HashMap<StringConstant, V>` key,
  and a `const` with no written type (`const GREETING = "hello";`), so a
  module-scope text constant allocates nothing and any thread may read it.
  Everywhere else, `var s = "x"` included, a literal is a `String`, as
  before.
- **Converting chains once**: a literal reaches a type that converts from
  `String` (`io.Path`, `Error`) directly, but a `StringConstant` variable
  does not, since conversions never chain. Write `String(text)` or pass a
  literal.
- **Comparing**: `==`, `!=`, `<`, `<=`, `>` and `>=` compare a
  `StringConstant` with another `StringConstant` (a literal included) or
  with a `String`, either way round, and copy nothing.
- **A literal method call** (`"a,b".split(",")`) calls the `String` method.

`to_string` turns any integer into its decimal text. For parsing and
generating text, `byte_at` and `substr_bytes` work in bytes (the offsets
`find` returns), `compare` and `<`, `<=`, `>`, `>=` order strings byte by byte
(code-point order for UTF-8), `lines()` splits on `"\n"` or `"\r\n"`,
`trim()`, `trim_start()` and `trim_end()` drop whitespace, `lower()` and
`upper()` change the case of ASCII letters, `repeat(n)` joins `n` copies, and
`bytes()` copies the UTF-8 bytes into an array. A
`StringBuilder` builds a long String from many pieces without recopying the
text built so far on every append:

```pepper
{{#include ../../examples/types-strings-text.pep}}
```

To search and take text apart, `find(needle, from)` starts at a byte offset
and `rfind` finds the last match, `split(separator)` cuts at every separator
and `split_once` at the first (giving an optional pair), `separator.join(parts)`
puts the parts back together, and `replace(from, to)` swaps every match
(to read a number from text, see
[Reading numbers from text](#reading-numbers-from-text)):

```pepper
{{#include ../../examples/types-strings-search.pep}}
```

An interpolated string puts values' text into a string literal:
`$"line {line + 1}: {message}"`. [String interpolation](interpolation.md) covers
which values it accepts.

A backslash in a string literal starts an escape sequence, as in C and Rust:

| Escape | Character |
|---|---|
| `\n` | newline |
| `\t` | tab |
| `\r` | carriage return |
| `\0` | the zero byte |
| `\\` | a backslash |
| `\"` | a double quote |
| `\'` | a single quote |
| `\xHH` | the ASCII character with hexadecimal code `HH`, at most `\x7F` (any byte in a [character literal](#characters)); always two digits, so `"\x4"` is an error |
| `\u{H...}` | the Unicode code point with hexadecimal code `H...` (1 to 6 digits) |

```pepper
print("name:\t\"Pepper\"");   # name:	"Pepper"
print("caf\u{e9}");            # café
```

Any other character after a backslash is an error:

```text
main.pep:2:13: error: unknown escape sequence '\q'
    2 |     print("a\qb");
      |             ^~
```

### Other built-in types

- `void` means "no value". It is the return type of a function that returns
  nothing.
- `Array<T>` is a growable array of `T`; `int[]` is shorthand for `Array<int>`,
  and `int[][]` for `Array<Array<int>>`. See [`Array`](../reference/array.md).
- `Optional<T>` is a value that may be missing; `int?` is shorthand for
  `Optional<int>`. See [Optional values](optionals.md).
- `HashMap<K, V>` and `HashSet<K>` are hash tables. See
  [HashMap and HashSet](../reference/hash.md).
- `Result<TValue, TError>` and `Error` describe operations that can
  fail. See [Error handling with Result](results.md).
- `async.Atomic<T>` is a value that threads can update safely. See
  [Atomics](atomics.md) and [Threads and shared data](threads.md).

### Raw pointers and `__null`

For talking to C, Pepper has raw pointers, written `__ptr<T>` (for example
`__ptr<char>` or `__ptr<void>`), and the null pointer literal `__null`:

```pepper
var p: __ptr<void> = __null;
assert(p == __null, "p is null");
```

Most programs never need them. [Calling C](c-interop.md#pointers) covers
pointers in full.

## Naming conventions

Primitive types and keywords are lowercase: `int`, `float`, `bool`, `var`,
`while`. Types, including the ones the runtime provides, are PascalCase:
`String`, `Array<T>`, `HashMap<K, V>`, `Result<TValue, TError>`. Functions,
variables and fields are `snake_case`, and constants are `SCREAMING_CASE`.
[Naming conventions](naming.md) has the full rules.

Identifiers are made of ASCII letters, digits and underscores, and cannot start
with a digit. Avoid names that start with two underscores: the compiler and
runtime use them for their own names, such as `__ptr` and `__null`.

## Variables

Declare a variable with `var` and let Pepper infer its type from the initial
value, or write the type yourself. Prefer `var` whenever the type is obvious from
the value.

```pepper
{{#include ../../examples/types-variables.pep}}
```

The three forms are:

- `var name = value;` infers the type from the value.
- `Type name = value;` is the C style, with the type first. Any type can come
  first, a tuple type too: `(String, int)[] sizes = [];`.
- `var name: Type = value;` puts the type after the name.

A variable declared without a value starts out as zero: `0` for numbers,
`false` for `bool`, and null for a struct type such as `String`. Give struct
variables a value before you use them.

When `var` infers the type of an arithmetic expression, it takes the type the
arithmetic produces under C's rules (see [Arithmetic follows C](#arithmetic-follows-c)):
`var m = 1 + 0.5;` is a `double` holding 1.5, and with `u8 small = 250;`,
`var s = small + 10;` is an `int` holding 260.

### Scope and shadowing

A variable is visible from its declaration to the end of the block that
declares it. Declaring the same name twice in one block is an error
(`redefinition of 'x'`, with a note at the first). A function's or closure's
parameters belong to its body's outermost block, so a local there may not
repeat a parameter's name either, nor may two parameters share one, as in
C++:

```text
main.pep:2:9: error: redefinition of 'x'
    2 |     var x = 5;
      |         ^
main.pep:1:3: note: previous definition is here
    1 | f(x: bool): int {
      |   ^
```

An inner scope may reuse a name, hiding the outer one until it ends: a nested
block, a `for` loop's variable, a `match` arm's or an `is` pattern's
bindings, and a closure's parameters.

```pepper
{{#include ../../examples/variables-shadowing.pep}}
```

### Constants

`const` declares a name that you do not intend to change:

```pepper
const LIMIT = 3;
const RATIO: double = 0.5;
```

Assigning to a `const`, with `=`, a compound assignment, `++` or `--`, is an
error:

```text
main.pep:5:5: error: cannot assign to const variable 'LIMIT'
    5 |     LIMIT = 4;
      |     ^~~~~
main.pep:1:7: note: 'LIMIT' declared const here
    1 | const LIMIT = 3;
      |       ^~~~~
```

### Module-level variables

A variable declared outside any function is a module-level (global) variable. It
exists for the whole run of the program and every function in the file can read
it. Its initializer can be any expression, including a function call, and runs
before `main`. Like other top-level declarations, a global is private to its
file (or module) unless you mark it `export` (see [Visibility](visibility.md)).

Any function can run on any thread, so every thread can reach a global. It
must therefore be declared `const` and have a thread-safe type, such as a
number, an `Atomic<T>`, a `ThreadLocal<T>`, or a `[Shared]` struct (see
[Module-scope variables](threads.md#module-scope-variables)). A global that
changes is an `Atomic<T>`, or a `[ThreadLocal]` `var`, which every thread has
its own copy of (see [Thread-local variables](threads.md#thread-local-variables)):

```pepper
const MAX_RETRIES = 3;
const requests = async.Atomic<long>(0);   # changed with requests.fetch_add(1)
[ThreadLocal]
var depth: int = 0;                       # one per thread
```

A global whose initializer is a literal (a number, a `bool`, `__null`, or a
string literal) is set when the program loads, with no code run. So is a
[`[Value]` struct](value-structs.md) made of literals, when its constructor only
stores its arguments and constants in its fields
(`const TABLE = Table("...", 4);`); a constructor that does anything else
runs at startup. One that nothing reads, like a function nothing calls, is
left out of the executable, so a module's data tables cost only the
programs that use them. A Windows build with `-g` keeps them all.

## Casting with `as`

`value as Type` converts a value to another type explicitly, like `static_cast`
in C++:

```pepper
var ratio = 7.9;
var whole = ratio as int;   # 7
var wide = whole as long;
```

- Floating point to integer truncates toward zero: `-7.9 as int` is `-7`.
- Integer to a narrower integer keeps the low bits: `70000 as u16` is 4464.
- Integer to a wider integer sign-extends a signed source and zero-extends an
  unsigned one: `(-1 as i16) as long` is -1, and `(65535 as u16) as long` is
  65535.
- `bool` and enums convert like integers: `true as int` is 1, and an enum
  converts to the integer it is stored as. An integer does not convert to an
  enum; name a case instead.
- A struct converts to a trait it conforms to: `dog as Named`. The other
  way, from a trait value, may fail: `shape as? Square` gives a `Square?`
  (see [Converting a trait value back](traits-and-extensions.md#converting-a-trait-value-back)).
- A pointer converts to `__ptr<void>` and back: `p as __ptr<void>`, then
  `v as __ptr<int>`.
- A value converts to its own type.

Anything else is a compile error at the `as`, since it would not be a value
conversion but a reinterpretation of memory:

```text
main.pep:3:15: error: cannot cast '__ptr<int>' to 'ulong' with 'as'; use 'unsafe_cast<ulong>(...)' to reinterpret
    3 |     var a = p as ulong;
      |               ^~
```

Casting between unrelated struct types, or between a struct and a number or
pointer, is an error with no alternative (`cannot cast 'P' to 'Q'`).

`as` binds more tightly than the arithmetic operators, so `x * 10 as int` means
`x * (10 as int)`. Put parentheses around the expression you want to convert:
`(x * 10) as int`. C-style casts such as `(int)x` do not exist.

Many conversions also happen without `as`: assigning or passing a number to a
variable or parameter of another numeric type converts it, as in C, including
narrowing conversions (`int n = 2.7;` stores 2).

## Reinterpreting with `unsafe_cast`

`unsafe_cast<Type>(value)` reinterprets a value's bits as another type, like
`reinterpret_cast` in C++. It is for C interop and low-level code, and nothing
checks that the result makes sense:

- A pointer to a pointer of another type: `unsafe_cast<__ptr<u8>>(text.c_str())`.
- A pointer to an integer, and an integer to a pointer:
  `unsafe_cast<ulong>(p)`, `unsafe_cast<__ptr<int>>(address)`.
- A number to another number of the same width, keeping its bits:
  `unsafe_cast<uint>(1.0 as float)` is `0x3F800000`, and
  `unsafe_cast<double>(bits)` turns a `ulong` back into a `double`.

```pepper
{{#include ../../examples/unsafe-cast.pep}}
```

It never converts a struct, trait or function value, so it cannot get around
reference counting. A conversion `as` can make is not a reinterpretation, so
`unsafe_cast<long>(n)` on an `int` is an error that says to use `as`:

```text
main.pep:3:13: error: 'unsafe_cast' cannot convert 'int' to 'long': the sizes differ; use 'as' to convert the value
    3 |     var w = unsafe_cast<long>(n);
      |             ^~~~~~~~~~~
```

## Arithmetic follows C

Arithmetic on numbers behaves exactly as it does in C (the "usual arithmetic
conversions"), so code ported from C gives the same results:

- **Integer promotion.** Types narrower than `int` (`char`, `u8`, `short`, `u16`,
  and `bool`) are converted to `int` before any arithmetic. The sum of two
  `char`s is an `int`, so `100 + 100` gives 200 rather than wrapping at 8 bits.
- **Mixed widths** use the wider type: `int + long` is a `long`.
- **Signed and unsigned.** When both operands have the same width and one is
  unsigned, the operation is unsigned: comparing `int -1` with `uint 1` treats
  -1 as 4294967295, so `-1 < 1` is false for those types.
- **Integer and floating point** gives floating point: `3 * 0.5` is 1.5.
- **Division** of integers truncates toward zero (`-7 / 2` is -3), and `%` takes
  the sign of the left operand (`-7 % 3` is -1).
- **Conditionals.** `c ? a : b` with numeric arms of different types has
  their common type by the same rules (`c ? 0 : s.length` is a `ulong`), and
  so does a [`match` expression](enums.md#match-expressions-is-and-literal-patterns)
  over its arms. The value converts from that type wherever it goes, and a
  `var` it initializes has that type (`var n = c ? 0 : s.length` is a
  `ulong`, not an `int`).
- **Shifts** take the type of the (promoted) left operand. `>>` keeps the sign for
  signed types and fills with zeros for unsigned types.
- **Overflow** is where Pepper leaves C: it panics, for signed and unsigned
  types alike (see [Integer overflow](#integer-overflow)).
- **Precedence** leaves C for `|` and `^`, which share a level, so
  `1 | 2 ^ 3` is `(1 | 2) ^ 3` (see [Operators](#operators)).

```pepper
{{#include ../../examples/types-arithmetic.pep}}
```

## Integer overflow

Integer arithmetic whose result does not fit its type stops the program, as in
Swift (and Rust's debug builds), instead of wrapping around silently:

```text
main.pep:3:16: panic: integer overflow in 'int' addition
```

The message names the operator's location and the type the operation ran at.
These operations check:

- `+`, `-`, `*` and `**`, unary `-`, `++` and `--`, and the compound
  assignments (`+=`, `-=`, `*=`). Negating the most negative value of a signed
  type overflows, and so does negating any nonzero unsigned value or
  subtracting past 0 (`uint 0 - 1`).
- `/` and `%` by zero (`division by zero`), and the most negative value of a
  signed type divided by -1 (`MIN / -1` and `MIN % -1`), whose result does not
  fit.
- `<<` and `>>` by a count of at least the type's width, or a negative one:
  `shift count out of range for 'int': must be from 0 to 31`.

Arithmetic on types narrower than `int` runs at `int` (see above), so it
overflows only past `int`'s range; storing the result back in the narrow type
keeps its low bits, like any narrowing conversion. `x++` on a `u8` holding 255
leaves 0, as `x += 1` does. Casts with `as` never check: `70000 as u16` is
4464.

When both operands are constants, an overflow is a compile error at the
operator, and so is a division by a constant 0:

```text
main.pep:2:28: error: integer overflow in 'int' multiplication
    2 |     var seconds = 100000 * 100000;
      |                          ^
```

### Wrapping on purpose

Hashes, checksums and random number generators rely on wrapping. Each integer
type has methods that say what to do on overflow instead of panicking:

| Method | On overflow |
|---|---|
| `wrapping_add(x)`, `wrapping_sub(x)`, `wrapping_mul(x)` | Wraps around: the result modulo 2^bits. |
| `checked_add(x)`, `checked_sub(x)`, `checked_mul(x)` | Returns Empty (the result is a `T?`). |
| `saturating_add(x)`, `saturating_sub(x)`, `saturating_mul(x)` | Clamps to the type's highest or lowest value. |
| `overflowing_add(x)`, `overflowing_sub(x)`, `overflowing_mul(x)` | Returns the wrapped result and `true` as a `(T, bool)`. |

```pepper
{{#include ../../examples/types-overflow.pep}}
```

The methods work at their type's own width: `byte 200.checked_add(100)` is
Empty, while `200 + 100` on two `byte`s is 300 at `int`.

### Removing the checks

The checks stay on at every optimization level. A build that has measured
their cost and accepts the risk can remove kinds of check with
`--no-runtime-checks`, a comma-separated list:

| Name | Removes | Then |
|---|---|---|
| `overflow` | The overflow checks of `+`, `-`, `*`, `**`, unary `-`, `++`, `--` | Arithmetic wraps around (never undefined). |
| `divide` | Division and remainder by zero, and `MIN / -1` | The result is undefined, as in C. |
| `shift` | The shift count check | The count is masked to the type's width (`x << 33` on an `int` shifts by 1). |
| `bounds` | `Array` and `String` index checks (`a[i]`, `byte_at`) | An index out of range reads or writes arbitrary memory. |
| `null` | Calls through null function and trait values, and `match` on a null reference | The program crashes or misbehaves. |
| `all` | Every check above | |

```bash
pepper build -O main.pep --no-runtime-checks=overflow,shift
```

Removing `bounds` or `null` gives up Pepper's memory safety: an index out of
range or a null reference then reads or writes arbitrary memory instead of
panicking. The flag does nothing at `-O0`, the default, where every check stays
on and the compiler warns
`warning: '--no-runtime-checks' has no effect at -O0`. It applies from `-O1`
up, `-g` included. The setting is part of the build cache's key, like the
optimization level.

To remove checks from one function instead of a whole build, mark it
`[Unsafe("...")]` with the same names, comma-separated in one string:
`[Unsafe("overflow")]`, `[Unsafe("overflow,bounds")]` or `[Unsafe("all")]`.
It removes them from that function's body only, at every optimization level
(`-O0` included), so the function behaves the same in every build. Closures
written in it lose the same checks. Functions it calls keep theirs, with one
exception: `bounds` also removes the index checks that `Array` and `String`
make for it, since those run inside their indexers. `[Unsafe]` goes on a free
function, a method or a constructor. An unknown name is an error at the
string.

```pepper
{{#include ../../examples/types-unsafe-checks.pep}}
```

## Bit operations and math functions

Each integer type has methods that compile to a single instruction on most
CPUs, through LLVM's intrinsics, for code that would otherwise loop over
bits:

| Method | Returns |
|---|---|
| `leading_zeros()`, `trailing_zeros()` | The zero bits above the highest set bit, or below the lowest; the type's width for zero. |
| `count_ones()`, `count_zeros()` | How many bits are set, or clear. |
| `swap_bytes()` | The value with its bytes reversed, to convert between little and big endian. |
| `reverse_bits()` | The value with its bits reversed. |
| `rotate_left(n)`, `rotate_right(n)` | The bits rotated by `n`, modulo the width. |
| `min(x)`, `max(x)` | The smaller or the larger value. |
| `abs()` | The value without its sign (signed types). Panics for the lowest value, whose negation does not fit. |

Like the overflow methods, they work at their type's own width:
`byte 1.leading_zeros()` is 7.

```pepper
{{#include ../../examples/types-bits.pep}}
```

`float` and `double` have `square_root()`, `floor()`, `ceiling()`,
`truncate()`, `round()` (halfway cases away from zero), `abs()`,
`copy_sign(sign)`, `multiply_add(factor, addend)` (`this * factor + addend`
rounded once) and `min(x)` and `max(x)` (which ignore a NaN argument):

```pepper
{{#include ../../examples/types-float-functions.pep}}
```

They also have the functions of C's `<math.h>`, with their names spelled
out. Angles are in radians. LLVM's intrinsics compute the ones it has, and
the C math library the rest:

| Methods | C's names |
|---|---|
| `sine()`, `cosine()`, `tangent()` | `sin`, `cos`, `tan` |
| `arc_sine()`, `arc_cosine()`, `arc_tangent()`, `y.arc_tangent2(x)` | `asin`, `acos`, `atan`, `atan2(y, x)` |
| `hyperbolic_sine()`, `hyperbolic_cosine()`, `hyperbolic_tangent()` | `sinh`, `cosh`, `tanh` |
| `arc_hyperbolic_sine()`, `arc_hyperbolic_cosine()`, `arc_hyperbolic_tangent()` | `asinh`, `acosh`, `atanh` |
| `exponential()`, `exponential2()`, `exponential_minus_one()` | `exp`, `exp2`, `expm1` |
| `logarithm()`, `logarithm2()`, `logarithm10()`, `logarithm_one_plus()` | `log`, `log2`, `log10`, `log1p` |
| `cube_root()`, `hypotenuse(other)` | `cbrt`, `hypot` |
| `remainder(divisor)` | `remainder` (the quotient rounded to nearest; `%` is `fmod`, rounded toward zero) |
| `is_nan()`, `is_infinite()`, `is_finite()`, `sign_bit()` | `isnan`, `isinf`, `isfinite`, `signbit` |

Powers are the `**` operator: `x ** 0.5`, or `x ** 3` with an integer
exponent. The [`math` module](../reference/math-module.md) has the
constants (`math.PI`, `math.TAU`, `math.E`, `math.INFINITY`, `math.NAN`,
and the epsilon and limits of `float` and `double`) and `math.gcd` and
`math.lcm` for integers:

```pepper
{{#include ../../examples/types-float-math.pep}}
```

Hints for the optimizer are [`[Likely]` and
`[Unlikely]`](control-flow.md#branch-hints-likely-and-unlikely) on a
branch and the prefetches of the [`hint` module](hints.md). Any other LLVM intrinsic can be declared as an
extern; see [LLVM intrinsics](c-interop.md#llvm-intrinsics).

## Operators

```pepper
{{#include ../../examples/types-operators.pep}}
```

| Kind | Operators |
|---|---|
| Arithmetic | `+` `-` `*` `/` `%` `**`, unary `-` and `+` |
| Comparison | `==` `!=` `<` `<=` `>` `>=` |
| Identity | `===` `!==` (two references to the same object; plain equality for numbers and `bool`) |
| Logical | `&&` (or `and`), `\|\|` (or `or`), `!` |
| Bitwise | `&` `\|` `^` `~` `<<` `>>` |
| Assignment | `=` `+=` `-=` `*=` `/=` `%=` `<<=` `>>=` `&=` `\|=` `^=` |
| Increment | `++` `--`, prefix or postfix |
| Conditional | `condition ? a : b` |

`&&` and `||` short-circuit: the right operand is evaluated only when the left
one does not decide the result, so `items.count > 0 && items[0] == 1` never
reads `items[0]` from an empty array.

Unary operators nest: `-~x` is `-(~x)`, and `!!x` is `!(!x)`, which turns a
number into a `bool`. A struct can define its own operators, the truth test
`!!` included (see [Operators](structs.md#operators)).

`**` raises a number to a power, and is right-associative: `2 ** 3 ** 2` is
`2 ** 9`. On two integers the result is an integer, and the exponent can be
any integer expression. A negative exponent gives the truncated real result: 1
for a base of 1, 1 or -1 for a base of -1, and 0 otherwise (`2 ** -1` is 0).

When either operand is a `float` or `double`, the result is floating point, by
the usual conversions above: `2.0 ** 0.5` is the square root of 2, `2.0 ** -2`
is 0.25, and `4 ** 0.5` is the `double` 2.0. An integer exponent of at most 32
bits computes by repeated multiplication (LLVM's `powi`), which is fast but may
differ from C's `pow` in the last bit; any other exponent calls `pow` itself.
`**` on anything but numbers or a struct that defines it is an error:

```text
main.pep:3:15: error: invalid operands to binary expression ('__ptr<int>' and 'int')
    3 |     var q = p ** 2;
      |               ^~
```

Operators bind in this order, tightest first:

1. Postfix: calls `f(x)`, indexing `a[i]`, member access `a.b`, `x++`, `x--`
2. `**`
3. `as`, `as?`
4. Unary `+`, `-`, `!`, `~`
5. Prefix `++`, `--`
6. `*`, `/`, `%`
7. `+`, `-`
8. `<<`, `>>`
9. `..`, `..>` (ranges; not associative)
10. `is`
11. `<`, `<=`, `>`, `>=`
12. `==`, `!=`, `===`, `!==`
13. `&`
14. `|`, `^`
15. `&&`, `and`
16. `||`, `or`
17. `? :`
18. `=` and the compound assignments (right-associative)

As in C, `&` binds more loosely than `==`, so write `(flags & mask) == mask`
with the parentheses.

Unlike C, `|` and `^` share one level and group left to right: `1 | 2 ^ 3`
is `(1 | 2) ^ 3`, which is 0, where C reads `1 | (2 ^ 3)`, which is 1. Code
ported from C that mixes the two needs parentheses.

An expression can nest at most 256 levels deep, counting each operator of a
chain as one level, so a sum of more than about 250 terms is a compile error
(see [Compiler errors](compiler-errors.md#common-errors)).

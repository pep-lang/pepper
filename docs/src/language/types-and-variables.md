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

```pepper
{{#include ../../examples/types-integers.pep}}
```

Storing a value that does not fit in the destination keeps its low bits, as in
C: a `u16` holding 65535 becomes 0 when you add 1 and store the result, and
`70000 as u16` is 4464.

A decimal literal larger than the largest `long` (9223372036854775807), or a
hexadecimal literal with more than 64 bits, is an error:

```text
main.pep:2:13: error: integer literal is too large to be represented in a 64-bit integer
    2 |     var f = 99999999999999999999;
      |             ^~~~~~~~~~~~~~~~~~~~
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

### Strings

`String` is a UTF-8 string. A string literal such as `"hello"` is a `String`
value, except where it is stored or passed as a `__ptr<char>`: there it is the
literal's NUL-terminated bytes (see [Passing strings](c-interop.md#passing-strings)). `+` joins two strings into a new one, `==` and `!=` compare contents,
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
| `\xHH` | the ASCII character with hexadecimal code `HH`, at most `\x7F` (any byte in a [character literal](#characters)) |
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
`while`. Structs, including the ones the runtime provides, are PascalCase:
`String`, `Array<T>`, `HashMap<K, V>`, `Result<TValue, TError>`. Follow the same
convention for your own structs. Functions and variables are usually written in
`snake_case`.

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
- `Type name = value;` is the C style, with the type first.
- `var name: Type = value;` puts the type after the name.

A variable declared without a value starts out as zero: `0` for numbers,
`false` for `bool`, and null for a struct type such as `String`. Give struct
variables a value before you use them.

When `var` infers the type of an arithmetic expression, it takes the type the
arithmetic produces under C's rules (see [Arithmetic follows C](#arithmetic-follows-c)):
`var m = 1 + 0.5;` is a `double` holding 1.5, and with `u8 small = 250;`,
`var s = small + 10;` is an `int` holding 260.

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
file unless you mark it `export` (see [Visibility](visibility.md)).

Any function can run on any thread, so every thread can reach a global. It
must therefore be declared `const` and have a thread-safe type, such as a
number, an `Atomic<T>`, a `ThreadLocal<T>`, or a `[Shared]` struct (see
[Module-scope variables](threads.md#module-scope-variables)). A global that
changes is an `Atomic<T>`:

```pepper
const MAX_RETRIES = 3;
const requests = async.Atomic<long>(0);   # changed with requests.fetch_add(1)
```

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
- Casting between unrelated struct types is a compile error
  (`cannot cast to Q`).

`as` binds more tightly than the arithmetic operators, so `x * 10 as int` means
`x * (10 as int)`. Put parentheses around the expression you want to convert:
`(x * 10) as int`. C-style casts such as `(int)x` do not exist.

Many conversions also happen without `as`: assigning or passing a number to a
variable or parameter of another numeric type converts it, as in C, including
narrowing conversions (`int n = 2.7;` stores 2).

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
  their common type by the same rules (`c ? 0 : s.length` is a `long`), and
  so does a [`match` expression](enums.md#match-expressions-is-and-literal-patterns)
  over its arms. The value converts from that type wherever it goes.
- **Shifts** take the type of the (promoted) left operand. `>>` keeps the sign for
  signed types and fills with zeros for unsigned types.
- **Overflow** of unsigned arithmetic wraps around. As in C, signed overflow,
  division by zero, and shifting by the operand's width or more are not
  defined; do not rely on what they do.

```pepper
{{#include ../../examples/types-arithmetic.pep}}
```

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

`**` raises an integer to an integer power, and is right-associative:
`2 ** 3 ** 2` is `2 ** 9`. The exponent can be any integer expression. A negative
exponent gives the truncated real result: 1 for a base of 1, 1 or -1 for a base
of -1, and 0 otherwise (`2 ** -1` is 0).

Some operators have limits today:

- **`**` works only on integers.** A floating-point operand is a compile error
  (`unsupported op Pow`).

Operators bind in this order, tightest first:

1. Postfix: calls `f(x)`, indexing `a[i]`, member access `a.b`, `x++`, `x--`
2. `**`
3. `as`
4. Unary `+`, `-`, `!`, `~`
5. Prefix `++`, `--`
6. `*`, `/`, `%`
7. `+`, `-`
8. `<<`, `>>`
9. `<`, `<=`, `>`, `>=`
10. `==`, `!=`, `===`, `!==`
11. `&`
12. `|`, `^`
13. `&&`, `and`
14. `||`, `or`
15. `? :`
16. `=` and the compound assignments (right-associative)

As in C, `&` binds more loosely than `==`, so write `(flags & mask) == mask`
with the parentheses.

An expression can nest at most 256 levels deep, counting each operator of a
chain as one level, so a sum of more than about 250 terms is a compile error
(see [Compiler errors](compiler-errors.md#common-errors)).

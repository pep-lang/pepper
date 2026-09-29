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
on its own is an `int`; it takes a wider type when you store it in a variable of
that type (`long big = 9000000000;`).

```pepper
{{#include ../../examples/types-integers.pep}}
```

Storing a value that does not fit in the destination keeps its low bits, as in
C: a `u16` holding 65535 becomes 0 when you add 1 and store the result, and
`70000 as u16` is 4464.

> **Watch out:** `var big = 3000000000;` makes an `int`, because the literal is
> an `int`, and the value silently wraps to -1294967296. Write the type when a
> value needs more than 32 bits: `long big = 3000000000;`. A literal larger than
> the largest `long` (9223372036854775807) currently crashes the compiler.

### Floating point

`float` is a 32-bit and `double` a 64-bit IEEE 754 number (`f32` and `f64` are
aliases). A literal with a decimal point or an exponent, such as `0.25` or `1e3`,
is a `double`.

### Booleans

`bool` holds `true` or `false`. Comparisons and the logical operators produce a
`bool`. In arithmetic a `bool` counts as 0 or 1, and `print(true)` prints `1`.

### Characters

`char` is an 8-bit signed integer, the same type as `i8`. Pepper has no character
literals (`'a'` is a syntax error); text is a `String`, and a single character is
a one-code-point `String`.

### Strings

`String` is a UTF-8 string. A string literal such as `"hello"` is a `String`
value. `+` joins two strings into a new one, `==` and `!=` compare contents,
`length()` counts code points, `size()` counts bytes, and `s[i]` gives the code
point at index `i` as a one-code-point `String`.

```pepper
{{#include ../../examples/types-strings.pep}}
```

A `String` is a reference type: `var alias = message;` makes a second reference
to the same object rather than a copy, so a change made with `append` shows
through both names. [Memory and reference counting](memory.md) explains how
references work, and the [`String`](../reference/string.md) reference lists every
method.

String literals are taken exactly as written between the quotes. There are no
escape sequences: `"a\nb"` is four characters, a backslash included, and a
string cannot contain a `"` character.

### Other built-in types

- `void` means "no value". It is the return type of a function that returns
  nothing.
- `Array<T>` is a growable array of `T`; `int[]` is shorthand for `Array<int>`,
  and `int[][]` for `Array<Array<int>>`. See [`Array`](../reference/array.md).
- `HashMap<K, V>` and `HashSet<K>` are hash tables. See
  [HashMap and HashSet](../reference/hash.md).
- `Result<TValue, TError>`, `Error` and `None` describe operations that can
  fail. See [Error handling with Result](results.md).
- `Atomic<T>` is a value that threads can update safely. See
  [Atomics and concurrency](atomics.md).

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

> **Watch out:** when `var` infers the type of an arithmetic expression, it
> takes the type of the *left* operand. `var m = 1 + 0.5;` is an `int` holding
> 1, and with `u8 small = 250;`, `var s = small + 10;` is a `u8` holding 4. The
> arithmetic itself follows C (see below); only the inferred variable type is
> affected. Write the type when you mix types: `double m = 1 + 0.5;`.

### Constants

`const` declares a name that you do not intend to change:

```pepper
const LIMIT = 3;
const RATIO: double = 0.5;
```

The compiler does not enforce this yet: assigning to a `const` compiles and
changes the value. Treat `const` as documentation for now.

### Module-level variables

A variable declared outside any function is a module-level (global) variable. It
exists for the whole run of the program and every function in the file can read
and assign it. Its initializer can be any expression, including a function call.
Like other top-level declarations, a global is private to its file unless you
mark it `export` (see [Visibility](visibility.md)).

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
| Identity | `===` (two references to the same object) |
| Logical | `&&` (or `and`), `\|\|` (or `or`), `!` |
| Bitwise | `&` `\|` `^` `~` `<<` `>>` |
| Assignment | `=` `+=` `-=` `*=` `/=` `%=` `<<=` `>>=` `&=` |
| Increment | `++` `--`, prefix or postfix |
| Conditional | `condition ? a : b` |

Some operators have limits today:

- **`&&` and `||` evaluate both operands.** They do not short-circuit yet, so
  `items.count() > 0 && items[0] == 1` still reads `items[0]` when the array is
  empty, and panics. Guard such checks with a nested `if` instead (see
  [Control flow](control-flow.md)).
- **`**` works on integers with a constant exponent from 0 to 31**, such as
  `2 ** 10`. It is right-associative: `2 ** 3 ** 2` is `2 ** 9`. A floating-point
  operand or an exponent held in a variable is a compile error
  (`unsupported op Pow`), and a negative literal exponent (`2 ** -1`) crashes the
  compiler.
- **`|=` and `^=` do not work yet.** `|=` crashes the compiler and `^=` performs
  `|=`. Write `x = x | y` and `x = x ^ y` instead.
- **`===`** compares struct references. It is not supported for numbers.

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
10. `==`, `!=`, `===`
11. `&`
12. `|`, `^`
13. `&&`, `and`
14. `||`, `or`
15. `? :`
16. `=` and the compound assignments (right-associative)

As in C, `&` binds more loosely than `==`, so write `(flags & mask) == mask`
with the parentheses.

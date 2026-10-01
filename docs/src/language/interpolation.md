# String interpolation

An interpolated string is a string literal with a `$` before its opening
quote. Inside it, an expression in braces, `{name}` or `{a + b}`, is replaced
by the text of its value:

```pepper
{{#include ../../examples/interpolation-basics.pep}}
```

- **`{expression}`** holds an expression: a name (a local, a parameter, a
  global, or inside a method a field), a member access (`{p.x}`), a call
  (`{f(x)}`), an index (`{items[0]}`), arithmetic (`{a + b}`), or a ternary
  (`{a > b ? a : b}`). Spaces around it are ignored.
- The expression **changes no variable**: an assignment (`=`, `+=`, ...),
  `++` or `--` anywhere in it is an error, even inside a call's arguments
  (`{f(a = 3)}`). Only a closure's body, which does not run in place, may
  hold one. A function it calls may still have effects of its own.
- **String literals** may appear inside the braces (`{greet("you")}`), and
  so may character literals and other interpolated strings. A `}` inside
  them, or inside brackets of the expression's own, does not end it.
- The expression fits on **one line** and holds **no comment**: a line break
  or a `#` inside the braces is an error.
- A **format specification** may follow the expression after a `:`, as in
  `{n:>8}` or `{n:08x}`: see [below](#format-specifications).
- **`{{` and `}}`** are a literal `{` and `}`.
- **Escapes** (`\n`, `\t`, `\"`, ...) work as in any
  [string literal](types-and-variables.md#strings).
- The result is a new `String`. An interpolated string with no braces is an
  ordinary string.

## Which values can be interpolated

Each value is converted with `to_string(value)`, so it can be:

- an integer of any size, signed or unsigned, which gives its decimal text;
- a `float` or `double`, which gives the shortest decimal text that reads
  back as the same number, as Swift prints one: `0.1`, `3.0` (a whole
  number keeps its `.0`), `-2.5`, and an exponent outside 1e-4 to 1e16
  (`1e+16`, `1.5e-05`); `nan`, `inf` and `-inf` for the special values;
- a `bool`, which gives `true` or `false`;
- a [tuple](tuples.md) of up to eight values that can each be
  interpolated, which gives its elements' text in parentheses, `(1, two)`
  (a `String` element without quotes);
- a `String`, which is used as it is;
- a value whose type has a `to_string(): String` method, such as a struct
  that implements the runtime's `ToString` trait, or a value of type
  `ToString` itself;
- a value whose type has a `to_string<T>` override. Like `hash<Point>` (see
  [overriding a generic function](generics.md#overriding-a-generic-function-for-one-type)), an override applies to the whole program, so
  it serves types that have no `to_string()` method of their own.

```pepper
{{#include ../../examples/interpolation-to-string.pep}}
```

Numbers and tuples, with the [format specifications](#format-specifications)
below:

```pepper
{{#include ../../examples/interpolation-numbers.pep}}
```

`String`, `StringBuilder` and `io.Path` implement `ToString`. An enum is
interpolated through a `to_string()` method it declares (`return name();`
gives the case's name).

A plain overload such as `to_string(p: Point)` is not used: overloads of a name do not merge across files (see
[overloading](overloading.md)), so the runtime cannot see yours. Write a
`to_string<Point>` override or a method instead.

## Format specifications

A `:` after the expression starts a format specification, which pads the
value's text, writes an integer in another base, or rounds a floating-point
number to a number of digits. Its parts, all optional, come in this order:

```text
{value:[[fill]align][+][0][width][.precision][type]}
```

| Part | Meaning |
|------|---------|
| `align` | `<` left, `^` centered (leaning left), `>` right. Without one, numbers go to the right and everything else to the left. |
| `fill` | The character the padding is made of, written before `align`; a space by default. It can be any character but `{`, `}`, `"`, `'` and `#`. |
| `+` | Writes a `+` before a number that is not negative. |
| `0` | Pads with zeros after the sign (`-0042`). It cannot be combined with `align`. |
| `width` | The least number of characters the text takes; longer text is kept whole. |
| `.precision` | For a `float` or `double`: the number of digits after the point, rounded to nearest, a tie to the even digit (`{pi:.2}` is `3.14`, `{0.125:.2}` is `0.12`; `.0` leaves no point). At most 100. |
| `type` | `d` decimal, `x` and `X` hexadecimal (lower and upper case), `b` binary, `o` octal. |

```pepper
{{#include ../../examples/interpolation-format.pep}}
```

- Padding (`fill`, `align` and `width`) works for any value that can be
  interpolated: it pads the value's `to_string` text, counting characters,
  not bytes.
- `+` and `0` need a number: an integer (of any size, signed or unsigned),
  or a `float` or `double` given a precision (`{x:+08.2}`). A `type` needs
  an integer, and a precision a `float` or `double`. Using one with any
  other value is an error at that character, and a precision cannot be
  combined with a `type`.
- A negative number keeps its sign in every base: `{-42:x}` is `-2a`, not
  the bits of its two's complement.
- The `:` that starts the specification is the one after the whole
  expression, so a ternary can be formatted as it is:
  `{n > 1 ? "many" : "one":>5}`.

## Formatting by position: `String.format`

`String.format` takes a string literal whose braces name its other
arguments by position, `{0}` for the first, each with an optional format
specification, and returns the text:

```pepper
{{#include ../../examples/interpolation-string-format.pep}}
```

- The format must be a **string literal**: the compiler reads it, so an
  index out of range, an argument no brace names, or a bad specification
  is an error at compile time. `{{` and `}}` are literal braces, as in an
  interpolated string.
- Each argument is **evaluated once**, from left to right, however many
  braces name it and in whatever order.
- An index can repeat, to show one value twice or in two forms
  (`"{0} is {0:x} in hex"`).
- It is part of the compiler, not a function in the runtime: it cannot be
  stored in a variable or called through a function value.
- [`print`](functions.md#printing-with-print) takes the same arguments:
  `print("{0} of {1}", done, total)` prints what `String.format` makes of
  them.

## Errors

A value with no conversion is reported at its braces, with a note at its
type:

```text
main.pep:5:17: error: cannot interpolate a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload
    5 |     print($"f = {f}");
      |                 ^~~
main.pep:1:8: note: declare 'to_string(): String' in 'Foo', or implement 'ToString' with 'extend Foo with ToString'
    1 | struct Foo {}
      |        ^~~
```

A lone brace is an error, since doubling it is how to write one, and so is
anything after the expression but its `}`:

```text
main.pep:2:15: error: unmatched '}' in interpolated string; write '}}' for a literal '}'
    2 |     print($"a } b");
      |               ^
main.pep:3:18: error: expected '}'
    3 |     print($"a {x b");
      |                  ^
main.pep:3:15: note: to match this '{'
    3 |     print($"a {x b");
      |               ^
```

Empty braces are reported where the expression should start:

```text
main.pep:2:16: error: expected an expression after '{' in interpolated string; write '{{' for a literal '{'
    2 |     print($"a {} b");
      |                ^
```

An error in the expression itself, such as a name that is not declared
(`use of undeclared identifier 'x'`), is reported like any other, at the
token inside the braces.

A format specification's errors are reported at the character in it that
is wrong:

```text
main.pep:5:16: error: unexpected 'q' in format specification; expected '[[fill]align][+][0][width][.precision][type]'
    5 |     print($"{n:q}");
      |                ^
main.pep:5:19: error: cannot format a value of type 'String' as an integer
    5 |     print($"{name:x}");
      |                   ^
main.pep:6:16: error: cannot format a value of type 'i32' with a precision; only 'float' and 'double' take one
    6 |     print($"{n:.2}");
      |                ^
```

`String.format` reports an index with no argument at the index, and an
argument with no index at the argument:

```text
main.pep:5:31: error: argument index 2 is out of range for 2 arguments
    5 |     print(String.format("{0} {2}", n, n));
      |                               ^
main.pep:5:35: error: argument 1 of 'String.format' is not used by its format string
    5 |     print(String.format("{0}", n, n + 1));
      |                                   ^~~~~
```

Changing a variable inside the braces is reported at the operator:

```text
main.pep:3:16: error: an assignment cannot appear in an interpolated string
    3 |     print($"{a += 1}");
      |                ^~
```

## How it works

The compiler turns `$"({x}, {y + 1})"` into `"(" + to_string(x) + ", " +
to_string(y + 1) + ")"`, resolving `to_string` in the runtime rather than
in your file. So a struct's own `to_string()` method can interpolate its
fields without calling itself, and the result costs what the same `+`
expression does. A value with a format specification goes through a
runtime call that pads or converts its text instead. `String.format` becomes
the same concatenation, with its arguments bound to hidden names first when
the braces name them out of order or more than once.

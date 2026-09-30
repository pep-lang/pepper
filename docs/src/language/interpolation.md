# String interpolation

An interpolated string is a string literal with a `$` before its opening
quote. Inside it, an expression in braces, `{name}` or `{a + b}`, is replaced
by the text of its value:

```pepper
{{#include ../../examples/interpolation-basics.pep}}
```

- **`{expression}`** holds any expression but an assignment: a name (a
  local, a parameter, a global, or inside a method a field), a member access
  (`{p.x}`), a call (`{f(x)}`), an index (`{items[0]}`), arithmetic
  (`{a + b}`), or a ternary (`{a > b ? a : b}`). Spaces around it are
  ignored.
- **String literals** may appear inside the braces (`{greet("you")}`), and
  so may character literals and other interpolated strings. A `}` inside
  them, or inside brackets of the expression's own, does not end it.
- The expression fits on **one line** and holds **no comment**: a line break
  or a `#` inside the braces is an error.
- There are **no format specifiers**: `{x:5}` is an error. Pad or format the
  value with a call instead.
- **`{{` and `}}`** are a literal `{` and `}`.
- **Escapes** (`\n`, `\t`, `\"`, ...) work as in any
  [string literal](types-and-variables.md#strings).
- The result is a new `String`. An interpolated string with no braces is an
  ordinary string.

## Which values can be interpolated

Each value is converted with `to_string(value)`, so it can be:

- an integer of any size, signed or unsigned, which gives its decimal text;
- a `bool`, which gives `true` or `false`;
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

`String`, `StringBuilder` and `io.Path` implement `ToString`. An enum is
interpolated through a `to_string()` method it declares (`return name();`
gives the case's name).

Floating-point numbers have no text conversion yet, so a `float` or `double`
cannot be interpolated. A plain overload such as `to_string(p: Point)` is not
used either: overloads of a name do not merge across files (see
[overloading](overloading.md)), so the runtime cannot see yours. Write a
`to_string<Point>` override or a method instead.

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

## How it works

The compiler turns `$"({x}, {y + 1})"` into `"(" + to_string(x) + ", " +
to_string(y + 1) + ")"`, resolving `to_string` in the runtime rather than in
your file. So a struct's own `to_string()` method can interpolate its fields
without calling itself, and the result costs what the same `+` expression
does.

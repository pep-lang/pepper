# Statements and semicolons

Every simple statement ends with a `;`: a variable declaration, an
expression, `return`, `break` and `continue`. So does every declaration that
does not end in a block: a module variable, a struct field, a type alias, an
import, a re-export and an `extern` function. A statement or declaration that
ends in a block (`if`, `while`, `for`, `with`, a function, a struct) needs
none.

Line breaks, spaces and comments mean nothing to the grammar. A statement
can span as many lines as it needs, breaking anywhere between tokens,
including before an operator or a `.`, and several statements can share a
line.

```pepper
{{#include ../../examples/statements-semicolons.pep}}
```

## Leaving out a `;` is deprecated

Semicolons used to be optional. Code that leaves one out still compiles, with
a warning at the place the `;` belongs and a fix that adds it. The language
server offers it as a quick fix, and [`pep-fmt`](../tools/pep-fmt.md) adds
them all:

```text
main.pep:2:18: warning: omitting ';' is deprecated; end the statement with ';' [deprecated]
    2 |     var total = 1
      |                  ^
      |                  ;
```

A later version makes a missing `;` an error.

Without its `;`, a statement runs on for as long as the next line can
continue it, since line breaks do not end anything. So

```pepper
x = y
-z
```

is `x = y - z`, and a line that starts with `(` calls the expression on the
line above. The one exception is a declaration: until a missing `;` becomes
an error, a declaration without one ends at the end of its line, so
`var x = 1` followed by `y = 2` stays two statements.

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

## A missing `;` is an error

Leaving out a `;` is an error, reported right after the statement it should
end, with a fix that adds it. The language server offers the fix as a quick
fix:

```text
main.pep:2:18: error: expected ';'
    2 |     var total = 1
      |                  ^
      |                  ;
```

Because line breaks do not end anything, a statement missing its `;` would
otherwise run on into the next line whenever that line can continue it:

```pepper
x = y
-z
```

reads as `x = y - z;` with its `;` missing, not as two statements. The error
says where the `;` belongs when the parse cannot go on.

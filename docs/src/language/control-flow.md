# Control flow

Pepper has the familiar structured control flow of C-family languages: `if` and
`else` to choose, `while` and `for` to repeat, and `break`, `continue` and
`return` to leave early.

## `if` and `else`

`if` runs a block when its condition is true, and the optional `else` block
when it is false. The parentheses around the condition are optional; the braces
around each block are required, even for a single statement.

```pepper
{{#include ../../examples/control-if.pep}}
```

The condition is usually a `bool`, but a number also works: any value other
than zero counts as true, as in C.

### Chains of conditions

`else if` is not supported yet: `else` must be followed by a block.

```pepper
if x > 0 {
    return 1;
} else if x < 0 {    # error
    return -1;
}
```

```
main.pep:4:12: error: expected '{'
    4 |     } else if x < 0 {
      |            ^~
```

Nest the second `if` inside the `else` block instead, or return early from each
branch as `classify` does in the example above:

```pepper
if x > 0 {
    return 1;
} else {
    if x < 0 {
        return -1;
    }
}
```

For a choice between two values, the conditional operator
`condition ? a : b` is often shorter than an `if`.

### Guarding a check

`&&` and `||` do not short-circuit yet: both operands are always evaluated. A
condition such as `items.count() > 0 && items[0] > 100` still reads `items[0]`
when the array is empty, which panics with `Array index read out of bounds`.
Until this is fixed, put the guard in its own `if`, as the example does with
`readings`.

## `while`

`while` repeats its block as long as the condition is true. The condition is
checked before each iteration, so the body may run zero times. As with `if`,
the parentheses are optional and the braces are required.

```pepper
var countdown = 3;
while countdown > 0 {
    countdown -= 1;
}
```

## `for`

`for` runs its block once for each element of an [`Array`](../reference/array.md),
each code point of a [`String`](../reference/string.md), or each value of any
type that follows the iterator protocol:

```pepper
for (var score in scores) {
    total += score;
}
```

The loop variable can be declared with `var` or a type
(`for (int score in scores)`, `for (var score: int in scores)`), and the
parentheses are optional. [Iteration](iteration.md) covers the protocol behind
`for` and how to make your own types iterable.

Pepper has no counting `for (init; condition; step)` loop and no range syntax.
To count, use a `while` loop with a counter.

## `break` and `continue`

`break` leaves the innermost loop immediately. `continue` skips the rest of the
current iteration and goes on with the next one; in a `while` loop that means
checking the condition again, so update the counter before any `continue`.

```pepper
{{#include ../../examples/control-loops.pep}}
```

Both work in `while` and `for` loops and always apply to the innermost loop.
There are no labeled breaks: to leave several loops at once, set a flag and test
it, or move the loops into a function and `return` from it.

## `return`

`return value;` leaves the current function and hands `value` back to the
caller. It works from anywhere in the function, including from inside loops.
See [Functions](functions.md).

A function that returns nothing cannot use a bare `return;` yet: `return` must
be followed by a value, and `return;` is a parse error (`expected expression`).
Structure the function with `if`/`else` so that it runs off the end instead.

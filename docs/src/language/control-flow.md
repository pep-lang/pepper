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
than zero counts as true, as in C. A raw pointer (`__ptr<T>`) or a function
value counts as true when it is not null. A struct counts only if it declares
the truth-test operator `!!(): bool`, which the condition calls; any other
struct is an error, so write `node !== __null` to ask whether a reference is
set (see [Truth tests and conditions](structs.md#truth-tests-and-conditions)).
The same holds for the condition of `while` and of `?:`, the operands of `&&`,
`||`, `and` and `or`, and the operand of `!`.

### Chains of conditions

`else if` tests another condition when the ones before it were false. The
first true condition's block runs, and the final `else` block, if there is
one, runs when none was true:

```pepper
if x > 0 {
    return 1;
} else if x < 0 {
    return -1;
} else {
    return 0;
}
```

For a choice between two values, the conditional operator
`condition ? a : b` is often shorter than an `if`.

### Guarding a check

`&&` and `||` short-circuit, as in C: the right operand is evaluated only when
the left one does not already decide the result. A guard can therefore come
first in the same condition:

```pepper
if items.count > 0 && items[0] > 100 {
    print("starts high");
}
```

When `items` is empty, `items[0]` is never read.

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

Pepper has no C-style `for (init; condition; step)` loop. To count, loop over
a [range](iteration.md#looping-over-a-range): `for (var i in 0..count)`.

## `with`

`with` enters a scope object for the length of a block and binds what it
hands out. The object cleans up when it is destroyed, on every way out of the
block:

```pepper
with (var session = Session("grace")) {
    greet(session.user);
}
```

[Scoped blocks with `with`](scopes.md) covers the protocol and the optional
`else` block.

## `match`

`match` runs the arm for the case an [enum](enums.md) value holds, and the
compiler checks that every case is handled:

```pepper
match (light) {
    Red, Amber => { stop(); }
    Green => { go(); }
}
```

[Enums and `match`](enums.md#match) covers patterns and the `else` arm.

## Branch hints: `[Likely]` and `[Unlikely]`

`[Likely]` or `[Unlikely]` on the line above an `if`, an `else if`'s `if`
or a `match` arm (the `else` arm too) says how often that branch runs. The
optimizer keeps the likely path as straight-line code and moves the
unlikely one, such as error handling, out of its way. A hint never changes
what the program computes; a wrong one costs only speed.

```pepper
{{#include ../../examples/control-branch-hints.pep}}
```

- `[Likely]` above an `if` marks its block, so its `else` is the unlikely
  side; `[Unlikely]` marks the block as the rare one. To mark an `else`,
  mark the `if` the other way.
- In an `else if`, the attribute goes between `else` and `if`: `} else
  [Unlikely] if (x) {`.
- A hint is an LLVM branch weight (2000 to 1, as clang gives
  `__builtin_expect`), so it matters with optimization (`-O1` and up).
- Only one of them, with no arguments, can mark a branch, and no other
  attribute can:

  ```text
  main.pep:3:5: error: 'Target' cannot mark an 'if'; only '[Likely]' or '[Unlikely]' can
      3 |     [Target(OS(Linux))]
        |     ^~~~~~~~~~~~~~~~~~~
  ```

`while` loops and the arms of a `match` expression take no hint yet.

## `break` and `continue`

`break` leaves the innermost loop immediately. `continue` skips the rest of the
current iteration and goes on with the next one; in a `while` loop that means
checking the condition again, so update the counter before any `continue`.

```pepper
{{#include ../../examples/control-loops.pep}}
```

Both work in `while` and `for` loops and apply to the innermost loop.

### Labeled loops

To leave or go on with an outer loop, give it a label, a name and a colon
before `for` or `while`, and name it after `break` or `continue`. `break
rows;` leaves the loop labeled `rows` and every loop inside it; `continue
rows;` goes on with the next iteration of `rows`:

```pepper
{{#include ../../examples/control-labels.pep}}
```

A label names a loop only inside that loop's body, and not inside a closure
there, whose body is a function of its own. Naming a label that no loop
around the `break` has is an error, and so is giving a loop the label of a
loop around it:

```text
main.pep:3:15: error: use of undeclared label 'nope'
    3 |         break nope;
      |               ^~~~
```

A label goes only on a loop (`expected 'for' or 'while' after the label
'a'`). A compile-time loop in a [`static` block](reflection.md) cannot have
a label yet.

## `return`

`return value;` leaves the current function and hands `value` back to the
caller. It works from anywhere in the function, including from inside loops.
See [Functions](functions.md).

In a function that returns nothing, a bare `return;` leaves the function early.

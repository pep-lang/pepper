# Compiler errors

When the compiler cannot build your program, it tells you what is wrong and
exactly where, in the same format as clang. This chapter shows how to read an
error and lists some common ones.

## Reading an error

Here is a program with a mistake in it:

```pepper
struct Point {
    var x: int;
    var y: int;
}

main(): int {
    var p = Point();
    var total = p.x + p.z;
    return total;
}
```

Compiling it prints:

```text
main.pep:8:25: error: no member named 'z' in 'Point'
    8 |     var total = p.x + p.z;
      |                         ^
```

An error has three parts:

1. **The header:** the file, line and column, then `error:` and the message.
   Editors and terminals recognize `file:line:column` and can jump to it.
2. **The source line** the error is on, with its line number.
3. **A caret** (`^`) under the exact token you need to change, with `~` under
   the rest of the token when it is longer than one character. Here, the
   member name `z`, not the whole statement.

Messages follow clang's style: they start in lowercase, put names and types in
single quotes (`'z'`, `'Point'`), and say what to do when there is an obvious
fix. The fixed program is:

```pepper
{{#include ../../examples/errors-fixed.pep}}
```

## Notes

Some errors are explained by a second place in your code. The compiler shows
that place as a `note:` after the error, in the same format. When one file
calls a function that another file did not export, the note points at the
declaration:

```text
main.pep:4:12: error: 'helper' is private to lib.pep; declare it with 'export' to use it from another file
    4 |     return helper();
      |            ^~~~~~
lib.pep:1:1: note: declared here
    1 | helper(): int { return 1; }
      | ^~~~~~
```

When a brace is never closed, the error is at the end of the file, and the
note shows the brace that opened the block:

```text
main.pep:5:1: error: expected '}'
    5 | 
      | ^
main.pep:1:13: note: to match this '{'
    1 | main(): int {
      |             ^
```

## One error at a time

The compiler stops at the first error it finds and exits with status 1, so fix
that error and compile again. It never produces an executable from a program
with an error.

On a terminal, errors are colored like clang's. Set the `NO_COLOR` environment
variable to turn colors off. Output that goes to a file or a pipe is never
colored.

Warnings do not stop the build. Besides the linker's own warnings, which the
compiler passes through (see [Linking](linking.md)), the only warnings today
are deprecations.

## Deprecations

Syntax on its way out keeps compiling for a while, with a warning that names
its replacement and shows the fix under the code it replaces. The language
server offers the same fix as a quick fix.

```text
main.pep:3:5: warning: `new` is deprecated; constructors are spelled `construct`, matching `destruct` [deprecated]
    3 |     new(this.x = 1) {}
      |     ^~~
      |     construct
```

| Deprecated | Replacement |
|------------|-------------|
| `new(...)` constructor | `construct(...)` |

## Errors in the editor

The Pepper language server, used by the VS Code extension, reports the same
errors at the same places while you type. It underlines the token the caret
would point at, and shows each note as related information that you can
click to jump to.

## Common errors

These are some errors you are likely to meet, with the exact text the compiler
prints.

**A name that was never declared**, often a typo:

```text
main.pep:3:16: error: use of undeclared identifier 'nope'
    3 |     return a + nope;
      |                ^~~~
```

```text
main.pep:2:12: error: call to undeclared function 'frob'
    2 |     return frob(1);
      |            ^~~~
```

**A type name that does not exist**, often a misspelled type or a missing
[import](modules.md):

```text
main.pep:2:12: error: unknown type name 'Frob'
    2 |     var x: Frob = 1;
      |            ^~~~
```

**A field or method the struct does not have:**

```text
main.pep:6:7: error: no member named 'move' in 'Point'
    6 |     p.move(1);
      |       ^~~~
```

**The wrong number of arguments.** When the function has
[default parameters](functions.md), the message gives the range:

```text
main.pep:4:12: error: too few arguments to 'add': expected 2, have 1
    4 |     return add(1);
      |            ^~~
```

```text
main.pep:3:12: error: too many arguments to 'f': expected at most 2, have 3
    3 |     return f(1, 2, 3) + f();
      |            ^
```

**A syntax error.** The parser says what it expected at the first place the
code stopped making sense:

```text
main.pep:2:14: error: expected ')'
    2 |     if (true {
      |              ^
```

```text
main.pep:2:13: error: expected expression
    2 |     var x = ;
      |             ^
```

**A value of the wrong type.** Numbers convert among themselves, as in C, but
a number is never a struct and one struct type is never another, except that
a struct converts to a [trait it declares](traits-and-extensions.md#traits-as-types),
and a value converts to a struct whose constructor from its type is
[`[Implicit]`](structs.md#implicit-conversions).
A raw pointer is never a struct either: a `__ptr<char>` is not a `String`
(copy it with `String(p)`), and a `String` is not a `__ptr<char>` (pass its
`c_str()`).
The check applies wherever a value flows into a typed place: a variable's
initializer, an assignment, an argument and a `return`:

```text
main.pep:2:5: error: cannot initialize variable 'x' of type 'int' with a value of type 'String'
    2 |     int x = "hello";
      |     ^~~
```

```text
main.pep:3:12: error: cannot pass a value of type 'i32' as argument 1 of 'g', which has type 'String'
    3 |     return g(5);
      |            ^
```

```text
main.pep:3:19: error: cannot pass a value of type '__ptr<char>' as argument 2 of 'assert', which has type 'String'; use 'String(...)' to copy a C string
    3 |     assert(false, p);
      |                   ^
```

```text
main.pep:2:12: error: cannot return a value of type 'String' from 'f', which returns 'int'
    2 |     return "a";
      |            ^~~
```

**A struct used as a trait it does not declare** (see
[Traits as types](traits-and-extensions.md#traits-as-types)):

```text
main.pep:11:20: error: 'Circle' does not conform to trait 'Shape'
   11 |     var s: Shape = Circle();
      |                    ^~~~~~
main.pep:6:8: note: declare it with 'extend Circle with Shape'
    6 | struct Circle {
      |        ^~~~~~
```

**A value that is not thread-safe given to another thread** (see
[Threads](threads.md#what-threads-can-share)): here a thread body, a
`shared` function value, that captures a `String`:

```text
main.pep:5:46: error: closure passed as 'shared () => void' captures 'name' of type 'String', which is not thread-safe
    5 |     var t = async.Thread.spawn(() => { print(name); });
      |                                              ^~~~
main.pep:4:9: note: capture a thread-safe value instead, such as an 'Atomic<T>' or a '[Shared]' struct
    4 |     var name = "worker";
      |         ^~~~
```

**The same name declared twice in one scope:**

```text
main.pep:3:9: error: redefinition of 'n'
    3 |     var n = 2;
      |         ^
main.pep:2:9: note: previous definition is here
    2 |     var n = 1;
      |         ^
```

**Looping over something that cannot be iterated** (see
[Iteration](iteration.md)):

```text
main.pep:3:19: error: type 'int' is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())
    3 |     for (var i in 5) {
      |                   ^
```

**An import that names nothing** (see [Modules and imports](modules.md)):

```text
main.pep:1:8: error: cannot find "nope.pep" or the module folder "nope" next to this file
    1 | import "nope";
      |        ^~~~~~
```

## Errors while the program runs

Some problems can only be found while the program runs, such as an array index
out of range or a failed `assert`. These are not compiler errors: the program
prints a message and stops immediately (it aborts, so it exits with a failure
status instead of returning from `main`). See [`assert` and
`panic`](../reference/internals.md).

## Current limitations

The type check does not compare the type arguments of generic structs yet, so
`Array<int> a = Array<String>();` compiles. Read such code carefully: the
resulting program has undefined behavior.

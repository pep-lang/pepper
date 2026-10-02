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

Warnings do not stop the build, and the compiler prints them whether or not
it also finds an error. Besides the linker's own warnings, which the compiler
passes through (see [Linking](linking.md)), the warnings today are
deprecations and a method whose parameter names differ from its trait's
(see [Traits](traits-and-extensions.md#traits)).

## Deprecations

A use of a declaration marked `[Deprecated("message")]` warns at the name,
with the message and a note at the declaration. When the attribute names a
replacement, the warning shows the rename under the code, and the language
server offers it as a quick fix. See [Deprecation](deprecation.md).

```text
main.pep:9:15: warning: 'clone' is deprecated: use 'copy' instead [deprecated]
    9 |     var b = a.clone();
      |               ^~~~~
      |               copy
main.pep:4:5: note: 'clone' declared here
    4 |     clone(): Counter { return this.copy(); }
      |     ^~~~~
```

Syntax of the language itself that is on its way out keeps compiling for a
while too, with a warning that names its replacement and shows the fix under
the code it replaces:

```text
main.pep:3:5: warning: `new` is deprecated; constructors are spelled `construct`, matching `destruct` [deprecated]
    3 |     new(this.x = 1) {}
      |     ^~~
      |     construct
```

| Deprecated | Replacement |
|------------|-------------|
| `new(...)` constructor | `construct(...)` |
| `io.Path.join_str(String)` | `io.Path.join(Path)`, which accepts a `String` |
| `String.clone()` | `String.copy()` |
| `ThreadLocal<T>.get()` for a `T` that is not thread-safe (now an error) | `with (var value = local.enter()) { ... }` |
| `io.Path.is_dir()` | `io.Path.is_directory()` |
| `io.File.set_len(ulong)` | `io.File.set_length(ulong)` |
| `io.File.write_string(String)` | `io.File.write_all(String)` |
| `io.TcpStream.write_string(String)`, `io.UnixStream.write_string(String)`, `tls.TlsStream.write_string(String)` | `write_all(String)` |
| `io.File.seek(Offset, int)` | `io.File.seek(io.SeekFrom)` |
| `io.File.std_file(int, String)` | `io.File.std_file(io.StdStream, String)` |
| `HashMap.cap()`, `HashSet.cap()` | the `capacity` property |
| `arguments()`, `exit(code)` in the prelude | `process.arguments()`, `process.exit(code)` (`import process`) |
| `Channel.send(x)`, `try_send(x)` with a variable something else references (now an error: `send` no longer copies) | `send(move(x))`, or `send(copy(x))` to keep using `x` |
| `[Sending]` parameter attribute (now an error) | `[Move]` |
| `io.Print` trait | `io.Writer` (which also needs `write(data)`) |
| `Atomic<T>` without an import (now an error: it moved to the `async` module) | `async.Atomic<T>` after `import async`, or `import [Atomic] from async` |
| `math.parse_int(text, base)` | `long.parse(text, base)`, with no import |
| `Optional<T>()` (now an error: `Optional` is an enum) | `Optional<T>.Empty` |
| `Optional` cases `None` and `Some(v)` (now an error: renamed) | `Empty` and `Value(v)` |
| `Optional<T>.some(v)`, `Optional<T>.none()` | the cases `Optional<T>.Value(v)`, `Optional<T>.Empty` |
| `Optional.is_some()`, `Optional.is_none()` | `is_value()`, `is_empty()` |
| `[LinkName("symbol")]` on an extern (now an error) | `[Link(name = "symbol")]` |
| A parameter's former name, kept by `[Rename("old", "new")]` | the new name (see [named arguments](functions.md#other-names-for-a-parameter)) |
| `Copyable<T>` implemented as `copy(copies: Copies): T`, with `copies.copy(x)` and `copies.register(original, made)` | `copy(): T`, with `copy(x)` and `register_copy(original, made)` (see [copying](memory.md)) |
| `hint.likely(condition)`, `hint.unlikely(condition)` | `[Likely]` or `[Unlikely]` above the `if` or `match` arm (see [branch hints](control-flow.md#branch-hints-likely-and-unlikely)) |

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

**A call no overload fits, or that two fit equally well.** Each note is a
candidate, and says why it does not fit (see [Overloading](overloading.md)):

```text
main.pep:3:22: error: call to 'f' is ambiguous
    3 | main(): int { return f(1); }
      |                      ^
main.pep:1:1: note: candidate function
    1 | f(x: long): int { return 1; }
      | ^
main.pep:2:1: note: candidate function
    2 | f(x: short): int { return 2; }
      | ^
```

**A struct used as a condition** without a truth-test operator. A struct is
never tested for null implicitly: declare `!!(): bool` on it, or compare with
`__null` (see [Truth tests and conditions](structs.md#truth-tests-and-conditions)):

```text
main.pep:6:9: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'
    6 |     if (node) {
      |         ^~~~
main.pep:1:8: note: 'Node' declared here
    1 | struct Node {
      |        ^~~~
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
Two specializations of one generic struct are different types: `Array<int>`
is not `Array<String>` and `Array<Derived>` is not `Array<Base>`. Type
arguments compare exactly, at every depth, after aliases resolve and omitted
arguments take their defaults (`Result<int>` is `Result<int, Error>`).
The check applies wherever a value flows into a typed place: a variable's
initializer, an assignment, an argument, a `return`, and each arm of
`c ? a : b`, whose false arm must convert to the true arm's type:

```text
main.pep:2:13: error: cannot initialize variable 'x' of type 'int' with a value of type 'String'
    2 |     int x = "hello";
      |             ^~~~~~~
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

```text
main.pep:2:20: error: cannot initialize variable 'a' of type 'Array<int>' with a value of type 'Array<String>'
    2 |     Array<int> a = Array<String>();
      |                    ^~~~~~~~~~~~~
```

```text
main.pep:3:35: error: incompatible operand types ('Array<int>' and 'Array<String>')
    3 |     var a = flag ? Array<int>() : Array<String>();
      |                                   ^~~~~~~~~~~~~
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
main.pep:4:9: note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct
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

The same holds for top-level types: two structs, traits, enums or type
aliases of one name in a file, or exported by two
[prelude modules](modules.md#the-runtime-prelude-and---import), report
`redefinition of 'Point'`.

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

**Code nested too deeply.** Parentheses, blocks, calls, and each operator of
a chain (`a + b + c` is two levels) nest the program one level deeper, and a
file may nest at most 256 levels. The error points at the token that crosses
the limit, here the 255th `+` of a long sum:

```text
main.pep:2:1030: error: code is nested too deeply: the limit is 256 levels; split it into smaller expressions or functions
    2 |     return 0 + 1 + 1 + ... + 1;
      |                             ^
```

Split the expression into steps (`var part = ...;`), or move the inner part
into a function.

**A generic that asks for a larger copy of itself** (see
[Generics](generics.md)). Each type argument makes a separate copy of a
generic, so a `Foo<T>` holding a `Foo<Array<T>>` never runs out of copies to
make. The compiler stops 64 levels deep, at the type that asks for the next
level, with a note where the chain started:

```text
main.pep:2:16: error: 'Foo' is specialized 65 levels deep, past the limit of 64; a generic whose instance asks for a larger instance of itself never ends
    2 |     var inner: Foo<Array<T>>;
      |                ^~~~~~~~~~~~~
main.pep:6:13: note: asked for by 'main' here
    6 |     var f = Foo<int>();
      |             ^~~~~~~~
```

**A cast that reinterprets memory.** `as` converts values, like `static_cast`
(see [Casting with `as`](types-and-variables.md#casting-with-as)); a pointer to
an integer, or to a pointer of another type, needs
[`unsafe_cast`](types-and-variables.md#reinterpreting-with-unsafe_cast):

```text
main.pep:3:15: error: cannot cast '__ptr<int>' to 'ulong' with 'as'; use 'unsafe_cast<ulong>(...)' to reinterpret
    3 |     var a = p as ulong;
      |               ^~
```

## Errors while the program runs

Some problems can only be found while the program runs, such as an array index
out of range, an [integer overflow](types-and-variables.md#integer-overflow), a
division by zero, or a failed `assert`. These are not compiler errors: the program
prints a message and stops immediately (it aborts, so it exits with a failure
status instead of returning from `main`). See [`assert` and
`panic`](../reference/internals.md).

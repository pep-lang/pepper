# Introduction

Pepper is a compiled programming language for writing fast, native programs
that are safe by default. Like Rust and Swift, it aims to rule out whole
classes of memory bugs without asking you to manage memory by hand. It puts
three things first:

- **Clarity.** Code should say what it does. Pepper has a small, familiar
  syntax, one way to write most things, and error messages that point at the
  exact token you need to change.
- **Simplicity.** There is no inheritance, no garbage collector to tune, and
  no ownership annotations to learn. Structs hold data, methods and
  extensions add behavior, and traits describe what a type can do.
- **Concurrent safety.** Shared data should be safe to use from more than one
  thread. Only thread-safe values can be shared: numbers, `Atomic<T>`, and
  structs declared `[Shared]`, whose fields the compiler checks.

Here is a complete Pepper program:

```pepper
{{#include ../examples/tutorial-hello.pep}}
```

## How Pepper manages memory

Every struct value in Pepper is a reference to an object on the heap, and the
object is freed when the last reference to it goes away. The model is exactly
C++'s `std::shared_ptr<T>` passed by value: storing a reference in a
variable, a field, an array element or a parameter adds a reference, and that
reference is released when the variable goes out of scope or is overwritten.
There is no separate notion of a "borrowed" reference to learn. Numbers and
other primitive values are copied, as in C.

Because the rules are the same everywhere, you can predict exactly when an
object is freed and when its destructor runs. The chapter on
[memory and reference counting](language/memory.md) covers the model in
detail.

## How Pepper is built

The compiler is written in Rust. It parses your program, checks it, and
generates native code through [LLVM](https://llvm.org), then links an
executable with the system's C toolchain. The same compiler powers a language
server, so editors such as VS Code show Pepper's errors as you type.

Pepper runs on Windows (x64), Linux (x64) and macOS (arm64).

## Current status

Pepper is young. The core language works and is tested: variables, functions,
structs with constructors, destructors and methods, enums with `match`, tuples
and multiple return values, generics (with type
arguments inferred at calls, and generic methods), type aliases,
traits (with default methods, and usable as types), function types and
closures, modules (with `export * from` re-exports), `Result`-based error handling, `Optional` values, iteration (with `map` and
`filter` adapters),
`with` blocks, weak references, and calling C (including C callbacks). The standard library covers strings, arrays, hash
maps and sets, atomics, threads, channels and mutexes, and file-system access. That is enough to write real
programs, but expect gaps. [pep-fmt](tools/pep-fmt.md), the code formatter, is
itself written in Pepper.
Some that you will meet quickly:

- Functions are values: a named function, a method (`p.norm`,
  `Point.norm`), a constructor (`Point`), a generic function's
  specialization (`larger<int>`) or a closure such as `(x: int) => x * 2`
  can be stored, passed and called through a function type such as
  `(int) => int` (see
  [function types and closures](language/function-types.md)).
- A constructor marked `[Implicit]` converts a value into its struct
  wherever the struct is expected, so `io.Path` parameters accept a `String`
  (see [implicit conversions](language/structs.md#implicit-conversions)).
- Free functions, methods, operators, extension methods and trait members
  can be [overloaded](language/overloading.md); constructors cannot yet.
- Generic parameters cannot require a trait yet (no `<T: Shape>`).
- Threads can share only thread-safe values, which the compiler checks,
  closure captures included. A channel copies what it is sent with `copy`,
  so a `String` or an `Array` crosses threads that way; mutexes and `Lazy`
  hold thread-safe values only, and a trait value cannot be copied yet (see
  [threads](language/threads.md#limitations)).
- Reference counting does not reclaim cycles on its own: two objects that
  refer to each other are never freed. Break the cycle with a
  [weak reference](language/memory.md#weak-references) on one side.
- `print` writes each argument on its own line.

Each chapter of this book says plainly what is and is not supported. When a
chapter shows a feature, the example was compiled and run to check it.

## How this book is organized

- **Tutorial.** [Getting started](tutorial/getting-started.md) builds the
  compiler and runs your first program. [A tour of Pepper](tutorial/tour.md)
  then walks through the main features by building a small word-counting
  program.
- **Language guide.** One chapter per part of the language, from
  [types and variables](language/types-and-variables.md) to
  [calling C](language/c-interop.md). Read it in order, or jump to the topic
  you need.
- **Standard library reference.** Every type and function in the runtime,
  generated from the runtime's own documentation comments. Start at the
  [overview](reference/README.md).

Every complete program in this book lives in the repository's
`docs/examples/` folder and is compiled and run by the test suite, so what
you read is what works.

## Versions of this book

This documentation is versioned with the compiler. Use the version picker in
the top-right corner of each page to switch between releases; `dev` follows the `main`
branch. Read the version that matches the compiler you are using.

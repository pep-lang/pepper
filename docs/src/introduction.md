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
  thread. Only thread-safe values can be shared: numbers, `async.Atomic<T>`, and
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

The compiler is written in Pepper, and builds itself. It parses your program, checks it, and
generates native code through [LLVM](https://llvm.org), then links an
executable with the system's C toolchain. The same compiler powers a language
server, so editors such as VS Code show Pepper's errors as you type.

Pepper runs on Windows (x64), Linux (x64) and macOS (arm64), compiles
to WebAssembly for WASI (`--target wasm32-wasip1`, see
[WebAssembly](language/platform-selection.md#webassembly)), and builds
libraries that iOS and Android apps call (see
[iOS and Android](language/mobile.md)).
Each release is prebuilt for Windows (x64), Linux (x64, glibc 2.28 or newer)
and macOS (arm64 and x64), and installs with one command: see
[Installing Pepper](tools/install.md).

## Current status

Pepper is young. The core language works and is tested: variables, functions,
structs with constructors, destructors, methods and [properties](language/properties.md), [value structs and enums](language/value-structs.md) (`[Value]`), derived `==` and `hash` ([`[Equatable]`](language/hashing.md)), enums (with cases that carry values, methods and computed properties) and `match` (as a statement or a value, on enums, integers, characters, strings and trait values, with `is` tests, nested and tuple patterns, guards, ranges and constants), tuples
and multiple return values, array and map literals, generics (with type
arguments inferred at calls, and generic methods), type aliases,
traits (with default methods, and usable as types that convert back with `as?`), function types and
closures, modules (with `export * from` re-exports), `Result`-based error handling (`Result` is an enum, and `?` propagates errors), `Optional` values, iteration (with `map`,
`filter`, `enumerate` and `zip` adapters),
`with` blocks, weak references (to structs and trait values), and calling C (including C callbacks), and being called from C (`[Export]`ed functions in a static or shared library, with a generated header). The standard library covers strings (with a `StringBuilder`, `StringConstant` for literals' constant bytes,
`to_string` and a `ToString` trait, `$"{a + b:>8}"` interpolation with format specifications, and `String.format`), sortable arrays, hash
maps and sets, sorted maps and sets (`Map`, `Set`) and an insertion-ordered `OrderedMap`, a `BitSet` of small integers, atomics, threads, channels and mutexes, tasks (green threads
that take turns on a few worker threads, parking on sockets and timeouts), file-system access (see [files](language/files.md)), text encodings (UTF-16, ASCII; see [text](language/text.md)),
TCP, UDP and Unix domain sockets, TLS, an HTTP/1.1 and HTTP/2 client and server (streamed bodies, redirects, connection reuse, ALPN), URI parsing and percent-encoding, [base64, form data and UUIDs](language/encodings.md), regular expressions, JSON (parsing and writing `JsonValue`s, JSONC documents that keep their comments, and converting structs with `json.encode` and `json.decode`), [TOML](language/toml.md) (parsing, writing, editing a document in place, and converting structs), gzip and zlib compression, tar archives, cryptographic hashes (SHA-256, SHA-1 and BLAKE3 in the `digest` module), [random numbers](language/random.md) (secure bytes from the operating system and a seedable generator), [SIMD vectors](language/simd.md) (`simd.Vector<T, N>`), command-line arguments (`main(args: String[])`, parsed into options with the `cli` module), starting child processes, the `os` module (environment variables, monotonic and wall clocks with `Duration`, and machine and user information), the `time` module (dates, times of day, time zones from the system's database, and RFC 3339, HTTP and `strftime` text), the `debug` module (stack backtraces, which a panic also prints, and the debugger), and [leveled, structured logging](language/logging.md) (the `log` module). [Unit tests](language/testing.md) are `[Test]` functions that
`pepper test` runs in parallel, each in a process of its own. That is enough to write real
programs, but expect gaps. [pep-fmt](tools/pep-fmt.md), the code formatter,
[pep-profile](tools/pep-profile.md), which profiles a program and draws a
flame graph, [pep-test](tools/pep-test.md), which runs unit tests, and
[`pepper`](tools/pepper.md), the entry point that runs every
tool, are themselves written in Pepper. A [`pep.toml`](tools/projects.md)
project builds with `pepper build` alone and imports the packages it depends
on by name, which [`pepper package`](tools/pep-package.md) fetches from
GitHub, GitLab or Codeberg.
Some things you will meet quickly:

- Functions are values: a named function, an `extern` C function, a method (`p.norm`,
  `Point.norm`), a constructor (`Point`), a generic function's
  specialization (`larger<int>`) or a closure such as `(x: int) => x * 2`
  can be stored, passed and called through a function type such as
  `(int) => int` (see
  [function types and closures](language/function-types.md)).
- A constructor marked `[Implicit]` converts a value into its struct
  wherever the struct is expected, so `io.Path` parameters accept a `String`
  (see [implicit conversions](language/structs.md#implicit-conversions)).
- Free functions, methods, operators, constructors, extension methods and
  trait members can be [overloaded](language/overloading.md).
- A `static` block runs in the compiler: it can list a struct's fields and
  the attributes on them (`[Attribute]` structs of your own) and generate
  code for each, so one function can encode any struct (see
  [reflection and attributes](language/reflection.md)).
- `-D NAME=VALUE` on the command line defines a build option, which
  `[BuildOption("NAME")]` and `[Target(BuildOption(NAME) >= 2)]` select code
  by and `static` blocks read (see
  [build options](language/build-options.md)).
- A call can name its arguments, `window("Editor", resizable = false)`, to
  skip defaulted parameters or pass them in any order (see
  [named arguments](language/functions.md#named-arguments)).
- Generic parameters can require traits (`<T: Shape & Named>`), checked
  wherever the generic is used and, inside the generic, against what the
  traits declare (see [constraints](language/generics.md#constraints)).
  Numbers, `bool` and enums whose cases carry nothing can declare traits
  too, for constraints, but are never trait values.
- Threads can share only thread-safe values, which the compiler checks,
  closure captures included. A channel hands over what it is sent without
  copying it (`send(move(x))`, or `send(copy(x))` to keep `x`), a `Select`
  waits to receive from or send to several channels at once, and a `Mutex` holds any struct, with
  the compiler keeping each locked value apart from the rest of the program
  (see
  [threads](language/threads.md#what-a-lock-body-may-do)). An `RwLock`
  lets many threads read a thread-safe value at once, and `Semaphore`,
  `Barrier` and `Latch` coordinate groups of threads. A `[ThreadLocal]`
  module-scope `var` gives every thread its own copy, compiled to the
  platform's native thread-local storage (see
  [thread-local variables](language/threads.md#thread-local-variables)).
- Integer arithmetic that overflows panics instead of wrapping, at every
  optimization level; `wrapping_add` and its siblings wrap on purpose (see
  [integer overflow](language/types-and-variables.md#integer-overflow)).
  Bit counting, rotation, byte swapping and the floating-point functions
  are methods that compile to LLVM's intrinsics, and any other intrinsic
  can be declared as an extern (see
  [LLVM intrinsics](language/c-interop.md#llvm-intrinsics)).
- Reference counting does not reclaim cycles on its own: two objects that
  refer to each other are never freed. Break the cycle with a
  [weak reference](language/memory.md#weak-references) on one side.

Each chapter of this book says plainly what is and is not supported. When a
chapter shows a feature, the example was compiled and run to check it.

## How this book is organized

- **Tutorial.** [Getting started](tutorial/getting-started.md) builds the
  compiler and runs your first program. [A tour of Pepper](tutorial/tour.md)
  then walks through the main features by building a small word-counting
  program.
- **Language guide.** One chapter per part of the language, from
  [types and variables](language/types-and-variables.md) to
  [naming conventions](language/naming.md). Read it in order, or jump to the
  topic you need.
- **Tools.** [The pepper command](tools/pepper.md),
  [pep-run](tools/pep-run.md),
  [pep-fmt](tools/pep-fmt.md), [pep-profile](tools/pep-profile.md),
  [pep-test](tools/pep-test.md) and [debugging](tools/debugging.md).
- **Standard library reference.** Every type and function in the runtime,
  generated from the runtime's own documentation comments. Start at the
  [overview](reference/README.md).
- **Contributing.** [Building this documentation](contributing/docs.md).

Every complete program in this book lives in the repository's
`docs/examples/` folder and is compiled and run by the test suite, so what
you read is what works.

## Versions of this book

This documentation is versioned with the compiler. Use the version picker in
the top-right corner of each page to switch between releases; `dev` follows the `main`
branch. Read the version that matches the compiler you are using.

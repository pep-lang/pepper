# A tour of Pepper

This chapter walks through the main features of Pepper by writing small
programs, and ends with a word counter that reads a file and reports how often
each word appears. It moves quickly and shows the common case of each feature;
every section links to the chapter of the language guide that covers it fully.

Every program here is complete: save it to a file, compile it as shown in
[Getting started](getting-started.md), and run it. Each one checks its own
results with `assert(condition, "message")`, which stops the program with the
message if the condition is false, so a program that runs to the end and
returns 0 did what the comments say.

## Variables and functions

```pepper
{{#include ../../examples/tutorial-tour-basics.pep}}
```

A few things to notice:

- `var` declares a variable whose type comes from its initial value: `42` is
  an `int`. You can also name the type yourself, as in `double ratio = 0.5;`.
  `as` converts between types, such as from `double` to `int`. See
  [Types and variables](../language/types-and-variables.md).
- A function is declared as `name(parameters): return type`, and each
  parameter as `name: type`. A parameter can have a default value, as `name`
  does in `greet`. A function that returns nothing leaves out the return type.
  See [Functions](../language/functions.md).
- `if` and `while` do not need parentheses around the condition, but the body
  always needs braces. Chain conditions with `else if`. See
  [Control flow](../language/control-flow.md).
- `+=` updates a variable in place, and `+` joins two strings.
- `print` writes one value per line. Called with several arguments, it prints
  each one on its own line.

## Structs

A struct groups related data with the methods that act on it:

```pepper
{{#include ../../examples/tutorial-tour-structs.pep}}
```

- Fields are declared like variables, with `var name: type`, and may have
  default values.
- The constructor is named `construct`. A parameter written as
  `this.x = 0` stores its argument straight into the field `x`, and `= 0`
  makes it optional, so `Point()` and `Point(3, 4)` both work.
- Methods are functions declared inside the struct. Inside a method, `this`
  is the object the method was called on.
- `extend Point { ... }` adds methods to a struct from outside its
  declaration, even to a struct from the standard library.

Struct values are references. `var q = p;` does not copy the point: `p` and
`q` refer to the same object, so moving `q` moves `p`. Pepper frees an object
when the last reference to it goes away, so you never free memory yourself.
See [Structs](../language/structs.md) and
[Memory and reference counting](../language/memory.md).

## Collections

The standard library provides growable arrays, strings, and hash maps. You do
not need to import them:

```pepper
{{#include ../../examples/tutorial-tour-collections.pep}}
```

- [`Array<T>`](../reference/array.md) is a list that grows as you `append`.
  `int[]` is a shorter way to write the type `Array<int>`. Indexing is checked:
  reading past the end stops the program with an error rather than reading
  stray memory.
- [`String`](../reference/string.md) holds UTF-8 text. `length()` counts
  characters (code points), and `s[i]` is the character at index `i`, as a
  one-character string. Strings compare by content with `==`.
- [`HashMap<K, V>`](../reference/hash.md) maps keys to values. Reading a key
  that is not there gives the default value of `V` (0 for numbers) without
  adding it; use `contains` to tell the two apart.
  [`HashSet<K>`](../reference/hash.md#hashset) keeps each key once.
- `for (var x in collection)` visits each element of an array, or each
  character of a string, in order. See [Iteration](../language/iteration.md).

## Handling errors with Result

Pepper has no exceptions. A function that can fail returns a
[`Result`](../reference/result.md): either a value, or an error that explains
what went wrong.

```pepper
{{#include ../../examples/tutorial-tour-results.pep}}
```

- `Result<int>` holds either an `int` or an `Error`. Build one with
  `Result<int>.ok(value)` or `Result<int>.err(Error("message"))`.
- `is_ok()` and `is_err()` tell you which one you have. `Value` and `Error`
  are its fields; `Error.Message` is the error's text.
- `value()` returns the value, and stops the program if there is none. Use it
  only when an error would be a bug. `ok_or(fallback)` returns the value, or
  `fallback` if there is none.

See [Error handling with Result](../language/results.md).

## Putting it together: a word counter

The last program combines everything above. It writes a short text file,
reads it back, and counts how often each word appears. It is split into two
files: `counter.pep` defines a `WordCounter` struct, and `main.pep` uses it.

`counter.pep`:

```pepper
{{#include ../../examples/tutorial-word-count/counter.pep}}
```

`main.pep`:

```pepper
{{#include ../../examples/tutorial-word-count/main.pep}}
```

Compile it by passing the entry file; the compiler finds `counter.pep` from
the import:

```sh
pepper main.pep -o word-count
./word-count
```

It prints each word followed by its count, one value per line, and then the
error message for the missing file (its exact text comes from the operating
system):

```text
the
3
cat
1
sat
2
...
No such file or directory
```

What is new here:

- **Imports.** `import "counter";` makes the declarations that `counter.pep`
  marks with `export` available in `main.pep`. Anything not exported stays
  private to its file. `import [File, Directory, Path] from io;` brings three
  names in from the standard library's `io` module, which, unlike `String` or
  `Array`, must be imported. See [Modules and imports](../language/modules.md)
  and [Visibility](../language/visibility.md).
- **Files.** `Directory.temp()` is the system's temporary directory, and
  `join` adds a name to a [`Path`](../reference/io-path.md); the name can be
  a plain `String`, which converts to a `Path` implicitly.
  [`File`](../reference/io-file.md) has helpers that read or write a whole
  file at once: `File.write_text` and `File.read_to_string`.
- **I/O errors are Results.** `File.read_to_string` returns a `Result` whose
  error is an [`IoError`](../reference/io-types.md), so reading a missing file
  is an ordinary error value, not a crash. `count_file` turns it into its own
  `Result<WordCounter>`.
- **Strings character by character.** `add_text` walks the text one character
  at a time and builds each word with `+=`, since the `String` type has no
  `split` method yet.

## Where to go next

You have now seen most of what you need to write everyday Pepper code. The
[language guide](../language/types-and-variables.md) covers each topic in
depth, including features this tour skipped:
[generics](../language/generics.md),
[function types and closures](../language/function-types.md),
[traits and extensions](../language/traits-and-extensions.md),
[atomics](../language/atomics.md),
[threads](../language/threads.md), and
[calling C](../language/c-interop.md).

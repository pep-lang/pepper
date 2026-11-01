# Deprecation

When an API is on its way out, mark it `[Deprecated("message")]`. Code that
uses it still compiles, but every use gets a warning that shows your message,
the same way clang reports `[[deprecated]]`. That gives the code that depends
on the API time to move before you remove it.

```pepper
{{#include ../../examples/deprecation-basics.pep}}
```

Compiling this prints a warning at each use of a deprecated name, with a note
at its declaration. The second of the two is:

```text
main.pep:25:16: warning: 'to_f' is deprecated: use 'fahrenheit' instead [deprecated]
   25 |     assert(old.to_f() == 212, "the old API still works");
      |                ^~~~
      |                fahrenheit
main.pep:6:5: note: 'to_f' declared here
    6 |     to_f(): int { return fahrenheit(); }
      |     ^~~~
```

Warnings never stop the build. The program above compiles and runs.

## The replacement

The attribute takes an optional second argument: the name that replaces the
deprecated one.

```pepper
[Deprecated("use 'copy' instead", "copy")]
clone(): Counter { ... }
```

With a replacement, the warning comes with a fix that renames the use. The
compiler shows the new name under the old one, as in the warning above, and
the language server offers the rename as a quick fix. The fix only renames,
so give a replacement only when the new declaration can be used the same way.
Otherwise leave it out and explain the change in the message.

An empty message is allowed. The warning then says only `'name' is
deprecated`.

## What it applies to

Put `[Deprecated(...)]` before any declaration other code refers to by name:

- a function or an `extern`
- a struct, an enum, a trait, or a type alias
- a module-scope variable
- a field, a method, or a constructor of a struct, or a method or a case of
  an enum
- a method in a trait or in an extension (put it on each method, not on the
  `extend` block)

A doc comment goes above the attribute, as it does for any attribute.

To rename a parameter while calls still [name the old
one](functions.md#named-arguments), put `[Rename("old", "new")]` on the
function instead (see [Other names for a parameter](functions.md#other-names-for-a-parameter)).

## Which uses warn

Every use of the declaration warns, at the name you wrote:

- a call, a reference to a function or variable, or a construction `S()`
  (a deprecated constructor is reported at the struct's name)
- a type name, anywhere a type is written
- a member access `x.name`, a method call `x.name()`, a static call
  `S.name()`, and a bare field or method name inside the struct's own methods
- an enum case, as a value `Color.Crimson` or `Color.Tint(3)`, and as a
  pattern that names it in a `match` arm or an `is` test (`Crimson =>`,
  `c is Tint(level)`)
- an entry in an import list, `import [name] from m`, and a qualified use
  `m.name`, where the warning points at `name`
- a call the compiler writes for you, at the token that stands for it: a
  `for` loop's `next()` and `current()` at `for`, a `with` block's `enter()`
  at `with`, and an operator overload at its operator (`a + b` at `+`; a
  deprecated `==` also warns at a `!=` that uses it). These warnings offer
  no rename fix.

These do not warn:

- the declaration itself
- a use inside a declaration that is deprecated too, including the methods of
  a deprecated struct and closures written inside a deprecated function, so
  old code can keep calling old code without noise
- a re-export, `export name as other` or `export [name] from source`, which
  passes the name on without using it

## Mistakes in the attribute

A malformed attribute is an error at the attribute:

```text
main.pep:1:1: error: 'Deprecated' expects a message string: [Deprecated("message")]
    1 | [Deprecated]
      | ^~~~~~~~~~~~
```

The other errors are `'Deprecated' expects the replacement as a string`, `the
replacement 'a b' is not a name`, `too many arguments to 'Deprecated':
expected at most 2, have 3`, `duplicate 'Deprecated' attribute`, and
`'Deprecated' cannot be applied to` an extension or a destructor.

## What is deprecated

Each API and piece of syntax deprecated so far, and what replaces it. Those
marked "now an error" no longer compile; the rest still do, with a warning
that names the replacement.

| Deprecated | Replacement |
|------------|-------------|
| `new(...)` constructor | `construct(...)` |
| A struct, enum, type alias, trait or variable that two files of one module both declare, privately (now an error: files of a module share their names) | one declaration, or two names |
| A declaration of another file of the module, used without importing that file (now an error) | `import "file";` in the file that uses it |
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
| `ArraySlice<T>`, `ArraySliceIterator<T>` | `ArrayView<T>`, `ArrayViewIterator<T>` |
| `Atomic<T>` without an import (now an error: it moved to the `async` module) | `async.Atomic<T>` after `import async`, or `import [Atomic] from async` |
| `math.parse_int(text, base)` | `long.parse(text, base)`, with no import |
| `Optional<T>()` (now an error: `Optional` is an enum) | `Optional<T>.Empty` |
| `Optional` cases `None` and `Some(v)` (now an error: renamed) | `Empty` and `Value(v)` |
| `Optional<T>.some(v)`, `Optional<T>.none()` | the cases `Optional<T>.Value(v)`, `Optional<T>.Empty` |
| `Optional.is_some()`, `Optional.is_none()` | `is_value()`, `is_empty()` |
| `Array.find(x)` returning a `long`, `-1` when not found (now an optional: comparing it with a number is an error) | `a.find(x).is_value()`, and `value()` or `value_or(...)` for the index |
| `io.Path.parent()`, `file_name()`, `file_stem()`, `extension()` returning an empty `Path` or `String`, and `dot_index` returning `name.size`, when there is none (now optionals) | `is_value()` / `is_empty()` on the result, as in `p.parent().is_empty()` |
| `[LinkName("symbol")]` on an extern (now an error) | `[Link(name = "symbol")]` |
| A parameter's former name, kept by `[Rename("old", "new")]` | the new name (see [named arguments](functions.md#other-names-for-a-parameter)) |
| `Copyable<T>` implemented as `copy(copies: Copies): T`, with `copies.copy(x)` and `copies.register(original, made)` | `copy(): T`, with `copy(x)` and `register_copy(original, made)` (see [copying](memory.md)) |
| `hint.likely(condition)`, `hint.unlikely(condition)` | `[Likely]` or `[Unlikely]` above the `if` or `match` arm (see [branch hints](control-flow.md#branch-hints-likely-and-unlikely)) |

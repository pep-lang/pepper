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
- a struct, a trait, or a type alias
- a module-scope variable
- a field, a method, or a constructor of a struct
- a method in a trait or in an extension (put it on each method, not on the
  `extend` block)

A doc comment goes above the attribute, as it does for any attribute.

## Which uses warn

Every use of the declaration warns, at the name you wrote:

- a call, a reference to a function or variable, or a construction `S()`
  (a deprecated constructor is reported at the struct's name)
- a type name, anywhere a type is written
- a member access `x.name`, a method call `x.name()`, a static call
  `S.name()`, and a bare field or method name inside the struct's own methods
- an entry in an import list, `import [name] from m`, and a qualified use
  `m.name`, where the warning points at `name`

These do not warn:

- the declaration itself
- a use inside a declaration that is deprecated too, including the methods of
  a deprecated struct and closures written inside a deprecated function, so
  old code can keep calling old code without noise
- a re-export, `export name as other`, which passes the name on without using
  it

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

## Limitations

- The compiler does not report uses it writes for you: the `next()` and
  `current()` calls of a `for` loop, the `enter()` call of a `with` block,
  and a call to an operator overload such as `a + b`.
- The language server shows the warnings for the file you are editing. It
  does not show them for other files the program imports.

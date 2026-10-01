# Platform selection

Some code only makes sense on one platform: a Windows API call, a
Linux-specific constant, a type whose size differs between operating systems.
The `[Target(...)]` attribute keeps a declaration or a block only when you
compile for a matching platform, so one source file can hold every platform's
version side by side.

The target is always the platform you compile on: Pepper does not
cross-compile yet.

## Writing a condition

`Target` takes one boolean condition built from two predicates:

- `OS(...)` is true on the named operating system: `Windows`, `Mac` (or
  `MacOS`), or `Linux`.
- `Arch(...)` is true on the named processor architecture: `x64` or `aarch64`.

Values are matched case-insensitively, so `OS(windows)` works too. Combine
predicates with `&&` (or `and`), `||` (or `or`), `!`, and parentheses:

```pepper
[Target(OS(Windows))]                     # Windows
[Target(!OS(Windows))]                    # Linux and macOS
[Target(OS(Linux) && Arch(x64))]          # Linux on x64 only
[Target(OS(Windows) || OS(Mac))]          # Windows and macOS
[Target(!(OS(Windows) || OS(Mac)))]       # Linux
```

An item may carry several attributes. They are combined with "and": the item
is kept only when every `Target` on it matches. Other attributes on the same
item, such as `[Link(...)]`, do not affect the selection.

## What it applies to

Put `[Target(...)]` before any top-level declaration: a function, an `extern`,
a struct, a trait, an extension, a type alias, a module-scope variable, an
`import`, or a re-export. It also works on the methods inside a struct, trait
or extension. When two declarations share a name, give them conditions that
never match on the same platform, so exactly one survives:

```pepper
{{#include ../../examples/platform-declarations.pep}}
```

The attribute goes before `export`, not after it:
`[Target(OS(Windows))] export f()`. Writing `export [Target(OS(Windows))] f()`
is a parse error.

## Blocks inside a function

Inside a function body, attach `[Target(...)]` to a block `{ ... }`. The block
is kept or removed like a declaration. Blocks may nest, and may appear inside
`if` and loop bodies.

This is the usual way to wrap C functions that differ per platform: declare
each platform's `extern` with its own condition, and call each one from a
block with the same condition.

```pepper
{{#include ../../examples/platform-externs.pep}}
```

## What happens to code that does not match

Code whose condition does not match is removed before type checking. That is
what makes the examples above work: a call to `GetCurrentProcessId`, which
exists only on Windows, is fine in a block that is removed everywhere else.
Removed code is not checked for errors beyond parsing, so a typo in it goes
unnoticed until you build on the platform that keeps it. The VS Code
extension shows it dimmed, from its attribute to its end, with a hint saying
it is not compiled for the platform you are building on.

It still has to parse, and every `Target` condition is validated on every
platform, even one inside removed code. A misspelled value is always an error,
never a silent "no match":

```pepper
[Target(OS(Darwin))] f(): int { return 1; }
```

```text
main.pep:1:1: error: unknown OS value `Darwin` (expected Windows, Mac, MacOS, Linux) in [Target(OS(Darwin))]
    1 | [Target(OS(Darwin))] f(): int { return 1; }
      | ^~~~~~~~~~~~~~~~~~~~
```

Other mistakes the compiler reports:

- `Target` takes exactly one condition: `[Target(OS(Windows), Arch(x64))]` is
  an error; write `[Target(OS(Windows) && Arch(x64))]`.
- Only `OS(...)` and `Arch(...)` may appear inside it. A bare name
  (`[Target(Windows)]`), another call (`[Target(Foo(x))]`), `not` in place of
  `!`, or a nested `Target` is an error.
- `OS(...)` and `Arch(...)` are only valid inside `Target(...)`, and the
  brackets hold one attribute: `[OS(Windows)]` and
  `[Target(OS(Windows)) && Export]` are parse errors.
- Struct fields cannot carry `[Target(...)]`. Select the whole struct instead,
  as `Cpu` does in the first example.

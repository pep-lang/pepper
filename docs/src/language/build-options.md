# Build options

Some code should be optional at build time: linking a library such as
libcrypto or zlib when it is there, tracing that only a debug build wants,
a backend chosen when the program is built. **Build options** set that on
the command line with `-D`, as in C compilers, and the code tests them with
`BuildOption`.

```sh
pep-build main.pep -D USE_LIBCRYPTO -D LOG_LEVEL=2 -D BACKEND=zlib -o app
```

- `-D NAME` defines an option. It counts as `NAME=1`, as in C.
- `-D NAME=VALUE` defines it with a value, which may be any text.
- Repeat `-D` for more options. When two name the same option, the later
  one wins.

`pep-build --test` defines `TEST`, which keeps the `[Test]` functions and
can mark code only tests use (see [Unit tests](testing.md#test-builds)).
A package's `[features]` that a build turns on define options too, named
`<package>_<feature>` (`http_tls`; see
[Features](../tools/projects.md#features)), and so do the
`pep:build-option=NAME` lines a package's build script prints, named
`<package>_<NAME>` (see [Build scripts](../tools/projects.md#build-scripts)).

A name is a letter or `_`, then letters, digits and `_`. Any other name is
an error:

```text
error: invalid build option name '2FAST' in '-D 2FAST'; a name is a letter or '_' followed by letters, digits and '_'
```

```pepper
{{#include ../../examples/build-options.pep}}
```

## Selecting code

`[BuildOption("NAME")]` keeps a declaration or a block only when the build
defines `NAME`. It is shorthand for `[Target(BuildOption(NAME))]`, and it
goes everywhere `[Target(...)]` goes: functions, `extern`s, structs,
methods, module-scope variables, `import`s, re-exports and `{ }` blocks in
a function (see [Platform selection](platform-selection.md)).

Inside `Target`, `BuildOption(NAME)` combines with `OS(...)`, `Arch(...)`,
`!`, `&&`, `||` and parentheses. Used alone, it is true when `NAME` is
defined, whatever its value, and false when it is not, with no warning:

```pepper
[BuildOption("USE_LIBCRYPTO")]
[Link("crypto")]
extern int SHA256_Init(__ptr<void> context);

[Target(!BuildOption(USE_LIBCRYPTO))]
_sha256_compress(...) { ... }   # the portable fallback

[Target(BuildOption(TRACE) && OS(Linux))]
import "linux_trace";
```

Several attributes on one item combine with "and", as `[Target]` does.

## Options the runtime reads

| Option | Effect |
|--------|--------|
| `USE_LIBCRYPTO` | `digest`'s SHA-256 and SHA-1 use libcrypto (CNG on Windows); see [Cryptographic hashes](digest.md#using-the-systems-crypto-library) |
| `USE_ZLIB` | `compress` uses zlib; see [Compression](compression.md#using-zlib) |
| `TEST` | defined by `pep-build --test`; see [Unit tests](testing.md#test-builds) |

## Comparing values

`BuildOption(NAME)` may be compared with a literal using `==`, `!=`, `<`,
`<=`, `>` and `>=`, on either side. The literal's type says how the value
is read:

| Literal | The value is read as | Example |
|---------|----------------------|---------|
| integer | a signed 64-bit integer, decimal or `0x` hex | `BuildOption(LOG_LEVEL) >= 2` |
| float | a `double` | `BuildOption(SCALE) > 1.5` |
| `true` / `false` | `true`/`false`, `1`/`0`, `on`/`off` or `yes`/`no`, in any case (`==` and `!=` only) | `BuildOption(TRACE) == true` |
| string | text, compared byte for byte | `BuildOption(BACKEND) == "zlib"` |

```pepper
[Target(BuildOption(LOG_LEVEL) >= 2 && OS(Linux))]
_trace(message: String) { ... }

[Target(BuildOption(BACKEND) == "zlib")]
import "zlib_backend";
```

A value the literal's type cannot read is an error at the comparison:

```text
main.pep:1:28: error: build option 'LEVEL' is 'high', which is not an integer
    1 | [Target(BuildOption(LEVEL) >= 2)]
      |                            ^~~~
```

Comparing a build option with anything but a literal or another build
option is an error too.

Two build options compare with each other, `BuildOption(A) <= BuildOption(B)`,
by their values: as integers when both read as integers, else as `double`s
when both read as numbers, else as text, byte for byte. Text compares only
with `==` and `!=`; ordering a value that is not a number is an error at
the operator:

```text
main.pep:1:27: error: build option 'MODE' is 'fast', which is not a number; '<' compares two build options only as numbers
    1 | [Target(BuildOption(MODE) < BuildOption(LEVEL))]
      |                           ^~~~~~~~~~~~~~~~~~~~
```

A comparison with an option the build does not define is false, whatever
the operator, and the compiler warns at it, since a missing option there is
usually a mistake. With two options, it is false when either is not
defined, `BuildOption(A) == BuildOption(B)` included when neither is, and
the compiler warns at each one missing:

```text
main.pep:3:13: warning: build option 'LOG_LEVEL' is not defined; the comparison is false
    3 |     [Target(BuildOption(LOG_LEVEL) >= 2)] {
      |             ^~~~~~~~~~~~~~~~~~~~~~
note: define it with '-D LOG_LEVEL=<value>'
```

## Reading values in `static` blocks

A [`static` block](reflection.md) reads build options while compiling:

- `reflect.has_build_option("NAME")` is whether the build defines `NAME`.
- `reflect.build_option("NAME")` is its value, as a `String`. It is an
  error when the build does not define `NAME`.
- `reflect.build_option("NAME", "default")` is its value, or `default`
  when the build does not define it.

## The build cache and the editor

The options and their values are part of the build cache's key, so building with other options never reuses objects built with
different ones.

The language server analyzes with the options in the VS Code setting
`pepper.buildOptions`, a list written as `-D` takes them
(`["USE_ZLIB", "LOG_LEVEL=2"]`). It has none by default, so code that needs
an option shows dimmed, and comparisons with options warn until the
setting names them.

## Not yet

- A `pep.toml` table declaring the options a package takes, with their
  types and defaults.
- Arithmetic on options.

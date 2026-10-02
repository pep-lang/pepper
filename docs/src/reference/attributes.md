<!-- Generated from runtime/attributes.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# attributes.pep

The built-in attributes, declared as `[Attribute]` structs so a `static`
block can read them like its own: `field.has_attribute<Deprecated>()`
tests for one and `function.attribute<Deprecated>().message` reads its
value (see the reflection chapter). The compiler acts on each attribute
itself; these declarations only describe the values it records.

Source: `runtime/attributes.pep`

## Attribute

```pepper
[Attribute] struct Attribute
```

Marks a struct as an attribute, which can then be written above a
declaration and read back in a `static` block.

## Deprecated

```pepper
[Attribute] struct Deprecated
```

Marks a public declaration as deprecated: each use outside a deprecated
declaration warns with `message`.

### Fields

#### message

```pepper
const message: String
```

What the warning says, such as "use 'open' instead".

#### replacement

```pepper
const replacement: String = ""
```

The name that replaces the declaration, offered as a fix; empty when
there is none.

## Alias

```pepper
[Attribute] struct Alias
```

Gives a parameter a second permanent name that a call may use:
`[Alias("size", "count")]` lets a call name `count` as `size`.

### Fields

#### alias

```pepper
const alias: String
```

The second name.

#### parameter

```pepper
const parameter: String
```

The parameter it names.

## Rename

```pepper
[Attribute] struct Rename
```

Keeps a parameter's former name working behind a deprecation warning:
`[Rename("n", "count")]`.

### Fields

#### old_name

```pepper
const old_name: String
```

The former name.

#### new_name

```pepper
const new_name: String
```

The parameter's name now.

## Link

```pepper
[Attribute] struct Link
```

Names the C library an extern links against, its C symbol, or both:
`[Link("m")]`, `[Link(name = "sym")]`, `[Link("ssl", path = "vendor")]`.

### Fields

#### lib

```pepper
const lib: String = ""
```

The library; empty when only the symbol is given.

#### path

```pepper
const path: String = ""
```

A folder the linker searches for libraries, relative to the file
that declares the extern unless absolute; empty for none.

#### name

```pepper
const name: String = ""
```

The C symbol, when it differs from the declared name; empty otherwise.

## Target

```pepper
[Attribute] struct Target
```

Keeps a declaration only on the platforms its condition matches:
`[Target(OS(Linux))]`, `[Target(!OS(Windows))]`.

### Fields

#### condition

```pepper
const condition: String
```

The condition as written, such as `!OS(Windows)`.

## BuildOption

```pepper
[Attribute] struct BuildOption
```

Keeps a declaration only when the build defines a build option with
`-D`: `[BuildOption("USE_ZLIB")]` is `[Target(BuildOption(USE_ZLIB))]`.

### Fields

#### name

```pepper
const name: String
```

The build option's name, such as `USE_ZLIB`.

## Likely

```pepper
[Attribute] struct Likely
```

Marks the `if` or `match` arm below it as the branch usually taken,
so the optimizer lays it out as the straight-line path.

## Unlikely

```pepper
[Attribute] struct Unlikely
```

Marks the `if` or `match` arm below it as a branch rarely taken, such
as error handling, so the optimizer moves it out of the fast path.

## NotCopyable

```pepper
[Attribute] struct NotCopyable
```

Forbids copying a struct with `copy(value)`, giving the reason in the
error.

### Fields

#### reason

```pepper
const reason: String
```

Why the struct cannot be copied.

## Value

```pepper
[Attribute] struct Value
```

Makes a struct a value: stored inline and copied on assignment, with no
reference count.

## Equatable

```pepper
[Attribute] struct Equatable
```

Makes a struct, or an enum whose cases carry values, compare and hash
by its fields, like a tuple of them, instead of by identity: the
compiler derives its `==` and its hash, so equal values find each other
as `HashMap` and `HashSet` keys.

On a field of such a struct, it says whether the field takes part:
`[Equatable(exclude = true)]` or `[Equatable(include = false)]` leaves it
out of both `==` and the hash. A field with neither takes part. On the
struct itself it takes no arguments.

### Fields

#### include

```pepper
bool include = true
```

Whether the field takes part in `==` and the hash; `false` leaves it
out.

#### exclude

```pepper
bool exclude = false
```

Whether the field is left out of `==` and the hash.

## Shared

```pepper
[Attribute] struct Shared
```

Makes a struct safe to share between threads: its counts step atomically
and its fields must be `const` and thread-safe.

## Isolated

```pepper
[Attribute] struct Isolated
```

Makes a struct a guard that can only be the scope of a `with` block and
never escapes it.

## Implicit

```pepper
[Attribute] struct Implicit
```

Lets a one-parameter constructor convert implicitly wherever a value of
its parameter's type flows into the struct's type.

## Move

```pepper
[Attribute] struct Move
```

Marks a parameter that takes its argument's reference: the caller's
variable may not be used again.

## MoveSource

```pepper
[Attribute] struct MoveSource
```

Marks the parameter of a function that moves a value out of its source,
as `move` does.

## Locked

```pepper
[Attribute] struct Locked
```

Marks a function-typed parameter that is called while a lock is held, so
it may use the locked value.

## Export

```pepper
[Attribute] struct Export
```

Makes a free function callable from C, in a library built with
`--lib static` or `--lib shared`: `[Export]`, or
`[Export(name = "c_name")]` for a C symbol other than its name.

### Fields

#### name

```pepper
const name: String = ""
```

The C symbol, when it differs from the function's name; empty
otherwise.

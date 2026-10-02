# Reflection and attributes

A program can look at its own types while it compiles: list a struct's
fields, read the attributes written on them, and generate code for each
one. This is how one function can turn any struct into JSON, declare a
command-line option per field, or compare two values field by field.

The work happens in the compiler, in a `static` block, so it costs nothing
at run time and needs no type information in the program. This is the model
of Zig's `comptime` and C++'s static reflection, not of Java or C# runtime
reflection.

```pepper
{{#include ../../examples/reflection-basics.pep}}
```

## `static` blocks

A `static` block is written inside a function. It names, in parentheses, the
runtime values it may emit code against: its **capture list**.

```pepper
static (out, value) {
    ...
}
```

`static { ... }` with no list is pure compile-time work, such as a check
with `reflect.assert`.

Each statement in the block either runs in the compiler or is **emitted**
into the function:

- A statement that uses a captured name, or a runtime local the block
  declares, is emitted. Its compile-time parts are filled in first:
  `out.append(field.name)` emits `out.append("x")`.
- Everything else runs in the compiler: `var` declarations whose value uses
  no captured name, `if` on a compile-time condition (only the branch taken
  is kept), `for` over a compile-time list, which is unrolled, one copy
  of its body per element, and `while` on a compile-time condition, which
  emits its body once per iteration.
- An `if` whose condition uses a captured name is emitted as a runtime
  `if`; its branches can still hold compile-time steps.

A `var` with a captured name in its value is a runtime local, and using it
counts as using a capture. Using a runtime value that is not captured is an
error at that name:

```text
main.pep:9:24: error: 'total' is a runtime value; add it to the static block's capture list
```

Each pass of an unrolled `for` or `while`, and the branch an `if` keeps, is
its own block, like the body of a real loop.

### Compile-time loops

`break` and `continue` in a compile-time `for` or `while` run in the
compiler: `continue` drops the rest of the pass, and `break` ends the
unrolling. They cannot sit in a runtime `if`, whose condition the compiler
does not know:

```text
main.pep:10:17: error: 'break' in a runtime 'if' cannot leave a compile-time loop; the condition is not known while compiling
```

A `while` that runs 100,000 times is taken to be endless and stops the
compile at its `while`.

```pepper
{{#include ../../examples/reflection-loops.pep}}
```

### In generic code

In a generic function, a `static` block runs once for each specialization,
when its type arguments are known: `describe<Point>` and `describe<Line>`
each get their own expansion. Code the block emits can call other generic
functions, such as `describe(field.get(value))` for a field that is itself a
struct, and those are specialized in turn. A mistake in a block is reported
when some specialization uses it, with the pass it happened in:

```text
main.pep:14:13: error: 'print' cannot be called at compile time
main.pep:12:27: note: in pass 1 of 2 (member 'x')
note: a 'static' block can call the 'reflect' functions and the methods of what they return; calling other functions at compile time is not supported yet
main.pep:10:1: note: in the static block of 'dump<Point>'
```

### At module scope

A `static` block outside any function runs once, while compiling. It has
nothing to capture and emits no code; instead, each `const` declared at the
top of the block becomes a module-scope constant holding what the block
computed. Its other `var`s, and anything declared in its loops and
branches, stay in the compiler. `export static` exports its constants, and
attributes written above the block (`[Target(...)]`) apply to them too.

```pepper
{{#include ../../examples/reflection-module/sizes.pep}}
```

```pepper
{{#include ../../examples/reflection-module/main.pep}}
```

A constant takes a number, `bool`, character or enum case; a
[module-scope variable](types-and-variables.md#module-level-variables) cannot be a `String`, since it must
be thread-safe. At module scope, a case's `get()` is the case itself, and a
statement that would emit code is an error:

```text
main.pep:7:9: error: a module-scope 'static' block cannot emit code; declare a 'const' with what it computes
```

### What the compiler can evaluate

Compile-time values are integers, floating-point numbers, `bool`, strings,
enum cases, and what the `reflect` functions return: members, cases,
functions, lists and attributes. Expressions can use literals, the
arithmetic, comparison and logical operators, `+` on strings, interpolated
strings (`$"{field.name}: "`), `?:`, assignment to a compile-time `var`
(`n += 1`), and indexing a list. A string has `length`, `is_empty`,
`starts_with`, `ends_with` and `contains`; a list has `count` and
`is_empty`.

Emitted code can use a compile-time number, `bool`, string or enum case;
the compiler writes it as a literal.

## The `reflect` functions

`reflect` is built in: a `static` block uses it without an import.

| Function | Returns |
|----------|---------|
| `reflect.name<T>()` | the type's name, as written (`"Box<int>"`) |
| `reflect.properties<T>()` | the public fields and [properties](properties.md) of a struct, in declaration order |
| `reflect.fields<T>()` | every field of a struct, private ones and a property's storage included; only in the file that declares `T` |
| `reflect.cases<E>()` | an enum's cases, in order |
| `reflect.functions_with<A>()` | every function in the program that carries attribute `A` |
| `reflect.is_struct<T>()`, `is_enum<T>()`, `is_trait<T>()` | what kind of type `T` is |
| `reflect.is_same<A, B>()` | whether `A` and `B` are the same type (`int` and `i32` are) |
| `reflect.has_attribute<T, A>()`, `reflect.attribute<T, A>()` | attribute `A` on struct or enum `T` |
| `reflect.print(value)` | writes `value` as a note while compiling |
| `reflect.error(message)` | fails the compile with `message` |
| `reflect.assert(condition, message)` | fails the compile with `message` when `condition` is false |

`fields` exists for code a struct's author writes, such as a field-by-field
`==`; anywhere else it is an error, which points at `properties`:

```text
main.pep:4:24: error: 'fields' of 'Account' is only available in the file that declares 'Account'; use 'properties'
```

A **member** (from `properties` or `fields`) has:

- `name`, `index`, `is_last`, `is_const`, `is_property`
- `type_name`: its type as a string; `field.Type` is the type itself, usable
  wherever a type is written: `var copy: field.Type = ...`,
  `reflect.is_same<field.Type, String>()`, `parse<field.Type>(text)`
- `has_attribute<A>()` and `attribute<A>()`
- `get(value)` and `set(value, x)`, which emit `value.name` and
  `value.name = x`

A **case** (from `cases`) has `name`, `value` (its integer value), `index`,
`is_last`, `has_attribute<A>()`, `attribute<A>()`, and `get()`, which
emits the case itself, for an enum whose cases carry no values.

A **function** (from `functions_with`) has `name`, `has_attribute<A>()`,
`attribute<A>()`, and `call(arguments...)`, which emits a direct call.

```pepper
{{#include ../../examples/reflection-types.pep}}
```

```pepper
{{#include ../../examples/reflection-fields.pep}}
```

## Attributes

An attribute is a struct marked `[Attribute]`. Writing it above a
declaration records a compile-time value of that struct, which
`has_attribute<A>()` tests for and `attribute<A>()` returns.

```pepper
{{#include ../../examples/reflection-attributes.pep}}
```

- **Fields** of an attribute struct are numbers, `bool`, `char`, `String`,
  or enums whose cases carry no values.
- **Arguments** are constants: literals, a negated number, an enum case
  (`Level.High`), or strings joined with `+`. They can be
  [named](functions.md#named-arguments): `[Check(weight = 3)]`.
- Without a constructor, the arguments set the fields in order, and a field
  with an initializer may be left out. A constructor may take `this.field`
  parameters, or parameters its body assigns to fields
  (`this.long_name = long_name;`), which is all its body may do.
- An attribute that names neither a built-in attribute nor an `[Attribute]`
  struct is an error, at its name: `unknown attribute 'Optoin'`.
- Built-in attributes (`Target`, `Shared`, `Deprecated`, ...) are visible
  too: `field.has_attribute<Deprecated>()` tests for one.

Attributes can go on structs, enums and their cases, fields, functions,
methods, constructors, parameters and module-scope variables.

```pepper
{{#include ../../examples/reflection-functions.pep}}
```

## Not supported yet

- Calling functions other than the `reflect` functions at compile time.
- Reflecting methods and constructors (`reflect.methods<T>()`).
- The values of built-in attributes: `attribute<Deprecated>()` is an error;
  `has_attribute<Deprecated>()` works.
- `get()` on a case of an enum whose cases carry values.
- Limiting where an attribute may be used (`[AttributeTargets(...)]`).
- Showing the code a block expands to, and tracing the blocks the compiler
  runs.
- Type information at run time.

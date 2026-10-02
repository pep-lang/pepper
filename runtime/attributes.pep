## The built-in attributes, declared as `[Attribute]` structs so a `static`
## block can read them like its own: `field.has_attribute<Deprecated>()`
## tests for one and `function.attribute<Deprecated>().message` reads its
## value (see the reflection chapter). The compiler acts on each attribute
## itself; these declarations only describe the values it records.

## Marks a struct as an attribute, which can then be written above a
## declaration and read back in a `static` block.
[Attribute]
export struct Attribute {}

## Marks a public declaration as deprecated: each use outside a deprecated
## declaration warns with `message`.
[Attribute]
export struct Deprecated {
    ## What the warning says, such as "use 'open' instead".
    const message: String;
    ## The name that replaces the declaration, offered as a fix; empty when
    ## there is none.
    const replacement: String = "";
}

## Gives a parameter a second permanent name that a call may use:
## `[Alias("size", "count")]` lets a call name `count` as `size`.
[Attribute]
export struct Alias {
    ## The second name.
    const alias: String;
    ## The parameter it names.
    const parameter: String;
}

## Keeps a parameter's former name working behind a deprecation warning:
## `[Rename("n", "count")]`.
[Attribute]
export struct Rename {
    ## The former name.
    const old_name: String;
    ## The parameter's name now.
    const new_name: String;
}

## Names the C library an extern links against, its C symbol, or both:
## `[Link("m")]`, `[Link(name = "sym")]`.
[Attribute]
export struct Link {
    ## The library; empty when only the symbol is given.
    const lib: String = "";
    ## The C symbol, when it differs from the declared name; empty otherwise.
    const name: String = "";
}

## Keeps a declaration only on the platforms its condition matches:
## `[Target(OS(Linux))]`, `[Target(!OS(Windows))]`.
[Attribute]
export struct Target {
    ## The condition as written, such as `!OS(Windows)`.
    const condition: String;
}

## Forbids copying a struct with `copy(value)`, giving the reason in the
## error.
[Attribute]
export struct NotCopyable {
    ## Why the struct cannot be copied.
    const reason: String;
}

## Makes a struct a value: stored inline and copied on assignment, with no
## reference count.
[Attribute]
export struct Value {}

## Makes a struct, or an enum whose cases carry values, compare and hash
## by its fields, like a tuple of them, instead of by identity: the
## compiler derives its `==` and its `hash`, so equal values find each
## other as `HashMap` and `HashSet` keys.
[Attribute]
export struct Equatable {}

## Leaves a field of an `[Equatable]` struct out of its derived `==` and
## `hash`.
[Attribute]
export struct NotCompared {}

## Makes a struct safe to share between threads: its counts step atomically
## and its fields must be `const` and thread-safe.
[Attribute]
export struct Shared {}

## Makes a struct a guard that can only be the scope of a `with` block and
## never escapes it.
[Attribute]
export struct Isolated {}

## Lets a one-parameter constructor convert implicitly wherever a value of
## its parameter's type flows into the struct's type.
[Attribute]
export struct Implicit {}

## Marks a parameter that takes its argument's reference: the caller's
## variable may not be used again.
[Attribute]
export struct Move {}

## Marks the parameter of a function that moves a value out of its source,
## as `move` does.
[Attribute]
export struct MoveSource {}

## Marks a function-typed parameter that is called while a lock is held, so
## it may use the locked value.
[Attribute]
export struct Locked {}

## Marks a function to be callable from C; the compiler does not act on it
## yet.
[Attribute]
export struct Export {}

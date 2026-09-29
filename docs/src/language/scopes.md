# Scoped blocks with `with`

A `with` block enters a scope object, binds what it hands out, and cleans up
when the object is destroyed. It plays the role of Python's `with` and C#'s
`using`, but the cleanup is ordinary destruction: it runs through the same
reference counting as every other object (see
[Memory and reference counting](memory.md)).

```pepper
{{#include ../../examples/scopes-with.pep}}
```

## The header

```pepper
with (var name = scope) { ... } else { ... }
with (Type name = scope) { ... }
with (scope) { ... }
```

- **`name` is bound to `scope.enter()`**, not to `scope` itself. A `Session`
  can hand out itself; a [`Weak<T>`](memory.md#weak-references) hands out
  a strong reference to the object it points at, or null once that object is
  gone.
- **Without a binding**, the block still holds the result of `enter()` until
  it ends. An `enter()` that returns nothing (declared without a return type)
  has nothing to bind, and binding it is an error.
- **The parentheses are optional**, as with `if`, `while` and `for`. The braces
  are required.
- **`name` cannot be reassigned** inside the block.

## Skipping the body

When `enter()` returns a struct reference that is null, the body is skipped
and the optional `else` block runs instead. `else` is only allowed when
`enter()` returns a struct type, since nothing else can be null.

## The `Scoped<T>` protocol

A type works in a `with` block when it has the methods of the `Scoped<T>`
trait (`runtime/scoped.pep`, documented in the [Scoped](../reference/scoped.md)
reference):

```pepper
export trait Scoped<T> {
    T enter();   # what the header binds; null skips the body
    exit();      # the cleanup; call it from the destructor
}
```

A `with` block goes by the methods a type has, not by the trait: a type
without `enter()` is a compile error in a `with` header. Declaring the trait
(`extend Session with Scoped<Session> {}`) documents the intent, and the
compiler then checks that the type has both `enter()` and `exit()`.

## When `exit()` runs

The block keeps two locals: the scope object and the bound value. Both are
released on every path out of the block (the end of the body, `return`,
`break` and `continue`), the bound value first. Implementations call `exit()`
from their destructor:

```pepper
destruct {
    this.exit();
}
```

so `exit()` runs when the scope object's **last** reference is released:

- A scope object created in the header (`with (var s = Session("grace"))`)
  is released by the block, so `exit()` runs at the end of the block.
- A scope object that something else also holds (a field, another local) lives
  on after the block, and `exit()` waits for its last owner. This is the same
  rule as any other object.
- A copy of the bound value that outlives the block (stored in a field,
  returned) keeps that value alive, but not the scope object.

A `panic` stops the program without running destructors, so `exit()` does not
run then.

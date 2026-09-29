# Memory and reference counting

Pepper frees memory for you, without a garbage collector and without
ownership annotations. Every struct object keeps a count of the references to
it, and the object is destroyed the moment that count drops to zero. Because
the rules are simple and the same everywhere, you can always tell when an
object will be destroyed and its [destructor](structs.md#destructors) will run.

If you know C++, the whole model fits in one sentence: every struct value
behaves exactly like a `std::shared_ptr<T>` passed by value.

## Values and references

Numbers, `bool`, and the other primitive types are plain values: assigning
one copies it, as in C.

Everything else, including your own structs, `String`, `Array`, `HashMap`, and
[function values](function-types.md), is a *reference* to an object on the
heap. Assigning a reference, passing it to a function, or storing it in a
field or an array shares the object. Nothing is copied.

```pepper
{{#include ../../examples/memory-sharing.pep}}
```

- `var yours = mine;` makes a second reference to the same `Account`.
  Changes through either name are visible through both.
- A parameter is one more reference to the caller's object. The function can
  change the object's fields, but assigning a new object to the parameter
  only changes the function's own reference.
- To get an independent object, create a new one. Pepper does not copy
  structs for you; some library types offer a method for it, such as
  [`Array`](../reference/array.md)'s `clone()`.

A struct-typed variable or field that has not been given a value, such as
`var next: Account;`, is *null*: it refers to no object. Reading a field or
calling a method through a null reference crashes the program. Use `===` to
check whether two references name the same object.

## When objects are destroyed

A reference is held by whatever stores it: a local variable, a parameter, a
field, an element of a container, or a temporary value in the middle of an
expression. Each of those releases its reference exactly once, when it goes
away. When the last reference is released, the object is destroyed: its
destructor runs, and then its fields release their own references, which may
destroy further objects in turn.

```pepper
{{#include ../../examples/memory-lifetime.pep}}
```

Concretely, a reference is released when:

- **A local variable goes out of scope**, at the closing brace of the block
  that declared it, or when the function returns.
- **A variable or field is overwritten.** `b = Tracked("b2");` releases the
  object `b` held before, after taking the new one. Assigning a variable to
  itself (`a = a`) changes nothing.
- **A parameter's function returns.** The function held its parameters for
  as long as it ran.
- **The object that holds a field is destroyed**, or a container removes an
  element (`clear()`, `remove_at()`, overwriting `list[i]`, and so on).
- **A temporary is no longer needed.** A result that is not stored anywhere,
  like the one from `make("temporary");`, is released at the end of the
  statement. The same goes for a call result passed straight to another
  function, and for the object in `make().name`.

Returning a local hands its reference to the caller, so the object survives
the function. Calling a method on an object does not add a reference to it:
inside the method, `this` refers to the caller's object.

## Cycles leak

Reference counting cannot free a *cycle*: objects that refer to each other,
directly or through a chain, keep each other's counts above zero even after
nothing else refers to them. Their destructors never run and their memory is
never freed.

```pepper
{{#include ../../examples/memory-cycles.pep}}
```

Pepper does not have weak references yet, so avoid cycles in long-lived data,
or break them yourself before the last outside reference goes away: clear the
container, or overwrite the field, that closes the loop. A common pattern is
a tree where parents hold their children but children do not hold their
parent; look a parent up by some other means, such as an index or a key into
a [`HashMap`](../reference/hash.md).

## Summary

| Code | What happens to references |
|---|---|
| `var b = a;` | `b` takes a new reference to `a`'s object. |
| `b = c;` | `b` takes a reference to `c`'s object, then releases its old one. |
| `f(a)` | The parameter takes a reference for the duration of the call. |
| `return a;` | The caller receives a reference to `a`'s object. |
| `a.method()` | No change: `this` refers to `a`'s object. |
| `make();` (result unused) | The result is released at the end of the statement. |
| end of a block | Every local declared in the block releases its reference. |

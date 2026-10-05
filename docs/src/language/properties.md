# Properties

A property is a struct member that is read and written like a field
(`account.name`, `account.name = "Savings"`) but whose `get` and `set`
accessors can run code. A property that needs somewhere to keep its value
gets it from the compiler: its **implied storage**, reachable as `field`
inside its accessors. You declare a separate private field only when you
want one.

## Declaring properties

A property is a field declaration followed by an accessor block instead of
`;`:

```pepper
{{#include ../../examples/properties-basics.pep}}
```

- `get;` and `set;` with no body are the defaults: `get` returns the
  storage, and `set` stores the new value in it. Either may have a body
  instead.
- A property has implied storage when an accessor is omitted (`get;` or
  `set;`) or an accessor body uses `field`. Otherwise it is **computed**: it
  takes no space, and its `get` runs every time it is read.
- An initializer after the accessors (`var limit: long { get; set; } = 100;`)
  initializes the storage, so it needs a property that has storage. It does
  not run `set`.
- Inside an accessor, `field` is the storage, and inside `set`, `value` is
  the new value (a by-value parameter). Both are contextual: outside
  accessors they are ordinary names, so a local or a member called `field`
  or `value` elsewhere keeps working. Inside an accessor, a bare `field`
  always means the storage; reach a member of that name as `this.field`.
- A property must have a `get`: `{ set; }` alone is an error.
- A property is declared with `var` and an explicit type; it cannot be
  `const`. There are no `static` properties.

## Reading and writing

- `p.count` calls `get`, and `p.count = x` calls `set`. A default accessor is
  not a call at all: an auto property (`{ get; set; }`) compiles to the same
  loads and stores as a field.
- `p.count += 1`, `p.count++` and the other compound assignments are a `get`
  and then a `set`. `p` is evaluated once.
- A constructor parameter `this.name` assigns the property, through its `set`
  when it has one. A field initializer and the struct's own field
  initialization do not.
- Inside the struct's methods, a property is reached by its bare name, like a
  field: `balance += amount;` is `this.balance += amount;`.
- A property's accessors are ordinary method calls for
  [reference counting](memory.md): `get` returns a temporary that owns one
  reference, and `value` is a by-value parameter, acquired on entry and
  released on exit.

## Read-only properties

`{ get; }` alone makes a property read-only **outside the struct**: assigning
it from other code is an error at the property's name.

```text
main.pep:6:7: error: cannot assign to 'balance': it has no 'set' accessor
    6 |     a.balance = 3;
      |       ^~~~~~~
main.pep:2:9: note: 'balance' declared here
    2 |     var balance: long { get; }
      |         ^~~~~~~
```

The struct's own constructors and methods may assign a get-only property
with implied storage; that writes the storage directly. An extension's
methods are not the struct's own code: they cannot assign it either.

## Properties in traits and extensions

A [trait](traits-and-extensions.md) can require a property, `var area:
double { get; }` or `{ get; set; }`, with no accessor bodies. A struct meets
the requirement with a property of the same name and type (auto or
computed), or with a plain field. Reading or writing the property through a
trait value calls the struct's accessors.

An [extension](traits-and-extensions.md) can add **computed** properties
only, since it cannot add storage to the struct:

```pepper
{{#include ../../examples/properties-traits.pep}}
```

An extension property that would need storage is an error:

```text
main.pep:5:9: error: an extension cannot add storage: property 'y' must be computed, with accessor bodies that do not use 'field'
```

An [enum](enums.md#properties) can declare computed properties too, under
the same rule, and no `set`, since its values never change.

## Properties of `[Shared]` structs

The fields of a [`[Shared]` struct](threads.md) are `const`, so the storage
of its properties is too:

- A property with implied storage must be `{ get; }`, and only the
  struct's constructors assign it. A `set`, with or without a body, is an
  error at `set`, with a note at `[Shared]`.
- A computed `get` over the struct's `const` fields is allowed, as any method
  is.

A `[Shared]` struct's properties are `get` only, by design: an assignment
`x.p = v` would read as a write to a struct whose fields cannot change. To
change what a thread-safe member holds (an `Atomic<int>`, or a value behind a
`Mutex`), declare a method that says what it does, such as
`store_hits(value)` or `add_name(name)`.

## How properties compile

The compiler lowers a property to plain members: a field for its storage
(named after the property when its `get` is the default, `__field_name`
otherwise), a getter method `__get_name()` and, with a `set`, a setter
`__set_name(value)`. Every read and write of the property becomes a storage
access or an accessor call once the receiver's type is known. The accessor
methods appear in debuggers and in profiles under those names.

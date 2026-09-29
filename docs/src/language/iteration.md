# Iteration

A `for` loop visits each element of a collection in turn. You can loop over an
[`Array`](../reference/array.md), over the code points of a
[`String`](../reference/string.md), and over any type of your own that follows
the iterator protocol.

## Looping over an array

`for (var x in source) { ... }` runs the body once per element, with `x` bound
to the element:

```pepper
{{#include ../../examples/iteration-arrays.pep}}
```

The example shows each part of the loop:

- **The loop variable** can be declared with `var` or with a type:
  `for (var x in nums)`, `for (long x in nums)`, and `for (var x: int in nums)`
  all work.
- **The parentheses are optional**, as with `if` and `while`:
  `for var x in nums { ... }`. The braces are required.
- **`break` and `continue`** work as they do in a `while` loop.
- **The loop variable is a copy**, like any `var`. Assigning a new value to it
  does not change the collection. For a struct element, though, the copy is
  another reference to the same object (see
  [Memory and reference counting](memory.md)), so `item.Value = ...` does
  change the element.
- **A temporary source stays alive.** The loop holds a reference to what it
  iterates, so `for (var item in make_items())` is safe.

## Looping over a string

A `String` yields its code points one at a time. Each one is a `String` holding
a single code point, the same value that indexing gives you (`word[i]`):

```pepper
{{#include ../../examples/iteration-strings.pep}}
```

## The iterator protocol

The `for` loop is not tied to `Array` and `String`. It works with any type
that has the right methods, described by two traits in the runtime
(`runtime/iterator.pep`, documented in the [Iterators](../reference/iterator.md)
reference):

```pepper
export trait Iterator<T> {
    bool next();     # advance; true if there is a current element
    T current();     # the element next() just moved to
}

export trait Iterable<T> {
    iterate(): Iterator<T>;
}
```

- An **iterator** steps through elements. `next()` moves to the next element
  and returns `true`, or returns `false` when there are no more (and keeps
  returning `false` after that). `current()` returns the element `next()`
  moved to.
- An **iterable** is a collection that hands out a fresh iterator from
  `iterate()`. `Array<T>` returns an `ArrayIterator<T>` and `String` returns a
  `StringIterator`.

`for (var x in source) { body }` behaves exactly like this:

```pepper
{
    var it = source.iterate();   # or `var it = source;` when source is itself an iterator
    while (it.next()) {
        var x = it.current();
        { body }
    }
}
```

The loop chooses by the methods the source's type has, like a C++ range-based
`for`: it uses `iterate()` if the type has one, and otherwise uses the source
itself as the iterator if it has both `next()` and `current()`. A type with
neither is a compile error:

```text
main.pep:4:19: error: type 'Foo' is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())
    4 |     for (var x in f) {
      |                   ^
```

`HashMap` and `HashSet` do not implement the protocol yet, so they cannot be
used in a `for` loop.

## Writing your own iterator

To make your own type work in a `for` loop, give it `next()` and `current()`
(an iterator), or give it an `iterate()` method that returns such a type (an
iterable):

```pepper
{{#include ../../examples/iteration-custom.pep}}
```

Some things to keep in mind:

- **Declaring the trait is optional.** Traits are not checked yet, so the loop
  looks only at which methods a type has. Writing
  `extend Countdown with Iterator<int> {}` documents your intent (see
  [Traits and extensions](traits-and-extensions.md)).
- **Looping over an iterator uses it up.** When the source is itself an
  iterator stored in a variable, the loop drives that same object, so it is
  exhausted afterwards. An iterable starts a new, independent pass every time
  you loop over it.
- **Generic code can loop** over a type parameter; each specialization checks
  the protocol for its own type (see [Generics](generics.md)).
- **Calling `current()` out of turn panics** in the runtime's iterators:
  before the first `next()` you get `ArrayIterator.current() before next()`,
  and after `next()` returned `false` you get
  `ArrayIterator.current() past the end`. Your own iterators should follow the
  same rule.

## Modifying a collection while you loop over it

Changing an `Array` or a `String` while a loop is iterating over it stops the
program with a panic, because the iterator could otherwise skip or repeat
elements, or read past the end:

```pepper
var nums = Array<int>();
nums.append(1);
nums.append(2);
for (var x in nums) {
    nums.append(x);   # panics: Array modified during iteration
}
```

Every method that changes an `Array` counts, including storing an element with
`nums[i] = v`. For a `String`, `append` and `grow` count, and the message is
`String modified during iteration`. The check happens on the iterator's next
step, so modifying the collection after the loop is finished is fine.

To change elements as you go, loop over an index with `while` and store through
it, or collect the changes in a second array and apply them after the loop.

## Loop scope

The loop variable and anything declared in the loop body exist only inside the
loop. Each pass gets a new loop variable, and struct values declared in the
body are released at the end of every pass, whether the pass ends normally or
by `continue`, `break`, or `return`. Leaving the loop early also releases the
hidden iterator, so a destructor on a custom iterator runs at that point.

Two limitations apply today:

- Using the loop variable or a body local after the loop does not yet produce
  a clear error: the compiler fails with an internal
  `Instruction does not dominate all uses` message instead of
  `use of undeclared identifier`.
- Do not give the loop variable the same name as a variable declared before
  the loop. The compiler currently mishandles the outer variable after the
  loop and fails with the same internal error. Going the other way works: a
  variable declared inside a nested loop's body may reuse the outer loop
  variable's name.

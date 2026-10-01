# Iteration

A `for` loop visits each element of a collection in turn. You can loop over an
[`Array`](../reference/array.md), over the code points of a
[`String`](../reference/string.md), over a range of numbers (`0..count`),
and over any type of your own that follows the iterator protocol.

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
  [Memory and reference counting](memory.md)), so `item.value = ...` does
  change the element.
- **A temporary source stays alive.** The loop holds a reference to what it
  iterates, so `for (var item in make_items())` is safe.

## Looping over a string

A `String` yields its code points one at a time. Each one is a `String` holding
a single code point, the same value that indexing gives you (`word[i]`):

```pepper
{{#include ../../examples/iteration-strings.pep}}
```

## Looping over a range

`a..b` is the numbers from `a` up to, but not including, `b`, and `a..>b`
includes `b`. Looping over one is how you count:

```pepper
{{#include ../../examples/iteration-ranges.pep}}
```

- **The bounds give the type.** A range's element type is inferred from its
  bounds like a generic call's type argument, so `0..names.count()` counts in
  `ulong`. The bounds must be integers; anything else is an error at the
  operator:

  ```text
  main.pep:2:22: error: range bounds must be integers, not 'String'
      2 |     for (var c in "a".."z") {
        |                      ^~
  ```

- **Precedence.** A range binds more loosely than arithmetic and shifts, and
  more tightly than comparisons, so `0..n + 1` is `0..(n + 1)`. Two range
  operators in a row (`1..2..3`) are an error; add parentheses. `...` is
  not a range operator.
- **An empty range runs no iterations.** A range whose start is past its end
  (`3..1`, `5..>4`) is empty, and `a..a` is too. A closed range ending at
  its type's largest value (`250..>top` with a `byte` `top` of 255) stops
  there without overflowing.
- **A range is a value**, a [`Range<T>`](../reference/range.md). It has
  `contains(x)` and `is_empty()`, and it is an `Iterator<T>`, so it has the
  [adapters](#adapters) `map` and `filter`. Looping over one allocates
  nothing; the optimizer turns it into a plain counting loop.

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
  `iterate()`. `Array<T>` returns an `ArrayIterator<T>`, `String` returns a
  `StringIterator`, and `HashMap<K, V>` and `HashSet<K>` return a
  `HashMapIterator<K, V>` and a `HashSetIterator<K>`.

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

`HashMap<K, V>` yields each entry as a [tuple](tuples.md) `(K, V)`, so
`for (var (name, age) in ages)` names both parts; `HashSet<K>` yields its
members. Both visit entries in no particular order. Changing a value
(`ages[name] = …` for a key already present) is fine while looping, but adding
or removing an entry stops the program at the iterator's next step.

## Adapters

`Iterator<T>` has default methods that wrap an iterator in another one.
Each works lazily, one element at a time as the loop asks for it:

- `map(transform)` yields `transform(x)` for each element `x`; its element
  type is whatever `transform` returns.
- `filter(keep)` yields only the elements for which `keep(x)` is `true`.
- `enumerate()` yields `(index, x)` [tuples](tuples.md), counting from 0 in
  `ulong`; `enumerate<int>()` counts in `int` instead.
- `zip(other)` yields `(x, y)` pairs, one element from each iterator in
  step, and stops when either runs out.

They return iterators, so they chain, and a `for` loop can use the result
directly; destructure a tuple to name its parts. `to_array()` runs an
iterator to the end and collects what is left into a new `Array`:

```pepper
{{#include ../../examples/iteration-adapters.pep}}
```

Every type that declares `Iterator<T>` gets them: `ArrayIterator<T>` (from
`Array.iterate()`), `StringIterator`, [ranges](#looping-over-a-range), and
your own iterators once you write `extend YourType with Iterator<T> {}`. The adapter holds its own copy of
the iterator it wraps (the runtime's iterators are
[value structs](value-structs.md), boxed when they become an `Iterator<T>`),
so a chain built from a temporary stays alive while the loop runs, and
`it.map(f)` and `it.to_array()` leave `it` where it was. They are generic methods (see
[Generics](generics.md#generic-methods)), so they are not callable through an
`Iterator<T>` trait value.

## Writing your own iterator

To make your own type work in a `for` loop, give it `next()` and `current()`
(an iterator), or give it an `iterate()` method that returns such a type (an
iterable):

```pepper
{{#include ../../examples/iteration-custom.pep}}
```

Some things to keep in mind:

- **Declaring the trait is optional.** The loop looks only at which methods a
  type has. Writing `extend Countdown with Iterator<int> {}` documents your
  intent, and the compiler then checks that `Countdown` has both `next()` and
  `current()` (see [Traits and extensions](traits-and-extensions.md)).
  Declaring it also lets the type be used as an `Iterator<int>` value, and a
  `for` loop over such a value calls the methods through the trait. It also
  gives the type the [adapters](#adapters) `map` and `filter`.
- **Looping over an iterator uses it up.** When the source is itself an
  iterator stored in a variable, the loop drives that variable in place, so
  it is exhausted afterwards, and a loop left with `break` can be resumed by
  looping over it again. A `const` variable holding a value iterator cannot
  be looped over, since `next()` changes it. An iterable starts a new, independent pass every time
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

Using the loop variable or a body local after the loop is an error, the same as
for any name that is out of scope:

```text
main.pep:6:12: error: use of undeclared identifier 'i'
    6 |     return i;
      |            ^
```

The loop variable, or a local in the loop body, may have the same name as a
variable declared before the loop. It hides the outer variable inside the loop,
and the outer variable keeps its value afterwards.

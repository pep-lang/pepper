<!-- Generated from runtime/bitset.pep by `pep-doc reference`. Do not edit. -->

# BitSet

`BitSet`: a set of small non-negative integers, stored one bit each.

Source: `runtime/bitset.pep`

## BitSet

```pepper
struct BitSet
```

A growable set of non-negative integers, one bit per possible member.

Member `n` is bit `n % 64` of word `n / 64`, so a set whose largest
member is `m` takes about `m / 8` bytes whatever its count: a good fit for
visited flags, masks, and sieve or liveness tables over small integers.
For sparse or large integers use a `HashSet<int>`.

`insert` grows the set as needed and `reserve` grows it ahead of time;
the set never shrinks. `contains` and `remove` take O(1); `count`,
`is_empty`, `==`, `hash`, iteration and the set operations take
O(capacity / 64).

Two sets are `==` when they hold the same members, whatever their
capacity, and equal sets hash equally, so a `BitSet` works as a
`HashMap` or `HashSet` key. A `BitSet` is not `[Shared]`: keep each one
on one thread.

**Example**
```pepper
BitSet primes = [2, 3, 5, 7];
primes.insert(11);
assert(primes.contains(5), "a member");
assert(primes.count == 5, "five members");
for (var p in primes) {
    print($"{p}");   # 2, 3, 5, 7, 11
}
```

### Properties

#### capacity

```pepper
var capacity: int { get; }
```

The number of members the set holds without growing, a multiple of 64.

#### count

```pepper
var count: int { get; }
```

The number of members in the set. O(capacity / 64).

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the set has no members. O(capacity / 64).

### Constructors

#### BitSet()

```pepper
construct(capacity: int = 0)
```

Creates an empty set with room for the members `0` up to (not
including) `capacity` before it grows.

**Parameters**
- `capacity` — the number of members to make room for; rounded up to a multiple of 64

**Panics**
- if `capacity` is negative

#### BitSet()

```pepper
[Implicit] construct(items: int[])
```

Creates a set holding each element of `items`.

The constructor is `[Implicit]`: an array converts to a set wherever
a set is expected, so an array literal can initialize one.

**Parameters**
- `items` — the members to insert; duplicates are kept once

**Panics**
- if an element of `items` is negative

**Example**
```pepper
BitSet flags = [1, 4, 4];
assert(flags.count == 2, "4 is kept once");
```

### Methods

#### reserve

```pepper
reserve(capacity: int)
```

Makes room for the members `0` up to (not including) `capacity`, so
inserting them does not grow the set. Never shrinks it.

**Parameters**
- `capacity` — the number of members to make room for

**Panics**
- if `capacity` is negative

#### clear

```pepper
clear()
```

Removes every member. The set keeps its capacity.

#### contains

```pepper
contains(n: int): bool
```

Returns whether `n` is a member. O(1).

**Parameters**
- `n` — the integer to look up; a negative one is never a member

**Returns**
- true when `n` is a member

#### insert

```pepper
insert(n: int): bool
```

Adds `n` to the set, growing it when `n` is past its capacity.

**Parameters**
- `n` — the integer to add

**Returns**
- true when `n` was added, false when it was already a member

**Panics**
- if `n` is negative

#### remove

```pepper
remove(n: int): bool
```

Removes `n` from the set. Does nothing when `n` is not a member.

**Parameters**
- `n` — the integer to remove

**Returns**
- true when `n` was a member and was removed, false otherwise

#### iterate

```pepper
iterate(): BitSetIterator
```

Returns an iterator over the members in ascending order;
`for (var n in set)` drives it.

The iterator holds a reference to the set. Changing the set while
iterating is safe: the iterator sees the members above its position
as they are when it reaches them.

**Returns**
- an iterator positioned before the smallest member

#### union_with

```pepper
union_with(other: BitSet)
```

Adds every member of `other` to this set.

**Parameters**
- `other` — the set whose members to add

#### intersect_with

```pepper
intersect_with(other: BitSet)
```

Keeps only the members that `other` also holds.

**Parameters**
- `other` — the set to intersect with

#### difference_with

```pepper
difference_with(other: BitSet)
```

Removes every member that `other` holds.

**Parameters**
- `other` — the set whose members to remove

#### symmetric_difference_with

```pepper
symmetric_difference_with(other: BitSet)
```

Keeps the members that exactly one of the two sets holds: removes
the members `other` also holds and adds those only `other` holds.

**Parameters**
- `other` — the set to compare with

#### union

```pepper
union(other: BitSet): BitSet
```

Returns a new set holding the members of either set.

**Parameters**
- `other` — the other set

**Returns**
- the union of the two sets

#### intersection

```pepper
intersection(other: BitSet): BitSet
```

Returns a new set holding the members both sets hold.

**Parameters**
- `other` — the other set

**Returns**
- the intersection of the two sets

#### difference

```pepper
difference(other: BitSet): BitSet
```

Returns a new set holding the members of this set that `other` does
not hold.

**Parameters**
- `other` — the set whose members to leave out

**Returns**
- this set minus `other`

#### symmetric_difference

```pepper
symmetric_difference(other: BitSet): BitSet
```

Returns a new set holding the members that exactly one of the two
sets holds.

**Parameters**
- `other` — the other set

**Returns**
- the symmetric difference of the two sets

#### is_subset

```pepper
is_subset(other: BitSet): bool
```

Returns whether every member of this set is also a member of `other`.
The empty set is a subset of every set.

**Parameters**
- `other` — the set to compare with

**Returns**
- true when this set holds no member that `other` lacks

#### is_disjoint

```pepper
is_disjoint(other: BitSet): bool
```

Returns whether the two sets have no member in common.

**Parameters**
- `other` — the set to compare with

**Returns**
- true when no integer is a member of both sets

#### operator ==

```pepper
==(rhs: BitSet): bool
```

Reports whether both sets hold the same members. Capacity is not
compared.

**Parameters**
- `rhs` — the set to compare with

**Returns**
- true when the sets have the same members

#### operator !=

```pepper
!=(rhs: BitSet): bool
```

Reports whether the sets differ in any member; the negation of `==`.

**Parameters**
- `rhs` — the set to compare with

**Returns**
- true when one set holds a member the other lacks

#### copy

```pepper
copy(): BitSet
```

Returns a new set with the same members and capacity. This is how
`copy(value)` copies a BitSet (the `Copyable<BitSet>`
implementation).

**Returns**
- the copy

## hash

```pepper
hash<BitSet>(value: BitSet): u64
```

Returns a hash of the members of `value`, so equal sets hash equally
whatever their capacity and a `BitSet` works as a `HashMap` or `HashSet`
key. O(capacity / 64).

**Parameters**
- `value` — the set to hash

**Returns**
- the 64-bit hash of the set's members

## BitSetIterator

```pepper
[Value] struct BitSetIterator
```

An `Iterator<int>` over the members of a `BitSet` in ascending order;
returned by `BitSet.iterate()` and driven by `for (var n in set)`.

**See also**
- `BitSet.iterate`

### Constructor

#### BitSetIterator()

```pepper
construct(source: BitSet)
```

Creates an iterator positioned before the smallest member of `source`.

**Parameters**
- `source` — the set to iterate

### Methods

#### next

```pepper
next(): bool
```

Advances to the next larger member.

**Returns**
- true when there is a current member, false once every member was visited

#### current

```pepper
current(): int
```

Returns the member the last successful `next()` moved to.

**Returns**
- the current member

**Panics**
- if `next()` was never called or already returned false ("BitSetIterator.current() without a member")

# Value structs: `[Value]`

Status: phases 1 (value structs, `Optional`) and 2 (boxing, iterators)
implemented; phase 3
proposed. Written 2026-10-01 against `main` at 08ccea91. Motivating items:
C1 and C2 in runtime-modernization.md.
Related designs: tuples (the value
aggregate this reuses), enums (payload
enums lowered to structs), trait values
(the two-word trait value a boxed value hides behind),
iterator protocol.

Decided by Justin before this draft: the attribute, inline storage with
tuple-like copies, reference fields still counted, iterators / `Optional` /
`Result` as the first users, boxing at trait conversions. Everything else
below is proposed; the choices that need an answer are in §16.

## 1. Summary

A struct marked `[Value]` is stored inline in whatever holds it (a local,
a field, an array element, a tuple element) and copied like a tuple. It has
no heap object, no refcount header, and no identity. Its reference-typed
fields are still counted: copying a value struct acquires each of them,
and dropping one releases each, exactly as for a tuple.

```pepper
[Value]
export struct Span {
    int start;
    int end;

    construct(this.start = 0, this.end = 0) {}

    length(): int {
        return end - start;
    }

    grow(by: int) {
        end = end + by;          # changes the storage `this` refers to
    }
}

main(): int {
    var a = Span(0, 4);         # no allocation: `a` is 8 bytes on the stack
    var b = a;                  # a copy; `b` and `a` are independent
    b.grow(2);
    return a.length() + b.length() - 10;   # 4 + 6 - 10 == 0
}
```

The runtime then marks `Optional<T>`, `Result<T, E>` and its iterators
`[Value]`, which makes `T?` and `for` over an `Array` allocation-free (C1,
C2), and later lets `Optional` become
`[Value] enum Optional<T> { None, Some(value: T) }`.

## 2. Motivation: what these cost today

Measured on this container (Linux x86-64, LLVM 20, `-O`, i.e. `-O2`),
10 million calls each, counting `malloc` with an `LD_PRELOAD` shim
(program kept in the session scratchpad, not committed):

| Loop body (10M iterations) | Time | `malloc` calls |
| --- | --- | --- |
| `for (var v in values)` over a 4-element `Array<int>` | 0.82 s | 10,000,020 |
| same sum with `while (i < values.count)` and `values[i]` | 0.09 s | 22 |
| `half(k).value_or(0)`, `half` returning `int?` | 0.27 s | 10,000,024 |
| `checked(k).ok_or(0)`, `checked` returning `Result<int>` (Ok path) | 0.30 s | 10,000,026 |

So a `for` over an `Array` costs about 9x an index loop, and every `T?`
or `Result` return is one heap allocation and free. In the emitted IR
(`--emit-llvm`):

- `Array<int>.iterate` calls the `ArrayIterator<int>` constructor
  (`_pep_malloc` of `{i32, i32, ptr, i64, i64, i1}`, 40 bytes with the
  header), the loop calls `next()`/`current()` through that pointer, and the
  scope exit calls `ArrayIterator<int>.__release`, which frees it.
- `Optional<int>.some` mallocs a 16-byte `{i32, i32, i1, i32}` object;
  inline it would be `{i1, i32}`, 8 bytes, returned in a register.
- `Result<int, Error>.Ok` mallocs `{i32, i32, i32, i32, ptr}`; inline it is
  `{i32 tag, i32, ptr}`, 16 bytes, returned in two registers.

The modernization scan lists the runtime code that avoids `T?`, `Result`
and `for` on hot paths for this reason (A2, A3, A4, A8, B10, section D).

## 3. Declaration

```text
[Value]
[export] struct Name[<T, ...>] { fields, constructors, methods }

[Value]
[export] enum Name[<T, ...>] { cases, methods }      # §8
```

- `[Value]` is a plain attribute on its own line (AGENTS.md), read by a new
  `StructDef::is_value()` next to `is_shared()`.
- Fields, constructors, methods, operators, static methods, `extend` blocks,
  generics and trait conformance work as for any struct.
- Field defaults and constructors work as today. The constructor's `this`
  is the storage being initialized, not a fresh heap object: there is no
  `_pep_malloc`, and the constructor returns the value.
- A slot of a value struct type that is given no value holds the **zero
  value**: every field zero, `false` or null, without running a
  constructor. `ArrayIterator<T>()` with no constructor declared is that
  zero value (Array.iterate relies on this today). See decision 6 for
  enums.

## 4. Semantics

A value struct behaves like a C++ struct whose reference fields are
`shared_ptr`s, held by value. Nothing new is added to the shared_ptr model
(AGENTS.md); each rule below is what C++ does for such a struct.

### 4.1 Copies, moves, assignment

| Construct | Effect |
| --- | --- |
| `var b = a;`, argument, return, field or element store | Copy: every field is copied; each reference field is acquired (a nested value struct recursively). |
| `var b = f();` (owned rvalue) | Moves in: no count work, as for a tuple result. |
| `b = a;` | Acquire `a`'s reference fields, then release `b`'s old ones. No identity test is needed: acquiring before releasing makes `a = a` safe (the tuple rule in INTERNALS §4.3). |
| Scope exit, parameter exit | Release each reference field. |
| Discarded temporary (`f();`, `f().m()`) | Released once at the end of the full expression. |
| `move(x)` | Yields the value and zeroes the slot (reference fields null), no count work. *Inferred: `codegen_move` needs a value-struct case; not checked for tuples today.* |

A value struct with no reference fields does no refcount work at all.

### 4.2 Mutation is of the storage, never shared

- `x.f = 1` changes the storage `x` names. A copy is never affected:
  after `var b = a; b.f = 1;`, `a.f` is unchanged. This is the main
  difference from heap structs, where `b` would alias `a`.
- A field of a value struct inside a heap object is that object's storage:
  `obj.span.end = 3` and `obj.span.grow(1)` change `obj`'s field in place,
  visible to every reference to `obj`.
- A field inside another value struct is part of it: `outer.inner.f = 1`
  changes `outer`.
- Assigning to a field of a **temporary** is an error, as in C++ for an
  rvalue: `a[i].end = 3` (`[]` returns a copy), `f().end = 3`. Write
  `var s = a[i]; s.end = 3; a[i] = s;` (decision 4 proposes sugar later).
- `const s = Span(0, 1); s.end = 2;` is an error: a `const` value struct
  is constant all the way down (C++ `const` struct). This differs from a
  `const` heap reference, whose object stays mutable.
- Tuple elements stay immutable (tuples decision 5), so `t.0.end = 3`
  remains the existing error.
- A `for` loop variable over value elements is a copy: `x.f = ...` in the
  body changes the copy, not the element. (For heap structs it changes the
  element.) The book's iteration chapter says this explicitly.

### 4.3 Methods: `this` refers to the storage

A method on a value struct gets `this` as a pointer to the receiver's
storage, the C++ `this` of a struct method. So:

- `x.m()` on a local, a parameter, or a field (of a value struct or of a
  heap object) passes that place's address. No copy, no count work, as
  for struct receivers today.
- On an rvalue (`f().m()`, `a[i].m()`), the value is put in a hidden
  temporary first; the temporary is released at the end of the full
  expression (`deferred_temps`, as today).
- **Mutating methods** (decision 2): sema infers whether a method mutates
  `this` (assigns a field of `this`, directly or through a nested value
  field, or calls a mutating method on `this` or on a value field of it;
  computed to a fixpoint per struct specialization). Calling a mutating
  method on a `const` place or on a temporary is an error, because the
  change would be lost or would break `const`. Non-mutating methods are
  fine on both.
- A closure created in a method captures a **copy** of `this`. Mutating
  `this` inside such a closure is an error, the same rule as today's
  `cannot assign to 'x' because a closure captures it`. A bound method
  value `s.length` binds a copy too.
- Passing `this` as an argument or returning it copies (acquire), exactly
  as for heap structs.

Lifetime: `this` points into its holder's storage for the call. For a
local or a field of a local that is safe. For a field of a heap object
(`obj.span.grow()`), the same caveat as today's struct receivers applies:
the method must not drop the last reference to `obj`. For array elements
the issue does not arise, because `a[i]` yields a copy and the method runs
on a temporary (so the buffer can be reallocated during the call without
harm). *Inferred, not checked: no runtime method today could reallocate a
holder mid-call through a value receiver, since none exist yet.*

### 4.4 Restrictions

Each is a sema error (§10), located at the token to change:

- **No identity.** `===`, `!==`, comparison with `__null`, assigning
  `__null`, `__address`, `__refcount`: there is no object.
- **No `__weak<V>`**, `__weak_from`, `__weak_upgrade`: there is no count.
  A `__weak<Heap>` field inside a value struct is fine.
- **Not recursive.** A value struct cannot contain itself through value
  fields (directly, through another value struct, a tuple, or a value
  enum such as `Optional<Self>` once `Optional` is a value). It can through
  a heap type (`Array<Self>`, a heap struct, a reference enum).
- **No `destruct`** in the first version (decision 3): copies would each
  run it. Field releases still happen.
- **No `extern` signatures** in the first version: the C struct calling
  convention needs per-target classification. Pointers to C memory keep
  using `__ptr<T>`.
- **`[Shared]`** (decision 5): a value struct is never shared by
  reference, so it needs no atomic counts of its own. It is thread-safe
  when every field type is, like a tuple, and can then go in a `[Shared]`
  struct's `const` field, a global, or a `[Sending]` parameter. `[Shared]`
  on a value struct is an error that says so.
- **`[Value]` on an enum whose cases carry nothing** is a warning: such an
  enum is already an integer value.

### 4.5 Equality and hashing (decision 7)

Without its own `==`, a value struct compares field by field when every
field has `==` (`tuple_equal`'s rule: a field's own `==`, else by value,
else identity for a heap reference), and `hash<V>` folds field hashes, so
it can be a `HashMap` key. A declared `==` or `hash` replaces them. It
cannot compare by identity, which is the heap-struct default.

### 4.6 Threads and fresh results

A value struct is disconnected (sync design) when every reference field is,
the per-element rule tuples already use. Sending one to another thread
copies it; the copy shares the heap objects its fields refer to, which must
be thread-safe, as for tuples.

## 5. Generics

Monomorphization means a generic sees the concrete type:

- `Optional<T>` (a value) with `T = int`: `{i1, i32}`. With `T = String`:
  `{i1, ptr}`, and copying the optional acquires the `String`. With
  `T = Span` (a value): the `Span` is inline, `{i1, {i32, i32}}`.
- `Array<V>` stores elements inline with stride `sizeof<V>()`.
  `_pep_move_ref`/`_pep_swap_refs` already move whole slots of any stride
  (trait values and tuples use them). `__is_pod<V>` is true only when no
  field, recursively, is a reference.
- A generic body that uses identity (`x === y`, `__null`) on `T` reports
  the error in the specialization at `V`, as other per-specialization
  checks do.
- Generic constraints (`<T: Iterator<int>>`) call methods statically: no
  boxing. This is the path `for` uses.
- Runtime helpers that branch on "struct or not" need a value case. The
  audit list: `copy<T>` and `copies.rs` (`__copy` copies field by
  field, deep-copying reference fields), the `_pep_check_sync` census
  (walk a value's fields inline), `release<T>`, `__default<T>` (zero
  value), `to_string<T>`.

## 6. Boxing through traits

A value struct can declare traits (`extend ArrayIterator<T> with
Iterator<T>`). Where a value of value struct type `V` flows into a slot of
trait type `Tr`, the value is **boxed**: copied into a new heap object,
and the trait value refers to the box.

- **Representation.** A synthesized heap struct `__box<V>` with one field
  `V value`, declaring `V`'s traits. Each trait method on the box forwards
  to `V`'s method with `this` = the box's field address. So the box is an
  ordinary struct, and the existing trait-value machinery (§4.2 of
  INTERNALS: `[2 x ptr]`, vtables, thunks) is used unchanged.
- **Conversion.** `convert_to_traits` today reports
  `'int' cannot be converted to trait 'Tr'` for value types. For a value
  struct it instead wraps the value as `ToTrait { __box<V>(value) }`. The
  box's constructor copies (acquire) from a place, or moves an owned
  rvalue in. One allocation per conversion.
- **Semantics.** The trait value has the box's identity: two conversions of
  one value are two boxes (`===` is false), and mutating methods called
  through the trait value change the box, not the original. So
  `Iterator<int> it = a.iterate(); it.next();` advances the boxed copy,
  which is what the caller expects.
- **Release.** The last release of the trait value releases the box,
  whose destructor releases `value`'s reference fields.
- **Default trait methods.** They are cloned onto the conforming struct,
  so `this` has the concrete type. `Iterator<T>.map` passes `this` into
  `MapIterator(source: Iterator<T>, ...)`, which boxes a **copy** of the
  iterator: `it.map(f)` no longer advances `it`. *Checked: no runtime or
  tools code uses an iterator after mapping it.*
- **Later:** the same box lifts the `int`/value-enum restriction, and a
  downcast `as V` copies out of the box.

## 7. Iterators and `for` (C2)

With `ArrayIterator<T>` a value struct, `for (var x in array)` lowers as
today (`var __for_iterator_0 = array.iterate(); while (__it.next()) ...`),
but `__it` is a 32-byte stack slot `{ptr _source, i64, i64, i1}`:

- `iterate()` returns the value (two registers plus a stack slot, or sret,
  as LLVM lowers it); the loop acquires the array once and releases it
  once at loop exit (`break`/`return` included); no `malloc`.
- `next()` and `current()` take `&__it`. At `-O` LLVM can inline them and
  promote the fields to registers, leaving an index loop with the
  fail-fast version check. *Inferred, not measured: the phase 2 PR
  re-runs the §2 benchmark and reports the numbers.*
- This replaces C2's suggestion of special-casing `for` over `Array<T>` as
  an index loop: it covers `String`, `HashMap` and `HashSet` too, keeps
  the modification check, and needs no second lowering.

Iterating a stored iterator (decision 8): today `for (var x in it)` drives
the object `it` refers to, so a partly consumed iterator can be resumed
after `break`, and the book says so. With a value iterator, a hidden copy
would silently drop that. Proposal: when the source is itself an iterator
(it has `next`/`current`, not `iterate`) and is a mutable place, the loop
drives the place in place (its address, no hidden copy); an rvalue source
still gets the hidden slot. A `const` iterator source is an error (`next`
is mutating).

## 8. Enums with payload: `[Value] enum`

A reference enum is already lowered to a struct (`StructDef` with
`enum_cases`: a `__tag` field, then every case's payload fields). A
`[Value]` enum is lowered the same way to a **value** struct:

- `Optional<int>` as `[Value] enum Optional<T> { None, Some(value: T) }`
  is `{i32 __tag, i32 Some.value}`; `Result<int, Error>` is
  `{i32 __tag, i32 Ok.value, ptr Err.error}`. Payloads do not overlap
  yet (the enum design's "later: a union"); a later PR can overlap them,
  since the release thunk can switch on `__tag`.
- Payloads stay immutable (enums decision 3), so a `[Value]` enum has no
  mutating methods and the temporary/`const` rules never trigger.
- A case that carries nothing is a constant value, not a static object.
- `match` copies the scrutinee into `__match_N` and bindings copy out, as
  today; for a value enum these are stack copies.
- Recursive `[Value]` enums are an error (`enum List<T>` stays a
  reference enum).
- `===` and the null default go away; see decision 6 for what an
  uninitialized slot holds.

## 9. Codegen

- **Layout.** A named LLVM struct of the fields' slot types in declaration
  order, no head fields (`apply_synthesized` skips `__refcount` and
  `__weakcount`), natural alignment, so it matches the C layout.
  Kept named for readable IR: `types::is_object` (today "named struct
  means object") consults a `Types::is_value` set instead of the name.
- **Slots.** `is_reference_name` includes value structs (copies acquire,
  scopes release), and `reference_value_type` returns the struct type
  itself, as for tuples. Locals are allocas; fields and array elements
  are inline.
- **Refcount thunks.** `V.__acquire(value)` / `V.__release(value)` step
  each reference field; the tuple emitter (`emit_tuple_refcount_thunk`)
  generalizes to "a value aggregate with element types". So every §5 row
  (copies, stores, scope exits, temporaries, `release_field_refs` in a
  holder's destructor) works on value structs by type name, as it did for
  tuples and trait values.
- **Methods.** `this` stays a `ptr`, and field access stays a GEP on the
  struct type, so method bodies change only in that the type has no
  header. Call sites change: the receiver is the address of a place
  (`place_address`: alloca, GEP into a value-struct place, GEP into a heap
  object, or a spilled temporary).
- **Constructors.** `this` is an alloca in the constructor; `return this`
  loads it. No `size` patching, no `_pep_malloc`.
- **ABI.** Inside Pepper code a value struct is passed and returned as an
  LLVM first-class aggregate, as tuples are. LLVM lowers it per target:
  small ones in registers, a large return demoted to a hidden sret
  pointer, large arguments on the stack. *Inferred from LLVM's lowering;
  the phase 1 PR checks the IR for a 64-byte struct on x86-64 and
  arm64.* If large copies show up in profiles, a later change can pass
  values over 32 bytes by pointer (callee copies and acquires on entry, as
  the shared_ptr rule says). No C ABI in v1 (§4.4).
- **Equality and hash.** `codegen_binary` and `Expression::Address` send
  value structs to the existing `tuple_equal`/`tuple_hash` (renamed for
  aggregates) unless the struct declares `==`/`hash`.

## 10. Sema checks and diagnostics

All clang-style, at the token to change, each with a rendered test in
`diagnostic_tests.rs`.

```text
main.pep:9:5: error: cannot assign to field 'end' of a temporary 'Span'
    9 |     spans[0].end = 3;
      |     ^~~~~~~~~~~~
main.pep:9:5: note: '[]' returns a copy; store it in a variable, change it, and assign it back
```

| Situation | Error, located at |
| --- | --- |
| `a === b` on a value struct | `'Span' is a value struct and has no identity; use '==' to compare values` — the operator |
| `x = __null`, `x === __null` | `value struct 'Span' cannot be null` — `__null` |
| `__weak<Span>` | `'__weak' needs a reference type; 'Span' is a value struct` — the type argument |
| `__address(x)`, `__refcount(x)` | `'Span' is a value struct and has no object` — the call |
| recursive value | `value struct 'Node' contains itself through field 'next'` — the field type; a note per step of a longer chain |
| `destruct` in a value struct | `value struct 'Span' cannot have a destructor` — `destruct` |
| `[Shared]` with `[Value]` | `'[Shared]' does not apply to value struct 'Span': it is thread-safe when its fields are` — the attribute |
| value struct in an `extern` signature | `value struct 'Span' cannot be passed to C; pass a pointer` — the type |
| field of a temporary assigned | as above — the member expression |
| field of a `const` assigned | `cannot assign to field 'end' of const variable 's'` — the member expression, note at the `const` |
| mutating method on a temporary | `cannot call mutating method 'grow' on a temporary 'Span'` — the method name, note at the method's first assignment to `this` |
| mutating method on a `const` | `cannot call mutating method 'grow' on const variable 's'` — the method name, same note |
| mutating `this` in a closure | `cannot change 'this' in a closure: the closure holds a copy of 'Span'` — the assignment |
| `[Value]` on a payload-free enum | warning: `'[Value]' has no effect: enum 'Color' carries no values and is already a value` — the attribute |
| uninitialized local of a value enum whose first case carries values (if decision 6 is a) | `variable 'r' of type 'Result<int>' needs a value: its first case 'Ok' carries values` — the name |

New pass: `value_structs` (after specialization and `resolve_implicit_types`,
before `convert_to_traits`, which needs to know what to box): installs the
set of value types (as `enums::install` does for enums), checks recursion
and attributes, infers mutating methods, and reports the identity,
temporary and `const` errors. `weak_types`, `check_shared_types` and
`copies` read the set.

LSP: hover shows `[Value] struct Span` and, on a method, "mutates `this`".
pep-fmt and `tools/syntax` need nothing: attributes already parse.

## 11. Runtime migration

In order, each with the phase that enables it:

1. **`Optional<T>`** (phase 1): add `[Value]` to the struct as it is. The
   fields are private, so no caller changes, and the builder's default
   `Optional<T>()` for an unset `T?` slot is the zero value (None). The
   doc comment's "For a struct `T` the optional acquires a reference" stays
   true. Fixes A2/A3/A8/B10 and section D costs at once.
2. **Iterators** (phase 2): `ArrayIterator`, `StringIterator`,
   `HashMapIterator`, `HashSetIterator`, `ChannelIterator`, and the
   adapters `MapIterator`/`FilterIterator` (their `Iterator<T>` source
   stays a boxed trait value; they avoid their own allocation). The doc
   comments that say "holds a reference to the Array" stay true (the
   `_source` field does).
3. **`Result<TValue, TError>`** (phase 3): `[Value] enum`. Every `Result`
   return stops allocating on the Ok path. The Err path still builds an
   `Error` and its `String`; decision 9 is whether `Error` becomes a value
   too.
4. **`Optional` becomes an enum** (phase 3): `[Value] enum Optional<T> {
   None, Some(value: T) }`, keeping `some`, `none`, `is_some`, `!!`,
   `value`, `value_or`, and gaining `match`/`is Some(v)`. `Optional<T>()`
   for None (7 uses, all in `runtime/optional.pep` and its docs) becomes
   `Optional<T>.None`; keep the constructor spelling working if enums can
   take a static `construct`-like factory, else migrate the uses in the
   same PR. *Inferred: enums cannot declare constructors today
   (`Shape(...)` is an error).*
5. **Later candidates, measured first:** `with` guards (need `destruct`,
   decision 3), small runtime records (`DirEntry`, `Uri` parts, HTTP
   header pairs). Not proposed here.

Behavior changes users can see, all listed in the PRs and the book:
copying an iterator or optional gives an independent value; `===` on an
`Optional`/`Result`/iterator becomes an error; `it.map(f)` no longer
advances `it`; a `Result` or `Optional` slot can no longer be null.

## 12. Build cache and ABI

- There is no external Pepper ABI: the whole program, runtime included,
  is compiled by one compiler. Changing a type to `[Value]` changes the
  signature of every function that takes or returns it.
- The build cache handles this already: a unit's interface hash prints
  each declaration with its attributes (`interface.rs`, `{:?}` of the
  declarations; `StructDecl.attributes` is part of it), so adding
  `[Value]` changes the interface and every dependent unit misses. The key
  also hashes the compiler, so the compiler release that adds `[Value]`
  starts from a cold cache. Marking `Optional` in the prelude makes every
  unit miss once. *Inferred from reading `keys.rs`/`interface.rs`; phase 1
  adds a `build_cache_tests` case that toggles `[Value]` on a struct in
  one unit and checks a dependent unit rebuilds.*
- No `.pep/cache` format change.

## 13. Phases

Each is one PR with tests, docs and examples.

1. **Value structs.** `[Value]` on structs; layout without a header;
   constructors without `malloc`; copy/store/scope-exit thunks
   (generalized from tuples); receivers by address; mutating-method
   inference; every §10 error except boxing; equality/hash; generics and
   `Array<V>`; `copy<T>`/census/`__default`/`__is_pod`. Migrate
   `Optional` (struct form). Book chapter; INTERNALS §3 (new pass), §4
   (new subsection), §5 (row); benchmark numbers in the PR.
2. **Boxing and iterators.** `__box<V>`, `ToTrait` from value structs,
   forwarding methods; `for` driving an iterator place in place (decision
   8); migrate the six iterators; re-run the `for` benchmark.
3. **Value enums with payload.** `[Value] enum`; zero value (decision 6);
   `Result` and then `Optional` as `[Value]` enums; `match`/`is` on them.
4. **Later, each only if wanted:** `destruct` on value structs (move-only
   or copy-runs-destructor), C struct ABI in `extern`, write-back sugar for
   `a[i].f = x`, overlapping enum payloads, boxing `int` and value enums
   into traits, large values by pointer.

## 14. Tests

- `crates/pepper-driver/tests/integration/value_struct_tests.rs` (new),
  using `support/mod.rs` helpers (`compile_jit_with_runtime`,
  `jit_census`): copy independence, mutation through locals, fields of
  heap objects, nested values, method receivers on every kind of place,
  constructors, zero values, `Array<V>`, `HashMap<V, int>` keys, generics
  over value and reference `T`, `Optional<V>`.
- `shared_ptr_semantics_tests.rs`: `PEP_TRACE` order of acquires/releases
  for copy, assignment (including self-assignment), parameter, return,
  discarded temporary, `match`, and a value struct field inside a heap
  object's destructor; `_pep_live_allocs()` is zero after `for` over an
  `Array` and after `T?`/`Result` returns.
- `trait_value_tests.rs`: boxing, mutating through the trait, last release
  frees the box and releases fields, `map`/`filter` over a value iterator.
- `iterator_tests.rs`, `optional_tests.rs`, `result_tests.rs`: existing
  suites pass unchanged after each migration (the semantics they test do
  not depend on identity); add resume-after-`break` for decision 8.
- `diagnostic_tests.rs`: one rendered test per §10 row.
- `build_cache_tests.rs`: the `[Value]` toggle case (§12).
- `docs_examples_tests` runs the new examples.

## 15. Docs changes

- New chapter `docs/src/language/value-structs.md`, "Value structs",
  listed in `SUMMARY.md` after "Structs": declaring, copying, mutation
  and `const`, methods and mutating methods, restrictions, traits and
  boxing, when to use one (small, short-lived, copied often; not for
  shared mutable state). Examples `docs/examples/value-structs-basics.pep`,
  `value-structs-methods.pep`, `value-structs-traits.pep`.
- `structs.md`: a pointer to the new chapter from "Declaring a struct";
  "Comparing structs" notes value structs compare by fields.
- `memory.md` "Values and references": value structs join numbers and
  tuples as plain values; the summary table.
- `introduction.md`: "Every struct value in Pepper is a reference" gains
  "unless marked `[Value]`"; "Current status" lists value structs.
- `optionals.md`: Optional is a value (no allocation); remove the line that
  an optional of a struct holds "a reference to the object, like any other
  struct slot" where it implies the optional itself is one; phase 3 adds
  `match`/`is Some(v)`.
- `results.md` and `enums.md`: `[Value] enum`; enums.md's "An enum with
  such a case is a reference type" and "`===` and `!==` compare identity"
  get the `[Value]` exception.
- `iteration.md`: the runtime's iterators are values; "Looping over an
  iterator uses it up" keeps its meaning (decision 8); a loop variable of
  value type is a copy; `map` copies its source.
- `traits-and-extensions.md`: a value struct can conform; converting one to
  a trait value boxes a copy.
- `tuples.md`: a value struct is the named, mutable cousin of a labeled
  tuple.
- `threads.md`: value structs are thread-safe when their fields are.
- `compiler-errors.md`: only if it lists errors by kind (it has a
  deprecation table; no row needed unless something is deprecated).
- Runtime doc comments for `Optional`, `Result` and the iterators mention
  the value semantics; regenerate `docs/src/reference/`.
- INTERNALS.md: §3 table (the `value_structs` pass), §4 new "Value
  structs" subsection beside tuples and trait values, §5 table row, §13
  if anything stays a sharp edge.

## 16. Open decisions

1. **Spelling `[Value]`** as an attribute (decided) rather than a keyword
   (`value struct`). Listed only to confirm the enum form uses the same
   attribute: `[Value] enum`. Recommend: yes, one attribute for both.
2. **Mutating methods are inferred**, not declared. Sema computes them;
   calling one on a temporary or a `const` is an error. The alternative is
   Swift's explicit marker (`[Mutating]`), which is more to write and to
   get wrong, or no check (C++ without `const`: mutations of temporaries
   silently lost). Recommend: inferred, shown on hover.
3. **No `destruct` on value structs** in the first version. Copies would
   each run it, which makes RAII guards (`with`) wrong without move-only
   types. Recommend: error now; revisit with move-only values in phase 4.
4. **`a[i].f = x` is an error** in v1, rather than sugar for
   `var t = a[i]; t.f = x; a[i] = t;` (Swift's get/modify). Recommend:
   error now, with the note showing the rewrite; sugar later if the
   pattern turns out common.
5. **`[Shared]` on a value struct is an error**; thread safety is inferred
   from the fields, like tuples. Alternative: allow `[Shared]` as an
   assertion checked against the fields. Recommend: error (one less
   meaning for `[Shared]`).
6. **Zero value of a `[Value]` enum**: (a) all-zero storage is the first
   case; a local of an enum whose first case carries values must be
   initialized (error), while a field falls back to the zero payload (like
   a null field today); (b) zero storage always, no error; (c) every slot
   must be initialized. Recommend: (a). `Optional` (first case `None`)
   then defaults to None for free, and `var r: Result<int>;` is caught.
7. **Synthesized `==` and `hash`** field by field when not declared, like
   tuples. Alternative: no `==` unless declared. Recommend: synthesize; a
   value struct is a named tuple, and `HashMap<Span, ...>` should work.
8. **`for` over an iterator place drives it in place**, keeping today's
   documented "the loop uses it up" behavior, instead of copying it into
   the hidden slot (Rust-like, where resuming needs `by_ref`). Recommend:
   in place.
9. **`Error` becomes `[Value]`** too, saving one allocation on every
   `Result.err` (the message `String` still allocates). Users comparing
   errors by identity would break (none found in the runtime; not
   searched outside it). Recommend: yes, in phase 3, after measuring the
   Err path.
10. **Optional's `Optional<T>()` spelling for None** after it becomes an
    enum: migrate the 7 runtime uses to `Optional<T>.None` and drop it
    (enums take no constructors), rather than adding constructors to
    enums. Recommend: drop it, with a `[Deprecated]` period if enums can
    express one cheaply, else outright with the PR saying so.

Taken unless you say otherwise: no C ABI for value structs in v1; values
pass as LLVM aggregates like tuples; a closure or bound method captures a
copy of a value `this`; boxing allocates one object per conversion and
gives the box its own identity; payload fields of `[Value]` enums do not
overlap in v1.

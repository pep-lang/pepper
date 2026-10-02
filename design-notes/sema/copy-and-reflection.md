# Deep copy and reflection (#324)

Status: decided (2026-10-02). `copy(value)` stays a compiler-synthesized
copy (`passes/copies.rs`); reflection replaces none of it today.

## 1. Question

#324 asked, once reflection (#232) landed, whether `_pep_copy` synthesis,
the `__copy<T>` intrinsic, and the `Copies` struct could move into Pepper
code driven by `reflect`, and whether the `Copyable<T>.copy(Copies)`
signature should change.

## 2. What a reflection-driven copy would need

A generic `_copy_fields<T>(value, copies)` with a `static` block over the
fields of `T` needs each of these. None exists, and each is a deliberate
limit or a separate feature:

| Needed | Today |
|--------|-------|
| Every field, private ones included, of a struct declared in another file | `reflect.fields<T>()` works only in the file that declares `T`; `properties` lists public members only. Opening `fields` to the runtime would break the rule that private fields are private to their file. |
| An object made without running a constructor | Only the compiler's `Expression::Allocate`. A Pepper spelling (`__allocate<T>()`) is a new intrinsic, not one fewer. |
| Whether a type is thread-safe (`[Shared]`, `shared` function, numbers) | Computed by `check_shared_types` (`ThreadSafeStructs`); no `reflect` function. |
| Whether a struct has a destructor or a raw pointer field | No `reflect` function. |
| The struct behind a trait value | Known only at run time. Reflection is compile-time and there is no run-time type information, so `_pep_copy_trait` must stay a synthesized vtable slot. |
| "cannot copy 'X' because it contains 'Y'" at the `copy(x)` call, with a note per field hop and the `Copyable<T>` fix-it | `reflect.error` reports in the static block, with "used by" notes; it cannot attach the per-field path or a `Fix`. |
| The `PEP_CHECK_SYNC` census (`__census` → `_pep_check_sync`) | Rides on the same copy, so it moves only if the copy moves. |

Adding those would add as much compiler surface as it removes: the
synthesis in `copies.rs` would become four new intrinsics or `reflect`
functions plus a generic Pepper function, and the error quality would drop.

## 3. Decision

- Keep `__copy<T>`, `__census<T>` and the synthesized `_pep_copy`,
  `_pep_copy_value`, `_pep_fix_weak` and `_pep_copy_trait`.
- Keep `Copies` as the context passed to `Copyable<T>.copy(copies)`; the
  signature does not change, so no deprecation path is needed.
- What reflection did make redundant: `copies.rs` hand-parsed
  `[NotCopyable("why")]` from the syntax tree and lost the reason when it
  was written `reason = "..."` or as joined strings. It now reads the
  attribute the way `reflect.attribute<NotCopyable>()` does
  (`static_blocks::attribute_string`).

## 4. When to revisit

Revisit if Pepper gets run-time type information, or if `reflect` gains
`is_thread_safe<T>()` and a way to build an object without a constructor
for other reasons (for example a reflection-driven `decode` that must not
run constructors). Even then, the trait-value copy stays a vtable slot.

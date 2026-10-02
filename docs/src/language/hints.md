# Optimizer hints

Hints tell the optimizer what it cannot see in the code. A hint never
changes what a program computes, only how fast it runs, so a wrong hint
costs speed and nothing else.

- **Which way a branch goes**: write `[Likely]` or `[Unlikely]` above the
  `if` or `match` arm (see [branch hints](control-flow.md#branch-hints-likely-and-unlikely)).
- **Memory a loop will soon touch**: the `hint` module's prefetches.

| Function | Tells the optimizer |
|---|---|
| `hint.prefetch_read(address)` | `address` will be read soon: start loading its cache line now. |
| `hint.prefetch_write(address)` | `address` will be written soon. |

A prefetch never faults, even for an address that is not mapped, and does
nothing where the CPU has no prefetch instruction.

```pepper
{{#include ../../examples/hint-basics.pep}}
```

The prefetches are LLVM's `llvm.prefetch` intrinsic (see
[LLVM intrinsics](c-interop.md#llvm-intrinsics)). They matter only with
optimization (`-O2` and up, where the runtime's functions inline into the
caller); at `-O0` they cost a call and do nothing.

`hint.likely(condition)` and `hint.unlikely(condition)` are deprecated:
each use warns and suggests the attribute.

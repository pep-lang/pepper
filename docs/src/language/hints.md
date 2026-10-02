# Optimizer hints

The `hint` module tells the optimizer what it cannot see in the code:
which way a branch usually goes, and which memory a loop will soon touch.
A hint never changes what a program computes, only how fast it runs, so a
wrong hint costs speed and nothing else.

| Function | Tells the optimizer |
|---|---|
| `hint.likely(condition)` | `condition` is usually true: lay out the true case as the straight-line path. |
| `hint.unlikely(condition)` | `condition` is usually false: move the true case, such as error handling, out of the way. |
| `hint.prefetch_read(address)` | `address` will be read soon: start loading its cache line now. |
| `hint.prefetch_write(address)` | `address` will be written soon. |

`likely` and `unlikely` return their argument, so they wrap the condition
of an `if` or a loop in place. A prefetch never faults, even for an address
that is not mapped, and does nothing where the CPU has no prefetch
instruction.

```pepper
{{#include ../../examples/hint-basics.pep}}
```

They are LLVM's `llvm.expect` and `llvm.prefetch` intrinsics (see
[LLVM intrinsics](c-interop.md#llvm-intrinsics)). Hints matter only with
optimization (`-O2` and up, where the runtime's functions inline into the
caller); at `-O0` they cost a call and do nothing.

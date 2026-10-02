## Hints to the optimizer about memory a loop will soon read or write.
##
## Bring it in with `import hint`. A hint never changes what a program
## computes, only how fast: a prefetch starts loading a cache line early.
## Where the CPU has no prefetch instruction it does nothing.
##
## To say which way a branch usually goes, write `[Likely]` or
## `[Unlikely]` above the `if` or `match` arm; `likely` and `unlikely`
## here are deprecated.
##
## @example
##     import hint;
##
##     main(): int {
##         var text = "a long text that a loop will read";
##         hint.prefetch_read(text.c_str());
##         assert(text.length > 0, "a prefetch changes nothing");
##         return 0;
##     }

# LLVM intrinsics (#344); see "LLVM intrinsics" in
# docs/src/language/c-interop.md.
[Link(name = "llvm.expect")]
extern bool _expect(bool value, bool expected);

[Link(name = "llvm.prefetch")]
extern void _prefetch(void* address, int write, int locality, int cache);

## Deprecated: write `[Likely]` above the `if` instead.
##
## Returns `condition`, telling the optimizer it is usually true
## (`llvm.expect`).
##
## @param condition the condition to test
## @returns `condition`
[Deprecated("write '[Likely]' above the 'if' instead")]
export likely(condition: bool): bool {
    return _expect(condition, true);
}

## Deprecated: write `[Unlikely]` above the `if` instead.
##
## Returns `condition`, telling the optimizer it is usually false
## (`llvm.expect`).
##
## @param condition the condition to test
## @returns `condition`
[Deprecated("write '[Unlikely]' above the 'if' instead")]
export unlikely(condition: bool): bool {
    return _expect(condition, false);
}

## Starts loading the cache line holding `address` for reading, so a read
## of it soon after does not wait on memory (`llvm.prefetch`). It never
## faults, even for an address that is not mapped, and does nothing where
## the CPU has no prefetch instruction.
##
## @param address memory that will be read soon
## @example
##     hint.prefetch_read(text.c_str());
export prefetch_read(address: __ptr<void>) {
    _prefetch(address, 0, 3, 1);
}

## Starts loading the cache line holding `address` for writing, so a
## store to it soon after does not wait on memory (`llvm.prefetch`). It
## never faults, even for an address that is not mapped, and does nothing
## where the CPU has no prefetch instruction.
##
## @param address memory that will be written soon
export prefetch_write(address: __ptr<void>) {
    _prefetch(address, 1, 3, 1);
}

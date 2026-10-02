## Hints to the optimizer: which way a branch usually goes, and memory a
## loop will soon read or write.
##
## Bring it in with `import hint`. A hint never changes what a program
## computes, only how fast: the optimizer lays out the likely path as the
## straight-line one, and a prefetch starts loading a cache line early. At
## `-O0`, and where the CPU has no prefetch instruction, they cost little
## and do nothing.
##
## @example
##     import hint;
##
##     main(): int {
##         var values = [3, 1, 2];
##         var total = 0;
##         for (var value in values) {
##             if (hint.unlikely(value < 0)) {
##                 return 1;
##             }
##             total += value;
##         }
##         assert(total == 6, "summed");
##         return 0;
##     }

# LLVM intrinsics (#344); see "LLVM intrinsics" in
# docs/src/language/c-interop.md.
[Link(name = "llvm.expect")]
extern bool _expect(bool value, bool expected);

[Link(name = "llvm.prefetch")]
extern void _prefetch(void* address, int write, int locality, int cache);

## Returns `condition`, telling the optimizer it is usually true, so the
## code for the true case is laid out as the fast path (`llvm.expect`).
##
## @param condition the condition to test
## @returns `condition`
## @example
##     if (hint.likely(index < count)) {
##         # the common case
##     }
export likely(condition: bool): bool {
    return _expect(condition, true);
}

## Returns `condition`, telling the optimizer it is usually false, so the
## code for the true case, such as error handling, is moved out of the
## fast path (`llvm.expect`).
##
## @param condition the condition to test
## @returns `condition`
## @example
##     if (hint.unlikely(length > LIMIT)) {
##         return error;
##     }
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

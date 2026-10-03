<!-- Generated from runtime/hint/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The hint module

Hints to the optimizer about memory a loop will soon read or write.

Bring it in with `import hint`. A hint never changes what a program
computes, only how fast: a prefetch starts loading a cache line early.
Where the CPU has no prefetch instruction it does nothing.

To say which way a branch usually goes, write `[Likely]` or
`[Unlikely]` above the `if` or `match` arm; `likely` and `unlikely`
here are deprecated.

**Example**
```pepper
    import hint;

    main(): int {
        var text = "a long text that a loop will read";
        hint.prefetch_read(text.c_str());
        assert(text.length > 0, "a prefetch changes nothing");
        return 0;
    }
```

Source: `runtime/hint/module.pep`

## likely

```pepper
[Deprecated("write '[Likely]' above the 'if' instead")] likely(condition: bool): bool
```

Deprecated: write `[Likely]` above the `if` instead.

Returns `condition`, telling the optimizer it is usually true
(`llvm.expect`).

**Parameters**
- `condition` — the condition to test

**Returns**
- `condition`

## unlikely

```pepper
[Deprecated("write '[Unlikely]' above the 'if' instead")] unlikely(condition: bool): bool
```

Deprecated: write `[Unlikely]` above the `if` instead.

Returns `condition`, telling the optimizer it is usually false
(`llvm.expect`).

**Parameters**
- `condition` — the condition to test

**Returns**
- `condition`

## prefetch_read

```pepper
prefetch_read(address: __ptr<void>)
```

Starts loading the cache line holding `address` for reading, so a read
of it soon after does not wait on memory (`llvm.prefetch`). It never
faults, even for an address that is not mapped, and does nothing where
the CPU has no prefetch instruction.

**Parameters**
- `address` — memory that will be read soon

**Example**
```pepper
    hint.prefetch_read(text.c_str());
```

## prefetch_write

```pepper
prefetch_write(address: __ptr<void>)
```

Starts loading the cache line holding `address` for writing, so a
store to it soon after does not wait on memory (`llvm.prefetch`). It
never faults, even for an address that is not mapped, and does nothing
where the CPU has no prefetch instruction.

**Parameters**
- `address` — memory that will be written soon

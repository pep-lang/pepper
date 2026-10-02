<!-- Generated from runtime/hint/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# hint/module.pep

Hints to the optimizer: which way a branch usually goes, and memory a
loop will soon read or write.

Bring it in with `import hint`. A hint never changes what a program
computes, only how fast: the optimizer lays out the likely path as the
straight-line one, and a prefetch starts loading a cache line early. At
`-O0`, and where the CPU has no prefetch instruction, they cost little
and do nothing.

**Example**
```pepper
    import hint;

    main(): int {
        var values = [3, 1, 2];
        var total = 0;
        for (var value in values) {
            if (hint.unlikely(value < 0)) {
                return 1;
            }
            total += value;
        }
        assert(total == 6, "summed");
        return 0;
    }
```

Source: `runtime/hint/module.pep`

## likely

```pepper
likely(condition: bool): bool
```

Returns `condition`, telling the optimizer it is usually true, so the
code for the true case is laid out as the fast path (`llvm.expect`).

**Parameters**
- `condition` — the condition to test

**Returns**
- `condition`

**Example**
```pepper
    if (hint.likely(index < count)) {
        # the common case
    }
```

## unlikely

```pepper
unlikely(condition: bool): bool
```

Returns `condition`, telling the optimizer it is usually false, so the
code for the true case, such as error handling, is moved out of the
fast path (`llvm.expect`).

**Parameters**
- `condition` — the condition to test

**Returns**
- `condition`

**Example**
```pepper
    if (hint.unlikely(length > LIMIT)) {
        return error;
    }
```

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

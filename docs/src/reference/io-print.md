<!-- Generated from runtime/io/print.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Print

`Print`, deprecated: `Writer` gives `print` and `print_line` to every
stream.

Source: `runtime/io/print.pep`

## Print

```pepper
[Deprecated("use 'Writer' instead", "Writer")] trait Print
```

Deprecated: use `Writer` instead.

A byte stream that values can be printed to, as the global `print` prints
to standard output.

A type has the trait by providing `write_all(data: u8[])`; it then gets
`print` and `print_line`, which write the text `to_string` makes of a
value (the text `$"{value}"` would hold).

**Example**
```pepper
    import io;

    main(): int {
        var path = io.Directory.temp().join("report.txt");
        var file = io.File.create(path).value();
        file.print("total: ");
        file.print_line(42);
        file.close();
        assert(io.File.read_to_string(path).value() == "total: 42\n", "printed");
        io.File.remove(path);
        return 0;
    }
```

### Methods

#### write_all

```pepper
write_all(data: u8[]): IoResult<void>
```

Writes all of `data`.

**Parameters**
- `data` — the bytes to write

**Returns**
- an Ok result once every byte is written; an error when the stream fails

#### print

```pepper
print<T>(value: T): IoResult<void>
```

Writes the text of `value`, with no line break after it: a String as
it is, anything else through `to_string`.

**Type parameters**
- `T` — the type of `value`

**Parameters**
- `value` — the value to print

**Returns**
- an Ok result once the text is written; an error as for `write_all`

**Example**
```pepper
    file.print("n = ");
    file.print(3);   # the file now holds "n = 3"
```

#### print_line

```pepper
print_line<T>(value: T): IoResult<void>
```

Writes the text of `value` and a line break (`\n`), as the global
`print` does on standard output.

**Type parameters**
- `T` — the type of `value`

**Parameters**
- `value` — the value to print

**Returns**
- an Ok result once the line is written; an error as for `write_all`

**Example**
```pepper
    file.print_line($"total: {total}");
    file.print_line((1, "two"));   # (1, two)
```

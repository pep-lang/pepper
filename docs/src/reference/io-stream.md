<!-- Generated from runtime/io/stream.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Reader and Writer

`Reader` and `Writer`: the traits of byte streams, such as a `File`, a
`TcpStream`, a `UnixStream` or a `tls.TlsStream`, so code can read from
or write to any of them.

Source: `runtime/io/stream.pep`

## Reader

```pepper
trait Reader
```

A stream of bytes that can be read: a `File`, `TcpStream`, `UnixStream`
or `tls.TlsStream`, or any type with `read(buffer, max)`.

A type has the trait by providing `read`; it then gets `lines()` and
`chunks(size)`, which read the stream as a `for` loop asks for more.
Take a `Reader` (or `<R: Reader>`) to accept any stream.

**Example**
```pepper
    import io;

    count_lines(source: io.Reader): int {
        var count = 0;
        for (var line in source.lines()) {
            if (line.is_err()) {
                break;
            }
            count += 1;
        }
        return count;
    }
```

### Methods

#### read

```pepper
read(buffer: u8[], max: ulong): IoResult<ulong>
```

Waits until some bytes are available, then appends up to `max` of
them to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 at the end of the stream; an error when the stream fails

#### lines

```pepper
lines(): Lines
```

Returns an iterator over the rest of the stream's lines, read as it
goes, so a `for` loop handles a large file without reading it all.

Each element is an `IoResult<String>`: a line without its line ending
(`\n`, or `\r\n`). The last line counts even without a final line
ending, and a stream that ends with one has no empty line after it. A
read error, or a line that is not valid UTF-8 (`is_invalid_input()`),
is yielded as an error and ends the lines. The stream is read in
64 KiB chunks, so a file's position after the loop is not the end of
the last line returned.

**Returns**
- a new `Lines` positioned before the first line

**Example**
```pepper
    var f = File.open(Path("notes.txt")).value();
    for (var line in f.lines()) {
        print(line.value());
    }
```

#### chunks

```pepper
chunks(size: ulong): Chunks
```

Returns an iterator over the rest of the stream in chunks of at most
`size` bytes, each read as the loop asks for it.

Each element is an `IoResult<u8[]>`: a new array of what one `read`
returned, which may be fewer than `size` bytes (a socket returns what
has arrived). The iteration ends at the end of the stream; a read
error is yielded and ends it.

**Parameters**
- `size` — the most bytes in one chunk

**Returns**
- a new `Chunks` positioned before the first chunk

**Panics**
- if `size` is 0 ("Reader.chunks() needs a size above 0")

**Example**
```pepper
    var total = 0;
    for (var chunk in stream.chunks(4096)) {
        total += chunk.value().count;
    }
```

## Writer

```pepper
trait Writer
```

A stream of bytes that can be written: a `File`, `TcpStream`,
`UnixStream` or `tls.TlsStream`, or any type with `write` and
`write_all`.

A type has the trait by providing `write` and `write_all(data: u8[])`; it
then gets `print` and `print_line`, which write the text `to_string` makes
of a value (the text `$"{value}"` would hold).

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

#### write

```pepper
write(data: u8[]): IoResult<ulong>
```

Writes what the stream takes in one call, which may be less than all
of `data`.

**Parameters**
- `data` — the bytes to write

**Returns**
- the number of bytes written; an error when the stream fails

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

## Lines

```pepper
struct Lines
```

The iterator `Reader.lines()` returns: the lines of a stream, read in
chunks as the loop asks for them, each as an `IoResult<String>`.

**See also**
- `Reader.lines`

**Example**
```pepper
    var f = File.open(Path("notes.txt")).value();
    var it = f.lines();
    while (it.next()) {
        var line = it.current();
    }
```

### Constructor

#### Lines()

```pepper
construct(source: Reader)
```

Makes an iterator over the lines of `source`, from what it reads next.

**Parameters**
- `source` — the open stream to read

### Methods

#### next

```pepper
next(): bool
```

Reads the next line.

Once it returns false it keeps returning false.

**Returns**
- true if there is a current element (a line, or the error that ends the lines), false at the end of the stream

#### current

```pepper
current(): IoResult<String>
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current line, or the error that ended the lines

**Panics**
- if `next()` was never called, or already returned false ("Lines.current() without a line")

## Chunks

```pepper
struct Chunks
```

The iterator `Reader.chunks(size)` returns: the rest of a stream, one
`read` of at most `size` bytes at a time, each as an `IoResult<u8[]>`.

**See also**
- `Reader.chunks`

### Constructor

#### Chunks()

```pepper
construct(source: Reader, size: ulong)
```

Makes an iterator over `source` in chunks of at most `size` bytes.

**Parameters**
- `source` — the open stream to read
- `size` — the most bytes in one chunk

### Methods

#### next

```pepper
next(): bool
```

Reads the next chunk.

Once it returns false it keeps returning false.

**Returns**
- true if there is a current element (a chunk, or the error that ends the chunks), false at the end of the stream

#### current

```pepper
current(): IoResult<u8[]>
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current chunk, or the error that ended the chunks

**Panics**
- if `next()` was never called, or already returned false ("Chunks.current() without a chunk")

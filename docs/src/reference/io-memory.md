<!-- Generated from runtime/io/memory.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Streams in memory

`ByteReader` and `ByteWriter`: a `Reader` over bytes already in memory,
and a `Writer` that collects what is written into memory, for code that
takes a stream when the data is in an array.

Source: `runtime/io/memory.pep`

## ByteReader

```pepper
struct ByteReader
```

A `Reader` over an array of bytes: each `read` takes the next bytes of
the array, and the stream ends after its last byte.

The reader keeps a reference to the array and does not copy it; changing
the array while reading changes what is read.

**Example**
```pepper
import io;

var data = "one\ntwo\n".bytes();
var count = 0;
for (var line in io.ByteReader(data).lines()) {
    count += 1;
}
assert(count == 2, "two lines");
```

### Properties

#### remaining

```pepper
var remaining: ulong { get; }
```

The number of bytes not read yet.

### Constructor

#### ByteReader()

```pepper
construct(data: u8[])
```

Makes a reader positioned at the first byte of `data`.

**Parameters**
- `data` — the bytes to read

### Methods

#### read

```pepper
read(buffer: u8[], max: ulong): IoResult<ulong>
```

Appends up to `max` of the next bytes to `buffer`.

**Parameters**
- `buffer` — the array the bytes are appended to
- `max` — the most bytes to read

**Returns**
- the number of bytes appended, 0 once every byte has been read

## ByteWriter

```pepper
struct ByteWriter
```

A `Writer` that appends everything written to an array in memory,
`bytes`.

**Example**
```pepper
import io;

var out = io.ByteWriter();
out.print("n = ");
out.print_line(3);
assert(out.bytes == "n = 3\n".bytes(), "collected");
```

### Fields

#### bytes

```pepper
var bytes: u8[]
```

The bytes written so far, in order.

### Constructor

#### ByteWriter()

```pepper
construct()
```

Makes a writer with nothing written yet.

### Methods

#### write

```pepper
write(data: u8[]): IoResult<ulong>
```

Appends all of `data` to `bytes`.

**Parameters**
- `data` — the bytes to write

**Returns**
- the number of bytes written: always `data.count`

#### write_all

```pepper
write_all(data: u8[]): IoResult<void>
```

Appends all of `data` to `bytes`.

**Parameters**
- `data` — the bytes to write

**Returns**
- an Ok result; writing to memory does not fail

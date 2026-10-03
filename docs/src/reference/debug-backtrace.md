<!-- Generated from runtime/debug/backtrace.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Backtraces

Capturing the call stack (`capture`, `Backtrace`) and resolving it to
functions and source lines (`StackFrame`).

Capturing only records return addresses, so it is cheap enough to do
whenever something might need reporting later. The addresses are
resolved, from the program's symbol table and its debug info, only when
`Backtrace.frames()` or `to_string()` asks for them.

A function name needs the program's symbol table, which every build
keeps unless the executable is stripped. A file, line and column need
the debug info a `-g` build carries:

- **Linux:** the executable's ELF symbol table and DWARF line table.
- **macOS:** the executable's symbol table, and the DWARF line table of
  the `.dSYM` bundle a `-g` build writes beside it.
- **Windows:** DbgHelp, which reads the `.pdb` every build writes beside
  the executable: function names only, or with `-g` source lines too (no
  columns).
- **WASI:** a WebAssembly program cannot walk its stack, so a backtrace
  is empty.

Frames inside the runtime's own capture and panic code are left out, and
so are the C runtime's frames below `main`. A function the optimizer
inlined into its caller has no frame of its own.

Source: `runtime/debug/backtrace.pep`

## StackFrame

```pepper
struct StackFrame
```

One call on the stack: where it returns to, and the function and source
position that address belongs to.

**Example**
```pepper
import debug;

main(): int {
    var frame = debug.capture().frames()[0];
    assert(frame.function == "main", "the innermost frame is main");
    print(frame.to_string());   # main at main.pep:4:21 in a -g build
    return 0;
}
```

### Fields

#### address

```pepper
var address: ulong
```

The return address: the instruction the call returns to.

#### function

```pepper
var function: String
```

The function's name, such as `main` or `Point.length`; empty when the
program has no symbol for the address.

#### file

```pepper
var file: String
```

The source file, as it was named to the compiler; empty without debug
info.

#### line

```pepper
var line: int
```

The 1-based source line of the call; 0 without debug info.

#### column

```pepper
var column: int
```

The 1-based source column of the call; 0 when unknown.

### Constructor

#### StackFrame()

```pepper
construct(address: ulong = 0)
```

Creates a StackFrame for `address`, with no function or source
position yet.

**Parameters**
- `address` — the return address

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the frame as text: `function at file:line:column`, with the
parts that are unknown left out, and the address in hexadecimal when
the function is unknown.

**Returns**
- the frame as text

## Backtrace

```pepper
struct Backtrace
```

The call stack at the point `capture()` ran, as return addresses,
innermost first.

**Example**
```pepper
import debug;

main(): int {
    var trace = debug.capture();
    for (var frame in trace.frames()) {
        print(frame.to_string());
    }
    return 0;
}
```

### Fields

#### addresses

```pepper
var addresses: Array<ulong>
```

The return address of each call, innermost first, as captured: it
includes the frames of `capture` itself, which `frames()` leaves out.

### Constructor

#### Backtrace()

```pepper
construct()
```

Creates an empty Backtrace. Use `capture()` to record the stack.

### Methods

#### frames

```pepper
frames(): Array<StackFrame>
```

Resolves each return address to its function and source position.
Runs in time proportional to the program's symbol and line tables,
which it reads each call.

Leaves out the frames of `capture` and of the runtime's panic code at
the top, and the C runtime's frames below `main`.

**Returns**
- the frames, innermost first

#### to_string

```pepper
to_string(): String
```

Returns the frames as text, one per line, each numbered and indented
(`  0: main at main.pep:4:5`), with a newline after the last.

**Returns**
- the frames as text

## capture

```pepper
capture(): Backtrace
```

Records the call stack: the return address of every call that led here.
Cheap: the addresses are resolved only when `Backtrace.frames()` or
`to_string()` asks for them.

Records at most 128 calls, the innermost ones. On WASI the Backtrace is
empty.

**Returns**
- the stack, innermost call first

**Example**
```pepper
import debug;

main(): int {
    var trace = debug.capture();
    print(trace.to_string());
    return 0;
}
```

## print_backtrace

```pepper
print_backtrace()
```

Writes the current call stack to standard error, a line per frame, after
a `backtrace:` line: what a panic prints after its message.

A panic prints it in a build without `-O`. Set the `PEPPER_BACKTRACE`
environment variable to `1` to print it in an optimized build too, or to
`0` to never print it.

**Example**
```pepper
import debug;

main(): int {
    debug.print_backtrace();
    return 0;
}
```

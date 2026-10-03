# Debugging

Build with `-g` to debug a Pepper program in gdb, lldb, Visual Studio or
WinDbg. The compiler then describes the program to the debugger, which can:

- stop at a `file:line` breakpoint;
- step through the source one statement at a time;
- show a backtrace with the source line of every Pepper frame;
- print parameters, locals, module-scope variables and struct fields.

```bash
pepper build -g main.pep -o main        # Linux: DWARF in the executable
pepper build -g main.pep -o main        # macOS: DWARF, and main.dSYM beside it
pepper build -g main.pep -o main.exe    # Windows: CodeView, and main.pdb beside it
```

On macOS the linker leaves the DWARF in the object files, so `-g` also runs
`dsymutil` (from Xcode's command line tools) to gather it into
`main.dSYM`. lldb finds the bundle beside the program; so do the program's
own [backtraces](../language/debug.md), which read their source lines from
it. Without `dsymutil` the program still builds, and its backtraces name
functions but not lines.

`-g` and `-O` work together. Optimized code still steps and shows a
backtrace, and a call the optimizer inlined still appears as its own frame.
A variable the optimizer removed shows as optimized out.

## A session

This program builds an array of points and adds up the first one:

```pepper
{{#include ../../examples/debugging.pep}}
```

Stop on line 18, after `first` is assigned, and look around. In gdb:

```text
$ pepper build -g debugging.pep -o debugging
$ gdb ./debugging
(gdb) break debugging.pep:18
(gdb) run
Breakpoint 1, main () at debugging.pep:18
18	    return total(first) - 3;
(gdb) info locals
points = 0x5555555592f0
p = 0x5555555592c0
first = 0x5555555592c0
(gdb) print *first
$1 = {__refcount = 3, __weakcount = 1, x = 1, y = 2}
(gdb) step
total (p=0x5555555592c0) at debugging.pep:8
8	    return p.x + p.y;
(gdb) backtrace
#0  total (p=0x5555555592c0) at debugging.pep:8
#1  main () at debugging.pep:18
```

lldb takes the same steps with `b debugging.pep:18`, `r`, `frame variable`
and `bt`. In Visual Studio, open the executable as a project (File > Open >
Project/Solution), set a breakpoint in the source file and start debugging.
The `.pdb` beside the executable is found automatically.

## What the debugger sees

- **Functions** under the names you wrote: `total`, `Point.length`,
  `Array<int>.append`. Methods the compiler writes for a struct, such as
  `__acquire` and `__release`, are marked artificial and placed on the
  struct's line.
- **Structs.** A variable of a struct type holds a reference, so the
  debugger shows an address. Dereference it (`print *first`) to see the
  fields. The fields include the `__refcount` and `__weakcount` head, which
  helps when chasing an ownership bug.
- **Numbers** under their Pepper names (`int`, `ulong`, `u8`).
- **Enums.** A plain enum shows its case by name. An enum with payloads
  shows as a struct holding its tag, `__tag` (the case's position), and its
  payload fields, each named `Case__value` (`Value__value`), which a
  debugger expression can name: `print found.Value__value`. A value enum
  (`[Value]`, such as `Optional` and `Result`) is that struct itself,
  held inline, with no reference counts.
- **Tuples** as a struct with members `0`, `1`, and so on.
- **Trait values** as the object they refer to and its vtable.
- **Generics.** Each instantiation is its own type, such as `Array<long>`.
- **Module-scope variables** under their names.
- **`String`, `Array` and `Optional`** read naturally once the
  debugger loads Pepper's formatters (see below): a `String` as its text,
  an `Array` as its count and elements, an `Optional` as its case, `Empty`
  or `Value`, and its value. A `String` and an `Array` also show their
  reference counts as `[ref count]` (strong references) and `[weak count]`.

Not yet supported: an enum with payloads shows its tag and every payload
field, rather than the active case and its payload alone.

## Formatters for the runtime's types

The runtime ships formatters for each debugger in `runtime/debuggers/`.
The sessions below stop in a program holding `var name = "pepper";`, an
`Array<int>` `values` of 3 and 4, and `var found = Optional<int>.Value(7);`.

- **gdb.** On Linux a `-g` program carries `gdb_printers.py` in its
  `.debug_gdb_scripts` section. gdb loads it from directories on its
  auto-load safe path, so add the program's directory to it, on the command
  line or in `~/.gdbinit`:

  ```bash
  gdb -iex "add-auto-load-safe-path ." ./debugging
  ```

  ```text
  (gdb) print name
  $1 = "pepper" = {[ref count] = 1, [weak count] = 1}
  (gdb) print values
  $2 = Array<int> of count 2 = {[ref count] = 1, [weak count] = 1, [0] = 3, [1] = 4}
  (gdb) print found
  $3 = Value = {value = 7}
  ```

- **lldb.** Import `lldb_formatters.py`, once per session or in
  `~/.lldbinit`:

  ```text
  (lldb) command script import runtime/debuggers/lldb_formatters.py
  (lldb) frame variable name *values found
  (String *) name = 0x00005555555592c0 "pepper"
  (Array<int>) *values = count=2 {
    [ref count] = 1
    [weak count] = 1
    [0] = 3
    [1] = 4
  }
  (Optional<int>) found = Value {
    value = 7
  }
  ```

- **Visual Studio and WinDbg.** A `-g` program's `.pdb` carries
  `pepper.natvis`, so nothing needs loading.

## Building with `-g`

Debug info changes the code each file compiles to, so `-g` builds keep
their own objects in the build cache, apart from builds without it. With
`-g`, editing a file recompiles the files that import it, even when the edit
only moves a declaration: their code records the line numbers of the
generics they instantiate from it.

## Backtraces without a debugger

A program can print its own stack: a panic does in a build without `-O`,
and the `debug` module's `capture()` and `print_backtrace()` do on request.
`debug.output`, `debug.is_debugger_attached` and `debug.breakpoint` talk to
an attached debugger. See [Backtraces and the debugger](../language/debug.md).

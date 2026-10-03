# Backtraces and the debugger

The `debug` module walks the call stack and talks to a debugger. Bring it in
with `import debug`.

| Function | Does |
|---|---|
| `debug.capture()` | Records the call stack as a `Backtrace`: the return address of each call, innermost first. |
| `trace.frames()` | Resolves the addresses to `StackFrame`s: `function`, `file`, `line`, `column` and `address`. |
| `debug.print_backtrace()` | Writes the current stack to standard error, as a panic does. |
| `debug.output(text)` | Writes to the platform's debugger channel. |
| `debug.is_debugger_attached()` | Whether a debugger is attached. |
| `debug.breakpoint()` | Stops in the debugger, as a breakpoint on that line would. |

```pepper
{{#include ../../examples/debug-backtrace.pep}}
```

Built with `-g`, this prints:

```text
Parser.where at debug-backtrace.pep:13:16
main at debug-backtrace.pep:19:24
done
```

## Capturing is cheap; resolving is not

`capture()` only records addresses, so a program can capture a stack
whenever it might want to report one later, such as when it creates an error
value. The work happens in `frames()` and `to_string()`, which read the
program's symbol table and line table each time they are called.

A function name needs the program's symbol table, which every build keeps
unless the executable is stripped. A file, line and column need the debug
info a `-g` build carries:

| Platform | Function names | Source lines |
|---|---|---|
| Linux | The executable's ELF symbol table | Its DWARF line table |
| macOS | The executable's symbol table | The `.dSYM` bundle a `-g` build writes beside the executable (with `dsymutil`, from Xcode's command line tools) |
| Windows | DbgHelp, from the `.pdb` every build writes beside the executable | DbgHelp, from the `.pdb` of a `-g` build (no columns) |
| WASI | none | none |

A WebAssembly program cannot walk its own stack, so on WASI a backtrace is
empty. A function the optimizer inlined into its caller has no frame of its
own: with `-O`, the caller's frame shows the inlined code's line instead.

`frames()` leaves out the frames of `capture` itself and of the runtime's
panic code at the top of the stack, and the C runtime's frames below `main`.

## Backtraces on panic

A [panic](functions.md#assertions-and-panics) prints the stack after its
message in a build without `-O`:

```text
main.pep:3:9: panic: index out of range
backtrace:
  0: inner at main.pep:3:9
  1: main at main.pep:8:12
```

An optimized build prints the message alone. The `PEPPER_BACKTRACE`
environment variable overrides the build: `PEPPER_BACKTRACE=1` prints a
backtrace in any build, and `PEPPER_BACKTRACE=0` never prints one. Without
`-g`, each frame shows its function but no file or line.

Only the first panic in a process prints a backtrace. If a second thread
panics at the same time, it prints just its message.

## The debugger channel

`debug.output(text)` writes a line where a debugger shows it:

- **Windows:** `OutputDebugStringW`. Visual Studio's Output window and
  WinDbg show it, and so does DebugView when no debugger is attached. It
  goes nowhere else.
- **Linux, macOS and WASI:** standard error. These systems have no separate
  channel, and debuggers show the program's own output.

`debug.is_debugger_attached()` reads `TracerPid` in `/proc/self/status` on
Linux, `P_TRACED` on macOS, and `IsDebuggerPresent` on Windows. It is always
false on WASI.

`debug.breakpoint()` executes the processor's debug trap. A debugger stops
there and can continue the program. With no debugger attached, the trap
ends the program, so guard it:

```pepper
if (debug.is_debugger_attached()) {
    debug.breakpoint();
}
```

`break` is a keyword, so the function is called `breakpoint`.

See [Debugging](../tools/debugging.md) for running a program under gdb,
lldb or Visual Studio.

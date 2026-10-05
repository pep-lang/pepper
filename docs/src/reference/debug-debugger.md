<!-- Generated from runtime/debug/debugger.pep by `pep-doc reference`. Do not edit. -->

# The debugger

Talking to a debugger: `output()` writes to the platform's debugger
channel, `is_debugger_attached()` asks whether a debugger is watching,
and `breakpoint()` stops in it.

Source: `runtime/debug/debugger.pep`

## output

```pepper
output(text: String)
```

Writes `text` to the platform's debugger channel, followed by a newline
when it does not end in one.

- **Windows:** `OutputDebugStringW`, which Visual Studio's Output window
  and WinDbg show (and DebugView, with no debugger attached). Nothing is
  written anywhere else.
- **Linux, macOS and WASI:** standard error, which debuggers show; these
  systems have no separate channel.

**Parameters**
- `text` — the text to write

**Example**
```pepper
import debug;

main(): int {
    debug.output("starting");
    return 0;
}
```

## is_debugger_attached

```pepper
is_debugger_attached(): bool
```

Returns whether a debugger is attached to the program: the `TracerPid`
of `/proc/self/status` on Linux, `P_TRACED` on macOS, and
`IsDebuggerPresent` on Windows. Always false on WASI.

**Returns**
- true while a debugger is attached

**Example**
```pepper
import debug;

main(): int {
    if (debug.is_debugger_attached()) {
        debug.output("hello, debugger");
    }
    return 0;
}
```

## breakpoint

```pepper
breakpoint()
```

Stops in the debugger, as a breakpoint set on this line would: the
processor's debug trap (`int3` on x64, `brk` on AArch64), through
`llvm.debugtrap`. The debugger can then continue the program.

With no debugger attached the trap ends the program: SIGTRAP on Linux
and macOS, a breakpoint exception on Windows. Guard it with
`is_debugger_attached()` to stop only under a debugger. Does nothing on
WASI.

**Example**
```pepper
import debug;

main(): int {
    if (debug.is_debugger_attached()) {
        debug.breakpoint();
    }
    return 0;
}
```

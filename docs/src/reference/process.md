<!-- Generated from runtime/process.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Arguments and exit

The running program: its command-line arguments and how it ends.

Source: `runtime/process.pep`

## arguments

```pepper
arguments(): Array<String>
```

Returns the program's command-line arguments.

Element 0 is the program as it was started (usually its path), and the
arguments typed after it follow in order, as the shell passed them: a
quoted argument with spaces is one element. Each call builds a new array.

On Windows the arguments are in the process's ANSI code page, so text
outside it is not preserved.

`main` receives the same array when it is declared
`main(args: String[]): int`; `arguments()` reads it anywhere else.

**Returns**
- the program name followed by its arguments

**Example**
```pepper
    verbose(): bool {
        for (var argument in arguments()) {
            if (argument == "-v") {
                return true;
            }
        }
        return false;
    }
```

## exit

```pepper
exit(code: int)
```

Ends the program at once with status `code`.

Flushes standard output and every other C output stream first, so text
printed so far is not lost. Nothing else runs: locals are not released,
destructors do not run, and other threads stop where they are. Returning
from `main` is the usual way to end; `exit` is for ending from deep inside
a call.

**Parameters**
- `code` — the exit status: 0 for success, anything else for failure (only its low 8 bits reach a POSIX parent)

**Example**
```pepper
    if (arguments().count() < 2) {
        print("usage: tool FILE");
        exit(2);
    }
```

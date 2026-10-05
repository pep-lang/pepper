<!-- Generated from runtime/process/child.pep by `pep-doc reference`. Do not edit. -->

# Child

A running child process (`Child`), the pipes to it, and how it ended
(`ExitStatus`).

Source: `runtime/process/child.pep`

## ExitStatus

```pepper
struct ExitStatus
```

How a child process ended: with an exit code, or (on POSIX) killed by a
signal.

**Example**
```pepper
var status = process.Command("false").run().value().status;
assert(!status.success(), "false fails");
assert(status.code().value() == 1, "with code 1");
```

### Constructor

#### ExitStatus()

```pepper
construct(code: int = 0, signal: int = 0)
```

Creates an ExitStatus.

**Parameters**
- `code` — the exit code, when the process exited
- `signal` — the signal that ended the process, or 0 when it exited

### Methods

#### success

```pepper
success(): bool
```

Returns whether the process exited with code 0.

**Returns**
- true for exit code 0

#### code

```pepper
code(): int?
```

Returns the exit code: the value the process passed to `exit` or
returned from `main`. On POSIX only its low 8 bits reach the parent,
so it is from 0 to 255; on Windows it is the whole 32-bit code (an
unhandled exception gives an `NTSTATUS` such as `0xC0000005`, a
negative number here).

**Returns**
- the exit code, or none when a signal ended the process

#### signal

```pepper
signal(): int?
```

Returns the signal that ended the process (POSIX only; a Windows
process always has an exit code).

**Returns**
- the signal number, such as 9 for `SIGKILL`, or none when the process exited

#### to_string

```pepper
to_string(): String
```

Returns how the process ended as text.

**Returns**
- `exit code N` or `signal N`

## Child

```pepper
[NotCopyable("owns a child process handle and cannot be copied")] struct Child
```

A child process started by `Command.spawn()`: its id, the pipes to the
streams that were piped, and its exit status once it ends.

Wait for every child with `wait()` (or until `try_wait()` returns a
status): on POSIX a child that ended but was never waited for stays in
the process table until the parent ends. Releasing the last reference to
a Child neither waits for it nor kills it; the process runs on.

**Example**
```pepper
import process;

main(): int {
    var child = process.Command("sleep").argument("10").spawn().value();
    child.kill();
    var status = child.wait().value();
    assert(!status.success(), "killed");
    return 0;
}
```

### Constructor

#### Child()

```pepper
construct()
```

Creates a Child that stands for no process: `id()` is 0, its streams
are closed, and `wait()`, `try_wait()` and `kill()` fail. Use
`Command.spawn()` to start one.

### Methods

#### id

```pepper
id(): ulong
```

Returns the child's process id, as the operating system knows it.
After the child has been waited for, the system may give the id to a
new process.

**Returns**
- the process id

#### stdin

```pepper
stdin(): io.File
```

Returns the pipe to the child's standard input, for writing. Close it
when done (`close()`), so that a child reading to the end sees the
end.

**Returns**
- the pipe, or a closed File when standard input was not `Stream.Pipe`

#### stdout

```pepper
stdout(): io.File
```

Returns the pipe from the child's standard output, for reading. A read
returns 0 once the child has ended (or closed its standard output) and
everything it wrote has been read.

**Returns**
- the pipe, or a closed File when standard output was not `Stream.Pipe`

#### stderr

```pepper
stderr(): io.File
```

Returns the pipe from the child's standard error, for reading.

**Returns**
- the pipe, or a closed File when standard error was not `Stream.Pipe`

#### wait

```pepper
wait(): io.IoResult<ExitStatus>
```

Waits for the child to end and returns how it ended. Standard input,
when piped, is closed first, so a child reading it to the end can
finish. Waiting again returns the same status.

In a task, the wait parks the task (it runs on a `run_blocking`
thread) rather than blocking its worker. Read piped output before
waiting: a child stalls when a pipe it writes to is full.

**Returns**
- the exit status, or an error from the system

#### try_wait

```pepper
try_wait(): io.IoResult<ExitStatus?>
```

Returns how the child ended if it has, without waiting.

**Returns**
- the exit status, or none while the child runs; or an error from the system

#### kill

```pepper
kill(): io.IoResult<void>
```

Ends the child at once: `SIGKILL` on POSIX, `TerminateProcess` (with
exit code 1) on Windows. The child still has to be waited for. Killing
a child that has already been waited for does nothing.

**Returns**
- Ok, or an error from the system

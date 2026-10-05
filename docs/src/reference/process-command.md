<!-- Generated from runtime/process/command.pep by `pep-doc reference`. Do not edit. -->

# Command

Starting a program: `Command` names it and its arguments, environment,
working directory and standard streams; `spawn()` starts it and `run()`
also waits for it and collects what it wrote.

Source: `runtime/process/command.pep`

## Stream

```pepper
enum Stream
```

Where a child's standard input, output or error goes (see
`Command.stdin`, `Command.stdout` and `Command.stderr`).

### Cases

#### Inherit

```pepper
Inherit
```

The child shares the parent's stream: it reads the parent's input,
or writes where the parent writes.

#### Pipe

```pepper
Pipe
```

A pipe connects the stream to the parent, which reaches it through
`Child.stdin()`, `Child.stdout()` or `Child.stderr()`.

#### Null

```pepper
Null
```

The stream is the null device: reading it finds the end at once, and
what is written to it is thrown away.

## Output

```pepper
struct Output
```

What a program `Command.run()` waited for left behind: how it ended and
what it wrote.

### Fields

#### status

```pepper
var status: ExitStatus
```

How the program ended.

#### stdout

```pepper
var stdout: String
```

Everything the program wrote to standard output, decoded as UTF-8
(each byte sequence that is not valid UTF-8 becomes U+FFFD); empty
when standard output was not piped.

#### stderr

```pepper
var stderr: String
```

Everything the program wrote to standard error, decoded the same
way; empty when standard error was not piped.

### Constructor

#### Output()

```pepper
construct(status: ExitStatus, stdout: String, stderr: String)
```

Creates an Output from its parts.

**Parameters**
- `status` — how the program ended
- `stdout` — what it wrote to standard output
- `stderr` — what it wrote to standard error

## Command

```pepper
struct Command
```

Describes a program to start: the program, its arguments, its
environment, its working directory, and where its standard streams go.

A builder in the style of Rust's `std::process::Command`: each setter
stores its value and returns this same Command, so calls chain, and one
Command can start the program any number of times.

The program is found the way a shell finds it: a name with no path
separator is searched for on the `PATH` (on Windows, also in the
directory of the running program and the system directories, and `.exe`
is added when the name has no extension); anything else is a path,
relative to the parent's current directory.

The child inherits the parent's environment, changed by `environment`,
`remove_environment` and `clear_environment`. By default it also
inherits the parent's current directory and its three standard streams;
`run()` instead pipes standard output and error, and gives standard
input the null device, unless they were set.

**Example**
```pepper
import process;

main(): int {
    var output = process.Command("clang").arguments(["--version"]).run().value();
    if (!output.status.success()) {
        print(output.stderr);
        return 1;
    }
    return 0;
}
```

### Fields

#### program

```pepper
var program: String
```

The program to start, as given to the constructor.

### Constructor

#### Command()

```pepper
construct(program: String)
```

Creates a Command that starts `program` with no arguments, the
parent's environment and current directory, and inherited streams.

**Parameters**
- `program` — the program: a name to search for on the `PATH`, or a path

### Methods

#### argument

```pepper
argument(value: String): Command
```

Adds one argument after those already added. It reaches the program
as one element of its arguments, whatever it holds: no shell splits
or expands it. On Windows, where a program receives one command line,
it is quoted so that the C runtime splits it back out as it was.

**Parameters**
- `value` — the argument

**Returns**
- this Command

#### arguments

```pepper
arguments(values: Array<String>): Command
```

Adds each of `values` as an argument, in order.

**Parameters**
- `values` — the arguments

**Returns**
- this Command

#### environment

```pepper
environment(name: String, value: String): Command
```

Sets the environment variable `name` to `value` for the child,
replacing any value it would inherit. On Windows, names are compared
without regard to case.

**Parameters**
- `name` — the variable's name
- `value` — its value

**Returns**
- this Command

#### remove_environment

```pepper
remove_environment(name: String): Command
```

Leaves the environment variable `name` out of the child's
environment, including a value an earlier `environment` set.

**Parameters**
- `name` — the variable's name

**Returns**
- this Command

#### clear_environment

```pepper
clear_environment(): Command
```

Starts the child with an empty environment, dropping every variable
the parent has and every change made so far; later calls to
`environment` add to it.

**Returns**
- this Command

#### working_directory

```pepper
working_directory(path: io.Path): Command
```

Starts the child in `path` instead of the parent's current directory.
A relative program path is still resolved against the parent's
current directory.

**Parameters**
- `path` — the child's current directory

**Returns**
- this Command

#### stdin

```pepper
stdin(stream: Stream): Command
```

Sets where the child's standard input comes from.

**Parameters**
- `stream` — `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`

**Returns**
- this Command

#### stdout

```pepper
stdout(stream: Stream): Command
```

Sets where the child's standard output goes.

**Parameters**
- `stream` — `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`

**Returns**
- this Command

#### stderr

```pepper
stderr(stream: Stream): Command
```

Sets where the child's standard error goes.

**Parameters**
- `stream` — `Stream.Inherit`, `Stream.Pipe` or `Stream.Null`

**Returns**
- this Command

#### spawn

```pepper
spawn(): io.IoResult<Child>
```

Starts the program and returns at once, without waiting for it.

Each stream that was not set is inherited. A piped stream is reached
through the Child; close a piped standard input when done writing, or
a child that reads to the end never finishes. Wait for the child with
`Child.wait()`: a child that is never waited for stays in the process
table until the parent ends.

**Returns**
- the running child; an error when the program cannot be started: `is_not_found()` when it is not found, `is_permission_denied()` when it is not executable, or another platform error

**Example**
```pepper
var child = process.Command("sort").stdin(process.Stream.Pipe).stdout(process.Stream.Pipe).spawn().value();
child.stdin().write_all("pear\napple\n");
child.stdin().close();
var sorted = child.stdout().read_string().value();   # "apple\npear\n"
child.wait();
```

#### run

```pepper
run(): io.IoResult<Output>
```

Starts the program, waits for it to end, and returns how it ended
with what it wrote.

Standard output and error are piped and collected unless they were
set, and standard input is the null device unless it was set. Both
outputs are read at once, so a child that fills one pipe while the
parent reads the other does not stall. In a task, the reads and the
wait park the task rather than blocking its worker.

**Returns**
- the exit status and output; an error when the program cannot be started (as for `spawn()`) or its output cannot be read

**Example**
```pepper
var output = process.Command("echo").argument("hello").run().value();
assert(output.status.success(), "echo succeeds");
assert(output.stdout == "hello\n", "and prints its argument");
```

#### exec

```pepper
exec(): io.IoError
```

Replaces the running program with this one, as a shell's `exec`
does: the program receives this process's signals, and its exit
status becomes this process's own. A launcher that only hands its
command line on to another program, such as `pepper`, ends this way.

On POSIX the program takes over this process (`execvp`): it keeps
the process id, the standard streams and every other descriptor not
marked close-on-exec, and nothing after the call runs. Windows cannot
replace a process, so there the program is started with the standard
streams inherited and waited for, and this process then ends with its
exit status, as `process.exit` does. While it waits, this process
ignores Ctrl-C and Ctrl-Break, which the program, sharing the
console, receives and handles itself.

Output `print` has buffered is flushed first. The standard streams
must be left inherited: no process remains to hold a pipe's other
end. When the call fails, the process carries on unchanged, in its
own working directory.

**Returns**
- only when the program cannot be started: why, as for `spawn()`, or an error with `is_invalid_input()` when a standard stream was set to something other than `Stream.Inherit`

**Example**
```pepper
import process;

main(args: String[]): int {
    # Run git with this program's arguments, as if it were git.
    var git = process.Command("git");
    ulong index = 1;
    while (index < args.count) {
        git.argument(args[index]);
        index += 1;
    }
    var error = git.exec();
    print($"cannot run git: {error.message}");
    return 1;
}
```

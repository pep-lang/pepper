# Processes

The `process` module starts other programs and holds what belongs to the
running one: its arguments, its exit, its id, its executable, and its working
directory. Bring it in with `import process`.

## Running a program

`Command` describes a program to start. Its setters return the same
`Command`, so they chain. `run()` starts the program, waits for it to end,
and returns an `Output`: the `status` it ended with, and the text it wrote to
`stdout` and `stderr`.

```pepper
{{#include ../../examples/processes-run.pep}}
```

- The program is found the way a shell finds it. A bare name is searched for
  on the `PATH` (on Windows, also next to the running program and in the
  system directories, with `.exe` added when the name has no extension).
  Anything with a path separator is a path.
- Each `argument` reaches the program as one argument, whatever it holds. No
  shell splits it or expands `*` or `$NAME`. On Windows, where a program
  receives a single command line, each argument is quoted so that the C
  runtime splits it back out as it was.
- `run()` collects standard output and error, both at once, so a child that
  fills one pipe while the parent reads the other does not stall. Standard
  input is the null device unless it was set. The output is decoded as UTF-8,
  with each invalid byte sequence replaced by U+FFFD; read a child's binary
  output from a pipe with `spawn()` instead.
- A program that cannot be started is an error (`is_not_found()` when it does
  not exist). A program that runs and fails is a successful result whose
  `status` says so.

## Exit status

`ExitStatus.success()` is true for exit code 0. `code()` returns the exit
code, and `signal()` the POSIX signal that ended the process (such as 9 for
`SIGKILL`). Each is an optional: a process killed by a signal has no exit
code, and a process that exited has no signal. Windows has no signals, so
there every process has a code; a POSIX parent sees only the low 8 bits of
it.

## Talking to a child

`spawn()` starts the program and returns a `Child` at once. Each of the three
standard streams is `Stream.Inherit` (shared with the parent, the default),
`Stream.Pipe` (connected to the parent), or `Stream.Null`. A piped stream is
an `io.File` from `child.stdin()`, `child.stdout()` or `child.stderr()`, so
the [file](../reference/io-file.md) read and write methods apply.

```pepper
{{#include ../../examples/processes-spawn.pep}}
```

- Close a piped standard input when you are done writing, or a child that
  reads to the end never finishes. `wait()` closes it too, before waiting.
- Read piped output before waiting. A child that fills a pipe stops until the
  parent reads it, so waiting first can wait forever.
- `wait()` returns the exit status, and again on later calls. `try_wait()`
  returns none while the child runs. `kill()` ends the child at once
  (`SIGKILL`, or `TerminateProcess` on Windows); wait for it afterwards.
- Wait for every child. On POSIX a child that ended stays in the process
  table until it is waited for. Releasing a `Child` neither waits for it nor
  kills it.

In a [task](tasks.md), `run()`, `wait()` and reads from a pipe park the task
rather than block its worker, so other tasks keep running.

## Environment and working directory

A child inherits the parent's environment. `environment(name, value)` sets a
variable for the child, `remove_environment(name)` leaves one out, and
`clear_environment()` starts from an empty environment. On Windows, names
ignore case. `working_directory(path)` starts the child in another
directory. The running process reads its own environment with
`os.environment(name)` (see [The operating system](os.md)).

```pepper
{{#include ../../examples/processes-environment.pep}}
```

## The running process

- `process.arguments()` returns the program's command-line arguments, the
  same array `main(args: String[])` receives (see
  [Functions](functions.md#command-line-arguments-and-exit)).
- `process.exit(code)` ends the program at once with status `code`.
- `process.id()` is the process's id.
- `process.executable_path()` is the absolute path of the running program's
  executable, so a tool can find files installed next to it.
- `process.working_directory()` and `process.change_working_directory(path)`
  read and change the directory relative paths are resolved against, as
  `io.Directory.current()` and `io.Directory.set_current(path)` do.

`arguments()` and `exit()` without `import process` still work, but are
deprecated and warn.

See the [process module reference](../reference/process-module.md).

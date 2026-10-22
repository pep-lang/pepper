<!-- Generated from runtime/process/current.pep by `pep-doc reference`. Do not edit. -->

# The running process

The running process: its arguments, id, executable and working
directory, and how it ends.

Two functions are listed only here, since the module exports them under
names the deprecated prelude functions still hold:

- `arguments(): Array<String>` returns the program's command-line
  arguments: element 0 is the program as it was started, and the
  arguments typed after it follow in order. `main` receives the same array
  when it is declared `main(args: String[]): int`. On Windows they are
  read as UTF-16 and converted to valid UTF-8.
- `exit(code: int)` ends the program at once with status `code` (only its
  low 8 bits reach a POSIX parent), as C's `exit` does: the handlers
  registered with C's `atexit` run, then standard output and the other C
  output streams are flushed. Locals are not released and destructors do
  not run; other threads keep running while the handlers run. In a copy
  `fork()` started, the handlers, which are the parent's, are skipped.

Source: `runtime/process/current.pep`

## fork

```pepper
fork(): io.IoResult<Child?>
```

Starts a copy of the running process (POSIX `fork`): the copy has the
same memory, open files and code, and both go on from here. In the
parent, returns the copy as a `Child` to wait for; in the copy, returns
none. The copy has only the calling thread, so fork before starting
threads or tasks, and end the copy with `exit()`, which there skips the
parent's `atexit` handlers.

The C standard streams are flushed first, so what `print` buffered is
written once. Not on Windows or WASI, which start processes only from a
program: there it returns an error.

**Returns**
- the child in the parent, none in the copy, or an error

**Example**
```pepper
import process;

main(): int {
    var forked = process.fork();
    if (forked.is_err()) {
        return 0;
    }
    if (!forked.value().is_value()) {
        process.exit(3);
    }
    var status = forked.value().value().wait().value();
    return status.code().value() == 3 ? 0 : 1;
}
```

## id

```pepper
id(): ulong
```

Returns the running process's id, as the operating system knows it.

**Returns**
- the process id (`getpid` on POSIX, `GetCurrentProcessId` on Windows)

## executable_path

```pepper
executable_path(): io.IoResult<io.Path>
```

Returns the path of the running program's executable file, as an
absolute path with symbolic links resolved (on Linux the target of
`/proc/self/exe`; on macOS `_NSGetExecutablePath`, resolved; on Windows
`GetModuleFileNameW`). A tool installed alongside others finds them
next to it with `executable_path().value().parent()`.

**Returns**
- the executable's path, or an error when the system cannot report it

**Example**
```pepper
import process;

main(): int {
    var path = process.executable_path().value();
    print(path.to_string());
    return 0;
}
```

## working_directory

```pepper
working_directory(): io.IoResult<io.Path>
```

Returns the process's current directory, against which relative paths
are resolved. The same as `io.Directory.current()`.

**Returns**
- the current directory as an absolute path; an error when it cannot be determined, such as `is_not_found()` on POSIX when the directory has been removed

## change_working_directory

```pepper
change_working_directory(path: io.Path): io.IoResult<void>
```

Changes the process's current directory. This affects the whole
process, every thread included. The same as `io.Directory.set_current`.

**Parameters**
- `path` — the new current directory; a relative path is resolved against the old one

**Returns**
- an Ok result; an error when the directory cannot be entered: `is_not_found()` when it is missing, `is_not_a_directory()` when it is a file, or `is_permission_denied()`

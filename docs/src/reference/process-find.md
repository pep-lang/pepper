<!-- Generated from runtime/process/find.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Finding programs

Finding programs: `find_executable` looks a program up on the `PATH`, as
a shell does before running it, `find_companion` looks beside the running
program first, and `is_executable` tells whether a file can be run.

Source: `runtime/process/find.pep`

## find_executable

```pepper
find_executable(name: String): io.Path?
```

Returns the program `name` would run as a command: the first file named
`name` in the directories `PATH` lists, in order, that this process may
run. A `name` that holds a path separator is not looked up: it is
returned when it names such a file itself. On Windows, a `name` with no
extension also matches `name.exe`.

**Parameters**
- `name` — the program's file name, such as `"perf"`

**Returns**
- the program's path, or none when no directory on the `PATH` holds it

**Example**
```pepper
import process;

main(): int {
    var git = process.find_executable("git");
    print(git.is_value() ? git.value().to_string() : "git is not installed");
    return 0;
}
```

## is_executable

```pepper
is_executable(path: io.Path): bool
```

Returns whether `path` is a file this process may run: on Linux and
macOS, a file with an execute permission bit set; on Windows, any file.

**Parameters**
- `path` — the file to check

**Returns**
- true when `path` names a file that may be run

## find_companion

```pepper
find_companion(name: String): io.Path?
```

Returns the program `name` installed beside the running one, else the
one `find_executable` finds on the `PATH`: how a tool finds the other
tools of its suite, as `pep-test` finds `pep-build`. On Windows, `.exe`
is added to `name` when looking beside the running program.

**Parameters**
- `name` — the program's file name, such as `"pep-build"`

**Returns**
- the program's path, or none when neither place holds it

**Example**
```pepper
import process;

main(): int {
    var compiler = process.find_companion("pep-build");
    print(compiler.is_value() ? compiler.value().to_string() : "pep-build is not installed");
    return 0;
}
```

<!-- Generated from runtime/os/environment.pep by `pep-doc reference`. Do not edit. -->

# Environment

The running process's environment variables.

`os` only reads them. Changing the process's own environment is not
thread-safe on POSIX (`setenv` races with every `getenv`), so a child
process gets a different environment through `process.Command`'s
`environment`, `remove_environment` and `clear_environment` instead.

Source: `runtime/os/environment.pep`

## environment

```pepper
environment(name: String): String?
```

Returns the value of the environment variable `name`, or none when it is
not set.

A variable set to the empty string is some empty String, not none. On
Windows names are not case-sensitive (`Path` finds `PATH`), and values
are read as UTF-16 and converted to UTF-8, so text outside the ANSI code
page survives.

**Parameters**
- `name` — the variable's name

**Returns**
- its value, or none when it is not set

**Example**
```pepper
import os;

main(): int {
    var home = os.environment("HOME");
    if (home) {
        print(home.value());
    }
    return 0;
}
```

## environment_variables

```pepper
environment_variables(): HashMap<String, String>
```

Returns every environment variable of the running process, by name.

The map has no order. On Windows it includes the variables whose names
start with `=`, such as `=C:`, which `cmd.exe` uses for each drive's
current directory; its keys keep the case the system reports, so look a
name up with `environment(name)` to ignore case. When a POSIX
environment holds one name twice, the first value wins, as `getenv`
returns it.

**Returns**
- a new map from each variable's name to its value

**Example**
```pepper
import os;

main(): int {
    for (var (name, value) in os.environment_variables()) {
        print($"{name}={value}");
    }
    return 0;
}
```

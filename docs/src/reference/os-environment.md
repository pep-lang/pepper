<!-- Generated from runtime/os/environment.pep by `pep-doc reference`. Do not edit. -->

# Environment

The running process's environment variables: reading them, and setting
and removing them for the process itself.

Every read and change the runtime makes goes through one lock, so Pepper
code never races with itself over the environment, on any thread. C code
that calls `getenv` itself is outside that lock: on POSIX `setenv` races
with such a call on another thread, as in every language. To give only a
child process a different environment, use `process.Command`'s
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

## set_environment

```pepper
set_environment(name: String, value: String)
```

Sets the environment variable `name` to `value` for the running process,
replacing any value it had.

The process's own later reads see the change, and so do the children it
starts afterwards. Safe from any thread for Pepper code; C code that calls
`getenv` on another thread at the same time can race with it on POSIX
(see this page's introduction). On Windows names are not case-sensitive.
WASI keeps the change inside the program.

**Parameters**
- `name` — the variable's name
- `value` — its new value; may be empty

**Panics**
- if `name` is empty or contains `=` or a NUL byte, or `value` contains a NUL byte

**Example**
```pepper
import os;

main(): int {
    os.set_environment("GREETING", "hello");
    print(os.environment("GREETING").value());   # hello
    return 0;
}
```

## remove_environment

```pepper
remove_environment(name: String)
```

Removes the environment variable `name` from the running process.

Removing a variable that is not set does nothing. The same thread-safety
note as `set_environment`'s applies.

**Parameters**
- `name` — the variable's name

**Panics**
- if `name` is empty or contains `=` or a NUL byte

**Example**
```pepper
import os;

main(): int {
    os.remove_environment("GREETING");
    print(os.environment("GREETING").is_empty());   # true
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

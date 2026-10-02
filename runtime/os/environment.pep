## The running process's environment variables.
##
## `os` only reads them. Changing the process's own environment is not
## thread-safe on POSIX (`setenv` races with every `getenv`), so a child
## process gets a different environment through `process.Command`'s
## `environment`, `remove_environment` and `clear_environment` instead.

import "sys_posix";
import "sys_wasi";
import "sys_windows";

## Returns the value of the environment variable `name`, or none when it is
## not set.
##
## A variable set to the empty string is some empty String, not none. On
## Windows names are not case-sensitive (`Path` finds `PATH`), and values
## are read as UTF-16 and converted to UTF-8, so text outside the ANSI code
## page survives.
##
## @param name the variable's name
## @returns its value, or none when it is not set
## @example
##     import os;
##
##     main(): int {
##         var home = os.environment("HOME");
##         if (home) {
##             print(home.value());
##         }
##         return 0;
##     }
export environment(name: String): String? {
    if (name.is_empty) {
        return Optional<String>.Empty;
    }
    return _os_sys_environment(name);
}

## Returns every environment variable of the running process, by name.
##
## The map has no order. On Windows it includes the variables whose names
## start with `=`, such as `=C:`, which `cmd.exe` uses for each drive's
## current directory; its keys keep the case the system reports, so look a
## name up with `environment(name)` to ignore case. When a POSIX
## environment holds one name twice, the first value wins, as `getenv`
## returns it.
##
## @returns a new map from each variable's name to its value
## @example
##     import os;
##
##     main(): int {
##         for (var (name, value) in os.environment_variables()) {
##             print($"{name}={value}");
##         }
##         return 0;
##     }
export environment_variables(): HashMap<String, String> {
    var variables = HashMap<String, String>();
    for (var entry in _os_environment_entries()) {
        # Search the bytes, not with `find`: a POSIX value need not be valid
        # UTF-8. The search starts at 1, past a Windows name's leading '='.
        ulong at = 1;
        while (at < entry.size && entry.byte_at(at) != '=') {
            at = at + 1;
        }
        if (at >= entry.size) {
            continue;
        }
        __ptr<char> data = entry.c_str();
        var name = String(data, at);
        if (!variables.contains(name)) {
            # A zero size measures to the terminating NUL: the value's end.
            variables.insert(name, String(data + at + 1));
        }
    }
    return variables;
}

# The environment as `NAME=VALUE` entries, for the process module too.
export _os_environment_entries(): Array<String> {
    return _os_sys_environment_entries();
}

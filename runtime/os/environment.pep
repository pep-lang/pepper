## The running process's environment variables: reading them, and setting
## and removing them for the process itself.
##
## Every read and change the runtime makes goes through one lock, so Pepper
## code never races with itself over the environment, on any thread. C code
## that calls `getenv` itself is outside that lock: on POSIX `setenv` races
## with such a call on another thread, as in every language. To give only a
## child process a different environment, use `process.Command`'s
## `environment`, `remove_environment` and `clear_environment` instead.

import async;
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
    var value = Optional<String>.Empty;
    with (var held = _os_environment_lock.lock()) {
        value = _os_sys_environment(name);
    }
    return value;
}

## Returns whether the environment variable `name` turns a switch on: it is
## set to anything but the empty string or `0`, as `PEPPER_LOCKED=1` does.
##
## @param name the variable's name
## @returns true when it is set to a value other than empty or `0`
## @example
##     import os;
##
##     main(): int {
##         if (os.environment_flag("VERBOSE")) {
##             print("verbose");
##         }
##         return 0;
##     }
export environment_flag(name: String): bool {
    var value = environment(name);
    return value.is_value() and !value.value().is_empty and value.value() != "0";
}

## Sets the environment variable `name` to `value` for the running process,
## replacing any value it had.
##
## The process's own later reads see the change, and so do the children it
## starts afterwards. Safe from any thread for Pepper code; C code that calls
## `getenv` on another thread at the same time can race with it on POSIX
## (see this page's introduction). On Windows names are not case-sensitive.
## WASI keeps the change inside the program.
##
## @param name the variable's name
## @param value its new value; may be empty
## @panics if `name` is empty or contains `=` or a NUL byte, or `value`
##     contains a NUL byte
## @example
##     import os;
##
##     main(): int {
##         os.set_environment("GREETING", "hello");
##         print(os.environment("GREETING").value());   # hello
##         return 0;
##     }
export set_environment(name: String, value: String) {
    _os_check_environment_name(name);
    if (value.contains("\0")) {
        panic($"cannot set environment variable '{name}': its value contains a NUL byte");
    }
    with (var held = _os_environment_lock.lock()) {
        _os_sys_set_environment(name, value);
    }
}

## Removes the environment variable `name` from the running process.
##
## Removing a variable that is not set does nothing. The same thread-safety
## note as `set_environment`'s applies.
##
## @param name the variable's name
## @panics if `name` is empty or contains `=` or a NUL byte
## @example
##     import os;
##
##     main(): int {
##         os.remove_environment("GREETING");
##         print(os.environment("GREETING").is_empty());   # true
##         return 0;
##     }
export remove_environment(name: String) {
    _os_check_environment_name(name);
    with (var held = _os_environment_lock.lock()) {
        _os_sys_remove_environment(name);
    }
}

# Panics on a name no platform can set: as Rust's `set_var` does.
_os_check_environment_name(name: String) {
    if (name.is_empty) {
        panic("cannot change an environment variable with an empty name");
    }
    if (name.contains("=") || name.contains("\0")) {
        panic($"cannot change environment variable '{name}': its name contains '=' or a NUL byte");
    }
}

# The value `_os_environment_lock` guards: nothing; the lock is what matters.
[Shared]
struct _EnvironmentLock {
    construct() {}
}

# Held by every read and change of the process's environment.
const _os_environment_lock = async.Mutex<_EnvironmentLock>(_EnvironmentLock());

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
    var entries = Array<String>();
    with (var held = _os_environment_lock.lock()) {
        entries = _os_sys_environment_entries();
    }
    return entries;
}

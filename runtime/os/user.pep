## The user the program runs as: their name, directories, and whether they
## have administrator rights.

import io;
import "environment";
import "sys_posix";
import "sys_wasi";
import "sys_windows";

## Returns the name of the user the program runs as: on POSIX the login
## name of the effective user id (from the user database, else `USER`),
## on Windows `GetUserNameW`'s answer (else `USERNAME`), and on WASI
## `USER`.
##
## @returns the user name, or none when it cannot be found
export user_name(): String? {
    return _os_sys_user_name();
}

## Returns whether the program runs with administrator rights: on POSIX,
## as root (effective user id 0); on Windows, from an elevated
## ("Run as administrator") process of a member of Administrators
## (`IsUserAnAdmin`); never on WASI. Tools that need them, such as a
## profiler that reads kernel events, check this to say so up front.
##
## @returns true when the program runs as root or elevated
export is_elevated(): bool {
    return _os_sys_is_elevated();
}

## Returns the user's home directory: on POSIX `HOME`, or the user
## database's entry when `HOME` is unset or empty; on Windows
## `USERPROFILE`; on WASI `HOME`.
##
## @returns the home directory, or none when it cannot be found
## @example
##     import os;
##
##     main(): int {
##         var home = os.home_directory();
##         if (home) {
##             print(home.value().join(".config").to_string());
##         }
##         return 0;
##     }
export home_directory(): io.Path? {
    var path = _os_sys_home_directory();
    if (path.is_empty() || path.value().is_empty) {
        return Optional<io.Path>.Empty;
    }
    return Optional<io.Path>.Value(io.Path(path.value()));
}

## Returns the directory for temporary files: `TMPDIR` or `/tmp` on POSIX,
## `GetTempPathW` on Windows. The same as `io.Directory.temp()`.
##
## @returns the temporary directory
export temp_directory(): io.Path {
    return io.Directory.temp();
}

# A variable's value when it is set and not empty.
export _os_nonempty_environment(name: String): String? {
    var value = environment(name);
    if (value.is_value() && value.value().is_empty) {
        return Optional<String>.Empty;
    }
    return value;
}

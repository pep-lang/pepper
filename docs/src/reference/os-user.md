<!-- Generated from runtime/os/user.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# User

The user the program runs as: their name, directories, and whether they
have administrator rights.

Source: `runtime/os/user.pep`

## user_name

```pepper
user_name(): String?
```

Returns the name of the user the program runs as: on POSIX the login
name of the effective user id (from the user database, else `USER`),
on Windows `GetUserNameW`'s answer (else `USERNAME`), and on WASI
`USER`.

**Returns**
- the user name, or none when it cannot be found

## is_elevated

```pepper
is_elevated(): bool
```

Returns whether the program runs with administrator rights: on POSIX,
as root (effective user id 0); on Windows, from an elevated
("Run as administrator") process of a member of Administrators
(`IsUserAnAdmin`); never on WASI. Tools that need them, such as a
profiler that reads kernel events, check this to say so up front.

**Returns**
- true when the program runs as root or elevated

## home_directory

```pepper
home_directory(): io.Path?
```

Returns the user's home directory: on POSIX `HOME`, or the user
database's entry when `HOME` is unset or empty; on Windows
`USERPROFILE`; on WASI `HOME`.

**Returns**
- the home directory, or none when it cannot be found

**Example**
```pepper
import os;

main(): int {
    var home = os.home_directory();
    if (home) {
        print(home.value().join(".config").to_string());
    }
    return 0;
}
```

## temp_directory

```pepper
temp_directory(): io.Path
```

Returns the directory for temporary files: `TMPDIR` or `/tmp` on POSIX,
`GetTempPathW` on Windows. The same as `io.Directory.temp()`.

**Returns**
- the temporary directory

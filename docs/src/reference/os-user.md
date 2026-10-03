<!-- Generated from runtime/os/user.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# User

The user the program runs as: their name and directories.

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

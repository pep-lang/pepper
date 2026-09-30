<!-- Generated from runtime/io/directory.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Directory

Source: `runtime/io/directory.pep`

## DirEntry

```pepper
struct DirEntry
```

One entry of a directory listing, as `Directory.entries()` returns it.

The kind flags come from the listing itself and describe the entry
without following symlinks. On POSIX a symlink has `is_symlink` set and
`is_file` and `is_directory` clear; on Windows a symlink or junction to a
directory has both `is_directory` and `is_symlink` set. Entries that are none of
these (a FIFO, socket or device on POSIX) have all three flags clear. Call
`metadata()` for the details of what the entry points to.

**Example**
```pepper
    import io;

    var list = io.Directory.open(io.Path("src")).value().entries().value();
    ulong i = 0;
    while (i < list.count()) {
        if (list[i].is_file) {
            print(list[i].Name);
        }
        i = i + 1;
    }
```

### Fields

#### path

```pepper
Path path
```

The entry's full path: the listed directory's path joined with
`name` (relative when the directory's path was relative).

#### name

```pepper
String name
```

The entry's own file name, without any directory part.

#### is_file

```pepper
bool is_file
```

Whether the entry is a regular file (never true for a symlink).

#### is_directory

```pepper
bool is_directory
```

Whether the entry is a directory. On POSIX never true for a symlink;
on Windows also true for a symlink or junction to a directory.

#### is_symlink

```pepper
bool is_symlink
```

Whether the entry is a symlink (on Windows, any reparse point,
junctions included), which is not followed.

### Constructor

#### DirEntry()

```pepper
construct()
```

Creates an empty entry: empty `path` and `name`, all kind flags
false. Entries are normally obtained from `Directory.entries()`.

### Methods

#### metadata

```pepper
IoResult<Metadata> metadata()
```

Returns the metadata of the entry, following symlinks, exactly like
`Path.metadata()` on the entry's `path`. The file system is queried
again now, so the result reflects any change since the listing was
read.

**Returns**
- the entry's `Metadata` (of the target, for a symlink); an error when it cannot be stat'ed, with `is_not_found()` when the entry was removed since the listing or is a dangling symlink

**See also**
- `Path.metadata`

## Directory

```pepper
struct Directory
```

A directory on the file system, identified by its path, together with
static functions that create, remove and inspect directories and the
process's current and temporary directories.

A `Directory` holds no operating-system handle: `open` only checks that
the path is a directory, and each call to `entries()` reads the listing
afresh.

**Example**
```pepper
    import io;

    var dir = io.Directory.temp().join("scratch").join("logs");
    if (io.Directory.create_all(dir).is_ok()) {
        var d = io.Directory.open(dir).value();
        var count = d.entries().value().count();
        io.Directory.remove_all(io.Directory.temp().join("scratch"));
    }
```

### Fields

#### path

```pepper
Path path
```

The directory's path, as given to `open`.

### Constructor

#### Directory()

```pepper
construct()
```

Creates a `Directory` with an empty `path`, which names no directory.
Use `Directory.open` to get one for an existing directory.

### Static methods

#### open

```pepper
static IoResult<Directory> open(Path path)
```

Checks that `path` exists and is a directory (following symlinks) and
returns a `Directory` for it. Nothing is kept open, so the directory
can still be renamed or removed afterwards.

**Parameters**
- `path` — the directory's path; a relative path is resolved against the current directory whenever the `Directory` is used

**Returns**
- the `Directory`; an error when `path` cannot be stat'ed (`is_not_found()` for a missing or empty path, `is_permission_denied()`) or is not a directory (`is_not_a_directory()`, message `"not a directory"`)

**Example**
```pepper
    import io;

    var d = io.Directory.open(io.Path("src"));
    if (d.is_err() && d.error().is_not_a_directory()) {
        print("src is a file");
    }
```

#### create

```pepper
static IoResult<void> create(Path path)
```

Creates one directory (`mkdir` on POSIX, with mode 0777 less the
umask; `CreateDirectoryW` on Windows). Its parent must already exist.

**Parameters**
- `path` — the directory to create

**Returns**
- an Ok result on success; an error when the directory cannot be created: `is_already_exists()` when anything (a file too) is already at `path`, `is_not_found()` when the parent is missing or the path is empty, `is_permission_denied()` when the parent is not writable

**See also**
- `create_all`

#### create_all

```pepper
static IoResult<void> create_all(Path path)
```

Creates a directory and any missing parents, like `mkdir -p`.
Succeeds without doing anything when `path` is empty or already a
directory (or a symlink to one). Parents are found lexically with
`Path.parent()`; a relative path is created under the current
directory. It is safe against another process creating the same
directories at the same time.

**Parameters**
- `path` — the directory to create, with its parents

**Returns**
- an Ok result on success; an error when a directory cannot be created: `is_already_exists()` when a file (not a directory) is at `path` or at one of its parents, `is_permission_denied()`, and so on. Parents created before the failure are left in place

**Example**
```pepper
    import io;

    var r = io.Directory.create_all(io.Path("build").join("out").join("logs"));
```

#### remove

```pepper
static IoResult<void> remove(Path path)
```

Removes an empty directory (`rmdir` on POSIX, `RemoveDirectoryW` on
Windows).

**Parameters**
- `path` — the directory to remove; it must be empty

**Returns**
- an Ok result on success; an error when it cannot be removed: `is_directory_not_empty()` when it still has entries, `is_not_found()` when it is missing or the path is empty, `is_not_a_directory()` when `path` is a file, `is_permission_denied()`

**See also**
- `remove_all`

#### remove_all

```pepper
static IoResult<void> remove_all(Path path)
```

Removes `path` and, if it is a directory, everything inside it,
recursively. Symlinks are removed, never followed, so nothing outside
the tree is touched. A file or symlink at `path` itself is simply
removed.

Stops at the first failure, leaving whatever was not yet removed; on
Windows a read-only file inside the tree is such a failure
(`is_permission_denied()`).

**Parameters**
- `path` — the file, symlink or directory tree to remove

**Returns**
- an Ok result on success; an error when something cannot be removed: `is_not_found()` when `path` does not exist (unlike `rm -rf`, a missing path is an error) or is empty, `is_permission_denied()`, and so on

**See also**
- `remove`

**Example**
```pepper
    import io;

    var tree = io.Directory.temp().join("my-scratch");
    var r = io.Directory.remove_all(tree);
    if (r.is_err() && !r.error().is_not_found()) {
        print(r.error().message);
    }
```

#### current

```pepper
static IoResult<Path> current()
```

Returns the process's current directory, against which relative paths
are resolved (`getcwd` on POSIX, `GetCurrentDirectoryW` on Windows).

**Returns**
- the current directory as an absolute path; an error when it cannot be determined, such as `is_not_found()` on POSIX when the directory has been removed

**See also**
- `set_current`

#### set_current

```pepper
static IoResult<void> set_current(Path path)
```

Changes the process's current directory (`chdir` on POSIX,
`SetCurrentDirectoryW` on Windows). This affects the whole process,
every thread included: relative paths used anywhere afterwards
resolve against the new directory.

**Parameters**
- `path` — the new current directory; a relative path is resolved against the old one

**Returns**
- an Ok result on success; an error when the directory cannot be entered: `is_not_found()` when it is missing or the path is empty, `is_not_a_directory()` when it is a file, `is_permission_denied()`

**See also**
- `current`

#### temp

```pepper
static Path temp()
```

Returns the directory for temporary files. It is not created or
checked, so it may not exist.

On POSIX it is `$TMPDIR` with any trailing `/` removed, or `/tmp`
when `TMPDIR` is unset or empty. On Windows it is what
`GetTempPathW` reports (from `TMP`, `TEMP`, `USERPROFILE`, or the
Windows directory) with its trailing separator removed unless it is
a root, or `.` if that call fails.

**Returns**
- the temporary directory's path, never an error

**Example**
```pepper
    import io;

    var scratch = io.Directory.temp().join("my-tool");
```

### Methods

#### entries

```pepper
IoResult<DirEntry[]> entries()
```

Reads the directory's listing now, all at once: every entry except
`.` and `..`, in the order the operating system returns them (not
sorted). Uses `opendir`/`readdir` on POSIX and
`FindFirstFileW`/`FindNextFileW` on Windows.

**Returns**
- the entries, possibly none; an error when the directory cannot be read: `is_not_found()` when it no longer exists (or, on POSIX, `path` is empty), `is_permission_denied()`, or on POSIX `is_not_a_directory()` when `path` now names a file

**Example**
```pepper
    import io;

    var list = io.Directory.open(io.Path(".")).value().entries();
    if (list.is_ok()) {
        var n = list.value().count();
    }
```

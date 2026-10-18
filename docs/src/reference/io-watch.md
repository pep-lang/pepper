<!-- Generated from runtime/io/watch.pep by `pep-doc reference`. Do not edit. -->

# Watch

Source: `runtime/io/watch.pep`

## ChangeKind

```pepper
enum ChangeKind
```

What happened to a path, as a `FileChange` reports it.

### Cases

#### Created

```pepper
Created
```

The path was created, or moved into the tree.

#### Removed

```pepper
Removed
```

The path was removed, or moved out of the tree.

#### Modified

```pepper
Modified
```

The file's contents or attributes changed.

#### Overflow

```pepper
Overflow
```

The system dropped changes because they came faster than they were
read; the `path` is the watched directory. List it again to catch up.

## FileChange

```pepper
struct FileChange
```

One change `Watcher.wait` reports.

### Fields

#### kind

```pepper
const kind: ChangeKind
```

What happened.

#### path

```pepper
const path: Path
```

The path that changed: the watched directory's path, as given to
`Watcher.open`, joined with the path inside it.

### Constructor

#### FileChange()

```pepper
construct(kind: ChangeKind, path: Path)
```

Creates a change.

**Parameters**
- `kind` — what happened
- `path` — the path that changed

## Watcher

```pepper
[NotCopyable("owns an operating-system handle and cannot be copied; open another Watcher on the receiving thread")] struct Watcher
```

Watches a directory and everything below it for changes: files and
directories created, removed, renamed or written.

`wait()` returns the next batch of changes, waiting until there is one.
In a task (inside `async.run`) the wait parks only the task, and the
task's cancel or timeout ends it; elsewhere it blocks the thread. A
rename reports the old path `Removed` and the new one `Created`. One write
may report `Modified` more than once, and consecutive repeats within a
batch are dropped.

Each system watches its own way: inotify on Linux, with a watch on every
directory of the tree (new ones are added as they appear, and what they
already hold is reported `Created`); kqueue on macOS, which holds a
descriptor for every directory and file, so a large tree may need a
higher `ulimit -n`; `ReadDirectoryChangesW` on Windows. Changes are
recorded from `open` on, also while no `wait` is running. When the
system drops changes, `wait` reports an `Overflow` change. A change made
right as a new directory appears may be missed on Linux and macOS: look
at the directory when its `Created` arrives if that matters. Watching is
not supported on WASI.

**Example**
```pepper
import io;

var watcher = io.Watcher.open(io.Path("src")).value();
while (true) {
    var changes = watcher.wait();
    if (changes.is_err()) {
        break;
    }
    for (var change in changes.value()) {
        print($"{change.kind.name()}: {change.path}");
    }
}
```

### Fields

#### directory

```pepper
Path directory
```

The directory being watched, as given to `open`.

### Constructor

#### Watcher()

```pepper
construct()
```

Creates a closed Watcher; `wait()` on it fails. Use `Watcher.open`.

### Static methods

#### open

```pepper
static open(directory: Path): IoResult<Watcher>
```

Starts watching `directory` and everything below it.

**Parameters**
- `directory` — the directory to watch; a symlink to one is followed

**Returns**
- the Watcher; an error when `directory` cannot be stat'ed (`is_not_found()`, `is_permission_denied()`), is not a directory (`is_not_a_directory()`), or the system cannot watch it (on Linux when the inotify watch limit is reached, on macOS when the process runs out of descriptors, and on WASI always)

**Example**
```pepper
import io;

var watcher = io.Watcher.open(io.Path("."));
if (watcher.is_err()) {
    print(watcher.error().message);
}
```

### Methods

#### wait

```pepper
wait(): IoResult<FileChange[]>
```

Waits for changes and returns them, oldest first: those recorded
since the last call, or, when there are none, the next ones to come.

**Returns**
- at least one change; an error when the Watcher is closed (also when another task closes it during the wait), when the task is cancelled or times out first (`is_cancelled()`, `is_timed_out()`), or when the system fails, as on Windows when the watched directory is removed

#### close

```pepper
close()
```

Stops watching and releases the system resources. A `wait` running in
another task ends with an error. Closing again does nothing.

#### is_open

```pepper
is_open(): bool
```

Returns whether the Watcher is still watching (not closed).

**Returns**
- true until `close()`

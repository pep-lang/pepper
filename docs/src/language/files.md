# Files and directories

The `io` module reads and writes files, lists and creates directories, and
inspects and changes what the file system records about them: permission
bits, timestamps and symbolic links. Every call that touches the file
system returns an `IoResult`, whose error says what went wrong portably
(`is_not_found()`, `is_permission_denied()`, `is_already_exists()`, ...;
see [Error handling with Result](results.md)).

- `Path` is a file-system path. Joining, `parent()`, `file_name()`,
  `extension()` and `normalize()` work on its text alone; `exists()`,
  `metadata()`, `canonicalize()` and the `set_*` methods below ask the file
  system.
- `File` is an open file. `File.open` reads, `File.create` writes a new or
  emptied file, and `OpenOptions` describes anything else (append, create
  only if missing, ...). `read_to_string`, `write_text`, `read_bytes`,
  `write_bytes`, `copy`, `rename` and `remove` work on a whole file by path.
- `Directory` creates and removes directories (`create`, `create_all`,
  `remove`, `remove_all`) and lists one, all at once with `entries()` or
  one entry at a time with `for`.
- `Metadata` is a snapshot of a path's kind, size, permission bits and
  timestamps, from `Path.metadata()` (which follows symlinks),
  `Path.symlink_metadata()` (which does not) or `File.metadata()`.
- `glob` finds the paths that match a pattern such as `src/**/*.pep`, and
  `Watcher` reports changes in a directory tree (see
  [Finding files by pattern](#finding-files-by-pattern) and
  [Watching for changes](#watching-for-changes)).

```pepper
{{#include ../../examples/files-basics.pep}}
```

## Permissions

A file's permission bits say who may read, write and run it. They are the
platform's own bits, as `Metadata.permissions` reports them:

- On Linux and macOS, the POSIX `mode_t` bits: read, write and execute for
  the owner, the group and everyone else, plus setuid, setgid and sticky.
  Pepper has no octal literals, so `rwxr-xr-x` (octal 755) is written 493,
  and a comment gives the octal. On a directory, read lets one list it,
  write lets one add and remove entries, and execute lets one reach
  anything inside it.
- On Windows, the `FILE_ATTRIBUTE_*` word. Only `FILE_ATTRIBUTE_READONLY`
  is a permission; whether a file runs depends on its extension.
- WASI has no permission bits.

Three ways to change them:

- `set_permissions(mode)` on a `Path` or an open `File` sets the raw bits
  (`chmod` and `fchmod`). On Windows it applies only the read-only bit of
  `mode`, and on WASI it returns an error.
- `set_read_only(bool)` is the portable read-only switch. On POSIX,
  read-only clears every write bit and writable sets only the owner's, so
  this never opens a file to others. On Windows it sets or clears
  `FILE_ATTRIBUTE_READONLY`.
- `set_executable(bool)` adds an execute bit wherever there is a read bit,
  as `chmod +x` does, or clears them all. It does nothing on Windows and
  WASI.

A file or directory can also be created with its bits, so that it never
exists with the default ones even for a moment: `OpenOptions.mode(m)` for a
new file, and `Directory.create(path, mode = m)` or `create_all(path, mode =
m)` for a directory. The process umask still applies, as it does to `open`
and `mkdir`. These are ignored on Windows and WASI.

## Timestamps

`Metadata.modified` and `Metadata.accessed` are nanoseconds since
1970-01-01 UTC. `set_modified(time)` and `set_accessed(time)` on a `Path`
or an open `File` set one and leave the other (`utimensat` and `futimens`;
`SetFileTime` on Windows, which keeps 100 ns). Writing to a file sets its
modification time, and adding or removing an entry sets a directory's, so
set a time after the contents are final.

```pepper
{{#include ../../examples/files-permissions.pep}}
```

On Windows, an open `File` must have been opened for writing to change its
read-only bit or its times.

## Symbolic links

`File.symlink(target, link)` and `Directory.symlink(target, link)` create
a symbolic link at `link` pointing to `target`. POSIX makes one kind of
link either way; Windows makes a file link and a directory link
differently, and a file link to a directory does not open, so use the one
that matches the target. The target is stored as given and need not exist;
a relative target is resolved from the directory holding the link.

`Path.read_link()` returns the target a link stores, without following it.
`Path.symlink_metadata()` describes the link itself, and `metadata()` what
it points to. `Directory.remove_all` removes links and never follows them.

```pepper
{{#include ../../examples/files-symlinks.pep}}
```

Making a symlink on Windows needs Developer Mode or an administrator;
without either it fails with `is_permission_denied()`.

## Moving a file to another thread

A `File` is not thread-safe, so a thread cannot capture one. To hand an
open file to another thread, such as the pipe from a child process's
output to a thread that reads it while this one writes to the child,
`file.into_transfer()` moves its handle into an `io.FileTransfer`, a
thread-safe token that a `shared` function can capture or a `Channel` can
carry, and `io.File.adopt(transfer)` takes it out again on the other
thread. The File it came from is closed afterwards, only the first `adopt`
gets the handle, and a token no one adopts closes the file when it goes.
A stream moves the same way, as a `SocketTransfer` (see
[Moving a stream to another worker](tasks.md#moving-a-stream-to-another-worker)).

```pepper
{{#include ../../examples/files-transfer.pep}}
```

## Finding files by pattern

`io.glob(pattern)` returns the existing paths that match a shell-style
pattern, sorted, and `io.glob_matches(pattern, path)` tests a path's text
against one without touching the file system:

- `*` matches any run of characters within one path component, and `?`
  one character; neither matches `/`.
- `**` as a whole component matches any number of directories, none
  included: `src/**/*.pep` matches `src/main.pep` and `src/net/http.pep`.
- `[abc]`, `[a-z]` and `[!abc]` (or `[^abc]`) match one character listed,
  in the range, or not listed.
- `{pep,md}` matches either alternative; alternatives may hold any
  pattern, braces included.

Patterns separate components with `/` on every system; on Windows a `\` in
the path being matched counts as `/` too. There is no escape character, so
that Windows paths stay as they are: `[*]` matches a literal `*`. An
unclosed `[` or `{` matches itself, so every pattern is valid. Matching is
case-sensitive, and `*` matches a leading `.` like any other character.

`glob` starts at the longest leading part of the pattern without
wildcards, so `src/**/*.pep` lists only under `src`, and a relative pattern
gives relative paths. `**` does not descend into symlinked directories, so
a link cycle cannot loop. Directories it cannot read are skipped, and a
pattern whose start does not exist matches nothing.

```pepper
{{#include ../../examples/files-glob.pep}}
```

## Watching for changes

`io.Watcher.open(directory)` watches a directory and everything below it.
Each `wait()` returns the changes recorded since the last one, or waits for
the next: a list of `FileChange`s, each a `ChangeKind` (`Created`,
`Removed`, `Modified`) and the `path` it happened to. A rename reports the
old path removed and the new one created. When the system drops changes
because they came too fast, `wait` reports one `Overflow` change for the
directory: list it again to catch up. `close()` stops watching, and a
`wait` running in another task then fails.

In a task (see [Tasks](tasks.md)) `wait` parks only the task, so others run
while it waits, and the task's cancel or `async.timeout` ends it. Outside a
task it blocks the thread.

```pepper
{{#include ../../examples/files-watch.pep}}
```

Each system watches its own way, and that shows in a few places:

- Linux uses inotify, with a watch on every directory of the tree. A new
  directory gets one as its creation is read, and what it already holds by
  then is reported created. The number of watches is limited
  (`/proc/sys/fs/inotify/max_user_watches`), and `open` fails past it.
- macOS uses kqueue, which holds an open descriptor for every directory and
  file of the tree, so a large tree may need a higher `ulimit -n`. A
  directory that changed is listed again to tell what came and went.
- Windows uses `ReadDirectoryChangesW`, which watches the whole tree with
  one handle. One write often reports `Modified` twice; repeats next to
  each other in one batch are dropped.
- WASI cannot watch: `open` fails.

## Archives

`archive.TarReader.extract` uses all of the above: it restores each file's
mode and modification time and makes the archive's symlinks, as long as
they stay inside the directory it extracts into. See
[Compression and archives](compression.md).

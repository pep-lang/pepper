## `TarReader` and `TarWriter`: tar archives (POSIX ustar, with the pax and
## GNU extensions for long names), read entry by entry from a stream,
## extracted safely into a directory, or written.

import io;
import text;
import "path";

## What a tar entry is.
export enum EntryKind {
    ## A regular file, whose contents follow the entry's header.
    File,
    ## A directory.
    Directory,
    ## A symbolic link to `TarEntry.link_target`.
    Symlink,
    ## A hard link to the earlier entry named `TarEntry.link_target`.
    HardLink,
    ## Anything else: a device, a FIFO, or a type this reader does not know.
    Other,
}

## One entry of a tar archive: its header, without its contents.
##
## @example
##     import archive;
##
##     var entry = archive.TarEntry("bin/run.sh", archive.EntryKind.File);
##     entry.mode = 493;   # octal 755: rwxr-xr-x
export struct TarEntry {
    ## The path in the archive, with `/` between components, as stored (a
    ## directory's may end with `/`).
    var path: String;
    ## What the entry is.
    var kind: EntryKind;
    ## The length of the contents in bytes; 0 for anything but a file.
    var size: ulong;
    ## The permission bits, such as 420 (octal 644, `rw-r--r--`).
    var mode: uint;
    ## The modification time, in seconds since 1970-01-01 UTC.
    var modified: long;
    ## The target of a symlink or hard link; empty otherwise.
    var link_target: String;

    ## Makes an entry with the given path and kind, mode 420 (octal 644) for
    ## a file and 493 (octal 755) otherwise, size 0 and modification time 0.
    ##
    ## @param path the path in the archive
    ## @param kind what the entry is
    construct(path: String = "", kind: EntryKind = EntryKind.File) {
        this.path = path;
        this.kind = kind;
        if (kind == EntryKind.File) {
            mode = 420;
        } else {
            mode = 493;
        }
        link_target = "";
    }
}

# The error for an archive that is not valid.
_tar_error(message: String): io.IoError {
    return io.IoError(io._io_sys_code_invalid_input(), message);
}

## Reads a tar archive from a stream, one entry at a time: `next_entry()`
## moves to the next entry and returns its header, then `read` (it is an
## `io.Reader`) reads that entry's contents. Contents not read are skipped.
##
## It reads POSIX ustar archives and the pax (`x`) and GNU (`L`, `K`)
## extensions for long paths, link targets and sizes, which is what GNU tar,
## bsdtar and Git (`git archive`, and the `.tar.gz` snapshots GitHub, GitLab
## and Codeberg serve) write. Global pax headers (`g`) are skipped.
## Wrap the source in a `compress.DecompressReader` to read a `.tar.gz`.
##
## @example
##     import archive;
##     import compress;
##     import io;
##
##     var file = io.File.open(io.Path("release.tar.gz")).value();
##     var tar = archive.TarReader(compress.DecompressReader(file, compress.Format.Gzip));
##     while (true) {
##         var entry = tar.next_entry().value();
##         if (entry.is_empty()) {
##             break;
##         }
##         print(entry.value().path);
##     }
export struct TarReader {
    # The stream of the archive, and bytes read from it but not used yet.
    var _source: io.Reader;
    var _buffer: u8[];
    var _position: ulong;
    # The current entry's contents not read yet, and the padding after them.
    var _left: ulong;
    var _padding: ulong;
    var _ended: bool;

    ## Makes a reader of the archive in `source`, before its first entry.
    ##
    ## @param source the stream of the archive
    construct(source: io.Reader) {
        _source = source;
        _buffer = Array<u8>();
    }

    # Appends up to `count` bytes of the archive to `out`, from the buffer
    # and then the source; returns how many, fewer only at its end.
    _take(out: u8[], count: ulong): io.IoResult<ulong> {
        ulong taken = 0;
        while (taken < count) {
            if (_position == _buffer.count) {
                _buffer.clear();
                _position = 0;
                var read = _source.read(_buffer, 65536);
                if (read.is_err()) {
                    return io.IoResult<ulong>.err(read.error());
                }
                if (read.value() == 0) {
                    break;
                }
            }
            var size = _buffer.count - _position;
            if (size > count - taken) {
                size = count - taken;
            }
            out._append_raw(_buffer._data + _position, size);
            _position += size;
            taken += size;
        }
        return io.IoResult<ulong>.ok(taken);
    }

    # Reads exactly `count` bytes; the archive ending first is an error.
    _take_exactly(count: ulong): io.IoResult<u8[]> {
        var out = Array<u8>(count);
        var taken = _take(out, count);
        if (taken.is_err()) {
            return io.IoResult<u8[]>.err(taken.error());
        }
        if (taken.value() != count) {
            return io.IoResult<u8[]>.err(_tar_error("tar archive is truncated"));
        }
        return io.IoResult<u8[]>.ok(out);
    }

    # Skips `count` bytes of the archive.
    _skip(count: ulong): io.IoResult<void> {
        var left = count;
        while (left > 0) {
            var size = left;
            if (size > 65536) {
                size = 65536;
            }
            var skipped = _take_exactly(size);
            if (skipped.is_err()) {
                return io.IoResult<void>.err(skipped.error());
            }
            left -= size;
        }
        return io.IoResult<void>.ok();
    }

    ## Moves to the next entry, skipping what is left of the current one's
    ## contents, and returns its header.
    ##
    ## The archive ends at two zero blocks, as tar writes, or at the end of
    ## the stream between entries.
    ##
    ## @returns the next entry, or none at the end of the archive; an
    ##   `is_invalid_input()` error for a damaged or truncated archive, or
    ##   the source's error
    next_entry(): io.IoResult<TarEntry?> {
        if (_ended) {
            return io.IoResult<TarEntry?>.ok(Optional<TarEntry>.Empty);
        }
        var skipped = _skip(_left + _padding);
        if (skipped.is_err()) {
            return io.IoResult<TarEntry?>.err(skipped.error());
        }
        _left = 0;
        _padding = 0;
        # Values from pax and GNU headers for the entry they come before.
        var long_path = Optional<String>.Empty;
        var long_link = Optional<String>.Empty;
        var long_size = Optional<ulong>.Empty;
        var long_modified = Optional<long>.Empty;
        while (true) {
            var header = Array<u8>(512);
            var taken = _take(header, 512);
            if (taken.is_err()) {
                return io.IoResult<TarEntry?>.err(taken.error());
            }
            if (taken.value() == 0) {
                _ended = true;
                return io.IoResult<TarEntry?>.ok(Optional<TarEntry>.Empty);
            }
            if (taken.value() != 512) {
                return io.IoResult<TarEntry?>.err(_tar_error("tar archive is truncated"));
            }
            if (_tar_is_zero(header)) {
                _ended = true;
                return io.IoResult<TarEntry?>.ok(Optional<TarEntry>.Empty);
            }
            if (!_tar_checksum_ok(header)) {
                return io.IoResult<TarEntry?>.err(_tar_error("tar header checksum mismatch"));
            }
            var size_field = _tar_number(header, 124, 12);
            if (size_field.is_empty()) {
                return io.IoResult<TarEntry?>.err(_tar_error("tar header has an invalid size"));
            }
            var size = size_field.value();
            var type_flag = header[156];
            var padding = (512 - size % 512) % 512;
            if (type_flag == 'x' || type_flag == 'g' || type_flag == 'L' || type_flag == 'K') {
                if (size > 16777216) {
                    return io.IoResult<TarEntry?>.err(_tar_error("tar extended header is too large"));
                }
                var data = _take_exactly(size);
                if (data.is_err()) {
                    return io.IoResult<TarEntry?>.err(data.error());
                }
                var after = _skip(padding);
                if (after.is_err()) {
                    return io.IoResult<TarEntry?>.err(after.error());
                }
                if (type_flag == 'L') {
                    long_path = Optional<String>.Value(_tar_string(data.value(), 0, size));
                } else if (type_flag == 'K') {
                    long_link = Optional<String>.Value(_tar_string(data.value(), 0, size));
                } else if (type_flag == 'x') {
                    var records = _tar_pax_records(data.value());
                    if (records.is_empty()) {
                        return io.IoResult<TarEntry?>.err(_tar_error("tar pax header is invalid"));
                    }
                    for (var (key, value) in records.value()) {
                        if (key == "path") {
                            long_path = Optional<String>.Value(value);
                        } else if (key == "linkpath") {
                            long_link = Optional<String>.Value(value);
                        } else if (key == "size") {
                            var parsed = ulong.parse(value);
                            if (parsed.is_empty()) {
                                return io.IoResult<TarEntry?>.err(_tar_error("tar pax header has an invalid size"));
                            }
                            long_size = Optional<ulong>.Value(parsed.value());
                        } else if (key == "mtime") {
                            var whole = value;
                            var dot = value.find(".");
                            if (dot >= 0) {
                                whole = value.substr_bytes(0, dot as ulong);
                            }
                            var parsed = long.parse(whole);
                            if (parsed.is_value()) {
                                long_modified = Optional<long>.Value(parsed.value());
                            }
                        }
                    }
                }
                continue;
            }

            var entry = TarEntry("", EntryKind.File);
            entry.path = _tar_string(header, 0, 100);
            # ustar ("ustar\0") puts a path prefix at 345; GNU's "ustar  "
            # uses that space for other fields.
            if (header[257] == 'u'
                && header[258] == 's'
                && header[259] == 't'
                && header[260] == 'a'
                && header[261] == 'r'
                && header[262] == 0) {
                var prefix = _tar_string(header, 345, 155);
                if (!prefix.is_empty) {
                    entry.path = prefix + "/" + entry.path;
                }
            }
            entry.link_target = _tar_string(header, 157, 100);
            entry.mode = (_tar_number(header, 100, 8).value_or(0) & 4095) as uint;
            entry.modified = _tar_number(header, 136, 12).value_or(0) as long;
            if (type_flag == '0' || type_flag == 0 || type_flag == '7') {
                entry.kind = EntryKind.File;
            } else if (type_flag == '5') {
                entry.kind = EntryKind.Directory;
            } else if (type_flag == '2') {
                entry.kind = EntryKind.Symlink;
            } else if (type_flag == '1') {
                entry.kind = EntryKind.HardLink;
            } else {
                entry.kind = EntryKind.Other;
            }
            # An old-style archive marks a directory by a final '/'.
            if (type_flag == 0 && entry.path.ends_with("/")) {
                entry.kind = EntryKind.Directory;
            }
            if (long_path.is_value()) {
                entry.path = long_path.value();
            }
            if (long_link.is_value()) {
                entry.link_target = long_link.value();
            }
            if (long_size.is_value()) {
                size = long_size.value();
                padding = (512 - size % 512) % 512;
            }
            if (long_modified.is_value()) {
                entry.modified = long_modified.value();
            }
            if (entry.kind == EntryKind.File) {
                entry.size = size;
            }
            _left = size;
            _padding = padding;
            return io.IoResult<TarEntry?>.ok(Optional<TarEntry>.Value(entry));
        }
        return io.IoResult<TarEntry?>.ok(Optional<TarEntry>.Empty);
    }

    ## Reads up to `max` more bytes of the current entry's contents and
    ## appends them to `buffer`.
    ##
    ## @param buffer the array the bytes are appended to
    ## @param max the most bytes to read
    ## @returns the number of bytes appended, 0 at the end of the entry's
    ##   contents (or before the first `next_entry()`); an error when the
    ##   archive is truncated or the source fails
    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        var count = max;
        if (count > _left) {
            count = _left;
        }
        var taken = _take(buffer, count);
        if (taken.is_err()) {
            return taken;
        }
        if (taken.value() != count) {
            return io.IoResult<ulong>.err(_tar_error("tar archive is truncated"));
        }
        _left -= count;
        return taken;
    }

    ## Reads the rest of the current entry's contents.
    ##
    ## @returns the bytes not read yet; an error as for `read`
    read_all(): io.IoResult<u8[]> {
        var data = _take_exactly(_left);
        if (data.is_ok()) {
            _left = 0;
        }
        return data;
    }

    ## Extracts the rest of the archive into the directory `target`,
    ## creating it and any directories the entries need.
    ##
    ## Each entry's path is checked first, so that no archive can write
    ## outside `target`: an absolute path, a `..` component, a `\` or a `:`
    ## (which Windows would read as a separator or a drive) is an
    ## `is_invalid_input()` error. Files are written (replacing a file
    ## already there) and directories created; a hard link becomes a copy of
    ## the file it names, which must be an earlier entry. Devices and FIFOs
    ## are skipped.
    ##
    ## Each file and directory gets the entry's modification time and, on
    ## Linux and macOS, its permission bits less the process umask, as
    ## `tar` gives them by default, so a script keeps its executable bit;
    ## the setuid, setgid and sticky bits are never applied. A directory's
    ## mode and time are set once everything inside it is written, so a
    ## read-only directory can still be filled. A directory that already
    ## exists keeps its own. On Windows and WASI permission bits are not
    ## applied.
    ##
    ## Symlinks are made after every other entry, so no file is ever
    ## written through one, and only when they stay inside `target`: a link
    ## whose target is absolute or climbs out of `target` with `..`, or that
    ## would be made inside another symlink, is skipped. Windows, where
    ## making a symlink needs Developer Mode or an administrator, skips them
    ## all.
    ##
    ## @param target the directory to extract into
    ## @param strip_components how many leading path components to drop
    ##   from each entry, as tar's `--strip-components` does: 1 drops the
    ##   `name-version/` directory that GitHub's snapshots put everything
    ##   in. An entry with no components left is skipped.
    ## @returns an Ok result once every entry is extracted; an
    ##   `is_invalid_input()` error for an unsafe path or a damaged archive,
    ##   or the error of a file that could not be written
    ## @example
    ##     import archive;
    ##     import compress;
    ##     import io;
    ##
    ##     var file = io.File.open(io.Path("pepper-main.tar.gz")).value();
    ##     var tar = archive.TarReader(compress.DecompressReader(file, compress.Format.Gzip));
    ##     tar.extract(io.Path(".pep/deps/pepper"), strip_components = 1).value();
    extract(target: io.Path, strip_components: ulong = 0): io.IoResult<void> {
        var created = io.Directory.create_all(target);
        if (created.is_err()) {
            return created;
        }
        # The directories this extraction made, with their mode and time,
        # and the symlinks it makes at the end.
        var directories = Array<(io.Path, uint, long)>();
        var links = Array<(String[], String)>();
        while (true) {
            var next = next_entry();
            if (next.is_err()) {
                return io.IoResult<void>.err(next.error());
            }
            if (next.value().is_empty()) {
                break;
            }
            var entry = next.value().value();
            if (entry.kind == EntryKind.Other) {
                continue;
            }
            var relative = _tar_safe_components(entry.path, strip_components);
            if (relative.is_err()) {
                return io.IoResult<void>.err(relative.error());
            }
            if (relative.value().is_empty) {
                continue;
            }
            if (entry.kind == EntryKind.Symlink) {
                links.append((relative.value(), entry.link_target));
                continue;
            }
            var destination = _tar_join(target, relative.value());
            var mode = entry.mode & 511;  # never setuid, setgid or sticky
            var modified = entry.modified * 1000000000;
            if (entry.kind == EntryKind.Directory) {
                if (destination.is_directory()) {
                    continue;
                }
                var parent = destination.parent();
                if (parent.is_value()) {
                    var made = io.Directory.create_all(parent.value());
                    if (made.is_err()) {
                        return made;
                    }
                }
                # The owner may fill it whatever its mode; `_tar_finish`
                # takes away what the entry does not grant.
                var made = io.Directory.create(destination, mode = mode | 448);
                if (made.is_err()) {
                    return made;
                }
                directories.append((destination, mode, modified));
                continue;
            }
            var parent = destination.parent();
            if (parent.is_value()) {
                var made = io.Directory.create_all(parent.value());
                if (made.is_err()) {
                    return made;
                }
            }
            var opened = _tar_create(destination, mode);
            if (opened.is_err()) {
                return io.IoResult<void>.err(opened.error());
            }
            var file = opened.value();
            io.IoResult<void> written;
            if (entry.kind == EntryKind.HardLink) {
                var linked = _tar_safe_components(entry.link_target, strip_components);
                if (linked.is_err()) {
                    return io.IoResult<void>.err(linked.error());
                }
                if (linked.value().is_empty) {
                    return io.IoResult<void>.err(_tar_error($"tar hard link '{entry.path}' has an invalid target"));
                }
                written = _tar_copy(_tar_join(target, linked.value()), file);
            } else {
                written = _write_entry(file);
            }
            if (written.is_ok()) {
                written = file.set_modified(modified);
            }
            var closed = file.close();
            if (written.is_err()) {
                return written;
            }
            if (closed.is_err()) {
                return closed;
            }
        }
        for (var (relative, link_target) in links) {
            var made = _tar_symlink(target, relative, link_target);
            if (made.is_err()) {
                return made;
            }
        }
        # Deepest first: setting a directory's time does not change its
        # parent's.
        var index = directories.count;
        while (index > 0) {
            index -= 1;
            var (path, mode, modified) = directories[index];
            var finished = _tar_finish(path, mode, modified);
            if (finished.is_err()) {
                return finished;
            }
        }
        return io.IoResult<void>.ok();
    }

    # Writes the current entry's contents to `file`.
    _write_entry(file: io.File): io.IoResult<void> {
        while (_left > 0) {
            var chunk = Array<u8>();
            var read = read(chunk, 65536);
            if (read.is_err()) {
                return io.IoResult<void>.err(read.error());
            }
            var written = file.write_all(chunk);
            if (written.is_err()) {
                return written;
            }
        }
        return io.IoResult<void>.ok();
    }
}

# A new file at `destination` with permission bits `mode` (less the umask),
# replacing whatever non-directory is there: removing it first means a file
# another path also links to is left alone, and so is a symlink's target.
_tar_create(destination: io.Path, mode: uint): io.IoResult<io.File> {
    var existing = destination.symlink_metadata();
    if (existing.is_ok() && (existing.value().is_symlink || !existing.value().is_directory)) {
        var removed = io.File.remove(destination);
        if (removed.is_err()) {
            return io.IoResult<io.File>.err(removed.error());
        }
    }
    return io.OpenOptions().write(true).create_new(true).mode(mode).open(destination);
}

# Copies the file at `from`, an entry extracted earlier, into `to`.
_tar_copy(from: io.Path, to: io.File): io.IoResult<void> {
    var opened = io.File.open(from);
    if (opened.is_err()) {
        return io.IoResult<void>.err(opened.error());
    }
    var source = opened.value();
    while (true) {
        var chunk = Array<u8>();
        var read = source.read(chunk, 65536);
        if (read.is_err()) {
            return io.IoResult<void>.err(read.error());
        }
        if (read.value() == 0) {
            return io.IoResult<void>.ok();
        }
        var written = to.write_all(chunk);
        if (written.is_err()) {
            return written;
        }
    }
    return io.IoResult<void>.ok();
}

# Makes the symlink at `relative` under `target` pointing to `link_target`,
# unless the link would leave `target` (see `TarReader.extract`); succeeds
# without making it then.
[Target(!OS(Windows))]
_tar_symlink(target: io.Path, relative: String[], link_target: String): io.IoResult<void> {
    if (!_tar_link_inside(relative, link_target)) {
        return io.IoResult<void>.ok();
    }
    # A symlink among the link's parents (one this extraction just made, or
    # one already there) could take a relative target somewhere else.
    var parent = target;
    var index: ulong = 0;
    while (index + 1 < relative.count) {
        parent = parent.join(relative[index]);
        var m = parent.symlink_metadata();
        if (m.is_ok() && m.value().is_symlink) {
            return io.IoResult<void>.ok();
        }
        index += 1;
    }
    var made = io.Directory.create_all(parent);
    if (made.is_err()) {
        return made;
    }
    var destination = parent.join(relative[relative.count - 1]);
    var existing = destination.symlink_metadata();
    if (existing.is_ok() && (existing.value().is_symlink || !existing.value().is_directory)) {
        var removed = io.File.remove(destination);
        if (removed.is_err()) {
            return removed;
        }
    }
    return io.File.symlink(io.Path(link_target), destination);
}

[Target(OS(Windows))]
_tar_symlink(target: io.Path, relative: String[], link_target: String): io.IoResult<void> {
    return io.IoResult<void>.ok();
}

# Whether a symlink at `relative` pointing to `link_target` stays inside
# the directory it is extracted into: the target is relative, and its `..`
# components never climb above that directory, counted from the link's.
_tar_link_inside(relative: String[], link_target: String): bool {
    if (link_target.is_empty
        || link_target.starts_with("/")
        || link_target.contains("\\")
        || link_target.contains(":")) {
        return false;
    }
    var depth = relative.count - 1;
    for (var component in link_target.split("/")) {
        if (component == "..") {
            if (depth == 0) {
                return false;
            }
            depth -= 1;
        } else if (!component.is_empty && component != ".") {
            depth += 1;
        }
    }
    return true;
}

# Gives a directory this extraction made its entry's time and, where there
# are permission bits, takes away the owner bits (octal 700) it was made
# with that the entry's `mode` does not grant; mkdir already applied the
# umask to the rest.
[Target(OS(Linux) || OS(Mac))]
_tar_finish(path: io.Path, mode: uint, modified: long): io.IoResult<void> {
    var timed = path.set_modified(modified);
    if (timed.is_err()) {
        return timed;
    }
    if ((mode & 448) == 448) {
        return io.IoResult<void>.ok();
    }
    var m = path.metadata();
    if (m.is_err()) {
        return io.IoResult<void>.err(m.error());
    }
    var extra = 448 ^ (mode & 448);
    return path.set_permissions((m.value().permissions | extra) ^ extra);
}

[Target(OS(Windows) || OS(Wasi))]
_tar_finish(path: io.Path, mode: uint, modified: long): io.IoResult<void> {
    return path.set_modified(modified);
}

extend TarReader with io.Reader;

# Joins `components` onto `base`, one at a time.
_tar_join(base: io.Path, components: String[]): io.Path {
    var path = base;
    for (var component in components) {
        path = path.join(component);
    }
    return path;
}

# The components of archive path `path` after the first `strip` are
# dropped; an error for a path that could reach outside the directory it is
# extracted into.
_tar_safe_components(path: String, strip: ulong): io.IoResult<String[]> {
    var components = safe_components(path);
    if (components.is_empty()) {
        return io.IoResult<String[]>.err(_tar_error($"tar entry '{path}' has an unsafe path"));
    }
    var kept = Array<String>();
    var index = strip;
    while (index < components.value().count) {
        kept.append(components.value()[index]);
        index += 1;
    }
    return io.IoResult<String[]>.ok(kept);
}

# Whether all 512 bytes of a header are zero.
_tar_is_zero(header: u8[]): bool {
    for (var byte in header) {
        if (byte != 0) {
            return false;
        }
    }
    return true;
}

# Whether a header's checksum field matches the sum of its bytes, with the
# field itself counted as spaces.
_tar_checksum_ok(header: u8[]): bool {
    var stored = _tar_number(header, 148, 8);
    if (stored.is_empty()) {
        return false;
    }
    ulong sum = 0;
    ulong index = 0;
    while (index < 512) {
        if (index >= 148 && index < 156) {
            sum += 32;
        } else {
            sum += header[index] as ulong;
        }
        index += 1;
    }
    return sum == stored.value();
}

# The number in the `size`-byte field at `start`: octal digits, padded with
# spaces or NULs, or GNU's base-256 form (first byte 0x80, then big-endian).
# Empty when the field holds anything else.
_tar_number(header: u8[], start: ulong, size: ulong): ulong? {
    if ((header[start] & 128) != 0) {
        ulong value = (header[start] & 127) as ulong;
        ulong index = 1;
        while (index < size) {
            if (value >= ((1 as ulong) << 55)) {
                return Optional<ulong>.Empty;
            }
            value = (value << 8) | (header[start + index] as ulong);
            index += 1;
        }
        return Optional<ulong>.Value(value);
    }
    ulong value = 0;
    ulong index = 0;
    while (index < size && header[start + index] == ' ') {
        index += 1;
    }
    while (index < size) {
        var digit = header[start + index];
        if (digit == 0 || digit == ' ') {
            break;
        }
        if (digit < '0' || digit > '7') {
            return Optional<ulong>.Empty;
        }
        value = value * 8 + ((digit - '0') as ulong);
        index += 1;
    }
    return Optional<ulong>.Value(value);
}

# The text of the `size`-byte field at `start`, up to its first NUL.
_tar_string(data: u8[], start: ulong, size: ulong): String {
    var bytes = Array<u8>(size);
    ulong index = 0;
    while (index < size && data[start + index] != 0) {
        bytes.append(data[start + index]);
        index += 1;
    }
    return text.Utf8.decode_lossy(bytes);
}

# The key and value of each record of a pax header ("<length> <key>=<value>\n").
_tar_pax_records(data: u8[]): Array<(String, String)>? {
    var records = Array<(String, String)>();
    ulong position = 0;
    while (position < data.count) {
        # Trailing NULs pad some writers' headers.
        if (data[position] == 0) {
            break;
        }
        ulong length = 0;
        var at = position;
        while (at < data.count && data[at] >= '0' && data[at] <= '9') {
            length = length * 10 + ((data[at] - '0') as ulong);
            if (length > data.count) {
                return Optional<Array<(String, String)>>.Empty;
            }
            at += 1;
        }
        var end = position + length;
        if (at == position || at >= data.count || data[at] != ' ' || end > data.count || data[end - 1] != '\n') {
            return Optional<Array<(String, String)>>.Empty;
        }
        var record = _tar_string_range(data, at + 1, end - 1);
        var equals = record.find("=");
        if (equals < 0) {
            return Optional<Array<(String, String)>>.Empty;
        }
        var split = equals as ulong;
        records.append((record.substr_bytes(0, split), record.substr_bytes(split + 1, record.size - split - 1)));
        position = end;
    }
    return Optional<Array<(String, String)>>.Value(records);
}

# The text of `data[start..end]`, NULs included.
_tar_string_range(data: u8[], start: ulong, end: ulong): String {
    var bytes = Array<u8>(end - start);
    bytes._append_raw(data._data + start, end - start);
    return text.Utf8.decode_lossy(bytes);
}

## Writes a tar archive to a stream: each `append` writes one entry's
## header and contents, and `finish()` writes the end-of-archive marker.
##
## It writes POSIX ustar headers, and a pax header before an entry whose
## path or link target does not fit one (a path over 100 bytes that cannot
## be split at a `/` into 155 and 100), so every path is kept whole. Owner
## ids are 0 and owner names empty. Wrap the sink in a
## `compress.CompressWriter` to write a `.tar.gz`.
##
## @example
##     import archive;
##     import io;
##
##     var out = io.ByteWriter();
##     var tar = archive.TarWriter(out);
##     tar.append_directory("docs");
##     tar.append_file("docs/readme.txt", "hello\n".bytes());
##     tar.finish();
##     assert(out.bytes.count == 4 * 512 + 2 * 512, "headers, contents, end marker");
export struct TarWriter {
    # Where the archive goes.
    var _sink: io.Writer;
    var _finished: bool;

    ## Makes a writer of a new archive into `sink`.
    ##
    ## @param sink the stream the archive is written to
    construct(sink: io.Writer) {
        _sink = sink;
    }

    ## Appends a regular file holding `data`.
    ##
    ## @param path the file's path in the archive, with `/` between
    ##   components
    ## @param data the file's contents
    ## @param mode the permission bits; 420 is octal 644 (`rw-r--r--`)
    ## @returns an Ok result; an error when writing to the sink fails
    ## @panics if `finish()` was called ("TarWriter used after finish()")
    append_file(path: String, data: u8[], mode: uint = 420): io.IoResult<void> {
        var entry = TarEntry(path, EntryKind.File);
        entry.mode = mode;
        return append(entry, data);
    }

    ## Appends a directory.
    ##
    ## @param path the directory's path in the archive; a final `/` is added
    ##   when missing
    ## @param mode the permission bits; 493 is octal 755 (`rwxr-xr-x`)
    ## @returns an Ok result; an error when writing to the sink fails
    ## @panics if `finish()` was called ("TarWriter used after finish()")
    append_directory(path: String, mode: uint = 493): io.IoResult<void> {
        var entry = TarEntry(path, EntryKind.Directory);
        entry.mode = mode;
        return append(entry, Array<u8>());
    }

    ## Appends a symbolic link.
    ##
    ## @param path the link's path in the archive
    ## @param target the path the link points to
    ## @returns an Ok result; an error when writing to the sink fails
    ## @panics if `finish()` was called ("TarWriter used after finish()")
    append_symlink(path: String, target: String): io.IoResult<void> {
        var entry = TarEntry(path, EntryKind.Symlink);
        entry.mode = 511;
        entry.link_target = target;
        return append(entry, Array<u8>());
    }

    ## Appends an entry with the given header and contents. The size
    ## written is `data.count` for a file and 0 for anything else, whatever
    ## `entry.size` holds.
    ##
    ## @param entry the entry's header
    ## @param data the contents of a file entry; ignored for other kinds
    ## @returns an Ok result; an error when writing to the sink fails
    ## @panics if `finish()` was called ("TarWriter used after finish()")
    append(entry: TarEntry, data: u8[]): io.IoResult<void> {
        ulong size = 0;
        if (entry.kind == EntryKind.File) {
            size = data.count;
        }
        var header = _header(entry, size);
        if (header.is_err()) {
            return header;
        }
        if (size == 0) {
            return io.IoResult<void>.ok();
        }
        var written = _sink.write_all(data);
        if (written.is_err()) {
            return written;
        }
        return _pad(size);
    }

    ## Appends a file entry whose contents are read from `source`: exactly
    ## `entry.size` bytes, so a large file need not be in memory.
    ##
    ## @param entry the entry's header; its `kind` must be `File`
    ## @param source the stream holding the contents
    ## @returns an Ok result; an error when reading or writing fails, or an
    ##   `is_invalid_input()` error when `source` ends before `entry.size`
    ##   bytes (the archive is then incomplete)
    ## @panics if `finish()` was called ("TarWriter used after finish()")
    ## @panics if `entry.kind` is not `File` ("append_stream needs a file entry")
    ## @example
    ##     var file = io.File.open(io.Path("big.bin")).value();
    ##     var entry = archive.TarEntry("big.bin");
    ##     entry.size = file.metadata().value().size;
    ##     tar.append_stream(entry, file);
    append_stream(entry: TarEntry, source: io.Reader): io.IoResult<void> {
        assert(entry.kind == EntryKind.File, "append_stream needs a file entry");
        var header = _header(entry, entry.size);
        if (header.is_err()) {
            return header;
        }
        var left = entry.size;
        while (left > 0) {
            var chunk = Array<u8>();
            var want = left;
            if (want > 65536) {
                want = 65536;
            }
            var read = source.read(chunk, want);
            if (read.is_err()) {
                return io.IoResult<void>.err(read.error());
            }
            if (read.value() == 0) {
                return io.IoResult<void>.err(_tar_error($"'{entry.path}' ended before its size"));
            }
            left -= read.value();
            var written = _sink.write_all(chunk);
            if (written.is_err()) {
                return written;
            }
        }
        return _pad(entry.size);
    }

    ## Writes the end-of-archive marker (two zero blocks). Later calls do
    ## nothing. It does not close the sink.
    ##
    ## @returns an Ok result; an error when writing to the sink fails
    finish(): io.IoResult<void> {
        if (_finished) {
            return io.IoResult<void>.ok();
        }
        _finished = true;
        return _sink.write_all(_tar_zeros(1024));
    }

    # Writes the zero padding after `size` bytes of contents.
    _pad(size: ulong): io.IoResult<void> {
        var padding = (512 - size % 512) % 512;
        if (padding == 0) {
            return io.IoResult<void>.ok();
        }
        return _sink.write_all(_tar_zeros(padding));
    }

    # Writes the header of `entry` with contents of `size` bytes, after a pax
    # header when a field does not fit.
    _header(entry: TarEntry, size: ulong): io.IoResult<void> {
        assert(!_finished, "TarWriter used after finish()");
        var path = entry.path;
        if (entry.kind == EntryKind.Directory && !path.ends_with("/")) {
            path += "/";
        }
        var pax = Array<u8>();
        var name = path;
        var prefix = "";
        if (path.size > 100) {
            var split = _tar_split_path(path);
            if (split.is_value()) {
                var (head, tail) = split.value();
                prefix = head;
                name = tail;
            } else {
                _tar_pax_record(pax, "path", path);
                name = _tar_truncate(path, 100);
            }
        }
        var link = entry.link_target;
        if (link.size > 100) {
            _tar_pax_record(pax, "linkpath", link);
            link = _tar_truncate(link, 100);
        }
        var size_field = size;
        if (size >= 8589934592) {
            _tar_pax_record(pax, "size", $"{size}");
            size_field = 0;
        }
        if (!pax.is_empty) {
            var pax_entry = TarEntry("././@PaxHeader", EntryKind.Other);
            var written = _sink.write_all(_tar_header(pax_entry, "././@PaxHeader", "", "", 'x', pax.count));
            if (written.is_err()) {
                return written;
            }
            written = _sink.write_all(pax);
            if (written.is_err()) {
                return written;
            }
            written = _pad(pax.count);
            if (written.is_err()) {
                return written;
            }
        }
        u8 type_flag = '0';
        if (entry.kind == EntryKind.Directory) {
            type_flag = '5';
        } else if (entry.kind == EntryKind.Symlink) {
            type_flag = '2';
        } else if (entry.kind == EntryKind.HardLink) {
            type_flag = '1';
        }
        return _sink.write_all(_tar_header(entry, name, prefix, link, type_flag, size_field));
    }
}

# `count` zero bytes.
_tar_zeros(count: ulong): u8[] {
    var zeros = Array<u8>(count);
    ulong index = 0;
    while (index < count) {
        zeros.append(0);
        index += 1;
    }
    return zeros;
}

# Splits a path of more than 100 bytes at a `/` into a ustar prefix of at
# most 155 bytes and a name of at most 100; none when no `/` works.
_tar_split_path(path: String): (String, String)? {
    var size = path.size;
    if (size > 256) {
        return Optional<(String, String)>.Empty;
    }
    var bytes = path.bytes();
    # The latest `/` that leaves a short enough prefix; the name after it
    # must then fit in 100 bytes and not be empty.
    var index = size - 1;
    while (index > 0) {
        if (bytes[index] == '/' && index <= 155 && size - index - 1 <= 100 && index + 1 < size) {
            return Optional<(String, String)>.Value(
                (path.substr_bytes(0, index), path.substr_bytes(index + 1, size - index - 1))
            );
        }
        index -= 1;
    }
    return Optional<(String, String)>.Empty;
}

# The first bytes of `text`, at most `size`, cut at a UTF-8 boundary.
_tar_truncate(text: String, size: ulong): String {
    if (text.size <= size) {
        return text;
    }
    var end = size;
    while (end > 0 && !text._is_boundary(end)) {
        end -= 1;
    }
    return text.substr_bytes(0, end);
}

# Appends the pax record "<length> <key>=<value>\n" to `out`.
_tar_pax_record(out: u8[], key: String, value: String) {
    # The length counts its own digits.
    var body = key.size + value.size + 3;
    var length = body + 1;
    while ($"{length}".size + body != length) {
        length += 1;
    }
    out.append_all($"{length} {key}={value}\n".bytes());
}

# Writes `value` as a zero-padded octal number filling `size - 1` bytes of
# the field at `start`, then a NUL.
_tar_octal(header: u8[], start: ulong, size: ulong, value: ulong) {
    var left = value;
    var index = size - 1;
    while (index > 0) {
        index -= 1;
        header[start + index] = ('0' + (left & 7)) as u8;
        left = left >> 3;
    }
    header[start + size - 1] = 0;
}

# Copies the bytes of `text` (at most `size`) into the field at `start`.
_tar_put(header: u8[], start: ulong, size: ulong, text: String) {
    var bytes = text.bytes();
    ulong index = 0;
    while (index < size && index < bytes.count) {
        header[start + index] = bytes[index];
        index += 1;
    }
}

# A 512-byte ustar header.
_tar_header(entry: TarEntry, name: String, prefix: String, link: String, type_flag: u8, size: ulong): u8[] {
    var header = _tar_zeros(512);
    _tar_put(header, 0, 100, name);
    _tar_octal(header, 100, 8, (entry.mode & 4095) as ulong);
    _tar_octal(header, 108, 8, 0);
    _tar_octal(header, 116, 8, 0);
    _tar_octal(header, 124, 12, size);
    ulong modified = 0;
    if (entry.modified > 0 && entry.modified < 8589934592) {
        modified = entry.modified as ulong;
    }
    _tar_octal(header, 136, 12, modified);
    header[156] = type_flag;
    _tar_put(header, 157, 100, link);
    _tar_put(header, 257, 6, "ustar");
    header[263] = '0';
    header[264] = '0';
    _tar_put(header, 345, 155, prefix);
    # The checksum counts its own field as spaces, then is written as six
    # octal digits, a NUL and a space.
    ulong index = 148;
    while (index < 156) {
        header[index] = ' ';
        index += 1;
    }
    ulong sum = 0;
    for (var byte in header) {
        sum += byte as ulong;
    }
    _tar_octal(header, 148, 7, sum);
    header[155] = ' ';
    return header;
}

# OpenOptions, Metadata, File.

import "types";
import "path";
import "sys_posix";
import "sys_windows";

# Rust's OpenOptions as a plain builder: each setter returns this.
export struct OpenOptions {
    bool Read;
    bool Write;
    bool Append;
    bool Truncate;
    bool Create;
    bool CreateNew;   # fail if it exists (O_EXCL / CREATE_NEW)

    new() {
    }

    OpenOptions read(bool v) {
        Read = v;
        return this;
    }

    OpenOptions write(bool v) {
        Write = v;
        return this;
    }

    OpenOptions append(bool v) {
        Append = v;
        return this;
    }

    OpenOptions truncate(bool v) {
        Truncate = v;
        return this;
    }

    OpenOptions create(bool v) {
        Create = v;
        return this;
    }

    OpenOptions create_new(bool v) {
        CreateNew = v;
        return this;
    }

    IoResult<File> open(Path path) {
        return File.open_with(path, this);
    }
}

export struct Metadata {
    ulong Size;
    bool IsFile;
    bool IsDir;
    bool IsSymlink;
    bool ReadOnly;
    long Modified;      # ns since the Unix epoch
    long Accessed;
    long Created;       # 0 where unavailable
    Mode Permissions;   # mode_t bits (POSIX) / FILE_ATTRIBUTE_* bits (Windows)

    new() {
    }
}

# Bytes per read when a whole file or stream is read.
export _io_chunk_size(): ulong {
    return 65536;
}

# Write all `n` bytes at `p`, looping over partial writes.
export _io_write_all_raw(h: FileHandle, p: __ptr<u8>, n: ulong): IoResult<None> {
    ulong done = 0;
    while (done < n) {
        var r = _io_sys_write(h, p + done, n - done);
        if (r.is_err()) {
            return IoResult<None>.err(r.Error);
        }
        if (r.Value == 0) {
            return IoResult<None>.err(IoError(_io_sys_code_write_zero(), "failed to write the whole buffer"));
        }
        done = done + r.Value;
    }
    return _io_ok_none();
}

export struct File {
    FileHandle Handle;
    Path Path;
    bool Owned;   # false for stdin/stdout/stderr: never closed by File

    new() {
        Handle = _io_sys_invalid_handle();
        Owned = true;
    }

    # Closes the handle if it is still open when the last reference goes.
    destruct {
        if (Owned && _io_sys_handle_valid(Handle)) {
            _io_sys_close(Handle);
        }
    }

    # Read-only.
    static IoResult<File> open(Path path) {
        return File.open_with(path, OpenOptions().read(true));
    }

    # Write-only; created if missing, truncated if present.
    static IoResult<File> create(Path path) {
        return File.open_with(path, OpenOptions().write(true).create(true).truncate(true));
    }

    static IoResult<File> open_with(Path path, OpenOptions options) {
        # As Rust: some access is required, and creating or truncating needs
        # write access.
        var writes = options.Write || options.Append;
        if (!options.Read && !writes) {
            return IoResult<File>.err(IoError(_io_sys_code_invalid_input(), "no access mode: set read, write or append"));
        }
        if ((options.Create || options.CreateNew || options.Truncate) && !writes) {
            return IoResult<File>.err(IoError(_io_sys_code_invalid_input(), "create and truncate need write or append"));
        }
        if (path.Value.Size == 0) {
            return IoResult<File>.err(IoError(_io_sys_code_not_found(), "empty path"));
        }
        var h = _io_sys_open(path, options);
        if (h.is_err()) {
            return IoResult<File>.err(h.Error);
        }
        var f = File();
        f.Handle = h.Value;
        f.Path = path;
        return IoResult<File>.ok(f);
    }

    static File std_file(int which, String name) {
        var f = File();
        f.Handle = _io_sys_std_handle(which);
        f.Path = Path(name);
        f.Owned = false;
        return f;
    }

    static File stdin() {
        return File.std_file(0, "<stdin>");
    }

    static File stdout() {
        return File.std_file(1, "<stdout>");
    }

    static File stderr() {
        return File.std_file(2, "<stderr>");
    }

    bool is_open() {
        return _io_sys_handle_valid(Handle);
    }

    IoResult<None> check_open() {
        if (!_io_sys_handle_valid(Handle)) {
            return IoResult<None>.err(IoError(_io_sys_code_bad_handle(), "file is closed"));
        }
        return _io_ok_none();
    }

    # Append up to `max` bytes to `buf` (growing it); returns the count, 0 at
    # end of file.
    IoResult<ulong> read(u8[] buf, ulong max) {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.Error);
        }
        if (max == 0) {
            return IoResult<ulong>.ok(0);
        }
        buf.reserve(buf.Size + max);
        var r = _io_sys_read(Handle, buf.Data + buf.Size, max);
        if (r.is_ok()) {
            buf.Size = buf.Size + r.Value;
        }
        return r;
    }

    # Everything from the current position to end of file.
    IoResult<u8[]> read_all() {
        var buf = Array<u8>();
        while (true) {
            var r = read(buf, _io_chunk_size());
            if (r.is_err()) {
                return IoResult<u8[]>.err(r.Error);
            }
            if (r.Value == 0) {
                break;
            }
        }
        return IoResult<u8[]>.ok(buf);
    }

    # read_all as UTF-8 text; fails with is_invalid_input() on bad UTF-8.
    IoResult<String> read_string() {
        var r = read_all();
        if (r.is_err()) {
            return IoResult<String>.err(r.Error);
        }
        var bytes = r.Value;
        var p = bytes.Data as __ptr<char>;
        if (!_io_utf8_valid(p, bytes.Size)) {
            return IoResult<String>.err(IoError(_io_sys_code_invalid_input(), "stream did not contain valid UTF-8"));
        }
        return IoResult<String>.ok(_io_string_from(p, bytes.Size));
    }

    # One write call; may be partial. Returns the count written.
    IoResult<ulong> write(u8[] data) {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.Error);
        }
        return _io_sys_write(Handle, data.Data, data.Size);
    }

    IoResult<None> write_all(u8[] data) {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_write_all_raw(Handle, data.Data, data.Size);
    }

    IoResult<None> write_string(String s) {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_write_all_raw(Handle, s.Data as __ptr<u8>, s.Size);
    }

    # No SeekFrom enum: one method per origin. Each returns the new offset
    # from the start of the file.
    IoResult<Offset> seek_start(Offset pos) {
        return seek(pos, 0);
    }

    IoResult<Offset> seek_end(Offset delta) {
        return seek(delta, 2);
    }

    IoResult<Offset> seek_current(Offset delta) {
        return seek(delta, 1);
    }

    IoResult<Offset> seek(Offset offset, int whence) {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<Offset>.err(c.Error);
        }
        return _io_sys_seek(Handle, offset, whence);
    }

    # Truncate or extend (with zeros) to `size` bytes; the position is kept.
    IoResult<None> set_len(ulong size) {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_truncate(Handle, size);
    }

    # fsync / FlushFileBuffers.
    IoResult<None> sync() {
        var c = check_open();
        if (c.is_err()) {
            return c;
        }
        return _io_sys_sync(Handle);
    }

    IoResult<Metadata> metadata() {
        var c = check_open();
        if (c.is_err()) {
            return IoResult<Metadata>.err(c.Error);
        }
        return _io_sys_fstat(Handle);
    }

    # Explicit close, to observe its error. Idempotent: closing a closed File
    # succeeds. A standard stream is only marked closed.
    IoResult<None> close() {
        if (!_io_sys_handle_valid(Handle)) {
            return _io_ok_none();
        }
        var h = Handle;
        Handle = _io_sys_invalid_handle();
        if (!Owned) {
            return _io_ok_none();
        }
        return _io_sys_close(h);
    }

    # ── Whole-file conveniences (Rust fs::read, fs::write, ...) ─────────────

    static IoResult<u8[]> read_bytes(Path path) {
        var f = File.open(path);
        if (f.is_err()) {
            return IoResult<u8[]>.err(f.Error);
        }
        return f.Value.read_all();
    }

    static IoResult<String> read_to_string(Path path) {
        var f = File.open(path);
        if (f.is_err()) {
            return IoResult<String>.err(f.Error);
        }
        return f.Value.read_string();
    }

    static IoResult<None> write_bytes(Path path, u8[] data) {
        var f = File.create(path);
        if (f.is_err()) {
            return IoResult<None>.err(f.Error);
        }
        var file = f.Value;
        var w = file.write_all(data);
        if (w.is_err()) {
            return w;
        }
        return file.close();
    }

    # The proposal's `write_to_string` (`write_string` is the instance
    # method's name, and methods do not overload).
    static IoResult<None> write_text(Path path, String s) {
        var f = File.create(path);
        if (f.is_err()) {
            return IoResult<None>.err(f.Error);
        }
        var file = f.Value;
        var w = file.write_string(s);
        if (w.is_err()) {
            return w;
        }
        return file.close();
    }

    # Copy the contents of `from` to `to` (created or truncated); returns the
    # number of bytes copied.
    static IoResult<ulong> copy(Path from, Path to) {
        var src = File.open(from);
        if (src.is_err()) {
            return IoResult<ulong>.err(src.Error);
        }
        var dst = File.create(to);
        if (dst.is_err()) {
            return IoResult<ulong>.err(dst.Error);
        }
        var input = src.Value;
        var output = dst.Value;
        var buf = Array<u8>();
        ulong total = 0;
        while (true) {
            buf.clear();
            var r = input.read(buf, _io_chunk_size());
            if (r.is_err()) {
                return IoResult<ulong>.err(r.Error);
            }
            if (r.Value == 0) {
                break;
            }
            var w = output.write_all(buf);
            if (w.is_err()) {
                return IoResult<ulong>.err(w.Error);
            }
            total = total + r.Value;
        }
        var c = output.close();
        if (c.is_err()) {
            return IoResult<ulong>.err(c.Error);
        }
        return IoResult<ulong>.ok(total);
    }

    # Rename or move, replacing an existing `to`.
    static IoResult<None> rename(Path from, Path to) {
        return _io_sys_rename(from, to);
    }

    # Delete a file (not a directory).
    static IoResult<None> remove(Path path) {
        return _io_sys_unlink(path);
    }
}

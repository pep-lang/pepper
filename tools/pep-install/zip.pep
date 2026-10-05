# Unpacking a zip archive, as the Windows releases are. Only what those
# hold is read: entries stored or compressed with DEFLATE, without zip64
# or encryption. The whole archive is checked against its `.sha256` before
# it is unpacked, so the entries' CRC-32s are not checked again.

import archive;
import compress;
import [Directory, File, Path] from io;
import io;
import text;

# The signatures of the end of the central directory, a central directory
# entry, and a local file header.
const END_SIGNATURE: uint = 0x06054b50;
const CENTRAL_SIGNATURE: uint = 0x02014b50;
const LOCAL_SIGNATURE: uint = 0x04034b50;
# The size of the end record without its comment; the comment is at most
# 65535 bytes.
const END_SIZE: ulong = 22;
const MAX_COMMENT: ulong = 65535;

# Unpacks the zip archive `data` into `target`, dropping the first `strip`
# components of each entry's path, as `TarReader.extract` does. An error
# for a damaged archive, an entry that would land outside `target`, or a
# file that cannot be written.
export unzip(data: u8[], target: Path, strip: ulong): Result<void> {
    var end = _find_end(data);
    if (end.is_empty()) {
        return Result<void>.Err("not a zip archive: no end of central directory");
    }
    var count = _u16(data, end.value() + 10);
    var at = _u32(data, end.value() + 16) as ulong;
    for (var index in 0..count) {
        if (at + 46 > data.count or _u32(data, at) != CENTRAL_SIGNATURE) {
            return Result<void>.Err($"damaged zip archive: entry {index} of its central directory");
        }
        var method = _u16(data, at + 10);
        var compressed_size = _u32(data, at + 20) as ulong;
        var size = _u32(data, at + 24) as ulong;
        var name_length = _u16(data, at + 28);
        var extra_length = _u16(data, at + 30);
        var comment_length = _u16(data, at + 32);
        var local = _u32(data, at + 42) as ulong;
        if (at + 46 + name_length > data.count) {
            return Result<void>.Err("damaged zip archive: an entry's name runs past its end");
        }
        # Windows' own zip writers have stored `\` between components.
        var name = text.Utf8.decode_lossy(_bytes(data, at + 46, name_length)).replace("\\", "/");
        at += 46 + name_length + extra_length + comment_length;
        var components = archive.safe_components(name);
        if (components.is_empty()) {
            return Result<void>.Err($"unsafe path in zip archive: {name}");
        }
        if (components.value().count <= strip) {
            continue;
        }
        var path = target;
        for (var component_index in strip..components.value().count) {
            path = path.join(components.value()[component_index]);
        }
        var folder = name.ends_with("/") ? Optional<Path>.Value(path) : path.parent();
        if (folder.is_value()) {
            var created = Directory.create_all(folder.value());
            if (created.is_err()) {
                return Result<void>.Err($"cannot create {folder.value().to_string()}: {created.error().message}");
            }
        }
        if (name.ends_with("/")) {
            continue;
        }
        var contents = _contents(data, local, method, compressed_size, size, name)?;
        var written = File.write_bytes(path, contents);
        if (written.is_err()) {
            return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
        }
    }
    return Result<void>.ok();
}

# The contents of the entry `name` whose local header is at `local`.
_contents(data: u8[], local: ulong, method: ulong, compressed_size: ulong, size: ulong, name: String): Result<u8[]> {
    if (local + 30 > data.count or _u32(data, local) != LOCAL_SIGNATURE) {
        return Result<u8[]>.Err($"damaged zip archive: the local header of {name}");
    }
    var start = local + 30 + _u16(data, local + 26) + _u16(data, local + 28);
    if (start + compressed_size > data.count) {
        return Result<u8[]>.Err($"damaged zip archive: {name} runs past its end");
    }
    var packed = _bytes(data, start, compressed_size);
    if (method == 0) {
        return Result<u8[]>.ok(packed);
    }
    if (method != 8) {
        return Result<u8[]>.Err($"{name} is compressed with method {method}; only stored and DEFLATE entries are read");
    }
    var unpacked = compress.DecompressReader(io.ByteReader(packed), compress.Format.Raw).read_all();
    if (unpacked.is_err() or unpacked.value().count != size) {
        return Result<u8[]>.Err($"damaged zip archive: cannot inflate {name}");
    }
    return Result<u8[]>.ok(unpacked.value());
}

# Where the end of the central directory record starts: the last
# signature that leaves room for the record and its comment.
_find_end(data: u8[]): ulong? {
    if (data.count < END_SIZE) {
        return Optional<ulong>.Empty;
    }
    var at = data.count - END_SIZE;
    var lowest = at > MAX_COMMENT ? at - MAX_COMMENT : 0;
    while (true) {
        if (_u32(data, at) == END_SIGNATURE and at + END_SIZE + _u16(data, at + 20) == data.count) {
            return Optional<ulong>.Value(at);
        }
        if (at == lowest) {
            return Optional<ulong>.Empty;
        }
        at -= 1;
    }
}

# The `count` bytes of `data` from `start`.
_bytes(data: u8[], start: ulong, count: ulong): u8[] {
    var bytes = Array<u8>(count);
    for (var index in start..start + count) {
        bytes.append(data[index]);
    }
    return bytes;
}

# The little-endian 16-bit number at `at`.
_u16(data: u8[], at: ulong): ulong {
    return (data[at] as ulong) | ((data[at + 1] as ulong) << 8);
}

# The little-endian 32-bit number at `at`.
_u32(data: u8[], at: ulong): uint {
    return ((data[at] as uint)
        | ((data[at + 1] as uint) << 8)
        | ((data[at + 2] as uint) << 16)
        | ((data[at + 3] as uint) << 24));
}

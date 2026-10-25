## `--lib static|shared`: a library C code links, instead of an executable
## (see the book's "Calling Pepper from C").
##
## A static library is an archive of the program's objects, written here in
## the target's format (`write_archive`), so no archiver needs to be
## installed: GNU's for ELF and WebAssembly, BSD's as Apple's linkers read
## it, and the COFF archive (an import-library-style `.lib`) for Windows,
## each with the index of the symbols every member defines that linkers
## search. A shared library is linked by clang like an executable, with
## `-shared` (`link_objects`). Beside either goes a C header declaring the
## `[Export]`ed functions (`sema.header`).

import [File, Path] from io;
import compiler.link;
import compiler.sema;
import text;
import "linker";

## The kind of library `--lib` builds.
export enum LibraryKind {
    ## An archive of objects (`--lib static`).
    Static,
    ## A shared library (`--lib shared`).
    Shared,
    ## An iOS `.xcframework` of static libraries for devices and the
    ## simulator (`--lib xcframework`, `xcframework.pep`).
    Xcframework,
    ## A Swift package folder around an `.xcframework` (`--lib swift-package`).
    SwiftPackage,
    ## An Android library (`.aar`) of a shared library for each Android ABI
    ## (`--lib aar`, `aar.pep`).
    Aar,
}

## The library's file name for `name` on `target`: `libname.a`,
## `libname.so` or `libname.dylib`; `name.lib` or `name.dll` on Windows;
## `name.xcframework`, or the folder `name` for a Swift package;
## `name.aar`.
##
## @param kind the kind of library
## @param name its name: the package's, or the entry file's stem
## @param target the compile target
## @returns the file name
export library_file_name(kind: LibraryKind, name: String, target: link.Target): String {
    if (kind == LibraryKind.Xcframework) {
        return $"{name}.xcframework";
    }
    if (kind == LibraryKind.SwiftPackage) {
        return name;
    }
    if (kind == LibraryKind.Aar) {
        return $"{name}.aar";
    }
    if (target.os == "windows") {
        return kind == LibraryKind.Static ? $"{name}.lib" : $"{name}.dll";
    }
    if (kind == LibraryKind.Static) {
        return $"lib{name}.a";
    }
    return target.is_apple() ? $"lib{name}.dylib" : $"lib{name}.so";
}

## Where the C header for the library at `library` goes: beside it, named
## for the library without its `lib` prefix (`libfoo.a` has `foo.h`;
## Windows names have no prefix).
##
## @param library the library's path
## @param target the compile target
## @returns the header's path
export header_path(library: Path, target: link.Target): Path {
    var stem = library.file_stem();
    var name = stem.is_value() ? stem.value() : "";
    if (name.starts_with("lib") and name.size > 3 and target.os != "windows") {
        name = name.substr_bytes(3, name.size - 3);
    }
    var folder = library.parent();
    var file = Path($"{name}.h");
    return folder.is_value() ? folder.value().join(file) : file;
}

## The name of OpenSSL's license beside an Android shared library that
## links it (`place_openssl_license`).
export const OPENSSL_LICENSE = "LICENSE-OpenSSL.txt";

## Beside the Android shared library `library`, copies OpenSSL's license
## (`<runtime>/tls/android/LICENSE.txt`) as `OPENSSL_LICENSE` when the
## library links the toolchain's static OpenSSL (it imports `tls`, so it
## links `ssl` and the runtime holds that license), since the app's users
## must get a copy; otherwise removes one an earlier build left there.
##
## @param library the shared library's path
## @param libraries the libraries the program links, by name
## @param runtime the runtime's folder, if any
## @returns nothing, or why the license cannot be copied
export place_openssl_license(library: Path, libraries: String[], runtime: Path?): Result<void, String> {
    var folder = library.parent();
    var placed = folder.is_value() ? folder.value().join(Path(OPENSSL_LICENSE)) : Path(OPENSSL_LICENSE);
    # A program may link an OpenSSL of its own (`-l ssl`), whose license is
    # its own business: only the toolchain's is copied.
    var license = runtime.is_value() ?
        runtime.value().join(Path("tls")).join(Path("android")).join(Path("LICENSE.txt")) :
        Path("");
    if (!libraries.contains("ssl") or !runtime.is_value() or !license.is_file()) {
        if (placed.is_file()) {
            File.remove(placed);
        }
        return Result<void, String>.ok();
    }
    var copied = File.copy(license, placed);
    if (copied.is_err()) {
        return Result<void, String>.err($"cannot copy OpenSSL's license {license}: {copied.error().message}");
    }
    return Result<void, String>.ok();
}

## Writes the C header of a library to `path`: the declarations of
## `exports`, and for a static library the libraries a program linking it
## must link too (`libraries`, then the target's system libraries). Warns
## when nothing is exported.
##
## @param path where the header goes (`header_path`)
## @param exports what the program exports
## @param representations each enum's stored type, by name
## @param kind the kind of library
## @param libraries the libraries the program links, by name
## @param target the compile target
## @returns nothing, or why the header cannot be written
export write_header(
    path: Path,
    exports: sema.Exports,
    representations: HashMap<String, (String, long)>,
    kind: LibraryKind,
    libraries: String[],
    target: link.Target
): Result<void, String> {
    var declarations = sema.header_declarations(exports, representations);
    if (declarations.is_empty) {
        File.stderr().write_all(
            "warning: the library exports no functions; mark the functions C calls with '[Export]'\n"
        );
    }
    # What a program linking the static library links too.
    var needs = Array<String>();
    if (kind == LibraryKind.Static) {
        var all = libraries.copy();
        all.append_all(default_system_libraries(target.os));
        for (var library in all) {
            if (!needs.contains(library) and !is_built_into_libc(target.os, library)) {
                needs.append(library);
            }
        }
    }
    var name = path.file_name();
    var content = sema.header(name.is_value() ? name.value() : "", declarations, needs);
    var written = File.write_text(path, content);
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {path}: {written.error().message}");
    }
    return Result<void, String>.ok();
}

## How an archive is laid out, by the platform that reads it.
enum _Format {
    ## GNU's, for ELF and WebAssembly: a `/` index of big-endian offsets.
    Gnu,
    ## BSD's, as Apple's linkers read it: `#1/` names and a `__.SYMDEF`
    ## index, every member 8-byte aligned.
    Darwin,
    ## The COFF archive Windows linkers read: GNU's index, then a second,
    ## little-endian one, sorted by name.
    Coff,
}

## A member of the archive: its name, its bytes, and the symbols it
## defines.
struct _Member {
    var name: String;
    var data: u8[];
    var symbols: String[];

    construct(name: String, data: u8[], symbols: String[]) {
        this.name = name;
        this.data = data;
        this.symbols = symbols;
    }
}

## Writes the static library `output`: an archive of `objects`, in
## `target`'s format, with the index of the symbols each defines.
##
## @param objects the object files
## @param output the archive to write
## @param target the compile target
## @returns nothing, or why it cannot be written
export write_archive(objects: Path[], output: Path, target: link.Target): Result<void, String> {
    var format = target.os == "windows" ? _Format.Coff : (target.is_apple() ? _Format.Darwin : _Format.Gnu);
    var extension = target.os == "windows" ? "obj" : "o";
    var members = Array<_Member>();
    for (var i in 0..objects.count) {
        var read = File.read_bytes(objects[i]);
        if (read.is_err()) {
            return Result<void, String>.err($"cannot read {objects[i]}: {read.error().message}");
        }
        # Named by number: the cache names every object `0.o`, and two
        # members must not share a name.
        var data = read.value();
        members.append(_Member($"p{i}.{extension}", data, defined_symbols(data)));
    }
    var bytes = format == _Format.Darwin ? _darwin_archive(members) : _gnu_archive(members, format == _Format.Coff);
    var written = File.write_bytes(output, bytes);
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {output}: {written.error().message}");
    }
    return Result<void, String>.ok();
}

## The symbols an object file defines for other objects to use: its global
## and weak definitions (common symbols included), read from its symbol
## table: ELF (32 or 64 bits), Mach-O (64 bits) or COFF (regular or
## `/bigobj`). None for any other file, such as WebAssembly's.
##
## @param object the object file's bytes
## @returns the symbols, in the order the object lists them
export defined_symbols(object: u8[]): String[] {
    if (object.count >= 16 and object[0] == 0x7f and object[1] == 'E' as u8 and object[2] == 'L' as u8) {
        return _elf_symbols(object);
    }
    if (object.count >= 32 and _u32(object, 0) == 0xfeedfacf) {
        return _macho_symbols(object);
    }
    if (object.count >= 20) {
        return _coff_symbols(object);
    }
    return Array<String>();
}

# The ELF object's global and weak definitions.
_elf_symbols(object: u8[]): String[] {
    var out = Array<String>();
    bool wide = object[4] == 2;
    ulong sections = wide ? _u64(object, 0x28) : _u32(object, 0x20);
    ulong entry = _u16(object, wide ? 0x3a : 0x2e);
    ulong count = _u16(object, wide ? 0x3c : 0x30);
    if (sections == 0 or entry == 0 or sections + entry > object.count) {
        return out;
    }
    # With more sections than the header holds, section 0's size has the
    # count.
    if (count == 0) {
        count = wide ? _u64(object, sections + 32) : _u32(object, sections + 20);
    }
    for (var s in 0..count) {
        var header = sections + s * entry;
        if (header + entry > object.count or _u32(object, header + 4) != 2) {
            continue;
        }
        # SHT_SYMTAB: its symbols, and the string table its link names.
        ulong offset = wide ? _u64(object, header + 24) : _u32(object, header + 16);
        ulong size = wide ? _u64(object, header + 32) : _u32(object, header + 20);
        ulong link = _u32(object, header + (wide ? 40 : 24));
        var strings_header = sections + link * entry;
        if (strings_header + entry > object.count) {
            return out;
        }
        ulong strings = wide ? _u64(object, strings_header + 24) : _u32(object, strings_header + 16);
        ulong symbol_size = wide ? 24 : 16;
        var symbol = offset + symbol_size;
        while (symbol + symbol_size <= offset + size and symbol + symbol_size <= object.count) {
            var info = object[symbol + (wide ? 4 : 12)] as ulong;
            var index = _u16(object, symbol + (wide ? 6 : 14));
            var binding = info >> 4;
            # GLOBAL, WEAK or GNU_UNIQUE, and not undefined.
            if ((binding == 1 or binding == 2 or binding == 10) and index != 0) {
                var name = _c_string_at(object, strings + _u32(object, symbol));
                if (!name.is_empty) {
                    out.append(name);
                }
            }
            symbol += symbol_size;
        }
    }
    return out;
}

# The 64-bit Mach-O object's external definitions.
_macho_symbols(object: u8[]): String[] {
    var out = Array<String>();
    var commands = _u32(object, 16);
    ulong command = 32;
    for (var _ in 0..commands) {
        if (command + 8 > object.count) {
            break;
        }
        var size = _u32(object, command + 4);
        # LC_SYMTAB: the symbols and their names.
        if (_u32(object, command) == 2 and command + 24 <= object.count) {
            var symbols = _u32(object, command + 8);
            var count = _u32(object, command + 12);
            var strings = _u32(object, command + 16);
            for (var i in 0..count) {
                var symbol = symbols + i * 16;
                if (symbol + 16 > object.count) {
                    break;
                }
                var kind = object[symbol + 4] as ulong;
                # Not a debugging entry, external, and defined (or common).
                bool defined = (kind & 0x0e) != 0 or _u64(object, symbol + 8) != 0;
                if ((kind & 0xe0) == 0 and (kind & 1) != 0 and defined) {
                    var name = _c_string_at(object, strings + _u32(object, symbol));
                    if (!name.is_empty) {
                        out.append(name);
                    }
                }
            }
        }
        if (size == 0) {
            break;
        }
        command += size;
    }
    return out;
}

# The COFF object's external definitions: a regular object, or one built
# with `/bigobj` (more than 65279 sections), which LLVM writes for a large
# part.
_coff_symbols(object: u8[]): String[] {
    var out = Array<String>();
    bool big = _u16(object, 0) == 0 and _u16(object, 2) == 0xffff;
    if (big and object.count < 56) {
        return out;
    }
    var machine = _u16(object, big ? 6 : 0);
    # x86-64, AArch64 (and ARM64EC), or 32-bit x86.
    if (machine != 0x8664 and machine != 0xaa64 and machine != 0xa641 and machine != 0x14c) {
        return out;
    }
    ulong table = _u32(object, big ? 48 : 8);
    ulong count = _u32(object, big ? 52 : 12);
    ulong record = big ? 20 : 18;
    var strings = table + count * record;
    ulong i = 0;
    while (i < count) {
        var symbol = table + i * record;
        if (symbol + record > object.count) {
            break;
        }
        long section = big ? (_u32(object, symbol + 12) as int) as long : (_u16(object, symbol + 12) as short) as long;
        var storage = object[symbol + (big ? 18 : 16)];
        var aux = object[symbol + (big ? 19 : 17)] as ulong;
        # EXTERNAL, and defined: in a section, absolute, or common.
        bool defined = section > 0 or section == -1 or (section == 0 and _u32(object, symbol + 8) != 0);
        if (storage == 2 and defined) {
            var name = "";
            if (_u32(object, symbol) == 0) {
                name = _c_string_at(object, strings + _u32(object, symbol + 4));
            } else {
                var end = symbol;
                while (end < symbol + 8 and object[end] != 0) {
                    end += 1;
                }
                name = _text(object, symbol, end - symbol);
            }
            if (!name.is_empty) {
                out.append(name);
            }
        }
        i += 1 + aux;
    }
    return out;
}

# The little-endian 16-bit number at `at` in `bytes`; 0 past the end.
_u16(bytes: u8[], at: ulong): ulong {
    if (at + 2 > bytes.count) {
        return 0;
    }
    return (bytes[at] as ulong) | ((bytes[at + 1] as ulong) << 8);
}

# The little-endian 32-bit number at `at` in `bytes`; 0 past the end.
_u32(bytes: u8[], at: ulong): ulong {
    if (at + 4 > bytes.count) {
        return 0;
    }
    return _u16(bytes, at) | (_u16(bytes, at + 2) << 16);
}

# The little-endian 64-bit number at `at` in `bytes`; 0 past the end.
_u64(bytes: u8[], at: ulong): ulong {
    if (at + 8 > bytes.count) {
        return 0;
    }
    return _u32(bytes, at) | (_u32(bytes, at + 4) << 32);
}

# The `size` bytes at `at` in `bytes`, as text.
_text(bytes: u8[], at: ulong, size: ulong): String {
    var out = Array<u8>();
    for (var i in at..(at + size)) {
        out.append(bytes[i]);
    }
    return text.Utf8.decode_lossy(out);
}

# The NUL-terminated text at `at` in `bytes`; empty past the end.
_c_string_at(bytes: u8[], at: ulong): String {
    if (at >= bytes.count) {
        return "";
    }
    var end = at;
    while (end < bytes.count and bytes[end] != 0) {
        end += 1;
    }
    return _text(bytes, at, end - at);
}

# Appends `value`'s bytes to `out`.
_put(out: u8[], value: String) {
    out.append_all(value.bytes());
}

# Appends `value` padded with spaces to `width` bytes.
_put_field(out: u8[], value: String, width: ulong) {
    _put(out, value);
    for (var _ in value.size..width) {
        out.append(' ' as u8);
    }
}

# Appends a member header: its name field, then a date, owner and group of
# 0 (so the same objects give the same archive), `mode`, and `size`.
_put_header(out: u8[], name: String, mode: String, size: ulong) {
    _put_field(out, name, 16);
    _put_field(out, "0", 12);
    _put_field(out, "0", 6);
    _put_field(out, "0", 6);
    _put_field(out, mode, 8);
    _put_field(out, $"{size}", 10);
    _put(out, "`\n");
}

# Appends `value` as 4 bytes, big-endian, or little-endian.
_put_u32(out: u8[], value: ulong, big: bool) {
    for (var i in 0..4) {
        var shift = big ? (3 - i) * 8 : i * 8;
        out.append(((value >> shift) & 0xff) as u8);
    }
}

# Appends `value` as 2 little-endian bytes.
_put_u16(out: u8[], value: ulong) {
    out.append((value & 0xff) as u8);
    out.append(((value >> 8) & 0xff) as u8);
}

# Appends `pad` until `out` is a multiple of `align` long.
_pad(out: u8[], align: ulong, pad: u8) {
    while (out.count % align != 0) {
        out.append(pad);
    }
}

# A GNU archive of `members`, or with `coff` a COFF one: the index of the
# symbols each defines (`/`, big-endian offsets), for COFF a second index
# sorted by name (`/`, little-endian), then the members, each 2-byte
# aligned. Names are short (`p0.o/`), so no table of long names is needed.
_gnu_archive(members: _Member[], coff: bool): u8[] {
    ulong symbols = 0;
    ulong names = 0;
    for (var member in members) {
        symbols += member.symbols.count;
        for (var symbol in member.symbols) {
            names += symbol.size + 1;
        }
    }
    # Where each member's header starts: after the magic and the indexes.
    var first = 4 + 4 * symbols + names;
    first += first % 2;
    ulong start = 8 + 60 + first;
    if (coff) {
        var second = 4 + 4 * members.count + 4 + 2 * symbols + names;
        start += 60 + second + second % 2;
    }
    var offsets = Array<ulong>();
    for (var member in members) {
        offsets.append(start);
        start += 60 + member.data.count + member.data.count % 2;
    }
    var out = Array<u8>();
    _put(out, "!<arch>\n");
    _put_header(out, "/", "0", first);
    _put_u32(out, symbols, true);
    for (var m in 0..members.count) {
        for (var _ in members[m].symbols) {
            _put_u32(out, offsets[m], true);
        }
    }
    for (var member in members) {
        for (var symbol in member.symbols) {
            _put(out, symbol);
            out.append(0);
        }
    }
    _pad(out, 2, '\n' as u8);
    if (coff) {
        # Each symbol with its member's number (from 1), sorted by name.
        var sorted = Array<(String, ulong)>();
        for (var m in 0..members.count) {
            for (var symbol in members[m].symbols) {
                sorted.append((symbol, m + 1));
            }
        }
        sorted.sort((a, b) => a.0 < b.0 ? -1 : (a.0 > b.0 ? 1 : 0));
        var second = 4 + 4 * members.count + 4 + 2 * symbols + names;
        _put_header(out, "/", "0", second);
        _put_u32(out, members.count, false);
        for (var offset in offsets) {
            _put_u32(out, offset, false);
        }
        _put_u32(out, symbols, false);
        for (var (_, index) in sorted) {
            _put_u16(out, index);
        }
        for (var (symbol, _) in sorted) {
            _put(out, symbol);
            out.append(0);
        }
        _pad(out, 2, '\n' as u8);
    }
    for (var member in members) {
        _put_header(out, member.name + "/", "644", member.data.count);
        out.append_all(member.data);
        _pad(out, 2, '\n' as u8);
    }
    return out;
}

# A BSD archive of `members` as Apple's linkers read it, as LLVM writes it
# for Darwin: each name after its header (`#1/<length>`), padded with NULs
# so the member's bytes start 8-byte aligned, and each member padded to 8
# bytes; first the `__.SYMDEF` index of `ranlib` entries (the name's
# offset in the index's strings, the member header's offset), little-endian.
_darwin_archive(members: _Member[]): u8[] {
    var strings = Array<u8>();
    var entries = Array<(ulong, ulong)>();
    for (var m in 0..members.count) {
        for (var symbol in members[m].symbols) {
            entries.append((strings.count, m));
            _put(strings, symbol);
            strings.append(0);
        }
    }
    _pad(strings, 8, 0);
    var index = Array<u8>();
    _put_u32(index, entries.count * 8, false);
    var start = 8 + _darwin_size("__.SYMDEF", 8, 4 + entries.count * 8 + 4 + strings.count);
    var offsets = Array<ulong>();
    for (var member in members) {
        offsets.append(start);
        start += _darwin_size(member.name, start, member.data.count);
    }
    for (var (name, m) in entries) {
        _put_u32(index, name, false);
        _put_u32(index, offsets[m], false);
    }
    _put_u32(index, strings.count, false);
    index.append_all(strings);
    var out = Array<u8>();
    _put(out, "!<arch>\n");
    _put_darwin_member(out, "__.SYMDEF", "0", index);
    for (var member in members) {
        _put_darwin_member(out, member.name, "644", member.data);
    }
    return out;
}

# How many bytes a Darwin member named `name` holding `size` bytes takes
# when its header starts at `at`: the header, the name padded so the bytes
# start 8-byte aligned, and the bytes padded to 8.
_darwin_size(name: String, at: ulong, size: ulong): ulong {
    var after = at + 60 + name.size;
    var named = name.size + (8 - after % 8) % 8;
    return 60 + named + size + (8 - size % 8) % 8;
}

# Appends a Darwin member named `name` holding `data` (see `_darwin_size`).
_put_darwin_member(out: u8[], name: String, mode: String, data: u8[]) {
    var after = out.count + 60 + name.size;
    var padding = (8 - after % 8) % 8;
    var size = data.count + (8 - data.count % 8) % 8;
    _put_header(out, $"#1/{name.size + padding}", mode, name.size + padding + size);
    _put(out, name);
    for (var _ in 0..padding) {
        out.append(0);
    }
    out.append_all(data);
    _pad(out, 8, 0);
}

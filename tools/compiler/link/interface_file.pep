## A Pepper library's interface file (`--lib pepper`'s `.pepi`, #220), as
## program loading reads it: an `import` of the library finds it in the
## library folders, and its files join the program.
##
## The file is a text header, then the checked record of the library's
## files (`incremental.library_interface` writes it). The header's first
## line is `INTERFACE_MAGIC` and `RECORD_VERSION`; then, for each of the
## library's files:
##
## - `file <namespace>`, with ` root` after it for the library's root;
## - `imports` and, per import of the file in order, the namespace of the
##   library file it names, or `-` for one the program resolves (a runtime
##   module);
## - `export <name> <declaration>` for each name an importer of the file
##   sees, and the linked name of the declaration it denotes;
## - `text <size>`, a line break, and that many bytes: the file's
##   declarations as the library wrote them, with every function body and
##   comment blanked to spaces (line breaks kept), so positions in it are
##   the library source's. Linking reads it as it reads a source file;
##   the declarations' checked form comes from the record.
##
## Then `record`, a line break, and the record.

import digest;
import [File, Path] from io;
import os;
import [Utf8] from text;
import [Target] from "platform";
import [RECORD_VERSION] from "stamp";

## The first line of a library interface, before its record version.
export const INTERFACE_MAGIC = "pepper-library-interface ";

## The extension of a library interface file.
export const INTERFACE_EXTENSION = "pepi";

## A file of a library, as its interface names it.
export struct InterfaceFile {
    ## Its namespace, which the library's mangled names carry.
    var namespace: String;
    ## Whether it is the library's root, which an import of the library
    ## names.
    var root: bool = false;
    ## Per import of the file: the namespace of the library file it names,
    ## or `-` for one the program resolves.
    var imports: String[] = Array<String>();
    ## Each name an importer of the file sees -> the linked name of the
    ## declaration it denotes.
    var exports: HashMap<String, String> = HashMap<String, String>();
    ## Its declarations, bodies and comments blanked.
    var text: String = "";

    ## @param namespace the file's namespace
    construct(namespace: String) {
        this.namespace = namespace;
    }
}

## A library interface a program loaded.
export struct LibraryInterface {
    ## The library's name: what `import` names.
    var name: String;
    ## The interface file.
    var path: Path;
    ## The library's archive, beside it.
    var archive: Path;
    ## The hash of the interface file's bytes (`interface_hash`), which
    ## the archive's stamp must name.
    var hash: String = "";
    ## The library's files.
    var files: InterfaceFile[] = Array<InterfaceFile>();
    ## The record of the library's files.
    var record: u8[] = Array<u8>();

    ## @param name the library's name
    ## @param path the interface file
    ## @param archive the library's archive
    construct(name: String, path: Path, archive: Path) {
        this.name = name;
        this.path = path;
        this.archive = archive;
    }
}

## Returns the name of the interface file of the library `name` for
## `target`, beside its archive: `libgeo.pepi`, `geo.pepi` on Windows.
##
## @param name the library's name
## @param target the compile target
## @returns the file name
export interface_file_name(name: String, target: Target): String {
    return target.os == "windows" ? $"{name}.{INTERFACE_EXTENSION}" : $"lib{name}.{INTERFACE_EXTENSION}";
}

## Returns the folders of `$PEPPER_LIBRARY_PATH`, separated as in `PATH`.
##
## @returns the folders
export library_path_dirs(): Path[] {
    var dirs = Array<Path>();
    var library_path = os.environment("PEPPER_LIBRARY_PATH");
    if (library_path.is_value()) {
        var separator = os.system_os() == os.OperatingSystem.Windows ? ";" : ":";
        for (var dir in library_path.value().split(separator)) {
            if (!dir.is_empty) {
                dirs.append(Path(dir));
            }
        }
    }
    return dirs;
}

## Returns the hash of a library interface's bytes, which its library's
## stamp names (`Stamp.interface`).
##
## @param bytes the interface
## @returns the hash, in hexadecimal
export interface_hash(bytes: u8[]): String {
    var hasher = digest.Blake3();
    hasher.update(bytes);
    return hasher.finish_hex().substr_bytes(0, 16);
}

## Returns the interface of the library `name` in the first of `dirs` that
## holds one (`interface_file_name`), with its archive beside it; none when
## no folder does.
##
## @param name the library's name
## @param dirs the library folders, in search order
## @param target the compile target
## @returns the interface, why it cannot be read, or none
export find_library_interface(name: String, dirs: Path[], target: Target): Result<LibraryInterface, String>? {
    for (var dir in dirs) {
        var path = dir.join(Path(interface_file_name(name, target)));
        if (!path.is_file()) {
            continue;
        }
        var archive = path.with_extension(target.os == "windows" ? "lib" : "a");
        if (!archive.is_file()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err(
                    $"the Pepper library interface {path} has no archive {archive} beside it"
                )
            );
        }
        var bytes = File.read_bytes(path);
        if (bytes.is_err()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err($"cannot read {path}: {bytes.error().message}")
            );
        }
        var out = LibraryInterface(name, path, archive);
        var read = read_interface_bytes(out, bytes.value());
        if (read.is_value()) {
            return Optional<Result<LibraryInterface, String>>.Value(
                Result<LibraryInterface, String>.err($"{path}: {read.value()}")
            );
        }
        return Optional<Result<LibraryInterface, String>>.Value(Result<LibraryInterface, String>.ok(out));
    }
    return Optional<Result<LibraryInterface, String>>.Empty;
}

## Reads the interface file `bytes` into `out`: its files, its record and
## its hash.
##
## @param out the interface
## @param bytes the interface file's bytes
## @returns why it cannot be read, if it cannot
export read_interface_bytes(out: LibraryInterface, bytes: u8[]): String? {
    out.hash = interface_hash(bytes);
    ulong at = 0;
    var first = _line(bytes, at);
    if (!first.is_value() or first.value().0 != $"{INTERFACE_MAGIC}{RECORD_VERSION}") {
        return Optional<String>.Value($"not a Pepper library interface of record version {RECORD_VERSION}");
    }
    at = first.value().1;
    while (true) {
        var next = _line(bytes, at);
        if (!next.is_value()) {
            return Optional<String>.Value("the library interface ends before its record");
        }
        var (line, after) = next.value();
        at = after;
        if (line == "record") {
            out.record = bytes.slice(at, bytes.count).to_array();
            return Optional<String>.Empty;
        }
        var parts = line.split(" ");
        if (parts[0] == "file" and (parts.count == 2 or (parts.count == 3 and parts[2] == "root"))) {
            var file = InterfaceFile(parts[1]);
            file.root = parts.count == 3;
            out.files.append(file);
            continue;
        }
        if (out.files.is_empty) {
            return Optional<String>.Value($"a malformed library interface line: '{line}'");
        }
        var file = out.files[out.files.count - 1];
        if (parts[0] == "imports") {
            for (var i in 1..parts.count) {
                file.imports.append(parts[i]);
            }
        } else if (parts[0] == "export" and parts.count == 3) {
            file.exports[parts[1]] = parts[2];
        } else if (parts[0] == "text" and parts.count == 2) {
            var size = ulong.parse(parts[1]);
            if (!size.is_value() or at + size.value() + 1 > bytes.count or bytes[at + size.value()] != '\n') {
                return Optional<String>.Value("a library file's text is cut short");
            }
            file.text = Utf8.decode_lossy(bytes.slice(at, at + size.value()).to_array());
            at += size.value() + 1;
        } else {
            return Optional<String>.Value($"a malformed library interface line: '{line}'");
        }
    }
    return Optional<String>.Empty;
}

# The line of `bytes` at `at`, and where the next starts; none at the end.
_line(bytes: u8[], at: ulong): (String, ulong)? {
    if (at >= bytes.count) {
        return Optional<(String, ulong)>.Empty;
    }
    var end = at;
    while (end < bytes.count and bytes[end] != '\n') {
        end += 1;
    }
    var line = Utf8.decode_lossy(bytes.slice(at, end).to_array());
    return Optional<(String, ulong)>.Value((line, end < bytes.count ? end + 1 : end));
}

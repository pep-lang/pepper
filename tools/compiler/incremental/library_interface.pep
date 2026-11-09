## A Pepper library's interface (#220): the checked record of the library's
## files, which `--lib pepper` writes beside its archive (`<lib>.pepi`) and
## a program reads instead of the library's sources, as it reads a
## compilation unit's record from the build cache.
##
## The file is a text header, then the record. The header's first line is
## `INTERFACE_MAGIC` and `link.RECORD_VERSION`; then, for each of the
## library's files, `file <namespace>`, with `root` after it for the
## library's root, and a line `export <name> <declaration>` for each name
## an importer of the file sees and the linked name of the declaration it
## denotes; then `record`. The record is the one the build cache keeps
## (`_record_bytes`): the program's files' namespaces, which its file slots
## name, then the library's files checked as one compilation unit, a delta
## on the runtime's alone (`library_units`). Each file of the library reads
## as a file index of its own after the reading program's files
## (`read_library_interface`); the runtime's files are the program's
## own, so the runtime the library was checked on must be the program's
## (`link.Stamp.runtime_interface`).
##
## The record holds what a program checks against and instantiates:
## declarations and their resolved types, field layouts, attributes,
## generic bodies and their expansions, link summaries, expanded `static`
## blocks. The library's non-generic functions and methods leave their
## bodies out, as the build cache's skipped ones do (`sema.strip_bodies`),
## when a link summary that calls through no trait value stands in for
## them; one whose summary does keeps its body, so a program that adds an
## implementation of the trait summarizes it again over its own
## (`sema.check_confinement`'s stale summaries).

import digest;
import [File, Path] from io;
import compiler.link;
import compiler.sema;
import [Utf8] from text;
import "compilation_units";

## The first line of a library interface, before its record version.
export const INTERFACE_MAGIC = "pepper-library-interface ";

## The extension of a library interface file.
export const INTERFACE_EXTENSION = "pepi";

## A file of a library, as its interface names it.
export struct LibraryFile {
    ## Its namespace, which the library's mangled names carry.
    var namespace: String;
    ## Its file index in the module read (`read_library_interface`): after
    ## the reading program's own files.
    var file: uint;
    ## Whether it is the library's root, whose exports an importer of the
    ## library sees.
    var root: bool = false;
    ## Each name an importer of the file sees -> the linked name of the
    ## declaration it denotes (`link.FileScope.exports`).
    var exports: HashMap<String, String> = HashMap<String, String>();

    ## @param namespace the file's namespace
    ## @param file its index in the program
    construct(namespace: String, file: uint) {
        this.namespace = namespace;
        this.file = file;
    }
}

## A library interface read back (`read_library_interface`).
export struct LibraryInterface {
    ## The library's files.
    var files: LibraryFile[] = Array<LibraryFile>();
    ## The module: the runtime the interface was read onto, with the
    ## library's declarations.
    var module: sema.Module;

    ## @param module the module read
    construct(module: sema.Module) {
        this.module = module;
    }
}

## Returns the path of the interface of the library at `archive`: beside
## it, with the extension `INTERFACE_EXTENSION` (`libgeo.a` ->
## `libgeo.pepi`).
##
## @param archive the library's archive
## @returns the interface's path
export interface_path(archive: Path): Path {
    return archive.with_extension(INTERFACE_EXTENSION);
}

## Returns the interface of the library `program` builds: `unit`'s files
## (`library_units`' last), checked as `checked_unit` on the module `base`
## indexes, the runtime's. Writing leaves `checked_unit` as it was.
##
## @param program the program
## @param unit the library's compilation unit
## @param checked_unit its checked unit (`sema.finish_checked`)
## @param base the index of the runtime's module it was checked on
## @returns the interface file's bytes
export library_interface(
    program: link.Program, unit: CompilationUnit, checked_unit: sema.CheckedUnit, base: sema.DeltaBase
): u8[] {
    var header = StringBuilder();
    header.append($"{INTERFACE_MAGIC}{link.RECORD_VERSION}\n");
    var files = HashSet<uint>();
    for (var file in unit.files) {
        files.insert(file as uint);
        var f = program.files[file];
        header.append($"file {f.namespace}{file == 0 ? " root" : ""}\n");
        var names = Array<String>();
        if (file < program.scopes.count) {
            for (var (name, _) in program.scopes[file].exports) {
                if (!name.is_empty) {
                    names.append(name);
                }
            }
        }
        names.sort((a, b) => a.compare(b));
        for (var name in names) {
            header.append($"export {name} {program.scopes[file].exports[name]}\n");
        }
    }
    header.append("record\n");
    var stripped = _strip(checked_unit.module, files);
    var record = _record_bytes(program, checked_unit, base);
    for (var (function, body) in stripped) {
        function.body = body;
    }
    var out = header.to_string().bytes();
    out.append_all(record);
    return out;
}

## Reads the library interface `bytes` onto `base`, the module of
## `program`'s runtime, checked (as `merged_module` merges a record).
##
## @param program the program reading it
## @param base its runtime's module, which the read changes: the caller
##   drops it
## @param bytes the interface file's bytes
## @returns the interface, or why it cannot be read
export read_library_interface(program: link.Program, base: sema.Module, bytes: u8[]): Result<LibraryInterface, String> {
    # The header is text, so its offsets are the bytes' in the decoded text.
    var marker = "\nrecord\n";
    var end = Utf8.decode_lossy(bytes).find(marker);
    if (end < 0) {
        return Result<LibraryInterface, String>.err("not a Pepper library interface");
    }
    var record_start = end as ulong + marker.size;
    var lines = Utf8.decode_lossy(bytes.slice(0, end as ulong).to_array()).split("\n");
    if (lines.is_empty or lines[0] != $"{INTERFACE_MAGIC}{link.RECORD_VERSION}") {
        return Result<LibraryInterface, String>.err(
            $"not a Pepper library interface of record version {link.RECORD_VERSION}"
        );
    }
    var slots = _record_slots(program);
    var files = Array<LibraryFile>();
    for (var i in 1..lines.count) {
        var parts = lines[i].split(" ");
        if (parts.count >= 2 and parts[0] == "file") {
            # The library's own, even when a file of the program has its
            # namespace.
            uint file = (program.files.count + files.count) as uint;
            slots[parts[1]] = file;
            var library_file = LibraryFile(parts[1], file);
            library_file.root = parts.count == 3 and parts[2] == "root";
            files.append(library_file);
        } else if (parts.count == 3 and parts[0] == "export" and !files.is_empty) {
            files[files.count - 1].exports[parts[1]] = parts[2];
        } else {
            return Result<LibraryInterface, String>.err($"a malformed library interface line: '{lines[i]}'");
        }
    }
    var read = _read_record(
        slots, bytes.slice(record_start, bytes.count).to_array(), Optional<sema.Module>.Value(base), true
    );
    if (read.is_err()) {
        return Result<LibraryInterface, String>.err(read.error());
    }
    var module = sema.resume_checked(read.value());
    sema.settle_merged(module);
    var out = LibraryInterface(module);
    out.files = files;
    return Result<LibraryInterface, String>.ok(out);
}

## Writes the interface `bytes` beside the library archive `archive`
## (`interface_path`).
##
## @param archive the library's archive
## @param bytes the interface (`library_interface`)
## @returns why it could not be written, if it could not
export write_library_interface(archive: Path, bytes: u8[]): Result<void, String> {
    var path = interface_path(archive);
    var written = File.write_bytes(path, bytes);
    if (written.is_err()) {
        return Result<void, String>.err($"cannot write {path}: {written.error().message}");
    }
    return Result<void, String>.ok();
}

## Returns the hash of a library interface's bytes, which its library's
## stamp names (`link.Stamp.interface`).
##
## @param bytes the interface
## @returns the hash, in hexadecimal
export interface_file_hash(bytes: u8[]): String {
    var hasher = digest.Blake3();
    hasher.update(bytes);
    return hasher.finish_hex().substr_bytes(0, 16);
}

# Takes the bodies of the library's non-generic functions and methods
# written in `files` out of `module` (as `sema.strip_bodies` does a cached
# file's) when a link summary that calls through no trait value stands in
# for each, and returns them to put back.
_strip(module: sema.Module, files: HashSet<uint>): Array<(sema.FunctionDef, sema.Block?)> {
    var out = Array<(sema.FunctionDef, sema.Block?)>();
    var strip = (key: String, function: sema.FunctionDef) => {
        if (function.loc.is_none()
            or !files.contains(function.loc.file)
            or function.name == "main"
            or !function.owner.is_none()
            or function.is_generic_func
            or function.generic_params.count > 0
            or (!function.body.is_value() and !function.pending_body.is_value())) {
            return;
        }
        var summary = module.checked.summaries.try_get(key);
        if (!summary.is_value()) {
            return;
        }
        var (_, text) = summary.value();
        if (text.contains("\n")) {
            return;
        }
        sema.full_body(function);
        out.append((function, function.body));
        sema.drop_body(function);
    };
    for (var function in module.functions) {
        strip(function.name, function);
    }
    for (var st in module.structs) {
        if (st.generic_params.count == 0) {
            for (var method in st.method_members) {
                strip(sema.method_key(st.name, method.name), method);
            }
        }
    }
    return out;
}

## A Pepper library's interface (#220): the checked record of the library's
## files, which `--lib pepper` writes beside its archive (`<lib>.pepi`) and
## a program that imports the library reads instead of its sources, as it
## reads a compilation unit's record from the build cache.
##
## The file is a text header, then the record (`link.interface_file`
## describes the header). For each of the library's files the header holds
## its namespace, the runtime modules it imports, its exports, and its link
## table (`link.link_table`): the names its declarations took and what
## linking reads of them, from which program loading links the file
## (`link.load`). No source text. The record is the one the build cache
## keeps (`_record_bytes`): the program's files'
## namespaces, which its file slots name, then the library's files checked
## as one compilation unit, a delta on the runtime's alone
## (`library_units`). A program's compilation unit of the library's files
## takes it as checked (`interface_records`); the runtime's files are the
## program's own, so the runtime the library was checked on must be the
## program's (`link.Stamp.runtime_interface`).
##
## The record holds what a program checks against and instantiates:
## declarations and their resolved types, field layouts, attributes,
## generic bodies and their expansions, link summaries, expanded `static`
## blocks. The library's non-generic functions and methods leave their
## bodies out, as the build cache's skipped ones do (`sema.strip_bodies`),
## when a link summary that calls through no trait value stands in for
## them; one whose summary does keeps its body, so a program that adds an
## implementation of the trait summarizes it again over its own
## (`sema.check_confinement`'s stale summaries). The program compiles none
## of them: the archive defines them.

import [File, Path] from io;
import compiler.link;
import compiler.sema;
import "compilation_units";

## Returns the path of the interface of the library at `archive`: beside
## it, with the extension `link.INTERFACE_EXTENSION` (`libgeo.a` ->
## `libgeo.pepi`).
##
## @param archive the library's archive
## @returns the interface's path
export interface_path(archive: Path): Path {
    return archive.with_extension(link.INTERFACE_EXTENSION);
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
    header.append($"{link.INTERFACE_MAGIC}{link.RECORD_VERSION}\n");
    var files = HashSet<uint>();
    for (var file in unit.files) {
        files.insert(file as uint);
    }
    for (var file in unit.files) {
        var f = program.files[file];
        header.append($"file {f.namespace}{file == 0 ? " root" : ""}\n");
        # The modules it imports or re-exports from that the program
        # loads: the runtime's.
        for (var m in 0..f.imports.count) {
            var target = f.imports[m];
            var imp = f.module.imports[m];
            if (target.is_value() and !files.contains(target.value() as uint) and !imp.is_local) {
                header.append($"import {imp.name}\n");
            }
        }
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
        header.append(link.link_table(f.module, program.target));
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

## Returns the records of the compilation units of `units` that hold the
## files of a Pepper library's interface (`link.ProgramFile.interface`),
## by compilation unit, as `check_compilation_units` takes records made
## already: the interface's record, its hash as the unit's own interface,
## and no warnings.
##
## @param program the program
## @param units its compilation units
## @returns the records
export interface_records(program: link.Program, units: CompilationUnit[]): HashMap<ulong, (u8[], String, String)> {
    var out = HashMap<ulong, (u8[], String, String)>();
    for (var k in 0..units.count) {
        var files = units[k].files;
        if (!files.is_empty and program.files[files[0]].interface.is_value()) {
            var interface = program.files[files[0]].interface.value();
            out[k] = (interface.record, interface.hash, "");
        }
    }
    return out;
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

# Takes the bodies of the library's non-generic functions and methods
# written in `files` out of `module` (as `sema.strip_bodies` does a cached
# file's) when a link summary that calls through no trait value stands in
# for each, and returns them to put back.
_strip(module: sema.Module, files: HashSet<uint>): Array<(sema.FunctionDef, sema.Block?)> {
    var out = Array<(sema.FunctionDef, sema.Block?)>();
    var strip = (key: String, function: sema.FunctionDef) => {
        if (function.loc.is_none()
            or !files.contains(function.loc.file)
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

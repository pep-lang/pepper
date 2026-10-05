## The build cache: each compilation unit's object, kept under a key that
## hashes everything its code can depend on, and a record of each program
## built, so an unchanged program is not built again.
##
## A unit's objects (a large unit is compiled as several) are
## `<cache>/v1/units/<unit>/<key>/<n>.o`: written to a folder of the build
## and moved into place as one, and never changed after, since the same key
## gives the same objects. So builds share the cache with no lock, and link
## the objects where they are. Each unit keeps its newest few keys
## (`_KEEP`), so switching between builds that differ (`-O` levels,
## programs with other overrides) does not rebuild every time.

import digest;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import process;

## The cache layout's version: a new layout gets a new folder.
const _VERSION = "v1";
## How many keys' objects each unit keeps.
const _KEEP = 8;

## A build cache.
export struct Cache {
    ## The folder holding this layout's files (`<cache>/v1`).
    var dir: Path;

    construct(dir: Path) {
        this.dir = dir.join(Path(_VERSION));
    }

    ## Returns the folder of the objects of `unit` built under `key`.
    ##
    ## @param unit the unit's name
    ## @param key its key
    ## @returns the folder, which need not exist
    objects(unit: String, key: String): Path {
        return dir.join(Path("units")).join(Path(unit)).join(Path(key));
    }

    ## Moves `built`, a folder of objects just written, to where the objects
    ## of `unit` under `key` belong, and removes the unit's oldest keys beyond
    ## the few it keeps. A folder already there, from a build that failed
    ## part way, is replaced.
    ##
    ## @param built the folder of objects
    ## @param unit the unit's name
    ## @param key its key
    ## @returns the objects' folder in the cache, or why it could not be moved
    store(built: Path, unit: String, key: String): Result<Path, String> {
        var target = objects(unit, key);
        var folder = target.parent().value();
        var created = Directory.create_all(folder);
        if (created.is_err()) {
            return Result<Path, String>.err($"cannot create {folder}: {created.error().message}");
        }
        if (File.rename(built, target).is_err()) {
            Directory.remove_all(target);
            var moved = File.rename(built, target);
            if (moved.is_err()) {
                return Result<Path, String>.err($"cannot move {built} to {target}: {moved.error().message}");
            }
        }
        _prune(folder);
        return Result<Path, String>.ok(target);
    }

    ## Returns where the record of the program that writes `output` is.
    _record(output: Path): Path {
        return dir.join(Path("programs")).join(Path(digest.to_hex(digest.blake3(output.to_string()))));
    }

    ## Returns whether `output` is what the program keyed `key` last built
    ## with no warnings, unchanged since.
    ##
    ## @param output the executable
    ## @param key the program's key (`program_key`)
    ## @returns true when nothing needs building
    is_built(output: Path, key: String): bool {
        var record = File.read_to_string(_record(output));
        if (record.is_err()) {
            return false;
        }
        var lines = record.value().split("\n");
        if (lines.count < 2 or lines[0] != key) {
            return false;
        }
        var built = File.read_bytes(output);
        return built.is_ok() and digest.to_hex(digest.blake3(built.value())) == lines[1];
    }

    ## Records that `output` is the program keyed `key`, built with no
    ## warnings; a build that warned forgets it instead, so it is checked,
    ## and warns, again.
    ##
    ## @param output the executable
    ## @param key the program's key
    ## @param warned whether the build printed warnings
    record(output: Path, key: String, warned: bool) {
        var path = _record(output);
        if (warned) {
            File.remove(path);
            return;
        }
        var built = File.read_bytes(output);
        if (built.is_err()) {
            return;
        }
        var created = Directory.create_all(path.parent().value());
        if (created.is_err()) {
            return;
        }
        var partial = Path($"{path}.{process.id()}");
        var written = File.write_text(partial, $"{key}\n{digest.to_hex(digest.blake3(built.value()))}\n");
        if (written.is_err() or File.rename(partial, path).is_err()) {
            File.remove(partial);
        }
    }
}

## Returns the cache a build uses: `$PEPPER_CACHE_DIR` when set, else
## `<work>/.pep/cache`.
##
## @param work the folder the build works in
## @returns the cache
export default_cache(work: Path): Cache {
    var named = os.environment("PEPPER_CACHE_DIR");
    if (named.is_value() and !named.value().is_empty) {
        return Cache(Path(named.value()));
    }
    return Cache(work.join(Path(".pep")).join(Path("cache")));
}

## Removes the oldest keys' objects in `folder` beyond the newest `_KEEP`.
## A build linking one of them at the same time would fail its link, and
## building again rebuilds it.
_prune(folder: Path) {
    var entries = Directory.open(folder);
    if (entries.is_err()) {
        return;
    }
    var listed = entries.value().entries();
    if (listed.is_err() or listed.value().count <= _KEEP) {
        return;
    }
    var aged = Array<(long, Path)>();
    for (var entry in listed.value()) {
        var path = folder.join(Path(entry.name));
        var metadata = path.metadata();
        if (metadata.is_ok() and metadata.value().is_directory) {
            aged.append((metadata.value().modified, path));
        }
    }
    aged.sort((a, b) => {
        var (x, _) = a;
        var (y, _) = b;
        return x > y ? -1 : (x < y ? 1 : 0);
    });
    for (var i in (_KEEP as ulong)..aged.count) {
        var (_, path) = aged[i];
        Directory.remove_all(path);
    }
}

## The keys of a program's units and of the program, from what its code
## can depend on.
export struct Keys {
    ## What every key starts from: the compiler and how the build
    ## generates code.
    var _base: String;
    ## Each file's hash: its name, namespace, kind and text.
    var _files: String[] = Array<String>();

    ## @param program the loaded program
    ## @param build how code is generated: the target, CPU, `-O` level and
    ##   anything else that changes it
    construct(program: link.Program, build: String) {
        var options = Array<String>();
        for (var (name, value) in program.target.build_options) {
            options.append($"{name}={value}");
        }
        options.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
        var defined = " ".join(options);
        _base = $"{compiler_identity()}\n{build}\n{program.target.os} {program.target.arch}\n{defined}\n";
        for (var file in program.files) {
            var hasher = digest.Blake3();
            hasher.update($"{file.name}\n{file.namespace}\n{file.prelude} {file.prelude_part}\n");
            hasher.update(file.source);
            _files.append(hasher.finish_hex());
        }
    }

    ## Returns the key of `unit`: its name and files, and each file its code
    ## can depend on (`link.unit_inputs`).
    ##
    ## @param program the program
    ## @param unit one of its units
    ## @returns the key, in hexadecimal
    unit(program: link.Program, unit: link.Unit): String {
        var hasher = digest.Blake3();
        hasher.update(_base);
        hasher.update($"unit {unit.name}\n");
        for (var file in unit.files) {
            hasher.update($"own {program.files[file].namespace}\n");
        }
        for (var file in link.unit_inputs(program, unit)) {
            hasher.update($"{_files[file]}\n");
        }
        return hasher.finish_hex();
    }

    ## Returns the key of the whole program: every file, in namespace order,
    ## and `linking`, what linking it takes (libraries, folders, output).
    ##
    ## @param program the program
    ## @param linking what the link takes, as text
    ## @returns the key, in hexadecimal
    program(program: link.Program, linking: String): String {
        var order = Array<ulong>();
        for (var i in 0.._files.count) {
            order.append(i);
        }
        order.sort((a, b) => {
            var x = program.files[a].namespace;
            var y = program.files[b].namespace;
            return x < y ? -1 : (x > y ? 1 : 0);
        });
        var hasher = digest.Blake3();
        hasher.update(_base);
        hasher.update($"program\n{linking}\n");
        for (var file in order) {
            hasher.update($"{_files[file]}\n");
        }
        return hasher.finish_hex();
    }
}

## Identifies the running compiler: its executable's path, size and time
## of modification, so a rebuilt compiler misses every key.
##
## @returns the identity, as text
export compiler_identity(): String {
    var executable = process.executable_path();
    if (executable.is_err()) {
        return "pepc";
    }
    var metadata = executable.value().metadata();
    if (metadata.is_err()) {
        return executable.value().to_string();
    }
    return $"{executable.value()} {metadata.value().size} {metadata.value().modified}";
}

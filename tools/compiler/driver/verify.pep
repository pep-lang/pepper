## `--verify-cache`: checks the build cache, for testing the compiler. A
## build that reused objects from the cache skipped the bodies of the files
## they came from, and linked objects an earlier build made; checking builds
## the same program again with an empty cache of its own, so every unit and
## compilation unit is generated from its sources with every body read, and
## fails if any object it stores differs from the one the build's cache
## holds under the same key: a cache hit whose code is stale, or a unit
## whose code changed because other units' bodies were skipped.

import [Cache] from compiler.incremental;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import "build";

## Builds `program` again as `options` say, with an empty cache in a
## folder of its own, and compares every object that build stores with the
## object `options.cache` holds under the same unit and key. A key the
## cache no longer holds (pruned, say) is not compared.
##
## @param program the program, loaded again as the build loaded it
## @param options the build's options, with its cache
## @returns nothing, or what differs
export verify_cache(program: link.Program, options: BuildOptions): Result<void, String> {
    if (!options.cache.is_value()) {
        return Result<void, String>.ok();
    }
    var dir = options.build_dir.join(Path($"verify.{process.id()}"));
    Directory.remove_all(dir);
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {dir}: {created.error().message}");
    }
    var fresh = Cache(dir.join(Path("cache")));
    var again = BuildOptions(dir.join(Path(options.output.file_name().value())), dir.join(Path("build")));
    again.opt_level = options.opt_level;
    again.libraries = options.libraries;
    again.library_dirs = options.library_dirs;
    again.objects = options.objects;
    again.cache = Optional<Cache>.Value(fresh);
    again.in_process = options.in_process;
    again.part_size = options.part_size;
    again.frame_pointers = options.frame_pointers;
    again.runtime_checks = options.runtime_checks;
    again.sysroot = options.sysroot;
    again.cpu = options.cpu;
    again.lto = options.lto;
    again.library = options.library;
    again.debug = options.debug;
    again.debug_static_expanded = options.debug_static_expanded;
    again.entry = options.entry;
    var built = build(program, again);
    if (built.is_err()) {
        Directory.remove_all(dir);
        return Result<void, String>.err(
            $"build cache: the program does not build again without the cache:\n{built.error()}"
        );
    }
    var differ = Array<String>();
    _compare(fresh.dir.join(Path("u")), options.cache.value().dir.join(Path("u")), "", differ);
    Directory.remove_all(dir);
    if (!differ.is_empty) {
        return Result<void, String>.err(
            $"build cache: these cached objects differ from the code generated for them again:\n  {"\n  ".join(differ)}"
        );
    }
    return Result<void, String>.ok();
}

# Compares each object under `fresh` (`<unit>/<key>/<n>.o`) with the file
# at the same place under `cached`, if it is there, adding to `differ` the
# relative path of each that differs.
_compare(fresh: Path, cached: Path, relative: String, differ: String[]) {
    var opened = Directory.open(fresh);
    if (opened.is_err()) {
        return;
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        return;
    }
    for (var entry in listed.value()) {
        var path = relative.is_empty ? entry.name : $"{relative}/{entry.name}";
        if (entry.is_directory) {
            _compare(entry.path, cached.join(Path(entry.name)), path, differ);
            continue;
        }
        if (!_is_object(entry.name)) {
            continue;
        }
        var theirs = cached.join(Path(entry.name));
        if (!theirs.is_file()) {
            continue;
        }
        var mine = File.read_bytes(entry.path);
        var other = File.read_bytes(theirs);
        if (mine.is_err() or other.is_err() or !_same(mine.value(), other.value())) {
            differ.append(path);
        }
    }
}

# Whether `name` is an object a unit or compilation unit was compiled into:
# native, or bitcode with link-time optimization.
_is_object(name: String): bool {
    return name.ends_with(".o") or name.ends_with(".obj") or name.ends_with(".bc");
}

# Whether `a` and `b` hold the same bytes.
_same(a: u8[], b: u8[]): bool {
    if (a.count != b.count) {
        return false;
    }
    for (var i in 0..a.count) {
        if (a[i] != b[i]) {
            return false;
        }
    }
    return true;
}

## The identity stamp in every program and library Pepper writes (#220),
## and reading it back from a file another build made.
##
## The stamp is text: `STAMP_MAGIC`, then one `key value` line per field,
## ended by a NUL. Codegen puts it in a section of its own (`.pepmeta`, or
## `__DATA,__pepmeta` on Mach-O) that the linker keeps, so an object, an
## archive of objects, a shared library and an executable all carry it as
## written. A reader finds it by its first line in the file's bytes, with
## no knowledge of the file's format.

import digest;
import [File, Path] from io;
import [Ascii] from text;

## The first line of every stamp, which a reader looks for.
export const STAMP_MAGIC = "pepper-stamp 1\n";

## The ABI the compiler writes code for. A compiler change that changes
## what the code of two builds relies on of each other (struct layouts,
## name mangling, the reference counting protocol, release hooks) bumps it.
export const ABI_VERSION: uint = 1;

## The features this compiler has, as a level the runtime can require: a
## compiler change the runtime may need to rely on raises it (#220).
export const COMPILER_LEVEL: long = 1;

## The name of the runtime's constant stating the `COMPILER_LEVEL` it needs.
## A runtime change that needs a newer compiler raises it, so a compiler
## below that level says so, at that constant, instead of failing on the
## new code.
export const REQUIRED_LEVEL_NAME = "_COMPILER_LEVEL";

## What built a program or library.
export struct Stamp {
    ## The compiler's release (`0.13.0-dev`).
    var version: String = "";
    ## Its `ABI_VERSION`.
    var abi: uint = 0;
    ## The platform the code is for: its OS and architecture.
    var target: String = "";
    ## A hash of the runtime's prelude, the types every build shares.
    var runtime: String = "";
    ## The build options defined, as `name=value`, sorted.
    var options: String[] = Array<String>();

    ## The stamp as text, as codegen writes it (without the NUL).
    text(): String {
        var out = StringBuilder();
        out.append(STAMP_MAGIC);
        out.append($"version {version}\nabi {abi}\ntarget {target}\nruntime {runtime}\n");
        for (var option in options) {
            out.append($"option {option}\n");
        }
        return out.to_string();
    }

    ## How an error names the build: `pepper 0.12.0 (ABI 1) for linux x86_64`.
    describe(): String {
        return $"pepper {version} (ABI {abi}) for {target}";
    }
}

## Returns the stamp of a build by the compiler of release `version`.
##
## @param version the compiler's release
## @param os the target's OS
## @param arch the target's architecture
## @param prelude the texts of the runtime's prelude files, in program order
## @param build_options the build options defined, by name
## @returns the stamp
export make_stamp(
    version: String, os: String, arch: String, prelude: String[], build_options: HashMap<String, String>
): Stamp {
    var stamp = Stamp();
    stamp.version = version;
    stamp.abi = ABI_VERSION;
    stamp.target = $"{os} {arch}";
    var hasher = digest.Blake3();
    for (var text in prelude) {
        hasher.update(text);
        hasher.update("\n");
    }
    stamp.runtime = hasher.finish_hex().substr_bytes(0, 16);
    for (var (name, value) in build_options) {
        stamp.options.append($"{name}={value}");
    }
    stamp.options.sort((a, b) => a.compare(b));
    return stamp;
}

## Parses `text`, a stamp starting with `STAMP_MAGIC`; nothing when it is
## not one.
export parse_stamp(text: String): Stamp? {
    if (!text.starts_with(STAMP_MAGIC)) {
        return Optional<Stamp>.Empty;
    }
    var stamp = Stamp();
    for (var line in text.substr_bytes(STAMP_MAGIC.size, text.size - STAMP_MAGIC.size).lines()) {
        var space = line.find(" ");
        if (space < 0) {
            return Optional<Stamp>.Empty;
        }
        var at = space as ulong;
        var key = line.substr_bytes(0, at);
        var value = line.substr_bytes(at + 1, line.size - at - 1);
        if (key == "version") {
            stamp.version = value;
        } else if (key == "abi") {
            var abi = uint.parse(value);
            if (!abi.is_value()) {
                return Optional<Stamp>.Empty;
            }
            stamp.abi = abi.value();
        } else if (key == "target") {
            stamp.target = value;
        } else if (key == "runtime") {
            stamp.runtime = value;
        } else if (key == "option") {
            stamp.options.append(value);
        }
    }
    # The magic alone, as a program holding this file's constant has it, is
    # no stamp.
    if (stamp.abi == 0) {
        return Optional<Stamp>.Empty;
    }
    return Optional<Stamp>.Value(stamp);
}

## The largest file `read_stamps` reads. A Pepper library, its runtime
## included, is a few MB; the libraries larger than this that a build
## links (LLVM's) are not Pepper's.
export const STAMP_SCAN_LIMIT: ulong = 64 * 1024 * 1024;

## Returns each different stamp in the file at `path` (an archive holds
## one per object that has one); none for a file no Pepper build wrote, or
## one larger than `STAMP_SCAN_LIMIT`.
##
## @param path the object, archive, shared library or executable
## @returns its stamps, or why the file could not be read
export read_stamps(path: Path): Result<Stamp[], String> {
    # shortcut: a Pepper library above the limit goes unchecked; read in
    # chunks if libraries that large appear.
    var metadata = path.metadata();
    if (metadata.is_ok() and metadata.value().size > STAMP_SCAN_LIMIT) {
        return Result<Stamp[], String>.ok(Array<Stamp>());
    }
    var bytes = File.read_bytes(path);
    if (bytes.is_err()) {
        return Result<Stamp[], String>.err($"cannot read {path}: {bytes.error().message}");
    }
    var data = bytes.value();
    var magic = STAMP_MAGIC.bytes();
    var out = Array<Stamp>();
    var seen = HashSet<String>();
    ulong at = 0;
    while (at + magic.count <= data.count) {
        if (!_starts_at(data, at, magic)) {
            at += 1;
            continue;
        }
        var end = at;
        while (end < data.count and data[end] != 0) {
            end += 1;
        }
        var text = Ascii.decode_lossy(data.slice(at, end).to_array());
        var stamp = parse_stamp(text);
        if (stamp.is_value() and !seen.contains(text)) {
            seen.insert(text);
            out.append(stamp.value());
        }
        at = end;
    }
    return Result<Stamp[], String>.ok(out);
}

# Whether `data` holds `magic` at `at`.
_starts_at(data: u8[], at: ulong, magic: u8[]): bool {
    for (var i in 0..magic.count) {
        if (data[at + i] != magic[i]) {
            return false;
        }
    }
    return true;
}

## Why the code `library` stamps cannot be linked into the build `build`
## stamps; nothing when it can. The ABI, the platform and the runtime must
## match, and so must each build option both define. The release may
## differ: the ABI says what changed.
##
## @param library the stamp read from the library
## @param build this build's
## @returns the reason, worded to follow "'libgeo.a' was built by ...;"
export stamp_mismatch(library: Stamp, build: Stamp): String? {
    if (library.abi != build.abi) {
        return Optional<String>.Value($"this build is {build.describe()}");
    }
    if (library.target != build.target) {
        return Optional<String>.Value($"this build is for {build.target}");
    }
    if (library.runtime != build.runtime) {
        return Optional<String>.Value($"this build's runtime differs ({library.runtime} there, {build.runtime} here)");
    }
    var ours = HashMap<String, String>();
    for (var option in build.options) {
        var (name, value) = _option(option);
        ours[name] = value;
    }
    for (var option in library.options) {
        var (name, value) = _option(option);
        var mine = ours.try_get(name);
        if (mine.is_value() and mine.value() != value) {
            return Optional<String>.Value(
                $"it defines the build option '{name}' as '{value}', and this build as '{mine.value()}'"
            );
        }
    }
    return Optional<String>.Empty;
}

# `name=value` split at its `=`.
_option(option: String): (String, String) {
    var equals = option.find("=");
    if (equals < 0) {
        return (option, "");
    }
    var at = equals as ulong;
    return (option.substr_bytes(0, at), option.substr_bytes(at + 1, option.size - at - 1));
}

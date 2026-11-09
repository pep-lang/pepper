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
export const STAMP_MAGIC = "pepper-stamp 2\n";

## The first line of a stamp an older compiler wrote, which reads as a
## self-contained library's (`KIND_C`).
const _STAMP_MAGIC_V1 = "pepper-stamp 1\n";

## What every version of `STAMP_MAGIC` starts with.
const _STAMP_PREFIX = "pepper-stamp ";

## A stamp's `kind` for a library built for a Pepper program
## (`--lib pepper`): it leaves the runtime to the program.
export const KIND_PEPPER = "pepper";

## A stamp's `kind` for a self-contained library, which holds its own
## runtime (`--lib static`, `--lib shared`, and any version 1 stamp).
export const KIND_C = "c";

## The ABI the compiler writes code for. A compiler change that changes
## what the code of two builds relies on of each other (struct layouts,
## name mangling, the reference counting protocol, release hooks) bumps it.
export const ABI_VERSION: uint = 2;

## The version of a Pepper library's interface (`--lib pepper`'s
## `.pepi`): the checked-unit record (`sema.CheckedUnit.write`) and what it
## means. Any change to the record's encoding or meaning bumps it, whatever
## the release; `record_schema_test.pep` fails when the record's code
## changes and it does not (#220).
export const RECORD_VERSION: uint = 2;

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
    ## The CPU the code is for (`codegen.Cpu.key`); empty when unknown.
    var cpu: String = "";
    ## The runtime checks kept, as the build writes them.
    var checks: String = "";
    ## Whether every function keeps its frame pointer.
    var frame_pointers: bool = false;
    ## A library's kind (`KIND_PEPPER`, `KIND_C`); empty for a program.
    var kind: String = "";
    ## A Pepper library's name; empty for any other build.
    var library: String = "";
    ## The function of a Pepper library that sets its globals.
    var init: String = "";
    ## The function of a Pepper library that releases a thread's
    ## thread-locals.
    var release: String = "";
    ## The Pepper libraries a Pepper library links, by name, which the
    ## program initializes first.
    var needs: String[] = Array<String>();
    ## Each runtime module the build loaded, as `name hash`, sorted, the
    ## hash of its files' interface hashes; only in a build that makes or
    ## links a Pepper library, once it is checked.
    var modules: String[] = Array<String>();
    ## The `RECORD_VERSION` of the compiler that wrote it; written for a
    ## Pepper library only.
    var record: uint = 0;
    ## A hash of the interface hashes of the runtime's prelude files (the
    ## build cache's, which a body edit leaves alone unless it changes a
    ## return type or a link summary); only in a build that makes or links
    ## a Pepper library, once it is checked.
    var runtime_interface: String = "";
    ## The hash of a Pepper library's interface file (`.pepi`).
    var interface: String = "";

    ## The stamp as text, as codegen writes it (without the NUL).
    text(): String {
        var out = StringBuilder();
        out.append(STAMP_MAGIC);
        out.append($"version {version}\nabi {abi}\ntarget {target}\nruntime {runtime}\n");
        if (!cpu.is_empty) {
            out.append($"cpu {cpu}\nchecks {checks}\nframe-pointers {frame_pointers}\n");
        }
        for (var option in options) {
            out.append($"option {option}\n");
        }
        if (!kind.is_empty) {
            out.append($"kind {kind}\n");
        }
        if (!library.is_empty) {
            out.append($"library {library}\ninit {init}\nrelease {release}\n");
        }
        if (kind == KIND_PEPPER) {
            out.append($"record {record}\n");
        }
        if (!runtime_interface.is_empty) {
            out.append($"runtime-interface {runtime_interface}\n");
        }
        if (!interface.is_empty) {
            out.append($"interface {interface}\n");
        }
        for (var name in needs) {
            out.append($"needs {name}\n");
        }
        for (var module in modules) {
            out.append($"module {module}\n");
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
    stamp.record = RECORD_VERSION;
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

## Parses `text`, a stamp starting with `STAMP_MAGIC`, or with version 1's
## magic, which reads as a self-contained library's (`KIND_C`); nothing
## when it is neither.
export parse_stamp(text: String): Stamp? {
    bool v1 = text.starts_with(_STAMP_MAGIC_V1);
    if (!v1 and !text.starts_with(STAMP_MAGIC)) {
        return Optional<Stamp>.Empty;
    }
    var stamp = Stamp();
    if (v1) {
        stamp.kind = KIND_C;
    }
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
        } else if (key == "cpu") {
            stamp.cpu = value;
        } else if (key == "checks") {
            stamp.checks = value;
        } else if (key == "frame-pointers") {
            stamp.frame_pointers = value == "true";
        } else if (key == "kind") {
            stamp.kind = value;
        } else if (key == "library") {
            stamp.library = value;
        } else if (key == "init") {
            stamp.init = value;
        } else if (key == "release") {
            stamp.release = value;
        } else if (key == "needs") {
            stamp.needs.append(value);
        } else if (key == "module") {
            stamp.modules.append(value);
        } else if (key == "record") {
            var record = uint.parse(value);
            if (!record.is_value()) {
                return Optional<Stamp>.Empty;
            }
            stamp.record = record.value();
        } else if (key == "runtime-interface") {
            stamp.runtime_interface = value;
        } else if (key == "interface") {
            stamp.interface = value;
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
    # Any version: `parse_stamp` tells them apart.
    var magic = _STAMP_PREFIX.bytes();
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
## stamps; nothing when it can. A self-contained library (any kind but
## `KIND_PEPPER`) keeps its runtime to itself, so only its platform must
## match. For a Pepper library the record version, the ABI, the platform
## and the CPU must match, and so must the runtime's interface, each
## runtime module's both load and each build option both define. The
## interfaces are compared once both stamps hold them (a build's, once it
## is checked). The compiler releases may differ: the record and ABI
## versions say what changed.
##
## @param library the stamp read from the library
## @param build this build's
## @returns the reason, worded to follow "'libgeo.a' was built by ...;"
export stamp_mismatch(library: Stamp, build: Stamp): String? {
    if (library.kind != KIND_PEPPER) {
        if (library.target != build.target) {
            return Optional<String>.Value($"this build is for {build.target}");
        }
        return Optional<String>.Empty;
    }
    if (library.record != build.record) {
        return Optional<String>.Value(
            $"its interface is record version {library.record}, and this build reads version {build.record}"
        );
    }
    if (library.abi != build.abi) {
        return Optional<String>.Value($"this build is {build.describe()}");
    }
    if (library.target != build.target) {
        return Optional<String>.Value($"this build is for {build.target}");
    }
    if (!library.runtime_interface.is_empty
        and !build.runtime_interface.is_empty
        and library.runtime_interface != build.runtime_interface) {
        return Optional<String>.Value(
            $"this build's runtime interface differs ({library.runtime_interface} there, {build.runtime_interface} here)"
        );
    }
    if (library.cpu != build.cpu) {
        return Optional<String>.Value($"it is for the CPU '{library.cpu}', and this build for '{build.cpu}'");
    }
    var modules = HashMap<String, String>();
    for (var module in build.modules) {
        var (name, hash) = _split_at(module, " ");
        modules[name] = hash;
    }
    for (var module in library.modules) {
        var (name, hash) = _split_at(module, " ");
        var mine = modules.try_get(name);
        if (mine.is_value() and mine.value() != hash) {
            return Optional<String>.Value($"the runtime module '{name}' differs ({hash} there, {mine.value()} here)");
        }
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

## What differs between the code a Pepper library's stamp `library`
## describes and the build `build` stamps that only changes the code
## inside each side: the runtime checks and the frame pointers.
##
## @param library the stamp read from the library
## @param build this build's
## @returns each difference, worded to follow "'libgeo.a' was built "
export stamp_warnings(library: Stamp, build: Stamp): String[] {
    var out = Array<String>();
    if (library.kind != KIND_PEPPER) {
        return out;
    }
    if (library.checks != build.checks) {
        out.append($"with the runtime checks '{library.checks}', and this build with '{build.checks}'");
    }
    if (library.frame_pointers != build.frame_pointers) {
        out.append(
            library.frame_pointers ?
                "with frame pointers, and this build without" :
                "without frame pointers, and this build with"
        );
    }
    return out;
}

# `name=value` split at its `=`.
_option(option: String): (String, String) {
    return _split_at(option, "=");
}

# `text` split at its first `separator`: all of it and empty without one.
_split_at(text: String, separator: String): (String, String) {
    var found = text.find(separator);
    if (found < 0) {
        return (text, "");
    }
    var at = found as ulong;
    return (text.substr_bytes(0, at), text.substr_bytes(at + separator.size, text.size - at - separator.size));
}

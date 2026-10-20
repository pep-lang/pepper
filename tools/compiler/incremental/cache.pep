## The build cache: each translation unit's object (`link.TranslationUnit`,
## one source file; here "unit" means a translation unit), kept under a key
## that hashes everything its code can depend on, and a record of each
## program built, so an unchanged program is not built again.
##
## A unit is compiled as one part or more, and each part's object is kept on
## its own, `<cache>/v3/u/<unit>#<n>/<key>/0.o`, under a key of its
## file's text and the interfaces of everything else it reads
## (`Keys.part`): like a C file's object, which depends on its text and its
## headers, so a body edit in one file compiles that file's parts again,
## and no other file's. A unit's own key (`<cache>/v3/u/<unit>/<key>/`) keeps what a later build needs to
## skip its bodies, and the list of its parts' objects (`parts`). A
## compilation unit's objects are kept the same way, as unit `+<name>`. Each is
## written to a folder of the build and moved into place as one, and never
## changed after, since the same key gives the same objects. So builds share the cache with no lock, and link
## the objects where they are. Each unit keeps its newest few keys
## (`_KEEP`), so switching between builds that differ (`-O` levels,
## programs with other overrides) does not rebuild every time; reusing a key
## makes it the newest, and a key stored or reused lately (`_GRACE`) is
## kept regardless, since another build may be linking it. A unit's
## folder spells its name's `/` as `.` (`process.command`), so it holds only
## its own keys: nested, unit `process` would prune the folders of units
## `process/test/...` beside its keys.
##
## Paths in the cache stay short, since it sits in the project's folder and
## Windows tools fail on a path over 260 characters: one-letter
## folders, a unit's folder cut to `_NAME_SIZE` characters
## (`_unit_folder`), and a key's to `_KEY_SIZE` (`_key_name`), so no path
## adds more than about 70 characters to the cache's own.

import compiler.ast;
import async;
import [Diagnostic] from compiler.diagnostic;
import digest;
import [Directory, File, IoResult, Path] from io;
import compiler.link;
import os;
import process;
import compiler.sema;
import "interface";

## The cache layout's version: a new layout gets a new folder.
const _VERSION = "v3";
## How many hexadecimal digits of a key name its folder: 80 bits, so two
## keys of one unit never share one.
const _KEY_SIZE: ulong = 20;
## The most characters of a unit's name its folder keeps.
const _NAME_SIZE: ulong = 20;
## How many keys' objects each unit keeps.
const _KEEP = 8;
## How long a key's objects are kept after they were stored or last reused,
## in nanoseconds, however many newer keys there are: a build running at
## the same time may be linking them.
const _GRACE: long = 600000000000;
## How many times `Cache.reused_objects` looks for a key's objects, and how
## long it waits between looks, in milliseconds: about a second in all.
const _REUSE_TRIES: ulong = 20;
const _REUSE_WAIT = 50;

## A build cache.
export struct Cache {
    ## The folder holding this layout's files (`<cache>/v3`).
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
        return dir.join(Path("u")).join(Path(_unit_folder(unit))).join(Path(_key_name(key)));
    }

    ## Returns the folder of the object of part `n` of `unit` built under
    ## `key` (`Keys.part`).
    ##
    ## @param unit the unit's name
    ## @param n the part's place among the unit's parts
    ## @param key its key
    ## @returns the folder, which need not exist
    part(unit: String, n: ulong, key: String): Path {
        return objects($"{unit}#{n}", key);
    }

    ## Marks the objects in `folder`, a key's, as just reused, so the
    ## unit's pruning counts them as its newest. Mark a key before checking
    ## its objects are there: a build pruning it then keeps it (`_prune`).
    ##
    ## @param folder the key's folder (`objects`)
    ## @returns whether it was marked; not when a build pruned it first
    used(folder: Path): bool {
        return folder.set_modified(os.SystemTime.now().unix_nanoseconds()).is_ok();
    }

    ## Returns the objects of `unit` under `key` (`numbered_objects`),
    ## marked as just reused, for linking a unit this build found in the
    ## cache when it checked it. A build pruning the unit moves a key's
    ## folder aside, and back when it was reused meanwhile (`_prune`), so a
    ## folder found missing or empty is looked for again for about a
    ## second: a link without its objects fails on undefined symbols.
    ##
    ## @param unit the unit's name
    ## @param key its key
    ## @param extension the objects' file extension
    ## @returns the objects, or why the cache no longer holds them
    reused_objects(unit: String, key: String, extension: String): Result<Path[], String> {
        var folder = objects(unit, key);
        for (var _ in 0.._REUSE_TRIES) {
            if (used(folder)) {
                var found = numbered_objects(folder, extension);
                if (!found.is_empty) {
                    return Result<Path[], String>.ok(found);
                }
            }
            async.Thread.sleep(_REUSE_WAIT);
        }
        return Result<Path[], String>.err(
            $"the build cache no longer holds the objects of '{unit}' ({folder}); build again"
        );
    }

    ## Moves `built`, a folder of objects just written, to where the objects
    ## of `unit` under `key` belong, and removes the unit's oldest keys beyond
    ## the few it keeps. When another build stored that key first, its
    ## objects stay and `built` goes: they are the same objects, and that
    ## build may be linking them now. A key's folder only ever appears whole,
    ## by a rename.
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
        var moved = File.rename(built, target);
        if (moved.is_err() and !target.metadata().is_ok()) {
            # A rename cannot cross drives, and the build folder can sit on
            # another one than the cache (a temp folder on C: and the
            # checkout on D:, as on a hosted Windows runner).
            moved = _move_across_drives(built, target);
        }
        if (moved.is_err()) {
            if (!target.metadata().is_ok()) {
                return Result<Path, String>.err($"cannot move {built} to {target}: {moved.error().message}");
            }
            Directory.remove_all(built);
        }
        _prune(folder);
        return Result<Path, String>.ok(target);
    }

    ## Returns where the record of the program that writes `output` is.
    _record(output: Path): Path {
        return dir.join(Path("p")).join(Path(_key_name(digest.to_hex(digest.blake3(output.to_string())))));
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

## The name of the folder of `unit`'s keys: its name with `/` as `.` and `:`
## as `_` (Windows forbids `:`), and when that is longer than `_NAME_SIZE`
## characters, its start and a hash of the whole, so no two units share a
## folder. A namespace never holds `.`.
_unit_folder(unit: String): String {
    var name = unit.replace("/", ".").replace(":", "_");
    if (name.length <= _NAME_SIZE) {
        return name;
    }
    var hash = digest.to_hex(digest.blake3(unit)).substr(0, 8);
    return $"{name.substr(0, _NAME_SIZE - 9)}~{hash}";
}

## The name of the folder or file of `key`, a hexadecimal hash: its first
## `_KEY_SIZE` digits.
_key_name(key: String): String {
    return key.substr(0, _KEY_SIZE);
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

## Removes the oldest keys' objects in `folder` beyond the newest `_KEEP`,
## but none stored or reused within `_GRACE`: a build running at the same
## time may be linking them. A key's folder leaves by a rename, whole, as it
## came, so a removal that stops partway (a file open on Windows) leaves no
## key without its objects. A key a build reused (`used`) after the listing
## here is put back: that build checks its objects after marking it, so
## either it finds the key gone and compiles, or the key stays.
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
    var now = os.SystemTime.now().unix_nanoseconds();
    for (var i in (_KEEP as ulong)..aged.count) {
        var (modified, path) = aged[i];
        if (now - modified < _GRACE) {
            continue;
        }
        # Reused since the listing: a build may be about to link it.
        var current = path.metadata();
        if (current.is_ok() and now - current.value().modified < _GRACE) {
            continue;
        }
        # A name no key has; a leftover is pruned again later.
        var removing = folder.join(Path($".removing.{process.id()}.{i}"));
        if (File.rename(path, removing).is_err()) {
            continue;
        }
        var renamed = removing.metadata();
        if (renamed.is_ok() and now - renamed.value().modified < _GRACE) {
            File.rename(removing, path);
            continue;
        }
        Directory.remove_all(removing);
    }
}

## The keys of a program's units and of the program, from what its code
## can depend on. A unit reads the files of other units by their interface
## hashes (`interface_hash`), so a body edit in one unit leaves the others'
## keys alone: early cutoff. A file of a unit that reaches this one back
## through the units' inputs (an override file the prelude instantiates, a
## forced import) is read by its text, since its interface can depend on
## this unit.
export struct Keys {
    ## What every key starts from: the compiler and how the build
    ## generates code.
    var _base: String;
    ## Each file's identity: its name, namespace and kind.
    var _identity: String[] = Array<String>();
    ## Each file's hash: its identity and text.
    var _files: String[] = Array<String>();
    ## Each unit's input files, and whether each is read by its text.
    var _inputs: Array<Array<(ulong, bool)>> = Array<Array<(ulong, bool)>>();
    ## Each file's unit, by index.
    var _unit_of: ulong[] = Array<ulong>();
    ## Whether every input is read by its text, never by its interface
    ## (`-g`): debug info holds the positions interfaces leave out.
    var exact_positions: bool = false;

    ## @param program the loaded program
    ## @param units its translation units
    ## @param build how code is generated: the target, CPU, `-O` level and
    ##   anything else that changes it
    construct(program: link.Program, units: link.TranslationUnit[], build: String) {
        var options = Array<String>();
        for (var (name, value) in program.target.build_options) {
            options.append($"{name}={value}");
        }
        options.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
        var defined = " ".join(options);
        _base = $"{compiler_identity()}\n{build}\n{program.target.os} {program.target.arch}\n{defined}\n";
        for (var file in program.files) {
            var identity = $"{file.name}\n{file.namespace}\n{file.prelude} {file.prelude_part}\n";
            _identity.append(identity);
            var hasher = digest.Blake3();
            hasher.update(identity);
            hasher.update(file.source);
            _files.append(hasher.finish_hex());
        }
        var unit_of = Array<ulong>();
        for (var _ in program.files) {
            unit_of.append(0);
        }
        for (var u in 0..units.count) {
            for (var file in units[u].files) {
                unit_of[file] = u;
            }
        }
        var inputs = Array<ulong[]>();
        var reads = Array<HashSet<ulong>>();
        for (var unit in units) {
            var files = link.unit_inputs(program, unit);
            inputs.append(files);
            var read = HashSet<ulong>();
            for (var file in files) {
                read.insert(unit_of[file]);
            }
            reads.append(read);
        }
        _unit_of = unit_of;
        var reaches = _reaches(reads);
        for (var u in 0..units.count) {
            var own = Array<(ulong, bool)>();
            for (var file in inputs[u]) {
                var v = unit_of[file];
                own.append((file, v == u or reaches[v].contains(u)));
            }
            _inputs.append(own);
        }
    }

    ## Returns what every key starts from: the compiler and how the build
    ## generates code.
    ##
    ## @returns the text
    base(): String {
        return _base;
    }

    ## Returns the key of unit `u`: its name and files, and each file its
    ## code can depend on (`link.unit_inputs`), by its text in its own unit
    ## and by its interface in another; none while an interface it needs is
    ## not known.
    ##
    ## @param program the program
    ## @param units its units
    ## @param u the unit's index
    ## @param interfaces each file's interface hash, when known
    ## @returns the key, in hexadecimal, or none
    unit(program: link.Program, units: link.TranslationUnit[], u: ulong, interfaces: Array<String?>): String? {
        var hasher = digest.Blake3();
        hasher.update(_base);
        hasher.update($"unit {units[u].name}\n");
        for (var file in units[u].files) {
            hasher.update($"own {program.files[file].namespace}\n");
        }
        for (var (file, by_text) in _inputs[u]) {
            if (by_text or exact_positions) {
                hasher.update($"{_files[file]}\n");
                continue;
            }
            if (!interfaces[file].is_value()) {
                return Optional<String>.Empty;
            }
            hasher.update($"{_identity[file]}interface {interfaces[file].value()}\n");
        }
        return Optional<String>.Value(hasher.finish_hex());
    }

    ## Returns the key of the part of unit `u` that compiles `files`, once
    ## sema has checked the program and every file's interface is known:
    ## the part's files by their text, and every other file the unit's code
    ## can depend on by its interface, the unit's other files included,
    ## those of a unit that reaches this one back by their text. The part's
    ## object holds the code of its files' own definitions, and copies of
    ## the generic code they use, which the interfaces hold; another file's
    ## non-generic bodies reach it only through what the interfaces keep of
    ## them (return types and link summaries).
    ##
    ## @param program the program
    ## @param units its units
    ## @param u the unit's index
    ## @param files the part's files
    ## @param interfaces each file's interface hash: those the unit reads set
    ## @returns the key, in hexadecimal
    part(
        program: link.Program, units: link.TranslationUnit[], u: ulong, files: ulong[], interfaces: Array<String?>
    ): String {
        var own = HashSet<ulong>();
        var hasher = digest.Blake3();
        hasher.update(_base);
        hasher.update($"part of {units[u].name}\n");
        for (var file in files) {
            own.insert(file);
            hasher.update($"own {_files[file]}\n");
        }
        for (var (file, by_text) in _inputs[u]) {
            if (own.contains(file)) {
                continue;
            }
            if ((by_text and _unit_of[file] != u) or exact_positions) {
                hasher.update($"{_files[file]}\n");
                continue;
            }
            hasher.update($"{_identity[file]}interface {interfaces[file].value()}\n");
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

## The units each unit reaches through the units it reads, itself only when
## a path leads back to it.
_reaches(reads: Array<HashSet<ulong>>): Array<HashSet<ulong>> {
    var out = Array<HashSet<ulong>>();
    for (var u in 0..reads.count) {
        var seen = HashSet<ulong>();
        var stack = Array<ulong>();
        for (var v in reads[u]) {
            if (v != u) {
                stack.append(v);
            }
        }
        while (stack.count > 0) {
            var v = stack.pop();
            if (seen.contains(v)) {
                continue;
            }
            seen.insert(v);
            for (var w in reads[v]) {
                stack.append(w);
            }
        }
        out.append(seen);
    }
    return out;
}

## Identifies the running compiler: its executable's path, size and time
## of modification, so a rebuilt compiler misses every key. For working on
## the compiler, `PEPC_COMPILER_IDENTITY` names it instead, so compilers
## built from changes that make the same output share the cache (as
## ccache's `compiler_check = string:...`): one that does not is wrong.
##
## @returns the identity, as text
export compiler_identity(): String {
    var named = os.environment("PEPC_COMPILER_IDENTITY");
    if (named.is_value() and !named.value().is_empty) {
        return named.value();
    }
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

## The units whose objects the build cache has, found before sema, which
## skips their bodies (`sema.strip_bodies`), and after it.
export struct Reused {
    ## Each unit's key, by its index in the program's units, once known.
    var keys: Array<String?> = Array<String?>();
    ## Each unit's objects from the cache; none for a unit to compile.
    var objects: Array<Path[]> = Array<Path[]>();
    ## Per program file, its interface hash, once known.
    var interfaces: Array<String?> = Array<String?>();
    ## Per program file, whether sema may skip its bodies: its unit's
    ## objects came from the cache with the link summaries recorded
    ## (`Module.cached_files`).
    var files: bool[] = Array<bool>();
    ## Those units' recorded link summaries (`Module.recorded_summaries`).
    var summaries: HashMap<sema.Loc, String> = HashMap<sema.Loc, String>();

    construct() {}
}

## The name of the file beside a unit's objects holding its functions' link
## summaries, one per line: `<namespace>\t<start>\t<end>\t<summary>`.
const _SUMMARIES = "summaries";
## The name of the file beside a unit's objects holding its files'
## interface hashes, one per line: `<namespace>\t<hash>`.
const _INTERFACES = "interfaces";
## The name of the file in a unit's folder listing its parts' objects, one
## per line, relative to the cache's folder (`Cache.part`).
const _PARTS = "parts";

## Finds `units` in `cache` before sema. Units resolve bottom up: a unit's
## key is known once the interfaces of the files it reads from other units
## are, which a hit's record gives. A hit's objects are used as they are,
## and when its link summaries were recorded, sema skips its files' bodies.
##
## @param program the program
## @param units its units
## @param keys the keys
## @param cache the build cache
## @param extension the objects' file extension
## @returns what the cache has
export reuse(
    program: link.Program, units: link.TranslationUnit[], keys: Keys, cache: Cache, extension: String
): Reused {
    var reused = Reused();
    for (var _ in program.files) {
        reused.files.append(false);
        reused.interfaces.append(Optional<String>.Empty);
    }
    for (var _ in units) {
        reused.keys.append(Optional<String>.Empty);
        reused.objects.append(Array<Path>());
    }
    var file_of = _files_by_namespace(program);
    bool progress = true;
    while (progress) {
        progress = false;
        for (var u in 0..units.count) {
            if (reused.keys[u].is_value()) {
                continue;
            }
            var key = keys.unit(program, units, u, reused.interfaces);
            if (!key.is_value()) {
                continue;
            }
            reused.keys[u] = key;
            progress = true;
            var folder = cache.objects(units[u].name, key.value());
            if (!cache.used(folder)) {
                continue;
            }
            var found = _objects_in(cache, folder, extension);
            var interfaces = File.read_to_string(folder.join(Path(_INTERFACES)));
            if (found.is_empty or interfaces.is_err()) {
                continue;
            }
            reused.objects[u] = found;
            for (var line in interfaces.value().split("\n")) {
                var fields = line.split_once("\t");
                if (!fields.is_value()) {
                    continue;
                }
                var (namespace, hash) = fields.value();
                var file = file_of.try_get(namespace);
                if (file.is_value()) {
                    reused.interfaces[file.value() as ulong] = Optional<String>.Value(hash);
                }
            }
            var text = File.read_to_string(folder.join(Path(_SUMMARIES)));
            if (text.is_err()) {
                continue;
            }
            for (var file in units[u].files) {
                reused.files[file] = true;
            }
            for (var line in text.value().split("\n")) {
                var entry = _parse_summary(line, file_of);
                if (entry.is_value()) {
                    var (loc, summary) = entry.value();
                    reused.summaries[loc] = summary;
                }
            }
        }
    }
    return reused;
}

## Finds the units whose keys `reuse` could not know in `cache`, now that
## sema has checked their files: each file's interface is hashed from its
## tokens and recorded summaries, so a unit whose inputs changed only in
## bodies is still a hit, and needs no code generated.
##
## @param reused what `reuse` found, completed in place
## @param program the program
## @param units its units
## @param keys the keys
## @param cache the build cache
## @param extension the objects' file extension
## @param facts each checked function's return type and link summary, by
##     location (`sema.function_facts`)
export reuse_after_sema(
    reused: Reused,
    program: link.Program,
    units: link.TranslationUnit[],
    keys: Keys,
    cache: Cache,
    extension: String,
    facts: HashMap<sema.Loc, String>
) {
    for (var i in 0..program.files.count) {
        if (!reused.interfaces[i].is_value()) {
            reused.interfaces[i] = Optional<String>.Value(interface_hash(program.files[i], i as uint, facts));
        }
    }
    for (var u in 0..units.count) {
        if (reused.keys[u].is_value()) {
            continue;
        }
        var key = keys.unit(program, units, u, reused.interfaces);
        reused.keys[u] = key;
        var folder = cache.objects(units[u].name, key.value());
        if (cache.used(folder) and folder.join(Path(_INTERFACES)).is_file()) {
            reused.objects[u] = _objects_in(cache, folder, extension);
        }
    }
}

## The objects of the unit whose folder is `folder`: those its parts list
## names, none when one is missing; else (a folder written before parts
## were kept on their own) `0.<extension>` on, until one is missing.
_objects_in(cache: Cache, folder: Path, extension: String): Path[] {
    var found = Array<Path>();
    var listed = File.read_to_string(folder.join(Path(_PARTS)));
    if (listed.is_ok()) {
        for (var line in listed.value().split("\n")) {
            if (line.is_empty) {
                continue;
            }
            var object = cache.dir.join(Path(line));
            # A part's folder is pruned on its own age: mark each as reused
            # too, or a build storing a newer key of that part removes it
            # while this one links it.
            if (!cache.used(object.parent().value()) or !object.is_file()) {
                return Array<Path>();
            }
            found.append(object);
        }
        return found;
    }
    while (true) {
        var object = folder.join(Path($"{found.count}.{extension}"));
        if (!object.is_file()) {
            break;
        }
        found.append(object);
    }
    return found;
}

## Each program file's index, by its namespace.
_files_by_namespace(program: link.Program): HashMap<String, uint> {
    var file_of = HashMap<String, uint>();
    for (var i in 0..program.files.count) {
        file_of[program.files[i].namespace] = i as uint;
    }
    return file_of;
}

## Parses one line of a summaries file (`_SUMMARIES`): the function's
## location and its summary, or none for a line that is not one.
_parse_summary(line: String, file_of: HashMap<String, uint>): (sema.Loc, String)? {
    var none = Optional<(sema.Loc, String)>.Empty;
    var first = line.split_once("\t");
    if (!first.is_value()) {
        return none;
    }
    var (namespace, rest) = first.value();
    var second = rest.split_once("\t");
    if (!second.is_value()) {
        return none;
    }
    var (start, after) = second.value();
    var third = after.split_once("\t");
    if (!third.is_value()) {
        return none;
    }
    var (end, summary) = third.value();
    var file = file_of.try_get(namespace);
    var from = ulong.parse(start);
    var to = ulong.parse(end);
    if (!file.is_value() or !from.is_value() or !to.is_value()) {
        return none;
    }
    var loc = sema.Loc.at(file.value(), ast.Span(from.value(), to.value()));
    return Optional<(sema.Loc, String)>.Value((loc, summary));
}

## Writes what a later build needs of `unit` into `folder`: its parts'
## objects, its files' interface hashes, and the link summaries sema
## recorded for its functions, so a later build can skip its bodies; no
## summaries when the build warned about the unit's code, so a later build
## checks it, and warns, again.
##
## @param folder where the unit's objects are written
## @param reused the files' interfaces
## @param module the checked model
## @param program the program
## @param unit the unit
## @param warnings the build's warnings
## @param parts its parts' objects, in the cache (`Cache.part`)
## @param cache the build cache
export write_record(
    folder: Path,
    reused: Reused,
    module: sema.Module,
    program: link.Program,
    unit: link.TranslationUnit,
    warnings: Diagnostic[],
    parts: Path[],
    cache: Cache
) {
    var listed = StringBuilder();
    var root = cache.dir.to_string();
    for (var object in parts) {
        # Relative to the cache's folder, so the cache can move.
        var path = object.to_string();
        if (path.starts_with(root) and path.size > root.size) {
            path = path.substr_bytes(root.size + 1, path.size - root.size - 1);
        }
        listed.append(path);
        listed.append("\n");
    }
    File.write_text(folder.join(Path(_PARTS)), listed.to_string());
    var interfaces = StringBuilder();
    for (var file in unit.files) {
        interfaces.append($"{program.files[file].namespace}\t{reused.interfaces[file].value()}\n");
    }
    File.write_text(folder.join(Path(_INTERFACES)), interfaces.to_string());
    var own = HashSet<ulong>();
    for (var file in unit.files) {
        own.insert(file);
    }
    for (var warning in warnings) {
        if (warning.location.is_value() and own.contains(warning.location.value().file)) {
            return;
        }
    }
    var text = StringBuilder();
    for (var (loc, summary) in module.summaries_to_record) {
        if (loc.is_none() or !own.contains(loc.file as ulong) or summary.contains("\n")) {
            continue;
        }
        text.append($"{program.files[loc.file as ulong].namespace}\t{loc.span.start}\t{loc.span.end}\t{summary}\n");
    }
    File.write_text(folder.join(Path(_SUMMARIES)), text.to_string());
}

# Moves the folder `built` to `target` where a rename cannot: copies it to a
# folder beside `target`, on the cache's own drive, and renames that, so a
# key's folder still only ever appears whole. `built` goes once the copy is
# in place.
export _move_across_drives(built: Path, target: Path): IoResult<void> {
    var staged = Path($"{target}.{digest.to_hex(digest.blake3(built.to_string())).substr(0, 12)}");
    Directory.remove_all(staged);
    var copied = _copy_folder(built, staged);
    if (copied.is_ok()) {
        copied = File.rename(staged, target);
    }
    if (copied.is_err()) {
        Directory.remove_all(staged);
        return copied;
    }
    Directory.remove_all(built);
    return IoResult<void>.ok();
}

# Copies the folder `from`, with every file and folder in it, to `to`.
_copy_folder(from: Path, to: Path): IoResult<void> {
    var created = Directory.create_all(to);
    if (created.is_err()) {
        return created;
    }
    var listing = Directory.open(from);
    if (listing.is_err()) {
        return IoResult<void>.err(listing.error());
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return IoResult<void>.err(entries.error());
    }
    for (var entry in entries.value()) {
        var into = to.join(Path(entry.name));
        if (entry.is_directory) {
            var r = _copy_folder(entry.path, into);
            if (r.is_err()) {
                return r;
            }
            continue;
        }
        var c = File.copy(entry.path, into);
        if (c.is_err()) {
            return IoResult<void>.err(c.error());
        }
    }
    return IoResult<void>.ok();
}

## The objects of a unit's parts in `folder`: `0.<extension>` and on, until
## one is missing.
##
## @param folder the folder of the objects
## @param extension the objects' file extension
## @returns the objects, none when `folder` holds no `0.<extension>`
export numbered_objects(folder: Path, extension: String): Path[] {
    var objects = Array<Path>();
    var at = folder.join(Path($"0.{extension}"));
    while (at.is_file()) {
        objects.append(at);
        at = folder.join(Path($"{objects.count}.{extension}"));
    }
    return objects;
}

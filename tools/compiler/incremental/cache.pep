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
## hard links to the objects (`Cache.pin`). Each unit keeps its newest few keys
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
## How many times `Cache.reused_objects` looks for a key's objects, or
## `_move_across_drives` renames a key's folder into place, and how long it
## waits between tries, in milliseconds: about a second in all.
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

    ## Returns the folder of the objects of `unit` under `key` whose last
    ## releases steer into the structs `steering` lists (`Keys.steering`):
    ## the key's own when it lists none, else one beside it named after
    ## both, so objects of one key built in programs whose cycles differ
    ## are kept side by side.
    ##
    ## @param unit the unit's name
    ## @param key its key
    ## @param steering what its objects steer into
    ## @returns the folder, which need not exist
    steered(unit: String, key: String, steering: String): Path {
        var folder = objects(unit, key);
        if (steering.is_empty) {
            return folder;
        }
        var hash = digest.to_hex(digest.blake3(steering)).substr(0, 8);
        return folder.parent().value().join(Path($"{_key_name(key)}.{hash}"));
    }

    ## Returns the folder of the objects of `unit` under `key` (`steered`)
    ## that steer into the most structs, among those whose structs' files
    ## are all in this program (`hashes`), and what they steer into: the
    ## key's own folder, steering into none, when no other is.
    ##
    ## @param unit the unit's name
    ## @param key its key
    ## @param hashes the hash of each of the program's files (`Keys.file_hashes`)
    ## @returns the folder, which need not exist, and its steering
    best_steered(unit: String, key: String, hashes: HashSet<String>): (Path, String) {
        var best = objects(unit, key);
        String steering = "";
        ulong most = 0;
        var listing = Directory.open(best.parent().value());
        if (listing.is_err()) {
            return (best, steering);
        }
        var entries = listing.value().entries();
        if (entries.is_err()) {
            return (best, steering);
        }
        var variant = $"{_key_name(key)}.";
        for (var entry in entries.value()) {
            if (!entry.name.starts_with(variant)) {
                continue;
            }
            var text = File.read_to_string(entry.path.join(Path(STEERS_FILE)));
            if (text.is_err() or !_steers_present(text.value(), hashes)) {
                continue;
            }
            var count = _lines(text.value()).count;
            if (count > most) {
                most = count;
                best = entry.path;
                steering = text.value();
            }
        }
        return (best, steering);
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

    ## Returns what `find` finds of a key this build already decided to
    ## reuse, looking again for about a second while it finds nothing. A
    ## build pruning the key's unit moves its folder aside, and back when it
    ## was reused meanwhile (`_prune`), so a key this build marked (`used`)
    ## can be missing for a moment: once a build decided to reuse a key, a
    ## look that misses it is not a plain miss. Every read of a key's
    ## folder after the decision goes through here.
    ##
    ## @typeParam T what is found
    ## @param find one look: marks the key as reused and reads what it needs
    ## @returns what `find` found, or none when it found nothing for about a
    ##   second
    look_again<T>(find: () => T?): T? {
        var found = find();
        for (var _ in 1.._REUSE_TRIES) {
            if (found.is_value()) {
                return found;
            }
            async.Thread.sleep(_REUSE_WAIT);
            found = find();
        }
        return found;
    }

    ## Returns the objects of `unit` under `key` (`numbered_objects`),
    ## marked as just reused, for linking a unit this build found in the
    ## cache when it checked it, looked for again while missing
    ## (`look_again`): a link without its objects fails on undefined
    ## symbols.
    ##
    ## @param unit the unit's name
    ## @param key its key
    ## @param extension the objects' file extension
    ## @returns the objects, or why the cache no longer holds them
    reused_objects(unit: String, key: String, extension: String): Result<Path[], String> {
        var folder = objects(unit, key);
        var found = look_again(() => {
            var listed = used(folder) ? numbered_objects(folder, extension) : Array<Path>();
            return listed.is_empty ? Optional<Path[]>.Empty : Optional<Path[]>.Value(listed);
        });
        if (!found.is_value()) {
            return Result<Path[], String>.err(
                $"the build cache no longer holds the objects of '{unit}' ({folder}); build again"
            );
        }
        return Result<Path[], String>.ok(found.value());
    }

    ## Returns `objects`, each one this cache holds replaced by a hard link
    ## to it in `folder`, for the link. A build pruning a unit can move a
    ## key's folder aside (`_prune`) after this build's last look at it, and
    ## the linker opens the objects later; the link keeps the file wherever
    ## the folder goes (#178). An object found missing is looked for again
    ## (`look_again`). One that cannot be linked but is there (`folder` on
    ## another volume) stays where it is: a copy of every object would slow
    ## every build to close a rare race.
    ##
    ## @param objects the objects to link
    ## @param folder a folder of this build's own, created here
    ## @returns the objects to link, or why the cache no longer holds one
    pin(objects: Path[], folder: Path): Result<Path[], String> {
        Directory.create_all(folder);
        var root = dir.to_string();
        var pinned = Array<Path>();
        for (var object in objects) {
            if (!object.to_string().starts_with(root)) {
                pinned.append(object);
                continue;
            }
            var pin = folder.join(Path($"{pinned.count}.{object.file_name().value()}"));
            var made = look_again(() => {
                if (File.hard_link(object, pin).is_ok()) {
                    return Optional<Path>.Value(pin);
                }
                return object.is_file() ? Optional<Path>.Value(object) : Optional<Path>.Empty;
            });
            if (!made.is_value()) {
                return Result<Path[], String>.err($"the build cache no longer holds {object}; build again");
            }
            pinned.append(made.value());
        }
        return Result<Path[], String>.ok(pinned);
    }

    ## Returns the key the cache holds objects of compilation unit `unit`,
    ## keyed `key`, under that link with the objects of the compilation units
    ## it reads, and hold `file`; none when it holds none. Such objects only
    ## declare what the objects below defined when they were compiled, the
    ## names listed beside them (`NEEDS_FILE`), and a body edit below can drop
    ## one of those without changing `key` (#24). So objects under `key` whose
    ## needs `below` lacks are passed over for those under `key` with `below`
    ## added (`store_unit`).
    ##
    ## @param unit the compilation unit's name in the cache (`+<name>`)
    ## @param key its key
    ## @param below what the objects of each compilation unit it reads define
    ## @param file a file its objects' folder must hold
    ## @returns the key of the objects to link, or none
    unit_objects(unit: String, key: String, below: Defines[], file: String): String? {
        var folder = objects(unit, key);
        if (used(folder) and folder.join(Path(file)).is_file() and _needs_met(folder, below)) {
            return Optional<String>.Value(key);
        }
        var other = _with_below(key, below);
        folder = objects(unit, other);
        if (used(folder) and folder.join(Path(file)).is_file() and _needs_met(folder, below)) {
            return Optional<String>.Value(other);
        }
        return Optional<String>.Empty;
    }

    ## Moves `built`, the objects of compilation unit `unit` just compiled on
    ## objects below that define `below`, into the build cache with what they
    ## use of those (`needs`, a name a line, kept as `NEEDS_FILE`), under
    ## `key`, or, when the cache holds objects under `key` already that do
    ## not link with the objects below, under `key` with `below` added. A
    ## key's folder appears whole, by a rename that fails when it is there
    ## already, so two builds storing one key at the same moment (#152) never
    ## see half of each other's: the one that renames second links the
    ## first's objects when they link with its objects below
    ## (`unit_objects`), and else keeps its own under the other key.
    ##
    ## @param built the folder of objects
    ## @param unit the compilation unit's name in the cache (`+<name>`)
    ## @param key its key
    ## @param needs what its objects use of what the objects below define
    ## @param below what the objects of each compilation unit it reads define
    ## @param file a file its objects' folder holds
    ## @returns the key of the objects to link, or why they could not be stored
    store_unit(
        built: Path, unit: String, key: String, needs: String, below: Defines[], file: String
    ): Result<String, String> {
        if (File.write_text(built.join(Path(NEEDS_FILE)), $"{stamp_of(below)}\n{needs}").is_err()) {
            return Result<String, String>.err($"cannot write to {built}");
        }
        var target = objects(unit, key);
        var placed = _place(built, target);
        if (placed.is_err()) {
            return Result<String, String>.err(placed.error());
        }
        if (placed.value()) {
            _prune(target.parent().value());
            return Result<String, String>.ok(key);
        }
        var found = unit_objects(unit, key, below, file);
        if (found.is_value()) {
            Directory.remove_all(built);
            return Result<String, String>.ok(found.value());
        }
        var other = _with_below(key, below);
        var stored = store(built, unit, other);
        if (stored.is_err()) {
            return Result<String, String>.err(stored.error());
        }
        return Result<String, String>.ok(other);
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
    ## @param steering what its objects steer into (`steered`)
    ## @returns the objects' folder in the cache, or why it could not be moved
    store(built: Path, unit: String, key: String, steering: String = ""): Result<Path, String> {
        if (!steering.is_empty and File.write_text(built.join(Path(STEERS_FILE)), steering).is_err()) {
            return Result<Path, String>.err($"cannot write to {built}");
        }
        var target = steered(unit, key, steering);
        var placed = _place(built, target);
        if (placed.is_err()) {
            return Result<Path, String>.err(placed.error());
        }
        if (!placed.value()) {
            Directory.remove_all(built);
        }
        _prune(target.parent().value());
        return Result<Path, String>.ok(target);
    }

    # Renames `built` to `target`, a key's folder. Returns whether it did:
    # not when another build's folder is there already, which stays, as
    # `built` does.
    _place(built: Path, target: Path): Result<bool, String> {
        var folder = target.parent().value();
        var created = Directory.create_all(folder);
        if (created.is_err()) {
            return Result<bool, String>.err($"cannot create {folder}: {created.error().message}");
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
                return Result<bool, String>.err($"cannot move {built} to {target}: {moved.error().message}");
            }
            return Result<bool, String>.ok(false);
        }
        return Result<bool, String>.ok(true);
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

    ## Returns the files the program that writes `output` was last built
    ## from, as `record` listed them.
    ##
    ## @param output the executable
    ## @returns the files' paths, or `Empty` when there is no record
    program_files(output: Path): String[]? {
        var record = File.read_to_string(_record(output));
        if (record.is_err()) {
            return Optional<String[]>.Empty;
        }
        var lines = record.value().split("\n");
        if (lines.count < 2) {
            return Optional<String[]>.Empty;
        }
        var files = Array<String>();
        for (var i in 2..lines.count) {
            if (!lines[i].is_empty) {
                files.append(lines[i]);
            }
        }
        return Optional<String[]>.Value(files);
    }

    ## Records that `output` is the program keyed `key`, built from `files`.
    ## A build that warned is recorded with no key, so `is_built` is false
    ## and the next build is checked, and warns, again; `program_files`
    ## still lists its files.
    ##
    ## @param output the executable
    ## @param key the program's key
    ## @param warned whether the build printed warnings
    ## @param files the paths of the files it was built from, which
    ##   `program_files` returns
    record(output: Path, key: String, warned: bool, files: String[]) {
        var path = _record(output);
        var built = File.read_bytes(output);
        if (built.is_err()) {
            File.remove(path);
            return;
        }
        var recorded = warned ? "" : key;
        var created = Directory.create_all(path.parent().value());
        if (created.is_err()) {
            return;
        }
        var partial = Path($"{path}.{process.id()}");
        var written = File.write_text(
            partial, $"{recorded}\n{digest.to_hex(digest.blake3(built.value()))}\n" + "\n".join(files) + "\n"
        );
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

## The name of the file beside a compilation unit's objects listing what
## they use of what the objects below them define: the stamp of those
## (`stamp_of`), then a name a line (`Cache.unit_objects`).
export const NEEDS_FILE = "needs";

## The name of the file beside a unit's objects listing the structs outside
## the files it reads that its last releases steer into (`Keys.steering`);
## objects that steer into none have none.
export const STEERS_FILE = "steers";

## Returns the lines of `text`, each a struct `Keys.steering` lists.
_lines(text: String): HashSet<String> {
    var out = HashSet<String>();
    for (var line in text.split("\n")) {
        if (!line.is_empty) {
            out.insert(line);
        }
    }
    return out;
}

## Whether every file of every struct `steering` lists (`Keys.steering`) is
## in the program, whose files' hashes are `hashes`.
_steers_present(steering: String, hashes: HashSet<String>): bool {
    for (var line in _lines(steering)) {
        var fields = line.split_once("\t");
        if (!fields.is_value()) {
            return false;
        }
        var (_, files) = fields.value();
        for (var hash in files.split(" ")) {
            if (!hashes.contains(hash)) {
                return false;
            }
        }
    }
    return true;
}

## Returns whether objects that steer into `recorded` (`Keys.steering`)
## steer into every struct a program's cycles give, `current`: when not,
## they were built in a program with fewer structs in those cycles, and
## the unit is compiled again.
##
## @param current what this program's cycles steer the unit into
## @param recorded what its cached objects steer into
## @returns whether the objects steer into all of `current`
export steers_within(current: String, recorded: String): bool {
    var kept = _lines(recorded);
    for (var line in _lines(current)) {
        if (!kept.contains(line)) {
            return false;
        }
    }
    return true;
}

## What the objects of one compilation unit define for those above: their
## `defines` file, a name a line.
export struct Defines {
    ## The file's text.
    var text: String;
    ## The hash of `text`.
    var hash: String;
    var _names: HashSet<String>? = Optional<HashSet<String>>.Empty;

    ## @param text the `defines` file's text
    construct(text: String) {
        this.text = text;
        this.hash = digest.to_hex(digest.blake3(text));
    }

    ## Returns the names `text` lists, read the first time.
    ##
    ## @returns the names
    names(): HashSet<String> {
        if (!_names.is_value()) {
            var out = HashSet<String>();
            for (var line in text.split("\n")) {
                if (!line.is_empty) {
                    out.insert(line);
                }
            }
            _names = Optional<HashSet<String>>.Value(out);
        }
        return _names.value();
    }
}

## Returns what identifies `below`: each one's hash, in order.
##
## @param below what the objects of each compilation unit one reads define
## @returns the hashes, a space apart
export stamp_of(below: Defines[]): String {
    var hashes = Array<String>();
    for (var defined in below) {
        hashes.append(defined.hash);
    }
    return " ".join(hashes);
}

## Whether every name the `needs` file in `folder` lists is in one of
## `below`: at once when its stamp is theirs, the objects below unchanged;
## not when it has none (objects of a build before it).
_needs_met(folder: Path, below: Defines[]): bool {
    var needs = File.read_to_string(folder.join(Path(NEEDS_FILE)));
    if (needs.is_err()) {
        return false;
    }
    var parts = needs.value().split_once("\n");
    if (!parts.is_value()) {
        return false;
    }
    var (stamp, names) = parts.value();
    if (stamp == stamp_of(below)) {
        return true;
    }
    for (var name in names.split("\n")) {
        if (name.is_empty) {
            continue;
        }
        bool found = false;
        for (var defined in below) {
            if (defined.names().contains(name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

## Returns every name one of `below` holds.
##
## @param below what the objects of each compilation unit one reads define
## @returns their union
export union_of(below: Defines[]): HashSet<String> {
    var out = HashSet<String>();
    for (var defined in below) {
        for (var name in defined.names()) {
            out.insert(name);
        }
    }
    return out;
}

## `key` with what identifies `below` added (`stamp_of`).
_with_below(key: String, below: Defines[]): String {
    return digest.to_hex(digest.blake3($"{key}\nbelow {stamp_of(below)}\n"));
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
## either it finds the key gone and compiles, or the key stays. It is
## missing meanwhile, so every later read of a key a build decided to
## reuse looks again (`Cache.look_again`), and the link reads hard links to
## the objects (`Cache.pin`), which a prune that stalled between its
## check and its rename cannot move.
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

    ## Returns the hash of each of the program's files: its identity and
    ## text, as keys name them.
    ##
    ## @returns the hashes
    file_hashes(): HashSet<String> {
        return HashSet<String>(_files);
    }

    ## Returns what the last releases in unit `u`'s objects can steer into
    ## beyond the files it reads (`link.unit_inputs`), which its key leaves
    ## out: each struct of a cycle of `cycles` (`codegen.generate`) that is
    ## declared in or names a type of a file outside them, when another
    ## struct of that cycle is wholly inside. One line each, its name, a tab
    ## and its files' hashes, sorted; empty when there are none. A trait's
    ## conformers and a function type's closures are the program's, so one
    ## file's code can steer into structs another program does not have.
    ##
    ## @param u the unit's index
    ## @param cycles the structs of each cycle, with their files
    ## @returns the lines
    steering(u: ulong, cycles: Array<Array<(String, ulong[])>>): String {
        if (cycles.is_empty) {
            return "";
        }
        var inputs = HashSet<ulong>();
        for (var (file, _) in _inputs[u]) {
            inputs.insert(file);
        }
        var lines = Array<String>();
        for (var cycle in cycles) {
            var outside = Array<String>();
            bool touched = false;
            for (var (name, files) in cycle) {
                bool inside = true;
                var hashes = Array<String>();
                for (var file in files) {
                    inside = inside and inputs.contains(file);
                    hashes.append(file < _files.count ? _files[file] : "");
                }
                if (inside) {
                    touched = true;
                } else {
                    hashes.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
                    outside.append($"{name}\t{" ".join(hashes)}");
                }
            }
            if (touched) {
                lines.append_all(outside);
            }
        }
        lines.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
        var out = StringBuilder();
        for (var line in lines) {
            out.append(line);
            out.append("\n");
        }
        return out.to_string();
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
    ## @param steering what the unit's last releases steer into
    ##   (`Keys.steering`)
    ## @returns the key, in hexadecimal
    part(
        program: link.Program,
        units: link.TranslationUnit[],
        u: ulong,
        files: ulong[],
        interfaces: Array<String?>,
        steering: String = ""
    ): String {
        var own = HashSet<ulong>();
        var hasher = digest.Blake3();
        hasher.update(_base);
        hasher.update($"part of {units[u].name}\n");
        hasher.update($"steers {steering}\n");
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
    ## What each unit's objects from the cache steer into (`Keys.steering`).
    var steering: String[] = Array<String>();

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

## A `Reused` that found none of `units` in the cache: every body is
## checked and compiled. A build that compiles compilation units in
## workers uses it, since it links only the compilation units' objects, so
## a file's body that it skipped would be defined nowhere.
##
## @param program the program
## @param units its units
## @returns a `Reused` with no unit found
export nothing_reused(program: link.Program, units: link.TranslationUnit[]): Reused {
    var reused = Reused();
    for (var _ in program.files) {
        reused.files.append(false);
        reused.interfaces.append(Optional<String>.Empty);
    }
    for (var _ in units) {
        reused.keys.append(Optional<String>.Empty);
        reused.objects.append(Array<Path>());
        reused.steering.append("");
    }
    return reused;
}

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
    program: link.Program,
    units: link.TranslationUnit[],
    keys: Keys,
    cache: Cache,
    extension: String,
    excluded: HashSet<ulong> = HashSet<ulong>()
): Reused {
    var reused = nothing_reused(program, units);
    var file_of = _files_by_namespace(program);
    var hashes = keys.file_hashes();
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
            if (excluded.contains(u)) {
                continue;
            }
            var (folder, steering) = cache.best_steered(units[u].name, key.value(), hashes);
            if (!cache.used(folder)) {
                continue;
            }
            reused.steering[u] = steering;
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
## @param excluded the units not to reuse (`reuse`)
export reuse_after_sema(
    reused: Reused,
    program: link.Program,
    units: link.TranslationUnit[],
    keys: Keys,
    cache: Cache,
    extension: String,
    facts: HashMap<sema.Loc, String>,
    excluded: HashSet<ulong> = HashSet<ulong>()
) {
    var hashes = keys.file_hashes();
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
        if (excluded.contains(u)) {
            continue;
        }
        var (folder, steering) = cache.best_steered(units[u].name, key.value(), hashes);
        if (cache.used(folder) and folder.join(Path(_INTERFACES)).is_file()) {
            reused.objects[u] = _objects_in(cache, folder, extension);
            reused.steering[u] = steering;
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
# in place. When another build's copy is in place first, it fails, leaving
# that copy and `built`.
export _move_across_drives(built: Path, target: Path): IoResult<void> {
    var staged = Path($"{target}.{digest.to_hex(digest.blake3(built.to_string())).substr(0, 12)}");
    Directory.remove_all(staged);
    var copied = _copy_folder(built, staged);
    if (copied.is_ok()) {
        copied = File.rename(staged, target);
        # Windows fails the rename ("Access is denied") while anything has a
        # file in the folder open, as a virus scan of the fresh copy does
        # (#227): try again, for about a second, while the key is not there.
        for (var _ in 1.._REUSE_TRIES) {
            if (copied.is_ok() or target.metadata().is_ok()) {
                break;
            }
            async.Thread.sleep(_REUSE_WAIT);
            copied = File.rename(staged, target);
        }
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
## one is missing, read from one listing of `folder`. A look per file could
## end the list early, without a part, when a build pruning the unit moves
## the folder aside and back between two looks (`_prune`); a listing reads
## one open folder, all of it or nothing.
##
## @param folder the folder of the objects
## @param extension the objects' file extension
## @returns the objects, none when `folder` holds no `0.<extension>`
export numbered_objects(folder: Path, extension: String): Path[] {
    var objects = Array<Path>();
    var opened = Directory.open(folder);
    if (opened.is_err()) {
        return objects;
    }
    var entries = opened.value().entries();
    if (entries.is_err()) {
        return objects;
    }
    var names = HashSet<String>();
    for (var entry in entries.value()) {
        names.insert(entry.name);
    }
    while (names.contains($"{objects.count}.{extension}")) {
        objects.append(folder.join(Path($"{objects.count}.{extension}")));
    }
    return objects;
}

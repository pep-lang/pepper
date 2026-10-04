## Where a program's files come from: the runtime directory, the module a
## file belongs to and the namespace that names it, and the files an
## import names. A module is a folder holding a `module.pep`, named after
## the folder. `import name` finds a module on the search paths (the `-I`
## directories, then the runtime directory); `import "path"` is local to
## the importing file: the file `path.pep` of the same module, or else the
## module folder `path/module.pep`.

import io;
import [Directory, Path] from io;
import os;
import process;

## The file a module's exports come from.
export const MODULE_FILE = "module.pep";

## The file that makes a folder a project.
export const MANIFEST_FILE = "pep.toml";

## The environment variable that names the runtime directory outright.
export const RUNTIME_ENV = "PEPPER_RUNTIME";

## Returns the directory holding the file `path`: `.` for a bare file name.
##
## @param path the file
## @returns its directory
export dir_of(path: Path): Path {
    var parent = path.parent();
    if (!parent.is_value() or parent.value().to_string().is_empty) {
        return Path(".");
    }
    return parent.value();
}

## Returns `path` made canonical. A file not on disk is normalized through
## its folder, so it compares equal to the canonical paths of real files
## next to it.
##
## @param path the path
## @returns the normalized path
export normalized(path: Path): Path {
    var canonical = path.canonicalize();
    if (canonical.is_ok()) {
        return canonical.value();
    }
    var dir = dir_of(path).canonicalize();
    var name = path.file_name();
    if (dir.is_ok() and name.is_value()) {
        return dir.value().join(name.value());
    }
    if (path.is_absolute()) {
        return path;
    }
    var cwd = process.working_directory();
    return cwd.is_ok() ? cwd.value().join(path) : path;
}

## Returns a path's identity for "already loaded" checks: canonical when
## the file exists.
##
## @param path the path
## @returns the key
export path_key(path: Path): String {
    return normalized(path).to_string();
}

## What a local import (`import "x"`) names.
export enum LocalImport {
    ## `x.pep` next to the importing file, which must belong to its module.
    ##
    ## @param path the file
    File(path: Path),
    ## `x/module.pep` next to the importing file: a module folder.
    ##
    ## @param path the folder's `module.pep`
    Module(path: Path),

    ## Returns the path either case names.
    ##
    ## @returns the path
    path(): Path {
        match (this) {
            File(path) => {
                return path;
            }
            Module(path) => {
                return path;
            }
        }
        return Path();
    }
}

## Returns what `import "stem"` from the file `from` names: the file
## `stem.pep` next to it, or else the module folder `stem/`.
##
## @param from the importing file
## @param stem the import's name without a trailing `.pep`
## @returns the file or module, or none
export resolve_local(from: Path, stem: String): LocalImport? {
    var dir = dir_of(from);
    var file = dir.join(stem + ".pep");
    if (file.is_file()) {
        return Optional<LocalImport>.Value(LocalImport.File(file));
    }
    var module = dir.join(stem).join(Path(MODULE_FILE));
    if (module.is_file()) {
        return Optional<LocalImport>.Value(LocalImport.Module(module));
    }
    return Optional<LocalImport>.Empty;
}

## Returns the `module.pep` of `import name` (`import x.y` names
## `x/y/module.pep`): the first on the search paths that exists.
##
## @param module_name the module's name
## @param search_paths where to look, in order
## @returns the module's `module.pep`, or none
export resolve_module(module_name: String, search_paths: Path[]): Path? {
    for (var dir in search_paths) {
        var module = dir;
        for (var part in module_name.split(".")) {
            module = module.join(part);
        }
        module = module.join(Path(MODULE_FILE));
        if (module.is_file()) {
            return Optional<Path>.Value(module);
        }
    }
    return Optional<Path>.Empty;
}

## Returns the file `--import NAME` adds: a module `NAME`, else a file
## `NAME.pep` on the search paths.
##
## @param name the name, with or without `.pep`
## @param search_paths where to look, in order
## @returns the file, or none
export resolve_forced(name: String, search_paths: Path[]): Path? {
    var stem = name.ends_with(".pep") ? name.substr_bytes(0, name.size - 4) : name;
    var module = resolve_module(stem, search_paths);
    if (module.is_value()) {
        return module;
    }
    for (var dir in search_paths) {
        var file = dir.join(stem + ".pep");
        if (file.is_file()) {
            return Optional<Path>.Value(file);
        }
    }
    return Optional<Path>.Empty;
}

## Returns the folder of the project the file `root` belongs to: the
## nearest folder above it holding a `pep.toml`, looking from above any
## `.pep` folder the file is in.
##
## @param root the program's root file
## @returns the project folder, or none
export find_project(root: Path): Path? {
    var file = root;
    if (!file.is_absolute()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            file = cwd.value().join(root).normalize();
        }
    }
    var start = dir_of(file);
    var outside = start;
    Path? dir = Optional<Path>.Value(start);
    while (dir.is_value()) {
        var name = dir.value().file_name();
        if (name.is_value() and name.value() == ".pep") {
            var parent = dir.value().parent();
            if (parent.is_value()) {
                outside = parent.value();
            }
            break;
        }
        dir = dir.value().parent();
    }
    dir = Optional<Path>.Value(outside);
    while (dir.is_value()) {
        if (dir.value().join(Path(MANIFEST_FILE)).is_file()) {
            return dir;
        }
        dir = dir.value().parent();
    }
    return Optional<Path>.Empty;
}

## The runtime a program is compiled with: its `.pep` sources, and every
## runtime directory found on the way, which module imports search.
export struct Runtime {
    ## The runtime's top-level `.pep` files, in directory order.
    var sources: Path[] = Array<Path>();
    ## The directories that exist among those searched, up to the runtime's.
    var dirs: Path[] = Array<Path>();

    ## Finds the runtime: `PEPPER_RUNTIME` names its directory outright;
    ## else `runtime` and `.pep/runtime` in the current directory, then
    ## `runtime` in up to five of its ancestors, then the same beside the
    ## running executable. The first directory with `.pep` files wins.
    ##
    ## @returns the runtime, with no sources when none is found
    static discover(): Runtime {
        var named = os.environment(RUNTIME_ENV);
        if (named.is_value() and !named.value().is_empty) {
            return Runtime._scan([Path(named.value())]);
        }
        var candidates = Array<Path>();
        var cwd = process.working_directory();
        var start = cwd.is_ok() ? cwd.value() : Path("");
        candidates.append(start.join("runtime"));
        candidates.append(start.join(".pep").join("runtime"));
        var above = Runtime._candidates_below(start);
        ulong i = 1;
        while (i < above.count) {
            candidates.append(above[i]);
            i += 1;
        }
        var executable = process.executable_path();
        if (executable.is_ok()) {
            var exe_dir = executable.value().parent();
            if (exe_dir.is_value()) {
                for (var candidate in Runtime._candidates_below(exe_dir.value())) {
                    candidates.append(candidate);
                }
            }
        }
        return Runtime._scan(candidates);
    }

    # `runtime` beside `start` and in up to 5 of its ancestors.
    static _candidates_below(start: Path): Path[] {
        var out = Array<Path>();
        out.append(start.join("runtime"));
        var up = "..";
        int level = 1;
        while (level <= 5) {
            out.append(start.join(up).join("runtime"));
            up = up + "/..";
            level += 1;
        }
        return out;
    }

    static _scan(candidates: Path[]): Runtime {
        var out = Runtime();
        var seen = HashSet<String>();
        for (var candidate in candidates) {
            var canonical = candidate.canonicalize();
            var dir = canonical.is_ok() ? canonical.value() : candidate;
            if (!dir.is_dir()) {
                continue;
            }
            if (seen.insert(dir.to_string())) {
                out.dirs.append(dir);
            }
            var listing = Directory.open(dir);
            if (listing.is_err()) {
                continue;
            }
            var entries = listing.value().entries();
            if (entries.is_err()) {
                continue;
            }
            for (var entry in entries.value()) {
                if (entry.name.ends_with(".pep") and entry.name.size > 4) {
                    out.sources.append(dir.join(entry.name));
                }
            }
            # The nearest runtime wins: merging a second copy would declare
            # every runtime symbol twice.
            if (out.sources.count > 0) {
                break;
            }
        }
        return out;
    }
}

## Where a file import lands relative to the importing file.
export enum Placement {
    ## In the importing file's module (or folder, outside any module).
    SameModule,
    ## In another module.
    OtherModule,
    ## Outside the importing file's module, in no module.
    OutsideModule,
    ## Outside the folder of an importing file that belongs to no module.
    OutsideFolder,
}

## Module folders: which module a file belongs to, the namespace that
## names it, and whether a file import stays inside its module. Each
## directory is looked up once.
export struct ModuleRoots {
    # directory (normalized) -> its module folder, or "" for none.
    var _by_dir: HashMap<String, String> = HashMap<String, String>();
    # path as given -> normalized.
    var _normalized: HashMap<String, Path> = HashMap<String, Path>();
    # The project directory (normalized), if any.
    var _project: Path?;

    ## Creates the module folders of a program built in the project
    ## directory `project`.
    ##
    ## @param project the project directory, if any
    construct(project: Path?) {
        if (project.is_value()) {
            var canonical = project.value().canonicalize();
            _project = Optional<Path>.Value(canonical.is_ok() ? canonical.value() : project.value());
        }
    }

    _normal(path: Path): Path {
        var key = path.to_string();
        var known = _normalized.try_get(key);
        if (known.is_value()) {
            return known.value();
        }
        var p = normalized(path);
        _normalized[key] = p;
        return p;
    }

    _of_dir(dir: Path): Path? {
        var key = dir.to_string();
        var known = _by_dir.try_get(key);
        if (known.is_value()) {
            return known.value().is_empty ? Optional<Path>.Empty : Optional<Path>.Value(Path(known.value()));
        }
        Path? root = Optional<Path>.Empty;
        if (dir.join(Path(MODULE_FILE)).is_file()) {
            root = Optional<Path>.Value(dir);
        } else {
            var parent = dir.parent();
            if (parent.is_value()) {
                root = _of_dir(parent.value());
            }
        }
        _by_dir[key] = root.is_value() ? root.value().to_string() : "";
        return root;
    }

    ## Returns the module folder the file `path` belongs to, if any.
    ##
    ## @param path the file
    ## @returns the module's folder, or none
    module_of(path: Path): Path? {
        var parent = _normal(path).parent();
        if (!parent.is_value()) {
            return Optional<Path>.Empty;
        }
        return _of_dir(parent.value());
    }

    ## Returns the namespace of the file `path`: for a file of a module, the
    ## module's name and the file's path inside it (`io/file`); for another
    ## file under the project directory, its path from there
    ## (`tests/util`); otherwise the file's name. Without its extension, and
    ## with any character a namespace cannot hold replaced by `_`.
    ##
    ## @param path the file
    ## @returns the namespace
    namespace_of(path: Path): String {
        var stem = _normal(path).with_extension("");
        var key = "";
        var root = module_of(path);
        if (root.is_value()) {
            var module = root.value().file_name();
            var inner = _strip_prefix(stem, root.value());
            key = (module.is_value() ? module.value() : "")
                + "/"
                + "/".join(inner.is_value() ? inner.value() : stem.components());
        } else {
            Array<String>? inner = Optional<Array<String>>.Empty;
            if (_project.is_value()) {
                inner = _strip_prefix(stem, _project.value());
            }
            if (inner.is_value()) {
                key = "/".join(inner.value());
            } else {
                var name = stem.file_name();
                key = name.is_value() ? name.value() : "";
            }
        }
        var out = StringBuilder();
        ulong i = 0;
        while (i < key.size) {
            var b = key.byte_at(i);
            bool kept = (b >= 'a' and b <= 'z')
                or (b >= 'A' and b <= 'Z')
                or (b >= '0' and b <= '9')
                or b == '_'
                or b == '/';
            out.append(kept ? key.substr_bytes(i, 1) : "_");
            i += 1;
        }
        return out.to_string();
    }

    ## Returns where a file import from `from` to the file `target` lands.
    ## Only `SameModule` is allowed: the target lies under the module's
    ## folder (for a file outside any module, its own folder) and not in
    ## another module nested there.
    ##
    ## @param from the importing file
    ## @param target the imported file
    ## @returns the placement
    placement(from: Path, target: Path): Placement {
        var from_path = _normal(from);
        var target_path = _normal(target);
        var from_dir = from_path.parent();
        var target_dir = target_path.parent();
        if (!from_dir.is_value() or !target_dir.is_value()) {
            return Placement.OutsideFolder;
        }
        var from_root = _of_dir(from_dir.value());
        var target_root = _of_dir(target_dir.value());
        var scope = from_root.is_value() ? from_root.value() : from_dir.value();
        bool same_root = from_root.is_value() == target_root.is_value()
            and (!from_root.is_value() or from_root.value().to_string() == target_root.value().to_string());
        if (_strip_prefix(target_path, scope).is_value() and same_root) {
            return Placement.SameModule;
        }
        if (target_root.is_value()) {
            return Placement.OtherModule;
        }
        if (from_root.is_value()) {
            return Placement.OutsideModule;
        }
        return Placement.OutsideFolder;
    }
}

# The components of `path` after `prefix`, when `prefix`'s components start
# it.
_strip_prefix(path: Path, prefix: Path): Array<String>? {
    var parts = path.components();
    var head = prefix.components();
    if (head.count > parts.count) {
        return Optional<Array<String>>.Empty;
    }
    ulong i = 0;
    while (i < head.count) {
        if (parts[i] != head[i]) {
            return Optional<Array<String>>.Empty;
        }
        i += 1;
    }
    var out = Array<String>();
    while (i < parts.count) {
        out.append(parts[i]);
        i += 1;
    }
    return Optional<Array<String>>.Value(out);
}

## Program loading: read and parse the root file, the prelude (forced
## imports, then the runtime), and every file their imports reach, then
## link them. The root is `files[0]`, followed by the files it reaches, then
## the prelude.

import compiler.ast;
import [Span] from compiler.ast;
import io;
import [File, Path] from io;
import json;
import [JsonValue] from json;
import os;
import compiler.parse;
import process;
import "files" as files;
import [LocalImport, ModuleRoots, Placement, Runtime] from "files";
import "link" as link;
import [FileScope, ModuleError, ProgramFile] from "link";
import [Target] from "platform";

## Where a program's files come from, beyond its root.
export struct Setup {
    ## `-I` directories, searched first for modules.
    var import_dirs: Path[] = Array<Path>();
    ## `--import` names: modules (or files) added to the prelude.
    var forced_imports: String[] = Array<String>();
    ## Load the discovered runtime as the prelude.
    var runtime: bool = true;
    ## The target platform selection evaluates against.
    var target: Target = Target();

    ## Creates the default setup: the runtime, and no other files.
    construct() {}
}

## A loaded, linked program. `files[0]` is the root.
export struct Program {
    ## The files, in load order.
    var files: ProgramFile[] = Array<ProgramFile>();
    ## What linking learned about each file.
    var scopes: FileScope[] = Array<FileScope>();
    ## Unresolved imports and linking errors, by file and position.
    var errors: ModuleError[] = Array<ModuleError>();
    ## The overload sets that span files.
    var overload_unions: Map<String, String[][]> = Map<String, String[][]>();

    ## Creates an empty program.
    construct() {}

    ## Returns the program as `pep-build --emit-linked` prints it: each
    ## file with its syntax tree after linking, the linking errors, and the
    ## overload sets that span files.
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        var out = JsonValue.object();
        var files_json = JsonValue.array();
        for (var f in files) {
            var file = JsonValue.object();
            file["name"] = JsonValue.String(f.name);
            file["namespace"] = JsonValue.String(f.namespace);
            file["module_root"] = f.module_root.is_value() ?
                JsonValue.String(f.module_root.value().to_string()) :
                JsonValue.Null;
            file["prelude"] = JsonValue.Bool(f.prelude);
            file["prelude_part"] = JsonValue.Bool(f.prelude_part);
            var imports = JsonValue.array();
            for (var target in f.imports) {
                imports.append(target.is_value() ? JsonValue.Integer(target.value() as long) : JsonValue.Null);
            }
            file["imports"] = imports;
            var folders = JsonValue.array();
            for (var folder in f.folder_imports) {
                folders.append(JsonValue.Bool(folder));
            }
            file["folder_imports"] = folders;
            file["module"] = f.module.to_json();
            files_json.append(file);
        }
        out["files"] = files_json;
        var errors_json = JsonValue.array();
        for (var e in errors) {
            var error = JsonValue.object();
            error["file"] = JsonValue.Integer(e.file as long);
            error["span"] = e.span.to_json();
            error["message"] = JsonValue.String(e.message);
            error["unresolved"] = JsonValue.Bool(e.unresolved);
            error["note"] = e.note_span.is_value() ?
                JsonValue.array([e.note_span.value().to_json(), JsonValue.String(e.note)]) :
                JsonValue.Null;
            errors_json.append(error);
        }
        out["errors"] = errors_json;
        var unions = JsonValue.object();
        for (var (name, groups) in overload_unions) {
            var groups_json = JsonValue.array();
            for (var group in groups) {
                var group_json = JsonValue.array();
                for (var part in group) {
                    group_json.append(JsonValue.String(part));
                }
                groups_json.append(group_json);
            }
            unions[name] = groups_json;
        }
        out["overload_unions"] = unions;
        return out;
    }
}

## Loads the program rooted at the file `root` as the compiler does:
## discovers the runtime, builds the search paths, resolves forced imports
## into the prelude, then loads and links every file.
##
## @param root the root file
## @param setup where the other files come from
## @returns the program, or why it cannot be loaded
export load_program(root: Path, setup: Setup): Result<Program, String> {
    var runtime = setup.runtime ? Runtime.discover() : Runtime();
    if (setup.runtime and runtime.sources.count == 0) {
        var named = os.environment(files.RUNTIME_ENV);
        if (named.is_value() and !named.value().is_empty) {
            return Result<Program, String>.err(
                $"cannot find the Pepper runtime: {files.RUNTIME_ENV} ({named.value()}) has no .pep files"
            );
        }
        var cwd = process.working_directory();
        return Result<Program, String>.err(
            $"cannot find the Pepper runtime: no runtime directory near {cwd.is_ok() ? cwd.value().to_string() : ""} or the compiler; set {files.RUNTIME_ENV} to its path"
        );
    }
    var search_paths = setup.import_dirs.copy();
    search_paths.append_all(runtime.dirs);
    # Forced imports join the prelude ahead of the runtime: where one
    # redefines a runtime export, the first definition wins.
    var prelude = Array<Path>();
    for (var name in setup.forced_imports) {
        var path = files.resolve_forced(name, search_paths);
        if (!path.is_value()) {
            var stem = name.ends_with(".pep") ? name.substr_bytes(0, name.size - 4) : name;
            return Result<Program, String>.err(
                $"--import {name}: cannot find module '{stem}' (no {stem}/module.pep) or file {stem}.pep in {_describe_paths(search_paths)}"
            );
        }
        prelude.append(path.value());
    }
    prelude.append_all(runtime.sources);
    return load(root, prelude, search_paths, setup.target);
}

# One file waiting to be loaded.
struct _Queued {
    var path: Path;
    var key: String;
    var prelude: bool;

    construct(path: Path, key: String, prelude: bool) {
        this.path = path;
        this.key = key;
        this.prelude = prelude;
    }
}

## Loads `root`, the `prelude` files, and everything their imports reach,
## resolving module imports against `search_paths`; then links them.
##
## @param root the root file
## @param prelude the prelude files, forced imports first
## @param search_paths where module imports look, in order
## @param target the target platform selection evaluates against
## @returns the program, or why a file cannot be read or parsed
export load(root: Path, prelude: Path[], search_paths: Path[], target: Target): Result<Program, String> {
    var program = Program();
    var index = HashMap<String, ulong>();
    # Resolved import keys per file, mapped to indices once all are loaded.
    var resolved = Array<Array<String?>>();
    var project = files.find_project(root);
    if (project.is_value()) {
        # The Rust compiler reads the project's `pep.toml` for its include
        # folders and dependencies; this loader does not yet.
        return Result<Program, String>.err(
            $"{project.value().join(Path(files.MANIFEST_FILE))}: pep.toml projects are not supported yet"
        );
    }
    if (!project.is_value()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            project = Optional<Path>.Value(cwd.value());
        }
    }
    var roots = ModuleRoots(project);
    # A stack: the root is taken first, and each file's imports are loaded
    # before the prelude.
    var root_key = files.path_key(root);
    var prelude_keys = HashSet<String>();
    var stack = Array<_Queued>();
    var queued = HashSet<String>();
    queued.insert(root_key);
    var keys = Array<String>();
    for (var p in prelude) {
        keys.append(files.path_key(p));
        prelude_keys.insert(keys[keys.count - 1]);
    }
    long p_index = prelude.count as long - 1;
    while (p_index >= 0) {
        var at = p_index as ulong;
        if (queued.insert(keys[at])) {
            stack.append(_Queued(prelude[at], keys[at], true));
        }
        p_index -= 1;
    }
    bool root_pending = true;
    while (true) {
        _Queued next = _Queued(root, root_key, prelude_keys.contains(root_key));
        if (!root_pending) {
            if (stack.count == 0) {
                break;
            }
            next = stack.pop();
        }
        root_pending = false;
        var path = next.path;
        var source = File.read_to_string(path);
        if (source.is_err()) {
            return Result<Program, String>.err($"cannot read {path}: {source.error().message}");
        }
        var parsed = parse.parse(source.value());
        if (parsed.is_err()) {
            var error = parsed.error();
            return Result<Program, String>.err(_render(path.to_string(), source.value(), error.span, error.message));
        }
        var module = parsed.value();
        ulong file = program.files.count;
        var targets = Array<String?>();
        var folders = Array<bool>();
        for (var imp in module.imports) {
            folders.append(false);
            # An import platform selection drops is never resolved.
            var kept = target.keep(imp.attributes);
            if (kept.is_err()) {
                program.errors.append(ModuleError(file, imp.span, kept.error()));
                targets.append(Optional<String>.Empty);
                continue;
            }
            if (!kept.value()) {
                targets.append(Optional<String>.Empty);
                continue;
            }
            Path? found = Optional<Path>.Empty;
            if (imp.is_local) {
                var local = files.resolve_local(path, imp.stem());
                if (local.is_value()) {
                    match (local.value()) {
                        File(p) => {
                            # A file of another module is reached through
                            # that module, not directly.
                            var placement = roots.placement(path, p);
                            if (placement != Placement.SameModule) {
                                var message = "";
                                match (placement) {
                                    OtherModule => {
                                        message = $"{imp.describe()} belongs to another module; import that module's folder instead";
                                    }
                                    OutsideModule => {
                                        message = $"{imp.describe()} is outside this file's module; a module imports only its own files";
                                    }
                                    else => {
                                        message = $"{imp.describe()} is outside this file's folder; a file outside any module imports only files in its folder or below";
                                    }
                                }
                                program.errors.append(ModuleError(file, imp.name_span, message));
                                targets.append(Optional<String>.Empty);
                                continue;
                            }
                            found = Optional<Path>.Value(p);
                        }
                        Module(p) => {
                            folders[folders.count - 1] = true;
                            found = Optional<Path>.Value(p);
                        }
                    }
                }
            } else {
                found = files.resolve_module(imp.name, search_paths);
            }
            if (found.is_value()) {
                var k = files.path_key(found.value());
                if (queued.insert(k)) {
                    stack.append(_Queued(found.value(), k, false));
                }
                targets.append(Optional<String>.Value(k));
                continue;
            }
            var message = "";
            if (imp.is_local) {
                message = $"cannot find {imp.describe()} or the module folder \"{imp.stem()}\" next to this file";
            } else {
                message = $"cannot find module '{imp.name}': no {imp.name.replace(".", "/")}/module.pep in {_describe_paths(search_paths)}";
            }
            # Only a module search depends on `-I`; a missing file is
            # missing everywhere.
            program.errors.append(ModuleError(file, imp.name_span, message, !imp.is_local));
            targets.append(Optional<String>.Empty);
        }
        index[next.key] = file;
        resolved.append(targets);
        var loaded = ProgramFile(path.to_string(), source.value(), module);
        loaded.namespace = roots.namespace_of(path);
        loaded.module_root = roots.module_of(path);
        loaded.prelude = next.prelude;
        loaded.folder_imports = folders;
        program.files.append(loaded);
    }
    ulong i = 0;
    while (i < program.files.count) {
        var imports = Array<ulong?>();
        for (var k in resolved[i]) {
            imports.append(k.is_value() ? index.try_get(k.value()) : Optional<ulong>.Empty);
        }
        program.files[i].imports = imports;
        i += 1;
    }
    # The files prelude files reach through local imports belong to them
    # (a forced module's other files).
    var part = Array<ulong>();
    i = 0;
    while (i < program.files.count) {
        if (program.files[i].prelude) {
            part.append(i);
        }
        i += 1;
    }
    while (part.count > 0) {
        var f = program.files[part.pop()];
        ulong m = 0;
        while (m < f.module.imports.count) {
            var t = f.imports[m];
            # Only its files: a module folder it imports is a module of
            # its own.
            if (t.is_value() and f.module.imports[m].is_local and !f.folder_imports[m]) {
                var reached = program.files[t.value()];
                if (!reached.prelude and !reached.prelude_part) {
                    reached.prelude_part = true;
                    part.append(t.value());
                }
            }
            m += 1;
        }
    }
    # Namespaces must be unique: two files outside the project and any
    # module, named by their file names, are told apart by load order.
    var taken = HashSet<String>();
    for (var f in program.files) {
        var base = f.namespace;
        ulong n = 1;
        while (!taken.insert(f.namespace)) {
            n += 1;
            f.namespace = $"{base}#{n}";
        }
    }
    var linked = link.link(program.files, target);
    program.errors.append_all(linked.errors);
    link.sort_errors(program.errors);
    program.scopes = linked.scopes;
    program.overload_unions = linked.overload_unions;
    return Result<Program, String>.ok(program);
}

_describe_paths(paths: Path[]): String {
    if (paths.count == 0) {
        return "(no search paths)";
    }
    var parts = Array<String>();
    for (var p in paths) {
        parts.append(p.to_string());
    }
    return ", ".join(parts);
}

# A parse error as the compiler reports it: `file:line:column: error: ...`.
_render(name: String, source: String, span: Span, message: String): String {
    ulong line = 1;
    ulong column = 1;
    ulong i = 0;
    while (i < span.start and i < source.size) {
        if (source.byte_at(i) == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
        i += 1;
    }
    return $"{name}:{line}:{column}: error: {message}";
}

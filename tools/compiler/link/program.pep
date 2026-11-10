## Program loading: read and parse the root file, the prelude (forced
## imports, then the runtime), and every file their imports reach, then
## link them. The root is `files[0]`, followed by the files it reaches, then
## the prelude.

import compiler.ast;
import [BUILT_IN_ATTRIBUTE, Declaration, Expression, Literal, Span] from compiler.ast;
import [
    compare_locations, Diagnostic, ERROR_LIMIT, Fix, Location, render_all, render_errors, shown_path, SourceText
] from compiler.diagnostic;
import io;
import [File, Path] from io;
import json;
import [JsonValue] from json;
import os;
import compiler.parse;
import process;
import [check_uses] from "deprecation";
import "files" as files;
import [LocalImport, ModuleRoots, Placement, Runtime] from "files";
import [find_library_interface, LibraryInterface] from "interface_file";
import "link" as link;
import [FileScope, ModuleError, ProgramFile] from "link";
import [demangle_name] from "names";
import [Target, undefined_build_option_comparisons] from "platform";
import [load_manifest, Packages, ungenerated_module] from "project";
import "project";
import [COMPILER_LEVEL, REQUIRED_LEVEL_NAME] from "stamp";
import [check_visibility] from "visibility";

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
    ## The text of files to load from here rather than the disk, by
    ## `files.path_key`: a test build's entry with its `main` added, or its
    ## generated entry and test files.
    var sources: HashMap<String, String> = HashMap<String, String>();
    ## Leave the files' bodies to `Program.link_bodies`: binding only.
    var defer_bodies: bool = false;
    ## The build's intermediate folder (`--build`), where `import generated`
    ## finds the modules a package's build script wrote; empty for the
    ## project's `.pep/build`.
    var build_dir: Path? = Optional<Path>.Empty;
    ## The most syntax errors to show (`--error-limit`); 0 shows every one.
    var error_limit: ulong = ERROR_LIMIT;
    ## The library's name in a library build (`--lib`), which namespaces
    ## its root and the files outside every module (`ModuleRoots.library`);
    ## empty for a program.
    var library: String = "";
    ## Runtime modules to load beside the root, by name: those a linked
    ## Pepper library loaded and the program does not import (#220). They
    ## are loaded as the program's imports are, not into the prelude.
    var extra_modules: String[] = Array<String>();
    ## The folders a module import that no source module answers looks in
    ## for a Pepper library's interface (`-L`, then `$PEPPER_LIBRARY_PATH`'s,
    ## #220).
    var library_dirs: Path[] = Array<Path>();
    ## Whether the library build (`library`) is `--lib pepper`'s, whose
    ## root's `main` is mangled like its other names.
    var pepper_library: bool = false;

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
    ## The target platform selection evaluated against.
    var target: Target = Target();
    ## Per file, whether its bodies were linked and are checked; empty:
    ## every file's (`link_bodies`).
    var bodies: bool[] = Array<bool>();
    ## The runtime's folders, as `files.path_key`s: found once per load,
    ## whether or not the program uses the runtime.
    var runtime_dirs: String[] = Array<String>();
    ## The most syntax errors `link_bodies` shows (`Setup.error_limit`).
    var error_limit: ulong = ERROR_LIMIT;
    # Linking left to `link_bodies`, when loaded with `defer_bodies`.
    var _pending: link.PendingLink? = Optional<link.PendingLink>.Empty;

    ## Creates an empty program.
    construct() {}

    ## Finishes linking a program loaded with `Setup.defer_bodies`: the bodies
    ## of the files `bodies` marks are linked, and only theirs are checked
    ## (`check`, `warnings`). A build leaves out the files whose compilation
    ## units its cache holds checked: they and what they import are as they
    ## were, and checked without an error or a warning then. Called again, it
    ## links the bodies of the files `bodies` marks that it left out before,
    ## as a compilation unit worker does for each compilation unit it is
    ## given. Without pending linking, nothing.
    ##
    ## @param bodies per file, whether to link and check its bodies
    ## @returns a syntax error in a body read now, rendered as `load`
    ##   renders one
    link_bodies(bodies: bool[]): String? {
        if (!_pending.is_value()) {
            return Optional<String>.Empty;
        }
        bool again = this.bodies.count > 0;
        # Loading read only the declarations: these files are read again,
        # whole. The declarations come out the same.
        for (var i in 0..files.count) {
            if ((i < bodies.count and !bodies[i]) or (again and this.bodies[i])) {
                continue;
            }
            var f = files[i];
            # A library interface's file has no bodies.
            if (f.interface.is_value()) {
                continue;
            }
            var parsed = parse.parse(f.source);
            if (parsed.is_err()) {
                var error = parsed.error();
                return Optional<String>.Value(_render(f.name, f.source, error, error_limit));
            }
            f.module = parsed.value();
            if (again) {
                var (scope, more) = _pending.value().finish_bodies(i);
                scopes[i] = scope;
                errors.append_all(more);
                link.sort_errors(errors);
                this.bodies[i] = true;
            }
        }
        if (again) {
            return Optional<String>.Empty;
        }
        var marked = Array<bool>();
        for (var i in 0..files.count) {
            marked.append(i >= bodies.count or bodies[i]);
        }
        _take_linked(_pending.value().finish(marked));
        this.bodies = marked;
        return Optional<String>.Empty;
    }

    # Takes the errors and scopes of finished linking.
    _take_linked(linked: link.Linked) {
        errors.append_all(linked.errors);
        link.sort_errors(errors);
        scopes = linked.scopes;
        overload_unions = linked.overload_unions;
    }

    ## Whether file `file`'s bodies are linked and checked.
    ##
    ## @param file the file's index
    ## @returns true unless `link_bodies` left them out
    has_bodies(file: ulong): bool {
        return file >= bodies.count or bodies[file];
    }

    ## Returns each file's name and text, for rendering diagnostics.
    ##
    ## @returns the files, by index
    sources(): SourceText[] {
        var out = Array<SourceText>();
        for (var f in files) {
            out.append(SourceText(f.name, f.source));
        }
        return out;
    }

    ## Returns what is wrong with the program before type checking,
    ## rendered: the linking errors; when there are none, any
    ## `[__BuiltIn]` declaration outside the runtime; when there is none of
    ## those either, the visibility errors.
    ##
    ## @returns the rendered errors, or none when the program is well-formed
    check(): String? {
        var errors = check_diagnostics();
        if (errors.count == 0) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(render_all(errors, sources()));
    }

    ## Returns what is wrong with the program before type checking, as
    ## `check` finds it: the linking errors; when there are none, any
    ## `[__BuiltIn]` declaration outside the runtime; when there is none of
    ## those either, the visibility errors.
    ##
    ## @param walked per file, whether to look for visibility errors in its
    ##   bodies; empty: in every file `link_bodies` linked. A compilation unit
    ##   worker names its unit's files, as the files of the units it checked
    ##   before are linked too, and clean
    ## @returns the errors; empty when the program is well-formed
    check_diagnostics(walked: bool[] = Array<bool>()): Diagnostic[] {
        var errors = Array<Diagnostic>();
        # A runtime newer than this compiler explains every error after it.
        var level = level_error();
        if (level.is_value()) {
            errors.append(level.value());
            return errors;
        }
        for (var e in this.errors) {
            errors.append(e.to_diagnostic());
        }
        if (errors.count == 0) {
            errors = built_in_errors();
        }
        if (errors.count == 0) {
            for (var e in check_visibility(files, scopes, target, walked.count > 0 ? walked : bodies)) {
                errors.append(e.to_diagnostic(files));
            }
        }
        return errors;
    }

    ## Returns the error for a runtime that needs a newer compiler than this
    ## one: a prelude file's `REQUIRED_LEVEL_NAME` constant above
    ## `COMPILER_LEVEL` (#220). Nothing when the runtime fits.
    ##
    ## @returns the error, located at the constant's value
    level_error(): Diagnostic? {
        for (var i in 0..files.count) {
            if (!files[i].prelude and !files[i].prelude_part) {
                continue;
            }
            for (var declaration in files[i].module.declarations) {
                var found = _required_level(declaration);
                if (found.is_value() and found.value().0 > COMPILER_LEVEL) {
                    var (level, span) = found.value();
                    return Optional<Diagnostic>.Value(
                        Diagnostic.error(
                            $"the runtime needs compiler level {level}, and this compiler is level {COMPILER_LEVEL}: build it with a newer compiler (CI: move the stage 0 pin, .github/stage0)"
                        ).at(Location(i, span))
                    );
                }
            }
        }
        return Optional<Diagnostic>.Empty;
    }

    ## Returns, for each file, whether it is part of the runtime: the
    ## prelude, a file a prelude file reaches, or a file under one of
    ## `runtime_dirs`.
    ##
    ## @returns one flag per file, by index
    in_runtime(): bool[] {
        var out = Array<bool>();
        for (var f in files) {
            bool inside = f.prelude or f.prelude_part;
            for (var dir in runtime_dirs) {
                if (f.key.starts_with(dir)) {
                    inside = true;
                }
            }
            out.append(inside);
        }
        return out;
    }

    ## Returns each Pepper library interface the program's imports loaded.
    ##
    ## @returns the interfaces, in load order
    interfaces(): LibraryInterface[] {
        var out = Array<LibraryInterface>();
        for (var f in files) {
            if (f.interface.is_value() and f.library_root) {
                out.append(f.interface.value());
            }
        }
        return out;
    }

    ## Returns every `[__BuiltIn]` declaration outside the runtime: only the
    ## runtime declares the compiler's built-ins.
    ##
    ## @returns an error at each
    built_in_errors(): Diagnostic[] {
        var in_runtime = in_runtime();
        var out = Array<Diagnostic>();
        ulong i = 0;
        while (i < files.count) {
            var f = files[i];
            if (!in_runtime[i]) {
                for (var d in f.module.declarations) {
                    for (var a in d.attributes()) {
                        if (a.name() != BUILT_IN_ATTRIBUTE) {
                            continue;
                        }
                        var at = a.body.span();
                        match (a.body) {
                            FunctionCall(function, _, _) => {
                                at = function.span();
                            }
                            else => {}
                        }
                        out.append(
                            Diagnostic.error(
                                "'__BuiltIn' declares a compiler built-in and is allowed only in the runtime"
                            ).at(Location(i, at))
                        );
                        break;
                    }
                }
            }
            i += 1;
        }
        return out;
    }

    ## Returns the warnings before type checking: deprecated syntax, then
    ## comparisons with build options the target does not define, then uses
    ## of declarations marked `[Deprecated]`.
    ##
    ## @returns the warnings
    warnings(): Diagnostic[] {
        var out = Array<Diagnostic>();
        ulong i = 0;
        while (i < files.count) {
            for (var w in files[i].module.warnings) {
                var at = Location(i, w.span);
                if (!w.message.is_empty) {
                    out.append(Diagnostic.warning(w.message).at(at));
                    continue;
                }
                out.append(
                    Diagnostic.deprecated(
                        w.what, w.instead, at, Fix($"Replace {w.what} with `{w.replacement}`", at, w.replacement)
                    )
                );
            }
            i += 1;
        }
        i = 0;
        while (i < files.count) {
            for (var attribute in files[i].module.build_option_tests) {
                for (var undefined in undefined_build_option_comparisons(target, attribute)) {
                    out.append(
                        Diagnostic
                            .warning($"build option '{undefined.name}' is not defined; the comparison is false")
                            .at(Location(i, undefined.span))
                            .with_note($"define it with '-D {undefined.name}=<value>'", Optional<Location>.Empty)
                    );
                }
            }
            i += 1;
        }
        out.append_all(check_uses(files, scopes, target, bodies));
        return out;
    }

    ## Returns what `pep-build --emit-checked` prints: the rendered errors
    ## of `check()`, if any, then the rendered warnings.
    ##
    ## @returns the text
    check_report(): String {
        var parts = Array<String>();
        var errors = check();
        if (errors.is_value()) {
            parts.append(errors.value());
        }
        var warnings = render_warnings();
        if (!warnings.is_empty) {
            parts.append(warnings);
        }
        return "\n".join(parts);
    }

    ## Returns `warnings()`, rendered.
    ##
    ## @returns the text, empty when there are none
    render_warnings(): String {
        return render_all(warnings(), sources());
    }

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
    var found = Runtime.discover();
    var runtime = setup.runtime ? found : Runtime();
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
    # The project's `pep.toml`: its `[build]` include folders follow the
    # `-I` ones.
    var import_dirs = setup.import_dirs.copy();
    var project = files.find_project(root);
    if (project.is_value()) {
        var manifest = load_manifest(project.value().join(Path(files.MANIFEST_FILE)), runtime.dirs);
        if (manifest.is_err()) {
            return Result<Program, String>.err(manifest.error());
        }
        import_dirs.append_all(manifest.value().include_dirs());
    }
    var search_paths = import_dirs;
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
    var runtime_dir = runtime.sources.count > 0 ?
        Optional<Path>.Value(files.dir_of(runtime.sources[0])) :
        Optional<Path>.Empty;
    var extra = Array<Path>();
    for (var name in setup.extra_modules) {
        var path = files.resolve_module(name, runtime.dirs);
        if (!path.is_value()) {
            return Result<Program, String>.err(
                $"a linked Pepper library needs the runtime module '{name}', which this runtime does not have; rebuild the library with this compiler"
            );
        }
        extra.append(path.value());
    }
    var loaded = load(
        root,
        prelude,
        search_paths,
        setup.target,
        setup.sources,
        setup.defer_bodies,
        setup.build_dir,
        runtime_dir,
        setup.error_limit,
        setup.library,
        extra,
        setup.library_dirs,
        setup.pepper_library
    );
    if (loaded.is_err()) {
        return loaded;
    }
    var program = loaded.value();
    for (var dir in found.dirs) {
        program.runtime_dirs.append(files.path_key(dir));
    }
    return Result<Program, String>.ok(program);
}

# The level and its span when `declaration` is the runtime's
# `REQUIRED_LEVEL_NAME` constant, an integer.
_required_level(declaration: Declaration): (long, Span)? {
    if (declaration is Declaration.Variable(decl)) {
        if (demangle_name(decl.name) == REQUIRED_LEVEL_NAME and decl.default_value.is_value()) {
            if (decl.default_value.value() is Expression.Literal(value, span)) {
                if (value is Literal.Integer(level)) {
                    return Optional<(long, Span)>.Value((level, span));
                }
            }
        }
    }
    return Optional<(long, Span)>.Empty;
}

# One file waiting to be loaded.
struct _Queued {
    var path: Path;
    var key: String;
    var prelude: bool;
    # A file of a library interface, and its index there.
    var interface: LibraryInterface? = Optional<LibraryInterface>.Empty;
    var index: ulong = 0;

    construct(path: Path, key: String, prelude: bool) {
        this.path = path;
        this.key = key;
        this.prelude = prelude;
    }
}

# Where the file of namespace `namespace` of the library interface
# `interface` loads from: a path inside the interface file, which names it
# in diagnostics.
_interface_path(interface: LibraryInterface, namespace: String): Path {
    return Path($"{interface.path}/{namespace}.pep");
}

## Loads `root`, the `prelude` files, and everything their imports reach,
## resolving module imports against `search_paths`; then links them.
##
## @param root the root file
## @param prelude the prelude files, forced imports first
## @param search_paths where module imports look, in order
## @param target the target platform selection evaluates against, which
##   gains the build options of the project's features turned on
##   (`Packages.turn_on_features`)
## @param sources the text of files to take from here rather than the disk, by `files.path_key`
## @param defer_bodies whether to leave the files' bodies to `Program.link_bodies`
## @param build_dir the build's intermediate folder, which holds the
##   packages' generated modules; empty for the project's `.pep/build`
## @param runtime_dir the runtime's folder, if any: its files belong to no
##   module folder above it (a toolchain installed in a package's folder)
## @param error_limit the most syntax errors to show; 0 shows every one
## @param library the library's name in a library build, which namespaces
##   its root and loose files; empty for a program
## @param extra more files to load as the root's imports are, not into
##   the prelude (`Setup.extra_modules`)
## @param library_dirs where a module import no source module answers
##   looks for a Pepper library's interface (`Setup.library_dirs`)
## @param pepper_library whether the library build is `--lib pepper`'s
## @returns the program, or why a file cannot be read or parsed or a feature
##   turned on
export load(
    root: Path,
    prelude: Path[],
    search_paths: Path[],
    target: Target,
    sources: HashMap<String, String> = HashMap<String, String>(),
    defer_bodies: bool = false,
    build_dir: Path? = Optional<Path>.Empty,
    runtime_dir: Path? = Optional<Path>.Empty,
    error_limit: ulong = ERROR_LIMIT,
    library: String = "",
    extra: Path[] = Array<Path>(),
    library_dirs: Path[] = Array<Path>(),
    pepper_library: bool = false
): Result<Program, String> {
    var program = Program();
    program.error_limit = error_limit;
    var index = HashMap<String, ulong>();
    # Resolved import keys per file, mapped to indices once all are loaded.
    var resolved = Array<Array<String?>>();
    # The `pep.toml` each file falls under, for the dependencies it imports.
    var packages = Packages(root, target);
    packages.build_dir = build_dir;
    var features = packages.turn_on_features();
    if (features.is_err()) {
        return Result<Program, String>.err(features.error());
    }
    var project = packages.project;
    if (!project.is_value()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            project = Optional<Path>.Value(cwd.value());
        }
    }
    var roots = ModuleRoots(project, runtime_dir);
    roots.library = library;
    var script_module = target.build_script_root.is_value() and packages.project.is_value() ?
        roots.key(packages.project.value()) :
        "";
    # A stack: the root is taken first, and each file's imports are loaded
    # before the prelude.
    var root_key = roots.key(root);
    var prelude_keys = HashSet<String>();
    var stack = Array<_Queued>();
    var queued = HashSet<String>();
    queued.insert(root_key);
    var keys = Array<String>();
    for (var p in prelude) {
        keys.append(roots.key(p));
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
    for (var path in extra) {
        var k = roots.key(path);
        if (queued.insert(k)) {
            stack.append(_Queued(path, k, false));
        }
    }
    # The library interfaces loaded, by the library's name.
    var interfaces = HashMap<String, LibraryInterface>();
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
        # A file of a library interface has no text: its declarations
        # come from its link table.
        var source = next.interface.is_value() ?
            Result<String, io.IoError>.ok("") :
            sources.contains(next.key) ? Result<String, io.IoError>.ok(sources[next.key]) : File.read_to_string(path);
        if (source.is_err()) {
            return Result<Program, String>.err($"cannot read {path}: {source.error().message}");
        }
        var interface_names = Array<String>();
        # Deferred, only the declarations: `link_bodies` reads the bodies
        # it links.
        var parsed = defer_bodies ? parse.parse_declarations(source.value()) : parse.parse(source.value());
        if (next.interface.is_value()) {
            var (declared, linked) = next.interface.value().files[next.index].declarations();
            parsed = Result<ast.Module, parse.ParseError>.ok(declared);
            interface_names = linked;
        }
        if (parsed.is_err()) {
            var error = parsed.error();
            return Result<Program, String>.err(_render(path.to_string(), source.value(), error, error_limit));
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
                match (packages.resolve(path, imp.name)) {
                    Found(p) => {
                        found = Optional<Path>.Value(p);
                    }
                    NotADependency => {
                        found = files.resolve_module(imp.name, search_paths);
                        # No source module: a Pepper library's interface
                        # (#220), all its files queued with its root.
                        if (!found.is_value() and !imp.name.contains(".") and !next.interface.is_value()) {
                            var known = interfaces.try_get(imp.name);
                            if (!known.is_value()) {
                                var read = find_library_interface(imp.name, library_dirs, target);
                                if (read.is_value() and read.value().is_err()) {
                                    program.errors.append(ModuleError(file, imp.name_span, read.value().error()));
                                    targets.append(Optional<String>.Empty);
                                    continue;
                                }
                                if (read.is_value()) {
                                    known = Optional<LibraryInterface>.Value(read.value().value());
                                    interfaces[imp.name] = known.value();
                                    for (var i in 0..known.value().files.count) {
                                        var at = _interface_path(known.value(), known.value().files[i].namespace);
                                        var entry = _Queued(at, roots.key(at), false);
                                        entry.interface = known;
                                        entry.index = i;
                                        if (queued.insert(entry.key)) {
                                            stack.append(entry);
                                        }
                                    }
                                }
                            }
                            if (known.is_value()) {
                                for (var f in known.value().files) {
                                    if (f.root) {
                                        found = Optional<Path>.Value(_interface_path(known.value(), f.namespace));
                                    }
                                }
                            }
                        }
                    }
                    Missing(message) => {
                        # Fetching the dependency, or fixing the `pep.toml`,
                        # resolves it.
                        program.errors.append(ModuleError(file, imp.name_span, message, true));
                        targets.append(Optional<String>.Empty);
                        continue;
                    }
                }
            }
            if (found.is_value()) {
                var k = roots.key(found.value());
                if (queued.insert(k)) {
                    stack.append(_Queued(found.value(), k, false));
                }
                targets.append(Optional<String>.Value(k));
                continue;
            }
            var message = "";
            if (imp.is_local) {
                message = $"cannot find '{imp.stem()}.pep' or the module folder '{imp.stem()}' next to this file";
            } else {
                var ungenerated = ungenerated_module(path, imp.name);
                message = ungenerated.is_value() ?
                    ungenerated.value() :
                    $"cannot find module '{imp.name}': no {imp.name.replace(".", "/")}/module.pep in {_describe_paths(search_paths)}";
            }
            # Only a module search depends on `-I`; a missing file is
            # missing everywhere.
            program.errors.append(ModuleError(file, imp.name_span, message, !imp.is_local));
            targets.append(Optional<String>.Empty);
        }
        index[next.key] = file;
        resolved.append(targets);
        var loaded = ProgramFile(path.to_string(), source.value(), module);
        loaded.key = next.key;
        if (next.interface.is_value()) {
            # Named, and mangled, as the library build named it.
            var named = next.interface.value().files[next.index];
            loaded.namespace = named.namespace;
            loaded.module_root = Optional<Path>.Empty;
            loaded.library_root = named.root;
            loaded.mangles_main = true;
            loaded.interface = next.interface;
            loaded.interface_names = interface_names;
            loaded.interface_exports = named.exports;
        } else {
            loaded.namespace = roots.namespace_of(path);
            loaded.module_root = roots.module_of(path);
            loaded.library_root = !library.is_empty and next.key == root_key;
            loaded.mangles_main = pepper_library;
        }
        # A file of a module sees the declarations of the module's other
        # files, so loading one loads its `module.pep`, and with it the
        # files the module reaches. Spelled from the file's own path, as an
        # import of it would be. Not in a build script's build, of the
        # module its package's folder is: the script stands apart from the
        # code it builds, which may import what it generates.
        if (loaded.module_root.is_value() and roots.key(loaded.module_root.value()) != script_module) {
            var module_key = roots.key(loaded.module_root.value());
            var dir = path.parent();
            while (dir.is_value()) {
                if (roots.key(dir.value()) == module_key) {
                    var module_file = dir.value().join(Path(files.MODULE_FILE));
                    var k = roots.key(module_file);
                    if (queued.insert(k)) {
                        stack.append(_Queued(module_file, k, false));
                    }
                    break;
                }
                dir = dir.value().parent();
            }
        }
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
    # module, named by their file names, are told apart by load order. A
    # library interface's keep theirs, which its record and mangled names
    # carry, so a program file may not share one.
    var taken = HashSet<String>();
    # The library each interface file's namespace belongs to.
    var library_of = HashMap<String, String>();
    for (var f in program.files) {
        if (f.interface.is_value()) {
            taken.insert(f.namespace);
            library_of[f.namespace] = f.interface.value().name;
        }
    }
    var clash = _library_clash(program.files, library_of);
    if (clash.is_value()) {
        return Result<Program, String>.err(render_all([clash.value()], program.sources()));
    }
    for (var f in program.files) {
        if (f.interface.is_value()) {
            continue;
        }
        # Only a file no program file imports (a forced import) is left.
        var owner = library_of.try_get(f.namespace);
        if (owner.is_value()) {
            return Result<Program, String>.err(
                $"{f.name} has the namespace '{f.namespace}' of a file of the Pepper library '{owner.value()}'; a program cannot import a library built from its own files"
            );
        }
        var base = f.namespace;
        ulong n = 1;
        while (!taken.insert(f.namespace)) {
            n += 1;
            f.namespace = $"{base}#{n}";
        }
    }
    program.target = target;
    if (defer_bodies) {
        var pending = link.PendingLink(program.files, target);
        var bound = pending.bound();
        program.scopes = bound.scopes;
        program.overload_unions = bound.overload_unions;
        program._pending = Optional<link.PendingLink>.Value(pending);
        return Result<Program, String>.ok(program);
    }
    program._take_linked(link.link(program.files, target));
    return Result<Program, String>.ok(program);
}

# The error for a file of the program that shares its namespace with a
# file of a Pepper library the program imports (`library_of`, by
# namespace): located at the import that reaches it from a file of the
# program's own, with a note at the program's import of the library.
# Nothing when no import reaches such a file.
_library_clash(files: ProgramFile[], library_of: HashMap<String, String>): Diagnostic? {
    for (var file in 0..files.count) {
        var g = files[file];
        if (g.interface.is_value() or library_of.contains(g.namespace)) {
            continue;
        }
        for (var m in 0..g.imports.count) {
            var t = g.imports[m];
            if (!t.is_value() or files[t.value()].interface.is_value()) {
                continue;
            }
            var clash = files[t.value()];
            var library = library_of.try_get(clash.namespace);
            if (!library.is_value()) {
                continue;
            }
            var name = library.value();
            var imported = g.module.imports[m].describe_as(g.folder_imports[m]);
            # A module (an `-I` module, a package) is a dependency the two
            # share; any other file is one of the library's own.
            var message = clash.module_root.is_value() ?
                $"{imported} is already part of the Pepper library '{name}'; drop this import and use what '{name}' exports, or rebuild '{name}' without it" :
                $"{imported} has the namespace '{clash.namespace}' of a file of the Pepper library '{name}'; a program cannot import a library built from its own files";
            var out = Diagnostic.error(message).at(Location(file, g.module.imports[m].name_span));
            for (var other in 0..files.count) {
                var h = files[other];
                for (var k in 0..h.imports.count) {
                    var u = h.imports[k];
                    if (!h.interface.is_value()
                        and u.is_value()
                        and files[u.value()].interface.is_value()
                        and files[u.value()].interface.value().name == name) {
                        return Optional<Diagnostic>.Value(
                            out.with_note(
                                $"the Pepper library '{name}' is imported here",
                                Optional<Location>.Value(Location(other, h.module.imports[k].name_span))
                            )
                        );
                    }
                }
            }
            return Optional<Diagnostic>.Value(out);
        }
    }
    return Optional<Diagnostic>.Empty;
}

_describe_paths(paths: Path[]): String {
    if (paths.count == 0) {
        return "(no search paths)";
    }
    var parts = Array<String>();
    for (var p in paths) {
        parts.append(shown_path(p.to_string()));
    }
    return ", ".join(parts);
}

# A file's syntax errors as the compiler reports them: `file:line:column:
# error: ...` with the line and a caret under the span, and a note at the
# place it is about, such as the `{` a missing `}` should close; ordered by
# place, each once, at most `limit` (`render_errors`). `error` is the one
# `parse` stopped at; the recovering parse, run on this error path alone,
# finds the rest, of which only those it can trust are kept: a missing `}`
# only when it is `error` (after another error it is mostly the skipping's
# doing), and past a line the lexer refused, which is read as spaces, only
# the lexer's errors.
_render(name: String, source: String, error: parse.ParseError, limit: ulong): String {
    var recovered = parse.parse_recovering(source);
    if (recovered.errors.is_empty) {
        recovered.errors.append(error);
    }
    ulong refused = recovered.lexical > 0 ? recovered.errors[0].span.start : source.size + 1;
    var errors = Array<Diagnostic>();
    for (var i in 0..recovered.errors.count) {
        var e = recovered.errors[i];
        if (i > 0 and (e.related.is_value() or (i >= recovered.lexical and e.span.start >= refused))) {
            continue;
        }
        var diagnostic = Diagnostic.error(e.message).at(Location(0, e.span));
        if (e.related is Value(related)) {
            diagnostic = diagnostic.with_note(e.related_message, Optional<Location>.Value(Location(0, related)));
        }
        errors.append(diagnostic);
    }
    errors.sort((a, b) => compare_locations(a, b));
    var shown = Array<Diagnostic>();
    for (var d in errors) {
        if (shown.is_empty
            or shown.last().location.value().span.start != d.location.value().span.start
            or shown.last().message != d.message) {
            shown.append(d);
        }
    }
    return render_errors(shown, [SourceText(name, source)], limit);
}

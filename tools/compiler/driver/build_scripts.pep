## Build scripts: a package's `build.pep` (or the file `[build]`'s
## `script` names), which a build compiles for the host and runs before it
## loads the program, and the `pep:` instructions the script prints to say
## what to link and which build options to define. Each package's script
## runs in `<build>/<package>-<hash>/` (`Manifest.script_folder`), the
## modules it generates are in `out/` there, and its result is kept there,
## in `stamp`, until what it depends on changes.

import compiler.codegen;
import digest;
import [Cache, default_cache] from compiler.incremental;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import process;
import toolchain;
import "linker";

## What the build scripts of a program's packages add to its build.
export struct ScriptOutput {
    ## Libraries to link, by name (`pep:link=NAME`).
    var libraries: String[] = Array<String>();
    ## Folders to search for them (`pep:link-path=DIR`).
    var library_dirs: Path[] = Array<Path>();
    ## Object files and static libraries to link (`pep:object=FILE`).
    var objects: Path[] = Array<Path>();
    ## The build options to define (`pep:build-option=NAME[=VALUE]`), each
    ## named `<package>_<NAME>`, as a feature's are.
    var build_options: HashMap<String, String> = HashMap<String, String>();
}

## What a build passes each build script, besides the package.
export struct ScriptInputs {
    ## What the program is built for.
    var target: link.Target = link.Target();
    ## The build's intermediate folder (`--build`): each script works in
    ## `Manifest.script_folder(build_dir)`.
    var build_dir: Path = Path(".");
    ## The optimization level, 0 to 3.
    var opt_level: uint = 0;
    ## The target's system root, if any (`--sysroot`).
    var sysroot: Path? = Optional<Path>.Empty;
    ## Whether a dependency with a build script is an error instead
    ## (`--no-build-scripts`); the project's own script still runs.
    var refuse: bool = false;
    ## The build cache the scripts build in; its record of each script's
    ## program names the files the script's stamp covers.
    var cache: Cache = default_cache(Path("."));
}

## Runs the build script of each package a build of `entry` turns on, the
## project's first, and gathers what they print. A script is compiled for
## the host with this compiler, with its package's build-dependencies, and
## runs in its package's folder; with nothing it depends on changed since
## its last run (`_key`), its last output is used again instead. In the
## build of a build script (`Target.build_script_root`), the scripts of its
## build-dependencies run, and not its own.
##
## @param entry the program's entry file
## @param inputs what the build is for
## @returns what to link and define, or why a script could not run or what
##   it printed is wrong
export run_build_scripts(entry: Path, inputs: ScriptInputs): Result<ScriptOutput, String> {
    var output = ScriptOutput();
    var packages = link.Packages(entry, inputs.target);
    # Loading the program reports a feature that cannot be turned on.
    packages.turn_on_features();
    for (var manifest in packages.reached) {
        var script = toolchain.build_script(manifest.dir());
        if (script.is_err()) {
            return Result<ScriptOutput, String>.err(script.error());
        }
        var native = manifest.native_for(inputs.target);
        if (!script.value().is_value() and !native.is_value()) {
            continue;
        }
        var name = manifest.name.is_empty ? manifest.dir().file_name().value_or("project") : manifest.name;
        # The project's own script is the user's code; a dependency's is not.
        bool own = packages.project.is_value()
            and manifest.dir().normalize().to_string() == packages.project.value().normalize().to_string();
        if (own and inputs.target.build_script_root.is_value()) {
            continue;
        }
        if (script.value().is_value()) {
            if (inputs.refuse and !own) {
                return Result<ScriptOutput, String>.err(
                    $"the dependency '{name}' has a build script, {script.value().value()}, which '--no-build-scripts' (or PEPPER_NO_BUILD_SCRIPTS) refuses to run; read it, and build without that option to run it"
                );
            }
            var ran = _run(name, manifest, script.value().value(), packages, inputs);
            if (ran.is_err()) {
                return Result<ScriptOutput, String>.err(ran.error());
            }
            var applied = _apply(name, manifest, ran.value(), output);
            if (applied.is_err()) {
                return Result<ScriptOutput, String>.err(applied.error());
            }
        }
        # After the script, so the C can include the headers it wrote. It
        # runs no package code, so `refuse` allows it, but for its `flags`.
        if (native.is_value()) {
            # A clang flag can load a plugin from the package (`-fplugin=`).
            if (inputs.refuse and !own and !native.value().flags.is_empty) {
                return Result<ScriptOutput, String>.err(
                    $"the dependency '{name}' gives its '[native]' C the clang flags '{" ".join(native.value().flags)}', which could load code from the package, and '--no-build-scripts' (or PEPPER_NO_BUILD_SCRIPTS) refuses them; read them, and build without that option to use them"
                );
            }
            var built = _build_native(name, manifest, native.value(), script.value().is_value(), inputs, output);
            if (built.is_err()) {
                return Result<ScriptOutput, String>.err(built.error());
            }
        }
    }
    return Result<ScriptOutput, String>.ok(output);
}

# The output of the build script `script` of the package `name`, whose
# pep.toml is `manifest`, one of `packages`: its last, when nothing its key
# covers changed and its `out` folder is there, else that of running it
# again. One build at a time runs a package's script, under the lock file
# in its folder.
_run(
    name: String, manifest: link.Manifest, script: Path, packages: link.Packages, inputs: ScriptInputs
): Result<String, String> {
    var dir = manifest.dir();
    var work = manifest.script_folder(inputs.build_dir);
    var out = work.join(Path("out"));
    # It holds the generated modules too, which the stamp does not name.
    bool lost = !out.is_directory();
    var created = Directory.create_all(out);
    if (created.is_err()) {
        return Result<String, String>.err($"cannot create {out}: {created.error().message}");
    }
    var lock = _lock(work.join(Path("lock")));
    if (lock.is_err()) {
        return Result<String, String>.err(lock.error());
    }
    # Its own source, its package's pep.toml, and pep.lock, which holds its
    # build-dependencies' revisions.
    var sources = [script, manifest.path, packages.deps_root.value().join(Path(link.LOCK_FILE))];
    var environment = _environment(name, dir, out, packages.features_on(manifest), inputs);
    var ran = _run_locked(name, dir, sources, work, environment, packages.deps_root.value(), lost, inputs);
    lock.value().close();
    return ran;
}

# The file `path`, opened and locked, so one build at a time works in its
# folder; closing it unlocks it.
_lock(path: Path): Result<File, String> {
    var opened = io.OpenOptions().write(true).create(true).open(path);
    if (opened.is_err()) {
        return Result<File, String>.err($"cannot open {path}: {opened.error().message}");
    }
    var held = opened.value().lock();
    if (held.is_err()) {
        return Result<File, String>.err($"cannot lock {path}: {held.error().message}");
    }
    return Result<File, String>.ok(opened.value());
}

# `_run`, holding the lock: `stamp` holds the key, then the output. The
# script is `sources[0]`, built for the host with the packages `deps_root`
# serves; `lost`, its `out` folder was gone, so it runs again. The key also
# covers the files the build cache recorded the script's program was built
# from (its modules, its build-dependencies'); with no record, it runs.
_run_locked(
    name: String,
    dir: Path,
    sources: Path[],
    work: Path,
    environment: String[][],
    deps_root: Path,
    lost: bool,
    inputs: ScriptInputs
): Result<String, String> {
    var script = sources[0];
    var stamp = work.join(Path("stamp"));
    var executable = work.join(Path("build-script" + toolchain.executable_suffix()));
    var imported = inputs.cache.program_files(executable);
    var kept = File.read_to_string(stamp);
    if (kept.is_ok() and !lost and imported.is_value()) {
        var split = kept.value().split_once("\n");
        if (split.is_value()) {
            var (key, last) = split.value();
            # An object it made since deleted needs a run.
            if (key == _key(dir, _with(sources, imported.value()), environment, last) and _objects_exist(dir, last)) {
                return Result<String, String>.ok(last);
            }
        }
    }
    var compiler = process.executable_path();
    if (compiler.is_err()) {
        return Result<String, String>.err($"cannot find this compiler to build {script}: {compiler.error().message}");
    }
    # For the host, with its package's build-dependencies; that build runs
    # their scripts and not this one, which would build itself.
    var arguments = [
        script.to_string(),
        "-o",
        executable.to_string(),
        "--build",
        work.join(Path("build")).to_string(),
        "--build-script",
        link.absolute(deps_root).to_string(),
        "--cache",
        inputs.cache.dir.parent().value().to_string()
    ];
    if (inputs.refuse) {
        arguments.append("--no-build-scripts");
    }
    var built = process
        .Command(compiler.value().to_string())
        .arguments(arguments)
        .stdout(process.Stream.Pipe)
        .stderr(process.Stream.Pipe)
        .run();
    if (built.is_err()) {
        return Result<String, String>.err($"cannot run {compiler.value()}: {built.error().message}");
    }
    if (!built.value().status.success()) {
        return Result<String, String>.err(
            $"cannot build the build script of '{name}', {script}:\n{(built.value().stderr + built.value().stdout).trim()}"
        );
    }
    var command = process.Command(executable.to_string()).working_directory(dir);
    for (var variable in environment) {
        command.environment(variable[0], variable[1]);
    }
    var ran = command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe).run();
    if (ran.is_err()) {
        return Result<String, String>.err(
            $"cannot run the build script of '{name}', {executable}: {ran.error().message}"
        );
    }
    if (!ran.value().status.success()) {
        var said = (ran.value().stderr + ran.value().stdout).trim();
        return Result<String, String>.err(
            $"the build script of '{name}', {script}, failed ({ran.value().status.to_string()})"
                + (said.is_empty ? "" : $":\n{said}")
        );
    }
    var printed = ran.value().stdout;
    if (!ran.value().stderr.trim().is_empty) {
        File.stderr().write_all(ran.value().stderr);
    }
    for (var line in _instructions(printed)) {
        if (line.starts_with("warning=")) {
            File.stderr().write_all($"warning: {name}: {line.substr_bytes(8, line.size - 8)}\n");
        }
    }
    var files = inputs.cache.program_files(executable);
    var key = _key(dir, _with(sources, files.is_value() ? files.value() : Array<String>()), environment, printed);
    var written = File.write_text(stamp, key + "\n" + printed);
    if (written.is_err()) {
        return Result<String, String>.err($"cannot write {stamp}: {written.error().message}");
    }
    return Result<String, String>.ok(printed);
}

# `sources`, then the files `paths` names.
_with(sources: Path[], paths: String[]): Path[] {
    var all = Array<Path>();
    for (var source in sources) {
        all.append(source);
    }
    for (var path in paths) {
        all.append(Path(path));
    }
    return all;
}

# The variables a script runs with, each a name and its value.
_environment(name: String, dir: Path, out: Path, features: String[], inputs: ScriptInputs): String[][] {
    var clang = find_link_driver();
    return [
        ["PEP_TARGET", codegen.target_triple(inputs.target)],
        ["PEP_TARGET_OS", inputs.target.os],
        ["PEP_TARGET_ARCH", inputs.target.arch],
        ["PEP_HOST", codegen.target_triple(link.Target())],
        ["PEP_OPT_LEVEL", to_string(inputs.opt_level)],
        ["PEP_FEATURES", ",".join(features)],
        ["PEP_PACKAGE_NAME", name],
        ["PEP_PACKAGE_DIR", link.absolute(dir).to_string()],
        ["PEP_OUT_DIR", link.absolute(out).to_string()],
        ["PEP_CLANG", clang.is_value() ? clang.value().to_string() : ""],
        ["PEP_SYSROOT", inputs.sysroot.is_value() ? inputs.sysroot.value().to_string() : ""]
    ];
}

# What a script's run depends on, as a hash: its inputs, the files
# `sources` (its own source first), and the files and variables its
# `output` names with `rerun-if-changed` and `rerun-if-env-changed`.
_key(dir: Path, sources: Path[], environment: String[][], output: String): String {
    var text = StringBuilder();
    for (var variable in environment) {
        text.append($"{variable[0]}={variable[1]}\n");
    }
    for (var source in sources) {
        text.append($"{source} {_hash(source)}\n");
    }
    for (var line in _instructions(output)) {
        if (line.starts_with("rerun-if-changed=")) {
            var path = dir.join(Path(line.substr_bytes(17, line.size - 17)));
            text.append($"{path} {_hash(path)}\n");
        } else if (line.starts_with("rerun-if-env-changed=")) {
            var variable = line.substr_bytes(21, line.size - 21);
            var value = os.environment(variable);
            text.append($"env {variable} {value.is_value() ? "=" + value.value() : "unset"}\n");
        }
    }
    return digest.to_hex(digest.blake3(text.to_string()));
}

# The hash of the file, or of every file in the folder, `path`; `missing`
# when there is neither.
_hash(path: Path): String {
    if (path.is_directory()) {
        var hashed = toolchain.vendored_sha256(path);
        return hashed.is_ok() ? hashed.value() : "unreadable";
    }
    var bytes = File.read_bytes(path);
    return bytes.is_ok() ? digest.to_hex(digest.blake3(bytes.value())) : "missing";
}

# Whether every `pep:object=` file `output` names, relative to `dir`, exists.
_objects_exist(dir: Path, output: String): bool {
    for (var line in _instructions(output)) {
        if (line.starts_with("object=") and !dir.join(Path(line.substr_bytes(7, line.size - 7))).is_file()) {
            return false;
        }
    }
    return true;
}

# The `pep:` lines of `output`, without the prefix; it may print others.
_instructions(output: String): String[] {
    var lines = Array<String>();
    for (var line in output.split("\n")) {
        var trimmed = line.trim();
        if (trimmed.starts_with("pep:")) {
            lines.append(trimmed.substr_bytes(4, trimmed.size - 4));
        }
    }
    return lines;
}

# Adds what the output of the build script of `name`, whose pep.toml is
# `manifest`, says to link and define to `into`: a relative path is
# relative to the package's folder.
_apply(name: String, manifest: link.Manifest, output: String, into: ScriptOutput): Result<void, String> {
    var dir = manifest.dir();
    for (var line in _instructions(output)) {
        var split = line.split_once("=");
        var known = [
            "link", "link-path", "object", "build-option", "warning", "rerun-if-changed", "rerun-if-env-changed"
        ];
        if (!split.is_value() or !known.contains(split.value().0)) {
            return Result<void, String>.err(
                $"the build script of '{name}' printed 'pep:{line}'; expected 'pep:' followed by one of {", ".join(known)}, '=' and a value"
            );
        }
        var (instruction, value) = split.value();
        if (value.is_empty and instruction != "warning") {
            return Result<void, String>.err($"the build script of '{name}' printed 'pep:{line}', with no value");
        }
        if (instruction == "link") {
            if (!into.libraries.contains(value)) {
                into.libraries.append(value);
            }
        } else if (instruction == "link-path") {
            into.library_dirs.append(link.absolute(dir.join(Path(value))));
        } else if (instruction == "object") {
            var object = link.absolute(dir.join(Path(value)));
            if (!object.is_file()) {
                return Result<void, String>.err(
                    $"the build script of '{name}' printed 'pep:{line}', and {object} does not exist"
                );
            }
            into.objects.append(object);
        } else if (instruction == "build-option") {
            # `NAME` is `NAME=1`, as with `-D`.
            var defined = value.split_once("=");
            var option = manifest.build_option(defined.is_value() ? defined.value().0 : value);
            if (!link.is_build_option_name(option)) {
                return Result<void, String>.err(
                    $"the build script of '{name}' printed 'pep:{line}', and '{option}' is not a build option name; a name is a letter or '_' followed by letters, digits and '_'"
                );
            }
            into.build_options[option] = defined.is_value() ? defined.value().1 : "1";
        }
    }
    return Result<void, String>.ok();
}

# Compiles the C sources `native` lists, the `[native]` tables of the
# package `name` whose pep.toml is `manifest`, for the build's target, with
# clang in the package's folder, and adds the objects and what the tables
# link to `into`. `scripted`: the package has a build script, whose
# `PEP_OUT_DIR` is searched for headers. Each object is kept in the
# package's script folder, in `native/<target>/`, beside the key it was compiled
# under (`_native_key`), and compiled again only when its key changes.
_build_native(
    name: String, manifest: link.Manifest, native: link.Native, scripted: bool, inputs: ScriptInputs, into: ScriptOutput
): Result<void, String> {
    var dir = manifest.dir();
    for (var library in native.link) {
        if (!into.libraries.contains(library)) {
            into.libraries.append(library);
        }
    }
    var triple = codegen.target_triple(inputs.target);
    var flags = ["--target=" + triple, $"-O{inputs.opt_level}"];
    if (inputs.sysroot.is_value()) {
        flags.append("--sysroot=" + inputs.sysroot.value().to_string());
    }
    # So an object links into a shared library too; elsewhere it is the default.
    if (inputs.target.os == "linux" or inputs.target.os == "android") {
        flags.append("-fPIC");
    }
    var work = manifest.script_folder(inputs.build_dir);
    if (scripted) {
        flags.append("-I" + link.absolute(work.join(Path("out"))).to_string());
    }
    for (var folder in native.include) {
        flags.append("-I" + folder);
    }
    for (var define in native.defines) {
        flags.append("-D" + define);
    }
    for (var library in native.pkg_config) {
        var found = _pkg_config(name, library, inputs, into);
        if (found.is_err()) {
            return Result<void, String>.err(found.error());
        }
        flags.append_all(found.value());
    }
    flags.append_all(native.flags);
    var sources = _native_sources(manifest, native);
    if (sources.is_err()) {
        return Result<void, String>.err(sources.error());
    }
    if (sources.value().is_empty) {
        return Result<void, String>.ok();
    }
    var clang = find_link_driver();
    if (!clang.is_value()) {
        return Result<void, String>.err(
            $"cannot compile the '[native]' sources of '{name}': this toolchain has no clang (see PEPPER_LLVM_PREFIX)"
        );
    }
    # A folder per target, so builds for two do not replace each other's.
    var folder = link.absolute(work.join(Path("native")).join(Path(triple)));
    var created = Directory.create_all(folder);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {folder}: {created.error().message}");
    }
    var lock = _lock(folder.join(Path("lock")));
    if (lock.is_err()) {
        return Result<void, String>.err(lock.error());
    }
    var compiled = _compile_native(name, dir, clang.value(), flags, sources.value(), folder, into);
    lock.value().close();
    return compiled;
}

# `_build_native`, holding the lock on `folder`: compiles each of
# `sources`, relative to `dir`, with `clang` and `flags` into `folder`,
# unless its object's key still holds.
_compile_native(
    name: String, dir: Path, clang: Path, flags: String[], sources: String[], folder: Path, into: ScriptOutput
): Result<void, String> {
    var stems = HashMap<String, String>();
    # shortcut: compiles one source at a time; run clang side by side when a
    # package's many sources make its first build slow.
    for (var source in sources) {
        var stem = source.replace("/", "_").replace(":", "_");
        var other = stems.try_get(stem);
        if (other.is_value()) {
            return Result<void, String>.err(
                $"cannot compile both '{other.value()}' and '{source}' of the '[native]' table of '{name}': each makes {stem}.o; rename one"
            );
        }
        stems[stem] = source;
        var object = folder.join(Path(stem + ".o"));
        var depfile = folder.join(Path(stem + ".d"));
        var stamp = folder.join(Path(stem + ".key"));
        var arguments = flags.copy();
        arguments.append_all(
            ["-c", source, "-o", object.to_string(), "-MD", "-MF", depfile.to_string(), "-MT", "object"]
        );
        var command = clang.to_string() + "\n" + "\n".join(arguments);
        into.objects.append(object);
        var kept = File.read_to_string(stamp);
        var key = _native_key(dir, command, depfile);
        if (kept.is_ok() and key.is_value() and kept.value() == key.value() and object.is_file()) {
            continue;
        }
        var ran = process.Command(clang.to_string()).arguments(arguments).working_directory(dir).run();
        if (ran.is_err()) {
            return Result<void, String>.err($"cannot run {clang}: {ran.error().message}");
        }
        if (!ran.value().status.success()) {
            # Clang's own `error:` lines would keep the report from adding one.
            return Result<void, String>.err(
                $"error: cannot compile '{source}' of the '[native]' table of '{name}':\n{(ran.value().stderr + ran.value().stdout).trim()}"
            );
        }
        # Its warnings.
        if (!ran.value().stderr.trim().is_empty) {
            File.stderr().write_all(ran.value().stderr);
        }
        var written = File.write_text(stamp, _native_key(dir, command, depfile).value_or(""));
        if (written.is_err()) {
            return Result<void, String>.err($"cannot write {stamp}: {written.error().message}");
        }
    }
    return Result<void, String>.ok();
}

# The files `native`'s `sources` name, relative to its package's folder
# and with `/` separators, each once; an error at the pattern that names
# none.
_native_sources(manifest: link.Manifest, native: link.Native): Result<String[], String> {
    var prefix = link.absolute(manifest.dir()).to_string().replace("\\", "/") + "/";
    var sources = Array<String>();
    for (var k in 0..native.sources.count) {
        var found = 0;
        for (var path in io.glob(prefix + native.sources[k])) {
            var written = path.to_string().replace("\\", "/");
            if (path.is_file() and written.starts_with(prefix)) {
                found += 1;
                var source = written.substr_bytes(prefix.size, written.size - prefix.size);
                if (!sources.contains(source)) {
                    sources.append(source);
                }
            }
        }
        if (found == 0) {
            var problem = link.ManifestError(
                $"'{native.sources[k]}' names no file in the package", native.source_spans[k]
            );
            return Result<String[], String>.err(link.render_manifest_errors(manifest.path, manifest.text, [problem]));
        }
    }
    return Result<String[], String>.ok(sources);
}

# What an object depends on, as a hash: `command`, which compiles it, and
# every file its depfile names (the source, and each header it includes,
# relative to `dir`); none when there is no depfile.
_native_key(dir: Path, command: String, depfile: Path): String? {
    var listed = File.read_to_string(depfile);
    if (listed.is_err()) {
        return Optional<String>.Empty;
    }
    var text = StringBuilder();
    text.append(command + "\n");
    for (var file in _depfile_paths(listed.value())) {
        var path = dir.join(Path(file));
        text.append($"{path} {_hash(path)}\n");
    }
    return Optional<String>.Value(digest.to_hex(digest.blake3(text.to_string())));
}

# The files a depfile clang wrote with `-MD -MT object` names: the words
# after `object:`, where `\` before a line break continues the line, `\`
# before a space or `#` keeps it, and `$$` is `$`.
_depfile_paths(text: String): String[] {
    var start = text.find(":");
    var from = start < 0 ? 0 as ulong : start as ulong + 1;
    var words = text
        .substr_bytes(from, text.size - from)
        .replace("\\\r\n", " ")
        .replace("\\\n", " ")
        .replace("\\ ", "\0")
        .replace("\\#", "#")
        .replace("$$", "$")
        .replace("\r", " ")
        .replace("\n", " ")
        .replace("\t", " ");
    var paths = Array<String>();
    for (var word in words.split(" ")) {
        if (!word.is_empty) {
            paths.append(word.replace("\0", " "));
        }
    }
    return paths;
}

# The flags pkg-config gives to compile with `library`, which the
# `[native]` table of `name` names; what it gives to link it is added to
# `into`.
_pkg_config(name: String, library: String, inputs: ScriptInputs, into: ScriptOutput): Result<String[], String> {
    var cflags = _run_pkg_config(name, library, "--cflags", inputs);
    if (cflags.is_err()) {
        return cflags;
    }
    var libs = _run_pkg_config(name, library, "--libs", inputs);
    if (libs.is_err()) {
        return libs;
    }
    for (var flag in libs.value()) {
        if (flag.starts_with("-L")) {
            into.library_dirs.append(Path(flag.substr_bytes(2, flag.size - 2)));
        } else if (flag.starts_with("-l") or flag == "-pthread") {
            var named = flag == "-pthread" ? "pthread" : flag.substr_bytes(2, flag.size - 2);
            if (!into.libraries.contains(named)) {
                into.libraries.append(named);
            }
        } else if (flag.ends_with(".a") or flag.ends_with(".lib")) {
            into.objects.append(Path(flag));
        } else {
            File.stderr().write_all(
                $"warning: {name}: pkg-config gives '{flag}' to link {library}, which the build cannot pass on: ignored\n"
            );
        }
    }
    return cflags;
}

# What `pkg-config <query> <library>` prints, split into flags: the
# pkg-config `PKG_CONFIG` names, else the one on the PATH, which a build
# for another system points at the target's system root's `.pc` folders,
# unless `PKG_CONFIG_LIBDIR` is set.
# shortcut: splits at spaces, so a path holding an escaped space breaks;
# parse pkg-config's quoting when a library needs it.
_run_pkg_config(name: String, library: String, query: String, inputs: ScriptInputs): Result<String[], String> {
    var program = os.environment("PKG_CONFIG").value_or("pkg-config");
    var command = process.Command(program).arguments([query, library]);
    var triple = codegen.target_triple(inputs.target);
    if (triple != codegen.target_triple(link.Target()) and !os.environment("PKG_CONFIG_LIBDIR").is_value()) {
        if (!inputs.sysroot.is_value()) {
            return Result<String[], String>.err(
                $"cannot ask pkg-config for '{library}', which the '[native]' table of '{name}' names, for {triple}: the build has no --sysroot, so pkg-config would describe this machine's libraries; set PKG_CONFIG_LIBDIR to the folders holding the target's .pc files"
            );
        }
        var root = inputs.sysroot.value().to_string();
        var folders = Array<String>();
        for (var folder in [
            "/usr/lib/pkgconfig",
            "/usr/share/pkgconfig",
            "/usr/local/lib/pkgconfig",
            $"/usr/lib/{inputs.target.arch}-linux-gnu/pkgconfig"
        ]) {
            folders.append(root + folder);
        }
        var separator = os.system_os() == os.OperatingSystem.Windows ? ";" : ":";
        command.environment("PKG_CONFIG_LIBDIR", separator.join(folders));
        if (!os.environment("PKG_CONFIG_SYSROOT_DIR").is_value()) {
            command.environment("PKG_CONFIG_SYSROOT_DIR", root);
        }
    }
    var ran = command.run();
    if (ran.is_err()) {
        return Result<String[], String>.err(
            $"cannot run {program} to find '{library}', which the '[native]' table of '{name}' names: {ran.error().message}; install pkg-config, or set PKG_CONFIG to the pkg-config to run"
        );
    }
    if (!ran.value().status.success()) {
        return Result<String[], String>.err(
            $"pkg-config cannot find '{library}', which the '[native]' table of '{name}' names: {ran.value().stderr.trim()}\ninstall it, or add the folder holding {library}.pc to PKG_CONFIG_PATH"
        );
    }
    var flags = Array<String>();
    for (var flag in ran.value().stdout.trim().split(" ")) {
        if (!flag.trim().is_empty) {
            flags.append(flag.trim());
        }
    }
    return Result<String[], String>.ok(flags);
}

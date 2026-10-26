## Build scripts: a package's `build.pep` (or the file `[build]`'s
## `script` names), which a build compiles for the host and runs before it
## loads the program, and the `pep:` instructions the script prints to say
## what to link and which build options to define. Each package's script
## runs in `<build>/<package>-<hash>/` (`Manifest.script_folder`), the
## modules it generates are in `out/` there, and its result is kept there,
## in `stamp`, until what it depends on changes.

import compiler.codegen;
import digest;
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
        if (!script.value().is_value()) {
            continue;
        }
        var name = manifest.name.is_empty ? manifest.dir().file_name().value_or("project") : manifest.name;
        # The project's own script is the user's code; a dependency's is not.
        bool own = packages.project.is_value()
            and manifest.dir().normalize().to_string() == packages.project.value().normalize().to_string();
        if (own and inputs.target.build_script_root.is_value()) {
            continue;
        }
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
    var lock_path = work.join(Path("lock"));
    var opened = io.OpenOptions().write(true).create(true).open(lock_path);
    if (opened.is_err()) {
        return Result<String, String>.err($"cannot open {lock_path}: {opened.error().message}");
    }
    var lock = opened.value();
    var held = lock.lock();
    if (held.is_err()) {
        return Result<String, String>.err($"cannot lock {lock_path}: {held.error().message}");
    }
    # Its own source, its package's pep.toml, and pep.lock, which holds its
    # build-dependencies' revisions.
    var sources = [script, manifest.path, packages.deps_root.value().join(Path(link.LOCK_FILE))];
    var environment = _environment(name, dir, out, packages.features_on(manifest), inputs);
    var ran = _run_locked(name, dir, sources, work, environment, packages.deps_root.value(), lost, inputs.refuse);
    lock.close();
    return ran;
}

# `_run`, holding the lock: `stamp` holds the key, then the output. The
# script is `sources[0]`, built for the host with the packages `deps_root`
# serves; `lost`, its `out` folder was gone, so it runs again.
_run_locked(
    name: String,
    dir: Path,
    sources: Path[],
    work: Path,
    environment: String[][],
    deps_root: Path,
    lost: bool,
    refuse: bool
): Result<String, String> {
    var script = sources[0];
    var stamp = work.join(Path("stamp"));
    var kept = File.read_to_string(stamp);
    if (kept.is_ok() and !lost) {
        var split = kept.value().split_once("\n");
        if (split.is_value()) {
            var (key, last) = split.value();
            # An object it made since deleted needs a run.
            if (key == _key(dir, sources, environment, last) and _objects_exist(dir, last)) {
                return Result<String, String>.ok(last);
            }
        }
    }
    var executable = work.join(Path("build-script" + toolchain.executable_suffix()));
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
        link.absolute(deps_root).to_string()
    ];
    if (refuse) {
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
    var written = File.write_text(stamp, _key(dir, sources, environment, printed) + "\n" + printed);
    if (written.is_err()) {
        return Result<String, String>.err($"cannot write {stamp}: {written.error().message}");
    }
    return Result<String, String>.ok(printed);
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

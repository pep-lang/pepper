# `pepper package install`: builds a package's program optimized and puts
# it in the Pepper home's `bin`, recording what it put there in
# `<home>/installed-tools.toml` for `--list`, `uninstall` and the next
# install of the same program.

import [Directory, File, Path] from io;
import process;
import toml;
import toolchain;

# What `install` put in the home's `bin`, recorded under the program's name.
export struct InstalledTool {
    # `github:owner/name`, or `path:` and the folder.
    var source: String = "";
    # The version its tag names, or empty.
    var version: String = "";
    # The commit, or empty for a folder.
    var commit: String = "";
    # The toolchain that built it.
    var toolchain_version: String = "";

    construct() {}

    # `1.2.0 (github:owner/name)`.
    describe(): String {
        return version.is_empty ? $"({source})" : $"{version} ({source})";
    }
}

# The file recording what `install` put in the home's `bin`.
_records_path(): Path {
    return toolchain.find_home().root.join("installed-tools.toml");
}

# What `install` put in the home's `bin`, by program name.
export read_installed(): Result<OrderedMap<String, InstalledTool>> {
    var path = _records_path();
    if (!path.is_file()) {
        return Result<OrderedMap<String, InstalledTool>>.Ok(OrderedMap<String, InstalledTool>());
    }
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<OrderedMap<String, InstalledTool>>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<OrderedMap<String, InstalledTool>>.Err(parsed.error().to_string());
    }
    var records = toml.from_toml<OrderedMap<String, InstalledTool>>(parsed.value());
    if (records.is_err()) {
        return Result<OrderedMap<String, InstalledTool>>.Err($"{path.to_string()}: {records.error().message}");
    }
    return Result<OrderedMap<String, InstalledTool>>.Ok(records.value());
}

_write_installed(records: OrderedMap<String, InstalledTool>): Result<void> {
    var path = _records_path();
    var written = File.write_text(path, toml.encode(records));
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
    }
    return Result<void>.ok();
}

# The program `pep-build`: the one beside this program, else the one on
# the PATH.
export pep_build(): String {
    var executable = process.executable_path();
    if (executable.is_ok() and executable.value().parent().is_value()) {
        var beside = executable.value().parent().value().join("pep-build" + toolchain.executable_suffix());
        if (beside.is_file()) {
            return beside.to_string();
        }
    }
    return "pep-build";
}

# The name of the program the package in `dir` builds: its `[build]`
# table's `output`, else its `[package]` `name`, without `.exe`.
_program_name(dir: Path): Result<String> {
    var manifest = dir.join("pep.toml");
    var text = File.read_to_string(manifest);
    if (text.is_err()) {
        return Result<String>.Err($"{dir.to_string()} has no pep.toml, so it is not a package to install");
    }
    var parsed = toml.parse(text.value(), path = manifest.to_string());
    if (parsed.is_err()) {
        return Result<String>.Err(parsed.error().to_string());
    }
    var name = "";
    for (var key in ["build.output", "package.name"]) {
        var value = parsed.value().lookup(key);
        if (name.is_empty and value.is_value() and value.value().as_string().is_value()) {
            name = Path(value.value().as_string().value()).file_name().value_or("");
        }
    }
    if (name.ends_with(".exe")) {
        name = name.substr(0, name.length - 4);
    }
    if (name.is_empty) {
        return Result<String>.Err($"{manifest.to_string()} names no program: give it '[build]' 'output'");
    }
    return Result<String>.Ok(name);
}

# Builds the package in `dir` with `-O` and `build_options`, and puts its
# program in the home's `bin`, recording it as `record`. A program there
# that `install` did not put there from the same source is replaced only
# when `force`. Returns what it did.
export install_program(dir: Path, record: InstalledTool, force: bool, build_options: Array<String>): Result<String> {
    var name = _program_name(dir)?;
    var bin = toolchain.find_home().bin;
    var target = bin.join(name + toolchain.executable_suffix());
    var records = read_installed()?;
    var previous = records.try_get(name);
    if (target.exists() and !force and (previous.is_empty() or previous.value().source != record.source)) {
        var whose = previous.is_value() ?
            $"was installed from {previous.value().source}" :
            "was not installed by 'pepper package install'";
        return Result<String>.Err($"{target.to_string()} exists and {whose}; give --force to replace it");
    }
    var output_dir = dir.join(".pep").join("install");
    var made = Directory.create_all(output_dir);
    if (made.is_err()) {
        return Result<String>.Err($"cannot create {output_dir.to_string()}: {made.error().message}");
    }
    var output = output_dir.join(name + toolchain.executable_suffix());
    var built = process
        .Command(pep_build())
        .arguments(["-O", "-o", output.to_string()])
        .arguments(build_options)
        .working_directory(dir)
        .run();
    if (built.is_err()) {
        return Result<String>.Err($"cannot run pep-build: {built.error().message}");
    }
    if (!built.value().status.success()) {
        return Result<String>.Err($"cannot build {name}:\n{built.value().stdout}{built.value().stderr}");
    }
    var contents = File.read_bytes(output);
    if (contents.is_err()) {
        return Result<String>.Err($"cannot read {output.to_string()}: {contents.error().message}");
    }
    var created = Directory.create_all(bin);
    if (created.is_err()) {
        return Result<String>.Err($"cannot create {bin.to_string()}: {created.error().message}");
    }
    toolchain.replace_executable(target, contents.value())?;
    records.insert(name, record);
    _write_installed(records)?;
    if (previous.is_value()) {
        return Result<String>.Ok(
            $"replaced {name} {previous.value().describe()} with {record.describe()} in {bin.to_string()}"
        );
    }
    return Result<String>.Ok($"installed {name} {record.describe()} in {bin.to_string()}");
}

# Removes the program `name` that `install` put in the home's `bin`, and
# its record. Returns what it did.
export uninstall_program(given: String): Result<String> {
    var name = given.ends_with(".exe") ? given.substr(0, given.length - 4) : given;
    var records = read_installed()?;
    var record = records.try_get(name);
    if (record.is_empty()) {
        return Result<String>.Err(
            $"'{name}' was not installed by 'pepper package install'; 'pepper package install --list' lists what was"
        );
    }
    var target = toolchain.find_home().bin.join(name + toolchain.executable_suffix());
    if (target.exists()) {
        toolchain.remove_executable(target)?;
    }
    records.remove(name);
    _write_installed(records)?;
    return Result<String>.Ok($"uninstalled {name} {record.value().describe()}");
}

# Where toolchains are installed, the Pepper home:
#
#     <home>/bin/pepper                 the entry point, which runs a toolchain's tools
#     <home>/bin/pep-install            installs and removes toolchains
#     <home>/toolchains/0.3.0/bin/      a toolchain's pep-build, pep-fmt, ...
#     <home>/toolchains/0.3.0/runtime/  and its runtime
#     <home>/default-toolchain          the default toolchain's version
#
# A program installed in a home's `bin`, or in one of its toolchains, uses
# that home. Any other uses
# `PEPPER_HOME`, else `%LOCALAPPDATA%\pepper` on Windows and `~/.pepper`
# elsewhere. Toolchains are also found in the folders `PEPPER_TOOLCHAIN_PATH`
# lists, each laid out as `<home>/toolchains` is.

import [Directory, File, Path] from io;
import os;
import process;
import "version";

## A Pepper home: the folder holding the installed toolchains.
export struct Home {
    const root: Path;
    ## Further folders holding toolchains, searched after `toolchains` in
    ## order, each laid out as it is: `<version>/bin/pep-build`. Toolchains
    ## are only found there; they are installed and removed in `toolchains`.
    var search = Array<Path>();

    construct(root: Path) {
        this.root = root;
    }

    ## The folder holding the entry point and `pep-install`.
    var bin: Path {
        get {
            return root.join("bin");
        }
    }

    ## The folder holding a folder for each installed toolchain.
    var toolchains: Path {
        get {
            return root.join("toolchains");
        }
    }

    ## Returns the folder of the toolchain `version` in `toolchains`, where
    ## it is installed and removed.
    toolchain(version: Version): Path {
        return toolchains.join(version.to_string());
    }

    ## Returns the folder the toolchain `version` is found in: the one in
    ## `toolchains` when that holds it, else the first in `search` that
    ## does, else the one in `toolchains`.
    installed_at(version: Version): Path {
        for (var folder in _folders()) {
            var candidate = folder.join(version.to_string());
            if (_holds_toolchain(candidate)) {
                return candidate;
            }
        }
        return toolchain(version);
    }

    ## Returns the folder holding the tools of the toolchain `version`, as
    ## `installed_at` finds it.
    toolchain_bin(version: Version): Path {
        return installed_at(version).join("bin");
    }

    ## Returns the installed toolchains, newest first and without repeats:
    ## each folder of `toolchains` and of the `search` folders named by a
    ## version that holds a `pep-build`.
    installed(): Array<Version> {
        var versions = Array<Version>();
        for (var folder in _folders()) {
            for (var version in _versions_in(folder)) {
                if (!versions.contains(version)) {
                    versions.append(version);
                }
            }
        }
        versions.sort((a, b) => b.compare(a));
        return versions;
    }

    # `toolchains`, then the `search` folders.
    _folders(): Array<Path> {
        var folders = Array<Path>();
        folders.append(toolchains);
        for (var folder in search) {
            folders.append(folder);
        }
        return folders;
    }

    # The versions naming a folder of `folder` that holds a toolchain.
    _versions_in(folder: Path): Array<Version> {
        var versions = Array<Version>();
        var opened = Directory.open(folder);
        if (opened.is_err()) {
            return versions;
        }
        var entries = opened.value().entries();
        if (entries.is_err()) {
            return versions;
        }
        for (var entry in entries.value()) {
            var version = parse_version(entry.name);
            if (version.is_value() and _holds_toolchain(entry.path)) {
                versions.append(version.value());
            }
        }
        return versions;
    }

    # Whether `folder` holds a toolchain: an executable `bin/pep-build`.
    _holds_toolchain(folder: Path): bool {
        return process.is_executable(folder.join("bin").join("pep-build" + executable_suffix()));
    }

    ## The file naming the default toolchain.
    var default_file: Path {
        get {
            return root.join("default-toolchain");
        }
    }

    ## Returns the default toolchain's version, if one is set.
    default_version(): Version? {
        var text = File.read_to_string(default_file);
        if (text.is_err()) {
            return Optional<Version>.Empty;
        }
        return parse_version(text.value().trim());
    }

    ## Makes `version` the default toolchain.
    set_default(version: Version): Result<void> {
        var written = File.write_text(default_file, version.to_string() + "\n");
        if (written.is_err()) {
            return Result<void>.Err($"cannot write {default_file.to_string()}: {written.error().message}");
        }
        return Result<void>.ok();
    }
}

## Returns the Pepper home: the one the running program is installed in
## (in its `bin`, or in a toolchain's), else `PEPPER_HOME` when it is set, else `%LOCALAPPDATA%\pepper` on
## Windows and `~/.pepper` elsewhere. Its `search` folders are those
## `PEPPER_TOOLCHAIN_PATH` lists.
export find_home(): Home {
    var installed = home_of_executable();
    if (installed.is_value()) {
        return installed.value();
    }
    # A toolchain's tool, `<home>/toolchains/<version>/bin/<tool>`.
    var executable = process.executable_path();
    if (executable.is_ok()) {
        var toolchains = executable.value().join("..").join("..").join("..").normalize();
        var root = toolchains.parent();
        if (toolchains.file_name().value_or("") == "toolchains" and root.is_value()) {
            var found = Home(root.value());
            found.search = toolchain_path();
            return found;
        }
    }
    var home = Home(_default_root());
    home.search = toolchain_path();
    return home;
}

_default_root(): Path {
    var variable = os.environment("PEPPER_HOME");
    if (variable.is_value() and !variable.value().is_empty) {
        return Path(variable.value());
    }
    if (is_windows()) {
        var local = os.environment("LOCALAPPDATA");
        if (local.is_value() and !local.value().is_empty) {
            return Path(local.value()).join("pepper");
        }
    }
    var home = os.home_directory();
    return (home.is_value() ? home.value() : Path(".")).join(".pepper");
}

## Returns the home the running program is installed in, when it runs from
## a home's `bin` folder: one beside a `toolchains` folder. Its `search`
## folders are those `PEPPER_TOOLCHAIN_PATH` lists.
export home_of_executable(): Home? {
    var executable = process.executable_path();
    if (executable.is_err()) {
        return Optional<Home>.Empty;
    }
    var bin = executable.value().parent();
    if (bin.is_empty()) {
        return Optional<Home>.Empty;
    }
    var root = bin.value().parent();
    if (root.is_empty() or !root.value().join("toolchains").is_directory()) {
        return Optional<Home>.Empty;
    }
    var home = Home(root.value());
    home.search = toolchain_path();
    return Optional<Home>.Value(home);
}

## Returns the folders `PEPPER_TOOLCHAIN_PATH` lists, separated as `PATH`
## separates them: by `;` on Windows and `:` elsewhere.
export toolchain_path(): Array<Path> {
    var folders = Array<Path>();
    var variable = os.environment("PEPPER_TOOLCHAIN_PATH");
    if (variable.is_empty()) {
        return folders;
    }
    for (var entry in variable.value().split(is_windows() ? ";" : ":")) {
        if (!entry.is_empty) {
            folders.append(Path(entry));
        }
    }
    return folders;
}

## Returns the name release archives give this machine (`linux-x64`,
## `macos-arm64`, `macos-x64` or `windows-x64`), or none when there are no
## releases for it.
export target_name(): String? {
    var system = os.system_os();
    var architecture = os.architecture() == "aarch64" ? "arm64" : os.architecture();
    if (system == os.OperatingSystem.Linux and architecture == "x64") {
        return Optional<String>.Value("linux-x64");
    }
    if (system == os.OperatingSystem.Mac and (architecture == "x64" or architecture == "arm64")) {
        return Optional<String>.Value("macos-" + architecture);
    }
    if (system == os.OperatingSystem.Windows and architecture == "x64") {
        return Optional<String>.Value("windows-x64");
    }
    return Optional<String>.Empty;
}

## Whether this is Windows.
export is_windows(): bool {
    return os.system_os() == os.OperatingSystem.Windows;
}

## Returns the suffix of an executable's file name: `.exe` on Windows.
export executable_suffix(): String {
    return is_windows() ? ".exe" : "";
}

## Puts `contents` at `path`, an executable: written beside it as
## `<path>.new`, then renamed into place, the file there first moved aside
## to `<path>.old`. Windows cannot remove or overwrite a running program's
## file but can rename it, so there the `.old` file of one that still runs
## stays, and the next call for `path` removes it.
##
## @param path the executable to write
## @param contents its bytes
## @returns nothing, or why it cannot be written or put in place
export replace_executable(path: Path, contents: u8[]): Result<void> {
    var old = Path(path.to_string() + ".old");
    if (old.exists()) {
        File.remove(old);
    }
    var fresh = Path(path.to_string() + ".new");
    var written = File.write_bytes(fresh, contents);
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {fresh.to_string()}: {written.error().message}");
    }
    fresh.set_executable(true);
    if (path.exists()) {
        var moved = File.rename(path, old);
        if (moved.is_err()) {
            File.remove(fresh);
            return Result<void>.Err($"cannot move {path.to_string()} aside: {moved.error().message}");
        }
    }
    var placed = File.rename(fresh, path);
    if (placed.is_err()) {
        return Result<void>.Err($"cannot replace {path.to_string()}: {placed.error().message}");
    }
    # Only Windows keeps it, while the old program still runs.
    File.remove(old);
    return Result<void>.ok();
}

## Removes the executable `path`. Where it cannot be removed because it
## runs (on Windows), it is moved aside to `<path>.old` instead, which the
## next `replace_executable` or `remove_executable` for `path` removes.
##
## @param path the executable to remove
## @returns nothing, or why it can be neither removed nor moved aside
export remove_executable(path: Path): Result<void> {
    var old = Path(path.to_string() + ".old");
    if (old.exists()) {
        File.remove(old);
    }
    if (File.remove(path).is_ok()) {
        return Result<void>.ok();
    }
    var moved = File.rename(path, old);
    if (moved.is_err()) {
        return Result<void>.Err($"cannot remove {path.to_string()}: {moved.error().message}");
    }
    return Result<void>.ok();
}

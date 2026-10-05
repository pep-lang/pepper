# Where toolchains are installed, the Pepper home:
#
#     <home>/bin/pepper                 the entry point, which runs a toolchain's tools
#     <home>/bin/pep-install            installs and removes toolchains
#     <home>/toolchains/0.3.0/bin/      a toolchain's pep-build, pep-fmt, ...
#     <home>/toolchains/0.3.0/runtime/  and its runtime
#     <home>/default-toolchain          the default toolchain's version
#
# A program installed in a home's `bin` uses that home. Any other uses
# `PEPPER_HOME`, else `%LOCALAPPDATA%\pepper` on Windows and `~/.pepper`
# elsewhere.

import [Directory, File, Path] from io;
import os;
import process;
import "version";

## A Pepper home: the folder holding the installed toolchains.
export struct Home {
    const root: Path;

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

    ## Returns the folder of the toolchain `version`.
    toolchain(version: Version): Path {
        return toolchains.join(version.to_string());
    }

    ## Returns the folder holding the tools of the toolchain `version`.
    toolchain_bin(version: Version): Path {
        return toolchain(version).join("bin");
    }

    ## Returns the installed toolchains, newest first: each folder of
    ## `toolchains` named by a version that holds a `pep-build`.
    installed(): Array<Version> {
        var versions = Array<Version>();
        var opened = Directory.open(toolchains);
        if (opened.is_err()) {
            return versions;
        }
        var entries = opened.value().entries();
        if (entries.is_err()) {
            return versions;
        }
        for (var entry in entries.value()) {
            var version = parse_version(entry.name);
            if (version.is_empty()) {
                continue;
            }
            if (process.is_executable(toolchain_bin(version.value()).join("pep-build" + executable_suffix()))) {
                versions.append(version.value());
            }
        }
        versions.sort((a, b) => b.compare(a));
        return versions;
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

## Returns the Pepper home: the one the running program is installed in,
## else `PEPPER_HOME` when it is set, else `%LOCALAPPDATA%\pepper` on
## Windows and `~/.pepper` elsewhere.
export find_home(): Home {
    var installed = home_of_executable();
    if (installed.is_value()) {
        return installed.value();
    }
    var variable = os.environment("PEPPER_HOME");
    if (variable.is_value() and !variable.value().is_empty) {
        return Home(Path(variable.value()));
    }
    if (is_windows()) {
        var local = os.environment("LOCALAPPDATA");
        if (local.is_value() and !local.value().is_empty) {
            return Home(Path(local.value()).join("pepper"));
        }
    }
    var home = os.home_directory();
    return Home((home.is_value() ? home.value() : Path(".")).join(".pepper"));
}

## Returns the home the running program is installed in, when it runs from
## a home's `bin` folder: one beside a `toolchains` folder.
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
    return Optional<Home>.Value(Home(root.value()));
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

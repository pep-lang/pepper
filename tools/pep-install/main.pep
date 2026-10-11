# pep-install: installs Pepper toolchains side by side and picks the
# default, run as `pepper install`, like rustup or nvm.
#
#     pepper install list               # installed toolchains, marking the default and the one in use here
#     pepper install list --available   # releases with an archive for this machine
#     pepper install add 0.3            # install the newest 0.3.x (or 0.3.0, or latest)
#     pepper install use 0.3.0          # make it the default
#     pepper install update             # install the newest release and make it the default
#     pepper install remove 0.2.1
#     pepper install which              # the toolchain this folder uses, and why
#
# Toolchains go in the Pepper home (`PEPPER_HOME`, else
# `%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere); see
# tools/toolchain for its layout and for how a folder's toolchain is
# chosen.
#
# Build it from the repository root, next to the compiler:
#
#     pep-build -I tools tools/pep-install/main.pep -o target/bin/pep-install

import cli;
import [Directory, File] from io;
import os;
import toolchain;
import "commands";
import "releases";

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.9.1";
}

main(args: String[]): int {
    var parser = cli.Parser(
        "pep-install", "Installs Pepper toolchains side by side and picks the default.", version = version()
    );
    var list = parser.command("list", "list the installed toolchains, marking the default and the one in use here");
    var available = list.flag("available", "a", "list the releases with an archive for this machine instead");
    var add = parser.command("add", "install a toolchain; the default stays as it is, unless there was none");
    var add_version = add.positional("version", "0.3.0, 0.3 for its newest patch, or latest");
    var use = parser.command("use", "make an installed toolchain the default");
    var use_version = use.positional("version", "0.3.0, or 0.3 for the newest installed 0.3.x");
    var update = parser.command("update", "install the newest release and make it the default");
    var remove = parser.command("remove", "remove an installed toolchain other than the default");
    var remove_version = remove.positional("version", "the installed toolchain, such as 0.2.1");
    var which = parser.command("which", "show the toolchain this folder uses, why, and its pep-build");
    if (!parser.parse(args)) {
        return 2;
    }
    var home = toolchain.find_home();
    var ran = Result<String>.ok(parser.help());
    if (list.is_selected) {
        ran = available.is_set ? _available(home) : Result<String>.ok(installed_list(home, _chosen(home)));
    } else if (add.is_selected) {
        ran = _add(home, add_version.value());
    } else if (use.is_selected) {
        ran = _with_spec(use_version.value(), (spec) => use_toolchain(home, spec));
    } else if (update.is_selected) {
        ran = _update(home);
    } else if (remove.is_selected) {
        ran = _with_spec(remove_version.value(), (spec) => remove_toolchain(home, spec));
    } else if (which.is_selected) {
        ran = which_toolchain(home, _chosen(home));
    }
    if (ran.is_err()) {
        File.stderr().write_all($"pep-install: error: {ran.error().message}\n");
        return 1;
    }
    File.stdout().write_all(ran.value());
    return 0;
}

# The toolchain this folder uses; none when that cannot be told, as when
# its pep.toml cannot be read.
_chosen(home: toolchain.Home): toolchain.Choice? {
    var directory = Directory.current();
    if (directory.is_err()) {
        return Optional<toolchain.Choice>.Empty;
    }
    var environment = os.environment("PEPPER_TOOLCHAIN");
    var chosen = toolchain.choose_toolchain(home, "", environment.value_or(""), directory.value());
    return chosen.is_ok() ? chosen.value() : Optional<toolchain.Choice>.Empty;
}

_with_spec(text: String, run: (toolchain.VersionSpec) => Result<String>): Result<String> {
    var spec = toolchain.parse_spec(text);
    if (spec.is_empty()) {
        return Result<String>.Err($"'{text}' is not a version such as 0.3.0, 0.3 or latest");
    }
    return run(spec.value());
}

# The releases for this machine.
_releases(): Result<Array<Release>> {
    var target = toolchain.target_name();
    if (target.is_empty()) {
        return Result<Array<Release>>.Err("there are no Pepper releases for this machine");
    }
    return fetch_releases(releases_url(), target.value());
}

_available(home: toolchain.Home): Result<String> {
    var releases = _releases()?;
    return Result<String>.ok(available_list(home, releases));
}

_add(home: toolchain.Home, text: String): Result<String> {
    var spec = toolchain.parse_spec(text);
    if (spec.is_empty()) {
        return Result<String>.Err($"'{text}' is not a version such as 0.3.0, 0.3 or latest");
    }
    var releases = _releases()?;
    return add_toolchain(home, releases, spec.value());
}

_update(home: toolchain.Home): Result<String> {
    var releases = _releases()?;
    return update_toolchain(home, releases);
}

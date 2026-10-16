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
#     pepper install setup              # set this machine up: install, default, PATH, prerequisites
#     pepper install uninstall          # remove the home and its PATH changes
#
# Toolchains go in the Pepper home (`PEPPER_HOME`, else
# `%LOCALAPPDATA%\pepper` on Windows and `~/.pepper` elsewhere); see
# tools/toolchain for its layout and for how a folder's toolchain is
# chosen. `--path <dir>` and `PEPPER_TOOLCHAIN_PATH` add folders that
# toolchains are found in, but never installed in or removed from.
#
# Build it from the repository root, next to the compiler:
#
#     pep-build tools/pep-install/main.pep -o target/bin/pep-install

import cli;
import [Directory, File, Path] from io;
import os;
import toolchain;
import "commands";
import "releases";
import "setup";

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.9.3";
}

main(args: String[]): int {
    var parser = cli.Parser(
        "pep-install", "Installs Pepper toolchains side by side and picks the default.", version = version()
    );
    var list = parser.command("list", "list the installed toolchains, marking the default and the one in use here");
    var available = list.flag("available", "a", "list the releases with an archive for this machine instead");
    var add = parser.command("add", "install a toolchain; the default stays as it is, unless there was none");
    var add_version = add.positional("version", "0.3.0, 0.3 for its newest patch, or latest");
    var add_force = add.flag("force", "f", "install it again even when it is installed, replacing it");
    var use = parser.command("use", "make an installed toolchain the default");
    var use_version = use.positional("version", "0.3.0, or 0.3 for the newest installed 0.3.x");
    var update = parser.command("update", "install the newest release and make it the default");
    var update_force = update.flag("force", "f", "install it again even when it is installed, replacing it");
    var remove = parser.command("remove", "remove an installed toolchain other than the default");
    var remove_version = remove.positional("version", "the installed toolchain, such as 0.2.1");
    var which = parser.command("which", "show the toolchain this folder uses, why, and its pep-build");
    var setup_command = parser.command(
        "setup",
        "set this machine up for Pepper: install a toolchain and make it the default, put pepper on the PATH, offer to install what linking needs, and build a program to check"
    );
    var setup_version = setup_command.positional(
        "version", "0.3.0, 0.3 for its newest patch, or latest", required = false, default_value = "latest"
    );
    var setup_archive = setup_command.option(
        "archive", "", "install this downloaded release archive instead, checked against FILE.sha256", "FILE"
    );
    var setup_yes = setup_command.flag("yes", "y", "install missing prerequisites without asking");
    var setup_no_path = setup_command.flag("no-modify-path", "", "leave the PATH and the shell startup files alone");
    var setup_no_prerequisites = setup_command.flag(
        "no-prerequisites", "", "neither check for nor install clang and the other prerequisites"
    );
    var uninstall_command = parser.command("uninstall", "remove the Pepper home and the PATH changes setup made");
    var path = parser.multiple<Path>(
        "path", "", "also find toolchains in DIR, laid out as the home's toolchains folder", "DIR", global = true
    );
    if (!parser.parse(args)) {
        return 2;
    }
    var home = toolchain.find_home();
    # --path's folders come before PEPPER_TOOLCHAIN_PATH's.
    var search = path.values();
    for (var folder in home.search) {
        search.append(folder);
    }
    home.search = search;
    var ran = Result<String>.ok(parser.help());
    if (list.is_selected) {
        ran = available.is_set ? _available(home) : Result<String>.ok(installed_list(home, _chosen(home)));
    } else if (add.is_selected) {
        ran = _add(home, add_version.value(), add_force.is_set);
    } else if (use.is_selected) {
        ran = _with_spec(use_version.value(), (spec) => use_toolchain(home, spec));
    } else if (update.is_selected) {
        ran = _update(home, update_force.is_set);
    } else if (remove.is_selected) {
        ran = _with_spec(remove_version.value(), (spec) => remove_toolchain(home, spec));
    } else if (which.is_selected) {
        ran = which_toolchain(home, _chosen(home));
    } else if (setup_command.is_selected) {
        var options = SetupOptions();
        if (setup_archive.is_set) {
            options.archive = Optional<Path>.Value(Path(setup_archive.value()));
        }
        options.assume_yes = setup_yes.is_set;
        options.modify_path = !setup_no_path.is_set;
        options.prerequisites = !setup_no_prerequisites.is_set;
        ran = _with_spec(setup_version.value(), (spec) => _setup(home, spec, options));
    } else if (uninstall_command.is_selected) {
        ran = uninstall(home);
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

_add(home: toolchain.Home, text: String, force: bool): Result<String> {
    var spec = toolchain.parse_spec(text);
    if (spec.is_empty()) {
        return Result<String>.Err($"'{text}' is not a version such as 0.3.0, 0.3 or latest");
    }
    var releases = _releases()?;
    return add_toolchain(home, releases, spec.value(), force);
}

_setup(home: toolchain.Home, spec: toolchain.VersionSpec, options: SetupOptions): Result<String> {
    options.spec = spec;
    setup(home, options)?;
    return Result<String>.ok("");
}

_update(home: toolchain.Home, force: bool): Result<String> {
    var releases = _releases()?;
    return update_toolchain(home, releases, force);
}

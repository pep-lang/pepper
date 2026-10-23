# What each `pepper install` command does to a Pepper home. Each returns
# the text to print, or an error saying what went wrong.

import archive;
import compress;
import digest;
import [Directory, File, Path] from io;
import io;
import process;
import toolchain;
import "releases";
import "zip";

# The installed toolchains, newest first, one a line, marking the default,
# `in_use`, the one this folder uses, and where those outside the home's
# `toolchains` are.
export installed_list(home: toolchain.Home, in_use: toolchain.Choice?): String {
    var installed = home.installed();
    if (installed.is_empty) {
        return "No toolchains are installed; install the newest with 'pepper install update'.\n";
    }
    var default_version = home.default_version();
    var text = "";
    for (var version in installed) {
        var notes = Array<String>();
        if (default_version.is_value() and default_version.value() == version) {
            notes.append("default");
        }
        # The default in use needs no second note.
        var used = in_use.is_value() and in_use.value().source != toolchain.Source.Default;
        if (used and in_use.value().version.is_value() and in_use.value().version.value() == version) {
            notes.append("in use here, " + in_use.value().reason());
        }
        var folder = home.installed_at(version);
        if (folder.to_string() != home.toolchain(version).to_string()) {
            notes.append("in " + folder.to_string());
        }
        text = text + version.to_string() + (notes.is_empty ? "" : " (" + ", ".join(notes) + ")") + "\n";
    }
    return text;
}

# The releases with an archive for this machine, newest first, one a line,
# marking those installed.
export available_list(home: toolchain.Home, releases: Array<Release>): String {
    if (releases.is_empty) {
        return "No releases have an archive for this machine.\n";
    }
    var installed = home.installed();
    var text = "";
    for (var release in releases) {
        text = text + release.version.to_string() + (installed.contains(release.version) ? " (installed)" : "") + "\n";
    }
    return text;
}

# Installs the newest of `releases` that `spec` names, unless it is
# installed and not `force`d; forced, it is installed again over the home's
# copy. The first toolchain installed becomes the default; otherwise the
# default stays as it is.
export add_toolchain(
    home: toolchain.Home, releases: Array<Release>, spec: toolchain.VersionSpec, force: bool = false
): Result<String> {
    var release = _newest_release(releases, spec)?;
    var version = release.version.to_string();
    if (!force and home.installed().contains(release.version)) {
        return Result<String>.ok(
            $"{version} is already installed; reinstall it with 'pepper install add --force {version}'\n"
        );
    }
    install_release(home, release)?;
    if (home.default_version().is_empty()) {
        home.set_default(release.version)?;
        return Result<String>.ok($"installed {version} and made it the default\n");
    }
    return Result<String>.ok($"installed {version}; make it the default with 'pepper install use {version}'\n");
}

# Installs the newest release, unless it is installed and not `force`d,
# and makes it the default. Older toolchains stay installed. The home's
# `pepper` and `pep-install` are then updated from that toolchain.
export update_toolchain(home: toolchain.Home, releases: Array<Release>, force: bool = false): Result<String> {
    var release = _newest_release(releases, toolchain.VersionSpec())?;
    var version = release.version.to_string();
    var installed = !force and home.installed().contains(release.version);
    if (!installed) {
        install_release(home, release)?;
    }
    var was_default = home.default_version().is_value() and home.default_version().value() == release.version;
    var text = $"{version}, the newest release, is installed and the default\n";
    if (!installed or !was_default) {
        home.set_default(release.version)?;
        text = (installed ? $"{version} is installed" : $"installed {version}") + " and made it the default\n";
    }
    var updated = update_entry_points(home, release.version)?;
    if (!updated.is_empty) {
        text = text + $"updated {" and ".join(updated)} in {home.bin.to_string()}\n";
    }
    return Result<String>.ok(text);
}

# Copies the entry point and pep-install from the toolchain `version` into
# the home's `bin` folder where they differ, and returns the names of those
# it copied. A toolchain from before side-by-side toolchains has no
# pep-install, and leaves both alone.
#
# A running program's file can be renamed but not overwritten or removed
# on Windows, and this one runs from that folder: each old file is moved
# aside to `<name>.old` before the new one takes its name, and an `.old`
# that cannot be removed yet is removed the next time.
export update_entry_points(home: toolchain.Home, version: toolchain.Version): Result<Array<String>> {
    var updated = Array<String>();
    var suffix = toolchain.executable_suffix();
    var source = home.toolchain_bin(version);
    if (!source.join("pep-install" + suffix).is_file()) {
        return Result<Array<String>>.ok(updated);
    }
    var created = Directory.create_all(home.bin);
    if (created.is_err()) {
        return Result<Array<String>>.Err($"cannot create {home.bin.to_string()}: {created.error().message}");
    }
    # The programs of the home's `bin` folder: the entry point and this.
    for (var name in ["pepper", "pep-install"]) {
        var from = source.join(name + suffix);
        var to = home.bin.join(name + suffix);
        var old = Path(to.to_string() + ".old");
        if (old.exists()) {
            File.remove(old);
        }
        var contents = File.read_bytes(from);
        if (contents.is_err()) {
            return Result<Array<String>>.Err($"cannot read {from.to_string()}: {contents.error().message}");
        }
        var current = File.read_bytes(to);
        if (current.is_ok() and current.value() == contents.value()) {
            continue;
        }
        toolchain.replace_executable(to, contents.value())?;
        updated.append(name);
    }
    return Result<Array<String>>.ok(updated);
}

# Makes the newest installed toolchain `spec` names the default.
export use_toolchain(home: toolchain.Home, spec: toolchain.VersionSpec): Result<String> {
    var version = toolchain.newest_match(home.installed(), spec);
    if (version.is_empty()) {
        return Result<String>.Err(
            $"no installed toolchain is {spec.to_string()}; install it with 'pepper install add {spec.to_string()}'"
        );
    }
    home.set_default(version.value())?;
    return Result<String>.ok($"{version.value().to_string()} is the default\n");
}

# Removes the installed toolchain `spec` names, which must be just one,
# and not the default.
export remove_toolchain(home: toolchain.Home, spec: toolchain.VersionSpec): Result<String> {
    var matching = Array<toolchain.Version>();
    for (var version in home.installed()) {
        if (spec.matches(version)) {
            matching.append(version);
        }
    }
    if (matching.is_empty) {
        return Result<String>.Err($"no installed toolchain is {spec.to_string()}");
    }
    if (matching.count > 1) {
        var names = Array<String>();
        for (var version in matching) {
            names.append(version.to_string());
        }
        return Result<String>.Err($"{spec.to_string()} names {", ".join(names)}; name one of them");
    }
    var version = matching[0];
    var folder = home.installed_at(version);
    if (folder.to_string() != home.toolchain(version).to_string()) {
        return Result<String>.Err(
            $"{version.to_string()} is in {folder.to_string()}, outside the Pepper home; pep-install removes only the toolchains it installs"
        );
    }
    var default_version = home.default_version();
    if (default_version.is_value() and default_version.value() == version) {
        return Result<String>.Err(
            $"{version.to_string()} is the default; make another the default with 'pepper install use <version>' first"
        );
    }
    var removed = Directory.remove_all(home.toolchain(version));
    if (removed.is_err()) {
        return Result<String>.Err($"cannot remove {home.toolchain(version).to_string()}: {removed.error().message}");
    }
    return Result<String>.ok($"removed {version.to_string()}\n");
}

# Which toolchain `choice` is, why, and where its compiler is; an error
# when no toolchain is chosen or the chosen one is not installed.
export which_toolchain(home: toolchain.Home, choice: toolchain.Choice?): Result<String> {
    if (choice.is_empty()) {
        return Result<String>.Err(
            "no toolchain is chosen here and there is no default; install one with 'pepper install update'"
        );
    }
    var chosen = choice.value();
    var spec = chosen.spec.to_string();
    if (chosen.version.is_empty()) {
        return Result<String>.Err(
            $"toolchain {spec} ({chosen.reason()}) is not installed; install it with 'pepper install add {spec}'"
        );
    }
    var version = chosen.version.value();
    var compiler = home.toolchain_bin(version).join("pep-build" + toolchain.executable_suffix());
    return Result<String>.ok($"{version.to_string()} ({chosen.reason()})\n{compiler.to_string()}\n");
}

# The newest of `releases` that `spec` names.
_newest_release(releases: Array<Release>, spec: toolchain.VersionSpec): Result<Release> {
    for (var release in releases) {
        if (spec.matches(release.version)) {
            return Result<Release>.ok(release);
        }
    }
    return Result<Release>.Err(
        $"no release is {spec.to_string()} with an archive for this machine; 'pepper install list --available' lists them"
    );
}

# Downloads and unpacks `release` into its folder of `home`. It is unpacked
# beside that folder first, so only a complete toolchain takes its place,
# and a toolchain already there is moved aside until it has.
export install_release(home: toolchain.Home, release: Release): Result<void> {
    var target = home.toolchain(release.version);
    var partial = Path(target.to_string() + ".partial");
    var download = Path(target.to_string() + ".download");
    _prepare(home, partial)?;
    var fetched = fetch_archive(release, download);
    if (fetched.is_err()) {
        File.remove(download);
        return fetched;
    }
    var unpacked = _unpack_toolchain(download, release.archive_name, partial);
    File.remove(download);
    if (unpacked.is_err()) {
        Directory.remove_all(partial);
        return unpacked;
    }
    return _put_in_place(partial, target);
}

# Installs the release archive `file`, which a `.sha256` beside it must
# match, into `home`, replacing any toolchain of its version there, and
# returns that version: the one its name gives (`pepper-0.3.0-linux-x64.tar.gz`),
# else, for a build named for no release (`pepper-dev-...`), the one its
# pep-build reports.
export install_archive(home: toolchain.Home, file: Path): Result<toolchain.Version> {
    var name = file.file_name().value_or("");
    var target = toolchain.target_name();
    if (target.is_empty()) {
        return Result<toolchain.Version>.Err("there are no Pepper releases for this machine");
    }
    var extension = target.value().starts_with("windows") ? ".zip" : ".tar.gz";
    var suffix = $"-{target.value()}{extension}";
    if (!name.starts_with("pepper-") or !name.ends_with(suffix)) {
        return Result<toolchain.Version>.Err(
            $"{file.to_string()} is not a release archive for this machine, pepper-<version>{suffix}"
        );
    }
    check_file(file)?;
    var partial = home.toolchains.join(name + ".partial");
    _prepare(home, partial)?;
    var unpacked = _unpack_toolchain(file, name, partial);
    if (unpacked.is_err()) {
        Directory.remove_all(partial);
        return Result<toolchain.Version>.Err(unpacked.error());
    }
    var named = name.substr_bytes(7, name.size - 7 - suffix.size);
    var version = _archive_version(named, partial);
    if (version.is_err()) {
        Directory.remove_all(partial);
        return version;
    }
    _put_in_place(partial, home.toolchain(version.value()))?;
    return version;
}

# The version of the toolchain unpacked in `folder` from an archive whose
# name gives `named` for it: that, else the one its pep-build reports.
_archive_version(named: String, folder: Path): Result<toolchain.Version> {
    var version = toolchain.parse_version(named);
    if (version.is_value()) {
        return Result<toolchain.Version>.ok(version.value());
    }
    var compiler = folder.join("bin").join("pep-build" + toolchain.executable_suffix());
    var ran = process.Command(compiler.to_string()).argument("--version").run();
    if (ran.is_err() or !ran.value().status.success()) {
        return Result<toolchain.Version>.Err($"cannot tell the version of the toolchain '{named}'");
    }
    var reported = ran.value().stdout.trim().replace("pep-build ", "");
    var reported_version = toolchain.parse_version(reported);
    if (reported_version.is_empty()) {
        return Result<toolchain.Version>.Err($"cannot tell the version of the toolchain '{named}' from '{reported}'");
    }
    return Result<toolchain.Version>.ok(reported_version.value());
}

# Checks `file` against the `.sha256` beside it, in `sha256sum`'s format.
export check_file(file: Path): Result<void> {
    var name = file.file_name().value_or("");
    var listed = File.read_to_string(Path(file.to_string() + ".sha256"));
    if (listed.is_err()) {
        return Result<void>.Err($"no {name}.sha256 beside {file.to_string()} to check it against");
    }
    var expected = listed.value().trim().split(" ")[0].lower();
    var opened = File.open(file);
    if (opened.is_err()) {
        return Result<void>.Err($"cannot read {file.to_string()}: {opened.error().message}");
    }
    var hasher = digest.Sha256();
    for (var chunk in opened.value().chunks(65536)) {
        if (chunk.is_err()) {
            return Result<void>.Err($"cannot read {file.to_string()}: {chunk.error().message}");
        }
        hasher.update(chunk.value());
    }
    var actual = digest.to_hex(hasher.finish());
    if (actual != expected) {
        return Result<void>.Err($"{name} does not match its .sha256: sha256 {actual}, expected {expected}");
    }
    return Result<void>.ok();
}

# Creates the home's `toolchains` folder, and removes what an earlier
# install left at `partial`.
_prepare(home: toolchain.Home, partial: Path): Result<void> {
    var created = Directory.create_all(home.toolchains);
    if (created.is_err()) {
        return Result<void>.Err($"cannot create {home.toolchains.to_string()}: {created.error().message}");
    }
    if (partial.exists()) {
        Directory.remove_all(partial);
    }
    return Result<void>.ok();
}

# Unpacks the toolchain archive `file`, named `name`, into `partial`.
_unpack_toolchain(file: Path, name: String, partial: Path): Result<void> {
    unpack(file, name.ends_with(".zip"), partial)?;
    var compiler = partial.join("bin").join("pep-build" + toolchain.executable_suffix());
    if (!compiler.is_file()) {
        return Result<void>.Err($"{name} holds no bin/pep-build");
    }
    return Result<void>.ok();
}

# Moves the unpacked toolchain `partial` to `target`, moving a toolchain
# already there aside until it has.
_put_in_place(partial: Path, target: Path): Result<void> {
    var old = Path(target.to_string() + ".old");
    if (old.exists()) {
        Directory.remove_all(old);
    }
    if (target.exists()) {
        # Fails on Windows while a program of it runs, leaving it as it is.
        var aside = File.rename(target, old);
        if (aside.is_err()) {
            Directory.remove_all(partial);
            return Result<void>.Err($"cannot move {target.to_string()} aside: {aside.error().message}");
        }
    }
    var moved = File.rename(partial, target);
    if (moved.is_err()) {
        Directory.remove_all(partial);
        if (old.exists()) {
            File.rename(old, target);
        }
        return Result<void>.Err($"cannot move {partial.to_string()} to {target.to_string()}: {moved.error().message}");
    }
    Directory.remove_all(old);
    return Result<void>.ok();
}

# Unpacks the release archive `file`, a `.zip` when `zipped` and a
# `.tar.gz` otherwise, holding one folder, into `target`, without that
# folder.
export unpack(file: Path, zipped: bool, target: Path): Result<void> {
    if (zipped) {
        var data = File.read_bytes(file);
        if (data.is_err()) {
            return Result<void>.Err($"cannot read {file.to_string()}: {data.error().message}");
        }
        return unzip(data.value(), target, 1);
    }
    var opened = File.open(file);
    if (opened.is_err()) {
        return Result<void>.Err($"cannot read {file.to_string()}: {opened.error().message}");
    }
    var tar = archive.TarReader(compress.DecompressReader(opened.value(), compress.Format.Gzip));
    var extracted = tar.extract(target, strip_components = 1);
    if (extracted.is_err()) {
        return Result<void>.Err($"cannot unpack {file.to_string()}: {extracted.error().message}");
    }
    return Result<void>.ok();
}

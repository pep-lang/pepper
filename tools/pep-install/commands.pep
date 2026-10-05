# What each `pepper install` command does to a Pepper home. Each returns
# the text to print, or an error saying what went wrong.

import archive;
import compress;
import [Directory, File, Path] from io;
import io;
import toolchain;
import "releases";
import "zip";

# The installed toolchains, newest first, one a line, marking the default
# and `in_use`, the one this folder uses.
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
        if (in_use.is_value() and in_use.value().version.is_value() and in_use.value().version.value() == version) {
            notes.append("in use here, " + in_use.value().reason());
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
# installed. The first toolchain installed becomes the default; otherwise
# the default stays as it is.
export add_toolchain(home: toolchain.Home, releases: Array<Release>, spec: toolchain.VersionSpec): Result<String> {
    var release = _newest_release(releases, spec)?;
    var version = release.version.to_string();
    if (home.installed().contains(release.version)) {
        return Result<String>.ok($"{version} is already installed\n");
    }
    install_release(home, release)?;
    if (home.default_version().is_empty()) {
        home.set_default(release.version)?;
        return Result<String>.ok($"installed {version} and made it the default\n");
    }
    return Result<String>.ok($"installed {version}; make it the default with 'pepper install use {version}'\n");
}

# Installs the newest release, unless it is installed, and makes it the
# default. Older toolchains stay installed.
export update_toolchain(home: toolchain.Home, releases: Array<Release>): Result<String> {
    var release = _newest_release(releases, toolchain.VersionSpec())?;
    var version = release.version.to_string();
    var installed = home.installed().contains(release.version);
    if (!installed) {
        install_release(home, release)?;
    }
    var was_default = home.default_version().is_value() and home.default_version().value() == release.version;
    if (installed and was_default) {
        return Result<String>.ok($"{version}, the newest release, is installed and the default\n");
    }
    home.set_default(release.version)?;
    return Result<String>.ok(
        (installed ? $"{version} is installed" : $"installed {version}") + " and made it the default\n"
    );
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
# beside that folder first, so only a complete toolchain takes its place.
export install_release(home: toolchain.Home, release: Release): Result<void> {
    var created = Directory.create_all(home.toolchains);
    if (created.is_err()) {
        return Result<void>.Err($"cannot create {home.toolchains.to_string()}: {created.error().message}");
    }
    var target = home.toolchain(release.version);
    var partial = Path(target.to_string() + ".partial");
    var download = Path(target.to_string() + ".download");
    var installed = _download_and_unpack(release, download, partial);
    File.remove(download);
    if (installed.is_err()) {
        Directory.remove_all(partial);
        return installed;
    }
    if (target.exists()) {
        Directory.remove_all(target);
    }
    var moved = File.rename(partial, target);
    if (moved.is_err()) {
        Directory.remove_all(partial);
        return Result<void>.Err($"cannot move {partial.to_string()} to {target.to_string()}: {moved.error().message}");
    }
    return Result<void>.ok();
}

_download_and_unpack(release: Release, download: Path, partial: Path): Result<void> {
    if (partial.exists()) {
        Directory.remove_all(partial);
    }
    fetch_archive(release, download)?;
    unpack(download, release.archive_name.ends_with(".zip"), partial)?;
    var compiler = partial.join("bin").join("pep-build" + toolchain.executable_suffix());
    if (!compiler.is_file()) {
        return Result<void>.Err($"{release.archive_name} holds no bin/pep-build");
    }
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

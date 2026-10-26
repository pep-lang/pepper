# pep.lock: the exact revision of every Git dependency in the graph, so a
# fresh checkout builds the same code. `pepper package` writes it; the
# compiler reads it to fetch what `.pep/deps` lacks.
#
#     version = 1
#
#     [[package]]
#     name = "geometry"
#     source = "github:someone/geometry"
#     version = "1.2.3"
#     commit = "0123456789abcdef0123456789abcdef01234567"
#     sha256 = "<the checksum of its files: see archive.pep>"
#
# A member of a repository's workspace has the member after `#` in its
# source (`github:someone/shapes#geo`), and its own commit and checkout.
# A package only `[dev-dependencies]` lead to has `dev = true`, one only
# `[build-dependencies]` lead to (a build script's, built for the machine
# building, never linked into the program) has `build = true`, and one only
# `[target.'<condition>'.dependencies]` lead to has `target`, the
# condition under which a build needs it (`target = "OS(Windows)"`): the
# lock lists every platform's packages, and a build fetches only its
# target's. A package pep.toml's `[overrides]` replaces has `override`, the
# replacement's source: a fork (`override = "github:you/geometry"`), whose
# commit `commit` is, or a folder (`override = "path:../geometry"`), which
# has no commit. When the graph holds several majors of one package, each
# is an entry of its own with `major` (`major = "1"`, or `"0.4"` for a
# 0.x version), checked out in `<name>@v<major>`.

import [File, Path] from io;
import toml;

# One locked package.
export struct Locked {
    # The package's own name (its `[package]` `name`).
    var name: String = "";
    # `github:owner/name`, or `github:owner/name#member`.
    var source: String = "";
    # The version its tag names, when one was chosen by version.
    var version: String = "";
    # The full commit.
    var commit: String = "";
    # The checksum of the package's files (`files_sha256`), which a fetch
    # without git verifies; empty in a lock written before it was kept.
    var sha256: String = "";
    # Whether only the project's dev-dependencies lead to it.
    var dev: bool = false;
    # Whether only build-dependencies lead to it.
    var build: bool = false;
    # The `[Target(...)]` condition under which a build needs it, or empty
    # when every build does.
    var target: String = "";
    # What `[overrides]` replaces it with: a fork's source, or `path:` and
    # the folder as pep.toml writes it. Empty when it is not overridden.
    var replaced_by: String = "";
    # The major version this copy serves, when the graph holds several
    # majors of the package (`range_major`); empty when it holds one.
    var major: String = "";

    construct() {}

    construct(name: String, source: String, version: String, commit: String) {
        this.name = name;
        this.source = source;
        this.version = version;
        this.commit = commit;
    }

    # The package's key in the graph: its source, with `@v` and the major
    # for one of several majors (`github:other/numbers@v1`), which
    # `split_source` turns into its folder.
    key(): String {
        return major.is_empty ? source : $"{source}@v{major}";
    }

    # For messages: `geometry 1.2.3`, else its short commit; only the name
    # when a folder overrides it.
    describe(): String {
        if (version.is_empty and commit.is_empty) {
            return name;
        }
        return name + " " + (version.is_empty ? commit.substr(0, 12) : version);
    }
}

# The lock file next to the pep.toml in `project`.
export lock_path(project: Path): Path {
    return project.join("pep.lock");
}

# Reads `path`; no packages when it does not exist.
export read_lock(path: Path): Result<Array<Locked>> {
    var packages = Array<Locked>();
    if (!path.is_file()) {
        return Result<Array<Locked>>.Ok(packages);
    }
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<Array<Locked>>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<Array<Locked>>.Err(parsed.error().to_string());
    }
    var entries = parsed.value().try_get("package");
    if (entries.is_empty()) {
        return Result<Array<Locked>>.Ok(packages);
    }
    var items = entries.value().as_array();
    if (items.is_empty()) {
        return Result<Array<Locked>>.Err($"{path.to_string()}: 'package' must be an array of tables");
    }
    for (var item in items.value()) {
        var locked = Locked();
        locked.name = _text(item, "name");
        locked.source = _text(item, "source");
        locked.version = _text(item, "version");
        locked.commit = _text(item, "commit");
        locked.sha256 = _text(item, "sha256");
        var dev = item.try_get("dev");
        locked.dev = dev.is_value() and dev.value().as_bool().value_or(false);
        var build = item.try_get("build");
        locked.build = build.is_value() and build.value().as_bool().value_or(false);
        locked.target = _text(item, "target");
        locked.replaced_by = _text(item, "override");
        locked.major = _text(item, "major");
        if (locked.source.is_empty or (locked.commit.is_empty and !locked.replaced_by.starts_with("path:"))) {
            return Result<Array<Locked>>.Err($"{path.to_string()}: every package needs a 'source' and a 'commit'");
        }
        packages.append(locked);
    }
    return Result<Array<Locked>>.Ok(packages);
}

_text(table: toml.TomlValue, key: String): String {
    var value = table.try_get(key);
    if (value.is_empty() or value.value().as_string().is_empty()) {
        return "";
    }
    return value.value().as_string().value();
}

# The lock file's text for `packages`, sorted by source so it changes only
# where the graph does.
export lock_text(packages: Array<Locked>): String {
    var sorted = packages.clone();
    sorted.sort((a, b) => a.key().compare(b.key()));
    var text = "# Written by `pepper package`: the exact revision of every dependency.\n";
    text += "# Commit it with pep.toml; do not edit it by hand.\n";
    text += "version = 1\n";
    for (var locked in sorted) {
        text += "\n[[package]]\n";
        text += "name = " + toml.TomlValue.String(locked.name).to_string() + "\n";
        text += "source = " + toml.TomlValue.String(locked.source).to_string() + "\n";
        if (!locked.version.is_empty) {
            text += "version = " + toml.TomlValue.String(locked.version).to_string() + "\n";
        }
        if (!locked.major.is_empty) {
            text += "major = " + toml.TomlValue.String(locked.major).to_string() + "\n";
        }
        if (!locked.replaced_by.is_empty) {
            text += "override = " + toml.TomlValue.String(locked.replaced_by).to_string() + "\n";
        }
        if (!locked.commit.is_empty) {
            text += "commit = " + toml.TomlValue.String(locked.commit).to_string() + "\n";
        }
        if (!locked.sha256.is_empty) {
            text += "sha256 = " + toml.TomlValue.String(locked.sha256).to_string() + "\n";
        }
        if (locked.dev) {
            text += "dev = true\n";
        }
        if (locked.build) {
            text += "build = true\n";
        }
        if (!locked.target.is_empty) {
            text += "target = " + toml.TomlValue.String(locked.target).to_string() + "\n";
        }
    }
    return text;
}

# Writes `packages` to `path`, or removes it when there are none.
export write_lock(path: Path, packages: Array<Locked>): Result<void> {
    if (packages.is_empty) {
        if (path.is_file()) {
            File.remove(path);
        }
        return Result<void>.ok();
    }
    var written = File.write_text(path, lock_text(packages));
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
    }
    return Result<void>.ok();
}

# The versioned documentation site: each version of the book lives in its
# own folder (`<site>/0.1.0/`, `<site>/dev/`), and nothing ever removes
# one, so the docs of every release stay available. `versions.json` lists
# the folders, newest first, for the version picker on every page;
# `index.html` sends visitors to the newest release.

import [Directory, File, Path] from io;
import json;
import [JsonValue] from json;

# The version name of unreleased docs built from `main`.
export const DEV = "dev";

# A semantic version: `MAJOR.MINOR.PATCH` with an optional `-prerelease`.
export struct Version {
    var major: ulong;
    var minor: ulong;
    var patch: ulong;
    # Empty for a release.
    var prerelease: String = "";

    construct() {}

    to_string(): String {
        var core = $"{major}.{minor}.{patch}";
        return prerelease.is_empty ? core : $"{core}-{prerelease}";
    }

    # Negative, zero or positive as this version sorts before, with or
    # after `other`. A prerelease sorts before its release.
    compare(other: Version): int {
        if (major != other.major) {
            return major < other.major ? -1 : 1;
        }
        if (minor != other.minor) {
            return minor < other.minor ? -1 : 1;
        }
        if (patch != other.patch) {
            return patch < other.patch ? -1 : 1;
        }
        if (prerelease.is_empty or other.prerelease.is_empty) {
            return prerelease.is_empty == other.prerelease.is_empty ? 0 : (prerelease.is_empty ? 1 : -1);
        }
        return prerelease.compare(other.prerelease);
    }
}

# Parses `1.2.3` or `1.2.3-beta.1` (a leading `v` is accepted, as in a
# `v1.2.3` tag).
export parse_version(written: String): Result<Version> {
    var text = written.starts_with("v") ? written.substr_bytes(1, written.size - 1) : written;
    var bad = Result<Version>.Err($"'{text}' is not a semantic version (MAJOR.MINOR.PATCH[-PRERELEASE])");
    var version = Version();
    var core = text;
    var dash = text.find("-");
    if (dash >= 0) {
        var at = dash as ulong;
        version.prerelease = text.substr_bytes(at + 1, text.size - at - 1);
        if (version.prerelease.is_empty) {
            return bad;
        }
        core = text.substr_bytes(0, at);
    }
    var parts = core.split(".");
    if (parts.count != 3) {
        return bad;
    }
    var numbers = Array<ulong>();
    for (var part in parts) {
        var number = _number(part);
        if (number.is_empty()) {
            return bad;
        }
        numbers.append(number.value());
    }
    version.major = numbers[0];
    version.minor = numbers[1];
    version.patch = numbers[2];
    return Result<Version>.ok(version);
}

# The number `text` spells in decimal digits, without a leading zero.
_number(text: String): ulong? {
    if (text.is_empty or (text.size > 1 and text.starts_with("0"))) {
        return Optional<ulong>.Empty;
    }
    ulong value = 0;
    for (var i in 0..text.size) {
        var b = text.byte_at(i);
        if (b < '0' or b > '9') {
            return Optional<ulong>.Empty;
        }
        value = value * 10 + (b - '0') as ulong;
    }
    return Optional<ulong>.Value(value);
}

# The version folders in `site`, newest release first, `dev` last.
export versions_in(site: Path): String[] {
    var releases = Array<Version>();
    bool dev = false;
    for (var name in _folders(site)) {
        if (!site.join(name).join("index.html").is_file()) {
            continue;
        }
        if (name == DEV) {
            dev = true;
            continue;
        }
        var version = parse_version(name);
        if (version.is_ok() and version.value().to_string() == name) {
            releases.append(version.value());
        }
    }
    releases.sort((a, b) => b.compare(a));
    var out = Array<String>();
    for (var release in releases) {
        out.append(release.to_string());
    }
    if (dev) {
        out.append(DEV);
    }
    return out;
}

# The names of the entries of `dir`; none when it cannot be read.
_folders(dir: Path): String[] {
    var names = Array<String>();
    var listing = Directory.open(dir);
    if (listing.is_err()) {
        return names;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return names;
    }
    for (var entry in entries.value()) {
        names.append(entry.name);
    }
    return names;
}

# The version `index.html` opens: the newest release that is not a
# prerelease, else the newest release, else `dev`.
export default_version(versions: String[]): String? {
    for (var v in versions) {
        var version = parse_version(v);
        if (version.is_ok() and version.value().prerelease.is_empty) {
            return Optional<String>.Value(v);
        }
    }
    for (var v in versions) {
        if (v != DEV) {
            return Optional<String>.Value(v);
        }
    }
    if (versions.is_empty) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(versions[0]);
}

# Writes `text` to the file `name` in `site`.
_write(site: Path, name: String, text: String): Result<void> {
    var path = site.join(name);
    var written = File.write_text(path, text);
    if (written.is_err()) {
        return Result<void>.Err($"cannot write {path.to_string()}: {written.error().message}");
    }
    return Result<void>.ok();
}

# Rewrites `versions.json` and `index.html` in `site` from its folders;
# `index.html` is titled `title`.
export write_index(site: Path, title: String): Result<void> {
    var versions = versions_in(site);
    var latest = default_version(versions);
    var list = JsonValue.array();
    for (var v in versions) {
        list.append(JsonValue.String(v));
    }
    var index = JsonValue.object();
    index["latest"] = latest.is_value() ? JsonValue.String(latest.value()) : JsonValue.Null;
    index["versions"] = list;
    _write(site, "versions.json", index.to_pretty_string() + "\n")?;
    var target = latest.is_value() ? latest.value() : DEV;
    _write(
        site,
        "index.html",
        $"<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>{title}</title>\n<meta http-equiv=\"refresh\" content=\"0; url={target}/\">\n<link rel=\"canonical\" href=\"{target}/\">\n</head>\n<body><p><a href=\"{target}/\">{title} {target}</a></p></body>\n</html>\n"
    )?;
    # GitHub Pages would otherwise run Jekyll, which drops mdBook's
    # underscore-prefixed files.
    return _write(site, ".nojekyll", "");
}

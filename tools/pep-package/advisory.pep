# Security advisories, which `audit` checks pep.lock against. The database
# is a Git repository of TOML files, one advisory each, anywhere in it
# (pep-lang/advisories, or the repository `PEPPER_ADVISORY_DB` names):
#
#     id = "PEP-2026-0001"
#     package = "github:someone/geometry"
#     title = "area() overflows on large polygons"
#     severity = "high"
#     url = "https://example.com/PEP-2026-0001"
#     patched = [">=1.1.0"]
#     unaffected = ["<1.0.0"]
#
# A version is affected unless a `patched` or `unaffected` range holds it,
# as in RustSec. The database is cloned into the Pepper home's cache,
# `cache/advisories`, and fetched again once the copy is an hour old.

import digest;
import [File, glob, Path] from io;
import os;
import [Version, VersionRange] from semver;
import toml;
import toolchain;
import "git";
import "lock";
import "manifest";
import "resolve";
import "tree";

# The database `audit` reads when `PEPPER_ADVISORY_DB` names none.
export const ADVISORY_DATABASE = "https://github.com/pep-lang/advisories.git";

# How old, in seconds, the cached database may be before `audit` fetches it
# again.
const REFRESH_SECONDS = 3600;

# The database's address: `PEPPER_ADVISORY_DB`, else `ADVISORY_DATABASE`.
export advisory_database(): String {
    var variable = os.environment("PEPPER_ADVISORY_DB");
    return variable.is_value() and !variable.value().is_empty ? variable.value() : ADVISORY_DATABASE;
}

# One advisory of the database.
export struct Advisory {
    var id: String = "";
    # The source of the package it is about, `github:owner/name`.
    var package: String = "";
    var title: String = "";
    var severity: String = "";
    var url: String = "";
    # `patched` as written, for the report.
    var patched: Array<String> = __null;
    # The ranges of `patched` and `unaffected`.
    var _safe: Array<VersionRange> = __null;

    construct() {
        patched = Array<String>();
        _safe = Array<VersionRange>();
    }

    # Whether `version` of the package is affected.
    affects(version: Version): bool {
        for (var range in _safe) {
            if (range.matches(version)) {
                return false;
            }
        }
        return true;
    }
}

# The folder of the copy of the database at `url` in the cache: cloned
# when missing, and fetched again when it is older than `REFRESH_SECONDS`,
# unless `offline`.
export fetch_database(url: String, offline: bool): Result<Path> {
    var base = toolchain
        .find_home().root
        .join("cache")
        .join("advisories")
        .join(digest.to_hex(digest.sha256(url)).substr(0, 16));
    var dir = base.to_string();
    var stamp = Path(dir + ".fetched");
    var lock = lock_file(Path(dir + ".lock"));
    if (lock.is_err()) {
        return Result<Path>.Err(lock.error().message);
    }
    if (checked_out(base).is_value()) {
        var fetched = stamp.metadata();
        var now = os.SystemTime.now().unix_seconds();
        if (offline or (fetched.is_ok() and now - fetched.value().modified / 1000000000 < REFRESH_SECONDS)) {
            return Result<Path>.Ok(base);
        }
        var pulled = git(["fetch", "--quiet", url, "HEAD"], dir);
        if (pulled.is_ok()) {
            pulled = git(["reset", "--quiet", "--hard", "FETCH_HEAD"], dir);
        }
        if (pulled.is_err()) {
            return Result<Path>.Err($"cannot fetch the advisory database {url}: {pulled.error().message}");
        }
    } else {
        if (offline) {
            return Result<Path>.Err(
                $"--offline, and the cache has no copy of the advisory database {url}; run 'pepper package audit' without --offline (or PEPPER_OFFLINE) once"
            );
        }
        # Cloned beside it and renamed, so an interrupted clone leaves none.
        var partial = Path(dir + ".partial");
        if (partial.exists()) {
            var cleared = remove_tree(partial);
            if (cleared.is_err()) {
                return Result<Path>.Err($"cannot remove {partial.to_string()}: {cleared.error().message}");
            }
        }
        if (base.exists()) {
            var cleared = remove_tree(base);
            if (cleared.is_err()) {
                return Result<Path>.Err($"cannot remove {dir}: {cleared.error().message}");
            }
        }
        var cloned = git(["clone", "--quiet", url, partial.to_string()]);
        if (cloned.is_err()) {
            return Result<Path>.Err($"cannot fetch the advisory database {url}: {cloned.error().message}");
        }
        var moved = File.rename(partial, base);
        if (moved.is_err()) {
            return Result<Path>.Err($"cannot move {partial.to_string()} to {dir}: {moved.error().message}");
        }
    }
    var written = File.write_text(stamp, "");
    if (written.is_err()) {
        return Result<Path>.Err($"cannot write {stamp.to_string()}: {written.error().message}");
    }
    return Result<Path>.Ok(base);
}

# Each of `advisories` with each package of `locked` it affects: one
# locked at a version, from the advisory's source.
export affected(advisories: Array<Advisory>, locked: Array<Locked>): Array<(Advisory, Locked)> {
    var hits = Array<(Advisory, Locked)>();
    for (var advisory in advisories) {
        for (var package in locked) {
            var version = tag_version(package.version);
            if (package.source == advisory.package and version.is_value() and advisory.affects(version.value())) {
                hits.append((advisory, package));
            }
        }
    }
    return hits;
}

# Every advisory in the database in `dir`, ordered by file.
export read_advisories(dir: Path): Result<Array<Advisory>> {
    var files = glob(dir.to_string().replace("\\", "/") + "/**/*.toml");
    files.sort((a, b) => a.to_string().compare(b.to_string()));
    var advisories = Array<Advisory>();
    for (var file in files) {
        var read = read_advisory(file);
        if (read.is_err()) {
            return Result<Array<Advisory>>.Err(read.error().message);
        }
        advisories.append(read.value());
    }
    return Result<Array<Advisory>>.Ok(advisories);
}

# The advisory in `path`; its problems are clang-style errors at their keys.
export read_advisory(path: Path): Result<Advisory> {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<Advisory>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<Advisory>.Err(parsed.error().to_string());
    }
    var root = parsed.value();
    # For `at_key`, which renders a problem at its key.
    var file = Manifest();
    file.path = path;
    file.text = text.value();
    var advisory = Advisory();
    for (var (key, value) in root.as_table().value()) {
        var given = value.as_string();
        if (key == "patched" or key == "unaffected") {
            var items = value.as_array();
            if (items.is_empty()) {
                return Result<Advisory>.Err(file.at_key("error", key, $"'{key}' must be an array of versions"));
            }
            for (var item in items.value()) {
                if (item.as_string().is_empty()) {
                    return Result<Advisory>.Err(file.at_key("error", key, $"'{key}' must be an array of versions"));
                }
                var written = item.as_string().value();
                var range = version_range(written);
                if (range.is_err()) {
                    return Result<Advisory>.Err(
                        file.at_key(
                            "error",
                            written,
                            $"'{key}' lists '{written}', which is not a version or range: {range.error().message}",
                            key
                        )
                    );
                }
                advisory._safe.append(range.value());
                if (key == "patched") {
                    advisory.patched.append(written);
                }
            }
        } else if (given.is_empty()) {
            return Result<Advisory>.Err(file.at_key("error", key, $"'{key}' must be a string"));
        } else if (key == "id") {
            advisory.id = given.value();
        } else if (key == "package") {
            advisory.package = given.value();
        } else if (key == "title") {
            advisory.title = given.value();
        } else if (key == "severity") {
            advisory.severity = given.value();
        } else if (key == "url") {
            advisory.url = given.value();
        }
    }
    for (var (key, value) in [("id", advisory.id), ("package", advisory.package)]) {
        if (value.is_empty) {
            return Result<Advisory>.Err(file.at_key("error", key, $"an advisory needs '{key}'"));
        }
    }
    return Result<Advisory>.Ok(advisory);
}

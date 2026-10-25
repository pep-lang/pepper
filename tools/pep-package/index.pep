# The package index, which `search`, `info` and `add <name>` read: a Git
# repository (pep-lang/index, or the one `PEPPER_PACKAGE_INDEX` names)
# with one TOML file per package in its `packages` folder, named for the
# package (`packages/semver.toml`):
#
#     source = "github:pep-lang/pepper-semver"
#     description = "Semantic Versioning 2.0.0: parse, compare and order versions"
#     keywords = ["semver", "version"]
#
# The file's name is the name `add` takes and imports the package by, so
# the pull request that adds the file claims the name. Versions are not
# listed: they are the source's tags, read when `info` asks, so the index
# changes only when a package is added or described anew. Like the
# advisory database, it is cloned into the Pepper home's cache,
# `cache/index`, and fetched again once the copy is an hour old.

import [File, glob, Path] from io;
import os;
import syntax;
import toml;
import "git";
import "manifest";

# The index `search`, `info` and `add` read when `PEPPER_PACKAGE_INDEX`
# names none.
export const PACKAGE_INDEX = "https://github.com/pep-lang/index.git";

# The index's address: `PEPPER_PACKAGE_INDEX`, else `PACKAGE_INDEX`.
export package_index(): String {
    var variable = os.environment("PEPPER_PACKAGE_INDEX");
    return variable.is_value() and !variable.value().is_empty ? variable.value() : PACKAGE_INDEX;
}

# One package the index lists.
export struct Listing {
    # The file's name: the name `add` takes and imports it by.
    var name: String = "";
    # Where it comes from, `github:owner/name`.
    var source: String = "";
    var description: String = "";
    var keywords: Array<String> = __null;

    construct() {
        keywords = Array<String>();
    }

    # Whether each of `words` is in its name, description or keywords,
    # ignoring case.
    matches(words: Array<String>): bool {
        var text = $"{name} {description} {" ".join(keywords)}".lower();
        for (var word in words) {
            if (!text.contains(word.lower())) {
                return false;
            }
        }
        return true;
    }
}

# Every package in the index, by name, from the cache's copy, which is
# fetched first unless `offline`.
export fetch_index(offline: bool): Result<Array<Listing>> {
    var dir = fetch_data_repository(package_index(), "index", "package index", offline);
    if (dir.is_err()) {
        return Result<Array<Listing>>.Err(dir.error().message);
    }
    return read_index(dir.value());
}

# The package the index lists as `name`.
export look_up_name(name: String, offline: bool): Result<Listing> {
    var index = fetch_index(offline);
    if (index.is_err()) {
        return Result<Listing>.Err(index.error().message);
    }
    for (var listing in index.value()) {
        if (listing.name == name) {
            return Result<Listing>.Ok(listing);
        }
    }
    return Result<Listing>.Err(
        $"the package index {package_index()} has no package '{name}'; look with 'pepper package search', or give its repository as owner/name"
    );
}

# Every package in the index in `dir`, by name.
export read_index(dir: Path): Result<Array<Listing>> {
    var files = glob(dir.to_string().replace("\\", "/") + "/packages/*.toml");
    files.sort((a, b) => a.to_string().compare(b.to_string()));
    var listings = Array<Listing>();
    for (var file in files) {
        var read = read_listing(file);
        if (read.is_err()) {
            return Result<Array<Listing>>.Err(read.error().message);
        }
        listings.append(read.value());
    }
    return Result<Array<Listing>>.Ok(listings);
}

# The package `path` lists; its problems are clang-style errors at their
# keys.
export read_listing(path: Path): Result<Listing> {
    var listing = Listing();
    listing.name = path.file_stem().value_or("");
    if (!syntax.is_identifier(listing.name)) {
        return Result<Listing>.Err(
            $"{path.to_string()}:1:1: error: the file's name, '{listing.name}', is the package's, and 'import' cannot use it"
        );
    }
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<Listing>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    var parsed = toml.parse(text.value(), path = path.to_string());
    if (parsed.is_err()) {
        return Result<Listing>.Err(parsed.error().to_string());
    }
    # For `at_key`, which renders a problem at its key.
    var file = Manifest();
    file.path = path;
    file.text = text.value();
    for (var (key, value) in parsed.value().as_table().value()) {
        if (key == "keywords") {
            var items = value.as_array();
            if (items.is_empty()) {
                return Result<Listing>.Err(file.at_key("error", key, "'keywords' must be an array of strings"));
            }
            for (var item in items.value()) {
                if (item.as_string().is_empty()) {
                    return Result<Listing>.Err(file.at_key("error", key, "'keywords' must be an array of strings"));
                }
                listing.keywords.append(item.as_string().value());
            }
        } else if (key == "source" or key == "description") {
            var given = value.as_string();
            if (given.is_empty()) {
                return Result<Listing>.Err(file.at_key("error", key, $"'{key}' must be a string"));
            }
            if (key == "description") {
                listing.description = given.value();
                continue;
            }
            # `host:owner/name`; a workspace member (`#member`) or a
            # range is not one.
            var split = given.value().split_once(":");
            var parts = split.is_value() ? split.value().1.split("/") : Array<String>();
            if (split.is_empty()
                or !is_host(split.value().0)
                or parts.count < 2
                or parts.contains("")
                or given.value().contains("#")
                or given.value().contains("@")) {
                return Result<Listing>.Err(
                    file.at_key(
                        "error", key, $"'source' must be a repository as host:owner/name, not '{given.value()}'"
                    )
                );
            }
            listing.source = given.value();
        }
    }
    if (listing.source.is_empty) {
        return Result<Listing>.Err($"{path.to_string()}:1:1: error: a package needs 'source'");
    }
    return Result<Listing>.Ok(listing);
}

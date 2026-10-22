# pep.toml as the package manager reads it: the package's name, the oldest
# toolchain it builds with, and its dependencies and dev-dependencies. The
# compiler checks the rest of the file when it builds.

import [File, Path] from io;
import toml;

# Whether `key` names a Git host a dependency can come from.
export is_host(key: String): bool {
    return key == "github" or key == "gitlab" or key == "codeberg";
}

# One entry of `[dependencies]` or `[dev-dependencies]`.
export struct Requirement {
    # The key: the name source code imports.
    var name: String = "";
    # `github`, `gitlab`, `codeberg`, or `path`.
    var host: String = "";
    # `owner/name`, or for a `path` dependency its folder as written.
    var repository: String = "";
    # `version`, `branch`, `tag`, `commit`, or `default` when none is given.
    var kind: String = "default";
    # The range, branch, tag or commit.
    var value: String = "";
    # Whether it is in `[dev-dependencies]`: only the project's own tests
    # and examples use it, so a project depending on this one ignores it.
    var dev: bool = false;

    construct() {}

    # Where the package comes from, which identifies it in the whole
    # graph: `github:owner/name` (or `path:<folder>`).
    source(): String {
        return host + ":" + repository;
    }

    is_path(): bool {
        return host == "path";
    }

    # The table it is in: `dependencies` or `dev-dependencies`.
    table(): String {
        return dev ? "dev-dependencies" : "dependencies";
    }

    # The revision as pep.toml writes it, for messages: `1.2`, `branch main`.
    describe(): String {
        if (kind == "version") {
            return value;
        }
        if (kind == "default") {
            return "the default branch";
        }
        return kind + " " + value;
    }
}

# A pep.toml.
export struct Manifest {
    # The file.
    var path: Path = Path("pep.toml");
    # Its text, for edits.
    var text: String = "";
    # `[package]`'s `name`.
    var name: String = "";
    # `[package]`'s `minimum_toolchain`: the oldest toolchain release that
    # builds it, or empty.
    var minimum_toolchain: String = "";
    var requirements: Array<Requirement> = __null;
    # `[fetch]`'s `hosts`: where `add` looks a repository up, in order.
    var hosts: Array<String> = __null;

    construct() {
        requirements = Array<Requirement>();
        hosts = ["github", "gitlab", "codeberg"];
    }

    # The folder holding it: the package's root.
    dir(): Path {
        var parent = path.parent();
        return parent.is_value() ? parent.value() : Path(".");
    }

    # The dependency or dev-dependency named `name`.
    requirement(name: String): Optional<Requirement> {
        for (var requirement in requirements) {
            if (requirement.name == name) {
                return Optional<Requirement>.Value(requirement);
            }
        }
        return Optional<Requirement>.Empty;
    }
}

# Reads the pep.toml at `path`.
export read_manifest(path: Path): Result<Manifest> {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<Manifest>.Err($"cannot read {path.to_string()}: {text.error().message}");
    }
    return parse_manifest(path, text.value());
}

# Reads `text`, the pep.toml at `path`.
export parse_manifest(path: Path, text: String): Result<Manifest> {
    var parsed = toml.parse(text, path = path.to_string());
    if (parsed.is_err()) {
        return Result<Manifest>.Err(parsed.error().to_string());
    }
    var root = parsed.value();
    var manifest = Manifest();
    manifest.path = path;
    manifest.text = text;
    var name = root.lookup("package.name");
    if (name.is_value() and name.value().as_string().is_value()) {
        manifest.name = name.value().as_string().value();
    }
    var minimum = root.lookup("package.minimum_toolchain");
    if (minimum.is_value() and minimum.value().as_string().is_value()) {
        manifest.minimum_toolchain = minimum.value().as_string().value();
    }
    var hosts = root.lookup("fetch.hosts");
    if (hosts.is_value()) {
        var items = hosts.value().as_array();
        if (items.is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[fetch]' 'hosts' must be an array of hosts");
        }
        manifest.hosts = Array<String>();
        for (var item in items.value()) {
            var host = item.as_string();
            if (host.is_empty() or !is_host(host.value())) {
                return Result<Manifest>.Err(
                    $"{path.to_string()}: '[fetch]' 'hosts' lists 'github', 'gitlab' or 'codeberg'"
                );
            }
            manifest.hosts.append(host.value());
        }
    }
    for (var name in ["dependencies", "dev-dependencies"]) {
        var dependencies = root.try_get(name);
        if (dependencies.is_empty()) {
            continue;
        }
        var table = dependencies.value().as_table();
        if (table.is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[{name}]' must be a table");
        }
        for (var (key, value) in table.value()) {
            var requirement = _requirement(path, key, value);
            if (requirement.is_err()) {
                return Result<Manifest>.Err(requirement.error().message);
            }
            requirement.value().dev = name == "dev-dependencies";
            manifest.requirements.append(requirement.value());
        }
    }
    return Result<Manifest>.Ok(manifest);
}

# What a pep.toml may use that an older toolchain rejects as unknown: each
# table or key, as `toml`'s `lookup` names it, and the first release that
# reads it. A package using one sets `minimum_toolchain` to that release
# or later, which `publish` checks.
export newer_manifest_features(): Array<(String, String)> {
    return [("dev-dependencies", "0.11.0")];
}

# One `[dependencies]` or `[dev-dependencies]` entry.
_requirement(path: Path, key: String, value: toml.TomlValue): Result<Requirement> {
    var fields = value.as_table();
    if (fields.is_empty()) {
        return Result<Requirement>.Err($"{path.to_string()}: dependency '{key}' must be a table");
    }
    var requirement = Requirement();
    requirement.name = key;
    for (var (field, field_value) in fields.value()) {
        var text = field_value.as_string();
        if (text.is_empty()) {
            return Result<Requirement>.Err($"{path.to_string()}: '{field}' of dependency '{key}' must be a string");
        }
        if (is_host(field) or field == "path") {
            requirement.host = field;
            requirement.repository = text.value();
        } else if (field == "version" or field == "branch" or field == "tag" or field == "commit") {
            requirement.kind = field;
            requirement.value = text.value();
        }
    }
    if (requirement.host.is_empty) {
        return Result<Requirement>.Err(
            $"{path.to_string()}: dependency '{key}' needs a source: 'github', 'gitlab' or 'codeberg' (\"owner/name\"), or 'path'"
        );
    }
    return Result<Requirement>.Ok(requirement);
}

# The nearest pep.toml in `dir` or a folder above it.
export find_manifest(dir: Path): Optional<Path> {
    var current = dir.canonicalize();
    if (current.is_err()) {
        return Optional<Path>.Empty;
    }
    var at = current.value();
    while (true) {
        var candidate = at.join("pep.toml");
        if (candidate.is_file()) {
            return Optional<Path>.Value(candidate);
        }
        var parent = at.parent();
        if (parent.is_empty() or parent.value().to_string() == at.to_string()) {
            return Optional<Path>.Empty;
        }
        at = parent.value();
    }
    return Optional<Path>.Empty;
}

# pep.toml as the package manager reads it: the package's name and its
# dependencies. The compiler checks the rest of the file when it builds.

import [File, Path] from io;
import toml;

# Whether `key` names a Git host a dependency can come from.
export is_host(key: String): bool {
    return key == "github" or key == "gitlab" or key == "codeberg";
}

# One entry of `[dependencies]`.
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

    construct() {}

    # Where the package comes from, which identifies it in the whole
    # graph: `github:owner/name` (or `path:<folder>`).
    source(): String {
        return host + ":" + repository;
    }

    is_path(): bool {
        return host == "path";
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
    var requirements: Array<Requirement> = __null;

    construct() {
        requirements = Array<Requirement>();
    }

    # The folder holding it: the package's root.
    dir(): Path {
        var parent = path.parent();
        return parent.is_value() ? parent.value() : Path(".");
    }

    # The dependency named `name`.
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
    var dependencies = root.try_get("dependencies");
    if (dependencies.is_empty()) {
        return Result<Manifest>.Ok(manifest);
    }
    var table = dependencies.value().as_table();
    if (table.is_empty()) {
        return Result<Manifest>.Err($"{path.to_string()}: '[dependencies]' must be a table");
    }
    for (var (key, value) in table.value()) {
        var requirement = _requirement(path, key, value);
        if (requirement.is_err()) {
            return Result<Manifest>.Err(requirement.error().message);
        }
        manifest.requirements.append(requirement.value());
    }
    return Result<Manifest>.Ok(manifest);
}

# One `[dependencies]` entry.
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

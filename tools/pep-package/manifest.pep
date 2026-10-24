# pep.toml as the package manager reads it: the package's name, the oldest
# toolchain it builds with, and its dependencies, dev-dependencies and
# `[target.'<condition>'.dependencies]`. The compiler checks the rest of the
# file, the conditions and `[features]` included, when it builds. Features
# do not change what is locked: an optional dependency is resolved and
# locked like any other. `[overrides]` replaces a package wherever the
# graph reaches it; only the project's own apply.

import [Span] from compiler.ast;
import [Diagnostic, Location, render_all, SourceText] from compiler.diagnostic;
import [File, glob, Path] from io;
import toml;

# Whether `key` names a Git host a dependency can come from.
export is_host(key: String): bool {
    return key == "github" or key == "gitlab" or key == "codeberg";
}

# One entry of `[dependencies]`, `[dev-dependencies]` or
# `[target.'<condition>'.dependencies]`.
export struct Requirement {
    # The key: the name source code imports.
    var name: String = "";
    # `github`, `gitlab`, `codeberg`, or `path`.
    var host: String = "";
    # `owner/name`, or for a `path` dependency its folder as written.
    var repository: String = "";
    # `package`: the member of the repository's workspace it is, by its
    # `[package]` name; empty for the repository's root package.
    var member: String = "";
    # `version`, `branch`, `tag`, `commit`, or `default` when none is given.
    var kind: String = "default";
    # The range, branch, tag or commit.
    var value: String = "";
    # Whether it is in `[dev-dependencies]`: only the project's own tests
    # and examples use it, so a project depending on this one ignores it.
    var dev: bool = false;
    # The `[target.'<condition>']` it is under (`OS(Windows)`): the
    # platforms that use it. Empty for every platform.
    var target: String = "";
    # Which of `optional`, `features`, `default-features`, `workspace` and
    # `package` it sets, as pep.toml writes them, which only newer
    # toolchains read.
    var feature_keys: Array<String> = __null;
    # `workspace = true`: its source and revision are those of the entry of
    # the same name in the workspace's `[workspace.dependencies]`.
    var inherits: bool = false;
    # `optional = true`: only a feature turns it on.
    var optional: bool = false;
    # The features its `features` turns on, for `tree`.
    var features: Array<String> = __null;

    construct() {
        feature_keys = Array<String>();
        features = Array<String>();
    }

    # Where the package comes from, which identifies it in the whole
    # graph: `github:owner/name`, `github:owner/name#member` for a member
    # of the repository's workspace (or `path:<folder>`).
    source(): String {
        return host + ":" + repository + (member.is_empty ? "" : "#" + member);
    }

    is_path(): bool {
        return host == "path";
    }

    # Its key in pep.toml: `[dependencies, name]`, `[dev-dependencies,
    # name]` or `[target, condition, dependencies, name]`.
    key(): Array<String> {
        if (!target.is_empty) {
            return ["target", target, "dependencies", name];
        }
        return [dev ? "dev-dependencies" : "dependencies", name];
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
    # `[fetch]`'s `vendor`: the folder `vendor` copied every locked package
    # into, which builds read; empty when the project is not vendored.
    var vendor: String = "";
    # Whether it has `[workspace]`: it is a workspace's root.
    var is_workspace: bool = false;
    # `[workspace]`'s `members` as written: folders, or globs of them.
    var members: Array<String> = __null;
    # `[workspace.dependencies]`, which `workspace = true` entries take
    # their source and revision from.
    var workspace_requirements: Array<Requirement> = __null;
    # A workspace root's members other than itself, as `read_project`
    # reads them.
    var member_manifests: Array<Manifest> = __null;
    # `[overrides]`: each the package that replaces another, its `name` the
    # source it replaces (`github:owner/name`).
    var overrides: Array<Requirement> = __null;

    construct() {
        requirements = Array<Requirement>();
        hosts = ["github", "gitlab", "codeberg"];
        members = Array<String>();
        workspace_requirements = Array<Requirement>();
        member_manifests = Array<Manifest>();
        overrides = Array<Requirement>();
    }

    # What `[overrides]` replaces `source` with, if anything.
    override_of(source: String): Optional<Requirement> {
        for (var replacement in overrides) {
            if (replacement.name == source) {
                return Optional<Requirement>.Value(replacement);
            }
        }
        return Optional<Requirement>.Empty;
    }

    # `message` as a clang-style `severity` diagnostic at the first place
    # `value` is written quoted: the key of the override of a source, or a
    # dependency's `path` or `package`; else at the line starting with the
    # key `key` (a dependency's, which inherits that value), when given.
    at_value(severity: String, value: String, message: String, key: String = ""): String {
        var start = text.find("\"" + value + "\"");
        if (start < 0) {
            start = text.find("'" + value + "'");
        }
        var length = value.length + 2;
        if (start < 0 and !key.is_empty) {
            var line = text.find("\n" + key + " ");
            start = line < 0 ? line : line + 1;
            length = key.length;
        }
        var at = start < 0 ? Span(0, 0) : Span(start as ulong, start as ulong + length);
        var diagnostic = severity == "error" ? Diagnostic.error(message) : Diagnostic.warning(message);
        return render_all([diagnostic.at(Location(0, at))], [SourceText(path.to_string(), text)]);
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
    if (root.try_get("workspace").is_value()) {
        manifest.is_workspace = true;
        var members = root.lookup("workspace.members");
        if (members.is_value() and members.value().as_array().is_value()) {
            for (var member in members.value().as_array().value()) {
                if (member.as_string().is_value()) {
                    manifest.members.append(member.as_string().value());
                }
            }
        }
        var shared = root.lookup("workspace.dependencies");
        if (shared.is_value() and shared.value().as_table().is_value()) {
            for (var (key, value) in shared.value().as_table().value()) {
                var requirement = _requirement(path, key, value);
                if (requirement.is_err()) {
                    return Result<Manifest>.Err(requirement.error().message);
                }
                manifest.workspace_requirements.append(requirement.value());
            }
        }
    }
    var vendor = root.lookup("fetch.vendor");
    if (vendor.is_value()) {
        if (vendor.value().as_string().is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[fetch]' 'vendor' must be a folder's name");
        }
        manifest.vendor = vendor.value().as_string().value();
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
    var overrides = root.try_get("overrides");
    if (overrides.is_value()) {
        var table = overrides.value().as_table();
        if (table.is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[overrides]' must be a table");
        }
        for (var (source, value) in table.value()) {
            var replacement = _requirement(path, source, value);
            if (replacement.is_err()) {
                return Result<Manifest>.Err(replacement.error().message);
            }
            manifest.overrides.append(replacement.value());
        }
    }
    var targets = root.try_get("target");
    if (targets.is_value()) {
        var conditions = targets.value().as_table();
        if (conditions.is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[target]' must be a table");
        }
        for (var (condition, tables) in conditions.value()) {
            var dependencies = tables.try_get("dependencies");
            if (dependencies.is_empty()) {
                continue;
            }
            var table = dependencies.value().as_table();
            if (table.is_empty()) {
                return Result<Manifest>.Err(
                    $"{path.to_string()}: '[target.'{condition}'.dependencies]' must be a table"
                );
            }
            for (var (key, value) in table.value()) {
                var requirement = _requirement(path, key, value);
                if (requirement.is_err()) {
                    return Result<Manifest>.Err(requirement.error().message);
                }
                requirement.value().target = condition;
                manifest.requirements.append(requirement.value());
            }
        }
    }
    return Result<Manifest>.Ok(manifest);
}

# What a pep.toml may use that an older toolchain rejects as unknown: each
# table or key, as `toml`'s `lookup` names it, and the first release that
# reads it. A package using one sets `minimum_toolchain` to that release
# or later, which `publish` checks.
export newer_manifest_features(): Array<(String, String)> {
    return [
        ("dev-dependencies", "0.11.0"),
        ("target", "0.11.0"),
        ("features", "0.11.0"),
        ("overrides", "0.11.0"),
        ("workspace", "0.11.0"),
        ("fetch.vendor", "0.11.0")
    ];
}

# The first release that reads a dependency's `optional`, `features`,
# `default-features`, `workspace` and `package`, which
# `newer_manifest_features` cannot name: they sit under each dependency's
# own key.
export const DEPENDENCY_FEATURES_RELEASE = "0.11.0";

# One `[dependencies]` or `[dev-dependencies]` entry.
_requirement(path: Path, key: String, value: toml.TomlValue): Result<Requirement> {
    var fields = value.as_table();
    if (fields.is_empty()) {
        return Result<Requirement>.Err($"{path.to_string()}: dependency '{key}' must be a table");
    }
    var requirement = Requirement();
    requirement.name = key;
    for (var (field, field_value) in fields.value()) {
        # The compiler checks these.
        if (field == "optional" or field == "features" or field == "default-features" or field == "workspace") {
            requirement.feature_keys.append(field);
            requirement.inherits = requirement.inherits or field == "workspace";
            if (field == "optional") {
                requirement.optional = field_value.as_bool().value_or(false);
            } else if (field == "features" and field_value.as_array().is_value()) {
                for (var item in field_value.as_array().value()) {
                    requirement.features.append(item.as_string().value_or(""));
                }
            }
            continue;
        }
        var text = field_value.as_string();
        if (text.is_empty()) {
            return Result<Requirement>.Err($"{path.to_string()}: '{field}' of dependency '{key}' must be a string");
        }
        if (is_host(field) or field == "path") {
            requirement.host = field;
            requirement.repository = text.value();
        } else if (field == "package") {
            requirement.member = text.value();
            requirement.feature_keys.append(field);
        } else if (field == "version" or field == "branch" or field == "tag" or field == "commit") {
            requirement.kind = field;
            requirement.value = text.value();
        }
    }
    if (requirement.host.is_empty and !requirement.inherits) {
        return Result<Requirement>.Err(
            $"{path.to_string()}: dependency '{key}' needs a source: 'github', 'gitlab' or 'codeberg' (\"owner/name\"), or 'path'"
        );
    }
    return Result<Requirement>.Ok(requirement);
}

# Reads the pep.toml at `path` in its workspace: a workspace's root with
# its members (`member_manifests`), and a root's or member's
# `workspace = true` entries filled in from the root's
# `[workspace.dependencies]`, a `path` there made absolute. The compiler
# checks the workspace itself, reporting its problems at their keys.
export read_project(path: Path): Result<Manifest> {
    var manifest = read_manifest(path);
    if (manifest.is_err()) {
        return manifest;
    }
    var root_path = find_workspace(path);
    if (root_path.is_empty()) {
        for (var requirement in manifest.value().requirements) {
            if (requirement.inherits) {
                return Result<Manifest>.Err(
                    $"{path.to_string()}: dependency '{requirement.name}' has 'workspace = true', and no workspace lists this package"
                );
            }
        }
        return manifest;
    }
    var root = manifest.value();
    if (!root.is_workspace) {
        var read = read_manifest(root_path.value());
        if (read.is_err()) {
            return read;
        }
        root = read.value();
    }
    var inherited = _inherit(manifest.value(), root);
    if (inherited.is_value()) {
        return Result<Manifest>.Err(inherited.value());
    }
    if (!manifest.value().is_workspace) {
        return manifest;
    }
    var own = root.dir().canonicalize();
    for (var dir in _member_dirs(root)) {
        if (own.is_ok() and dir.to_string() == own.value().to_string()) {
            continue;
        }
        var member = read_manifest(dir.join("pep.toml"));
        if (member.is_err()) {
            return member;
        }
        var problem = _inherit(member.value(), root);
        if (problem.is_value()) {
            return Result<Manifest>.Err(problem.value());
        }
        root.member_manifests.append(member.value());
    }
    return manifest;
}

# The pep.toml of the workspace `path`, a pep.toml, is in: itself for a
# workspace's root, else the nearest one above it with `[workspace]`, not
# past a `.pep` folder, when that lists it; none when it is in no
# workspace.
export find_workspace(path: Path): Optional<Path> {
    var manifest = read_manifest(path);
    if (manifest.is_ok() and manifest.value().is_workspace) {
        return Optional<Path>.Value(path);
    }
    var dir = manifest.is_ok() ?
        manifest.value().dir().canonicalize() :
        path.parent().value_or(Path(".")).canonicalize();
    if (dir.is_err()) {
        return Optional<Path>.Empty;
    }
    var at = dir.value();
    while (true) {
        var name = at.file_name();
        var parent = at.parent();
        if ((name.is_value() and name.value() == ".pep")
            or parent.is_empty()
            or parent.value().to_string() == at.to_string()) {
            return Optional<Path>.Empty;
        }
        at = parent.value();
        var candidate = at.join("pep.toml");
        var text = File.read_to_string(candidate);
        if (text.is_err() or !text.value().contains("[workspace")) {
            continue;
        }
        var root = read_manifest(candidate);
        if (root.is_err() or !root.value().is_workspace) {
            continue;
        }
        for (var member in _member_dirs(root.value())) {
            if (member.to_string() == dir.value().to_string()) {
                return Optional<Path>.Value(candidate);
            }
        }
        return Optional<Path>.Empty;
    }
    return Optional<Path>.Empty;
}

# The folders `root`'s `members` name, each canonical: a folder, or a glob
# of folders, relative to the root.
_member_dirs(root: Manifest): Array<Path> {
    var dirs = Array<Path>();
    var base = root.dir().canonicalize();
    if (base.is_err()) {
        return dirs;
    }
    for (var pattern in root.members) {
        var found = Array<Path>();
        if (pattern.contains("*") or pattern.contains("?") or pattern.contains("[") or pattern.contains("{")) {
            # The glob's separators are `/` on every platform.
            found = glob(base.value().to_string().replace("\\", "/") + "/" + pattern);
        } else {
            found.append(base.value().join(pattern));
        }
        for (var dir in found) {
            var canonical = dir.canonicalize();
            if (canonical.is_ok() and canonical.value().join("pep.toml").is_file()) {
                dirs.append(canonical.value());
            }
        }
    }
    return dirs;
}

# Each member of the workspace whose root is `root_dir`, other than the
# root: its canonical folder and its `[package]` name. None when `root_dir`
# holds no workspace.
export workspace_members(root_dir: Path): Array<(Path, String)> {
    var members = Array<(Path, String)>();
    var root = read_manifest(root_dir.join("pep.toml"));
    if (root.is_err() or !root.value().is_workspace) {
        return members;
    }
    for (var dir in _member_dirs(root.value())) {
        var member = read_manifest(dir.join("pep.toml"));
        if (member.is_ok()) {
            members.append((dir, member.value().name));
        }
    }
    return members;
}

# Fills in `manifest`'s `workspace = true` entries from `root`'s
# `[workspace.dependencies]`; why one cannot be, if so.
_inherit(manifest: Manifest, root: Manifest): Optional<String> {
    for (var requirement in manifest.requirements) {
        if (!requirement.inherits) {
            continue;
        }
        var found = Optional<Requirement>.Empty;
        for (var shared in root.workspace_requirements) {
            if (shared.name == requirement.name) {
                found = Optional<Requirement>.Value(shared);
            }
        }
        if (found.is_empty()) {
            return Optional<String>.Value(
                $"{manifest.path.to_string()}: dependency '{requirement.name}' has 'workspace = true', and '[workspace.dependencies]' of {root.path.to_string()} has no '{requirement.name}'"
            );
        }
        requirement.host = found.value().host;
        requirement.repository = found.value().repository;
        requirement.member = found.value().member;
        requirement.kind = found.value().kind;
        requirement.value = found.value().value;
        if (requirement.is_path()) {
            var folder = root.dir().join(requirement.repository).canonicalize();
            if (folder.is_ok()) {
                requirement.repository = folder.value().to_string();
            }
        }
    }
    return Optional<String>.Empty;
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

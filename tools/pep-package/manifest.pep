# pep.toml as the package manager reads it: the package's name, the oldest
# toolchain it builds with, and its dependencies, dev-dependencies,
# build-dependencies and `[target.'<condition>'.dependencies]` (and
# `.build-dependencies`). The compiler checks the rest of the
# file, the conditions and `[features]` included, when it builds. Features
# do not change what is locked: an optional dependency is resolved and
# locked like any other. `[overrides]` replaces a package wherever the
# graph reaches it; only the project's own apply. `[retract]` lists the
# package's own withdrawn versions, and `[audit]` the advisories `audit`
# ignores.

import [Span] from compiler.ast;
import [Diagnostic, Location, render_all, SourceText] from compiler.diagnostic;
import [File, glob, Path] from io;
import semver;
import [parse_range, Version, VersionRange] from semver;
import toml;

# Whether `key` names a Git host a dependency can come from.
export is_host(key: String): bool {
    return key == "github" or key == "gitlab" or key == "codeberg";
}

# One entry of `[dependencies]`, `[dev-dependencies]`,
# `[build-dependencies]` or `[target.'<condition>'.dependencies]` (or
# `.build-dependencies`).
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
    # Whether it is in `[build-dependencies]`: only the package's build
    # script imports it, built for the machine building.
    var build: bool = false;
    # The `[target.'<condition>']` it is under (`OS(Windows)`): the
    # platforms that use it (for a build-dependency, the hosts). Empty for
    # every platform.
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
    # name]`, `[build-dependencies, name]` or `[target, condition,
    # dependencies, name]` (`build-dependencies`).
    key(): Array<String> {
        var table = dev ? "dev-dependencies" : build ? "build-dependencies" : "dependencies";
        return target.is_empty ? [table, name] : ["target", target, table, name];
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

# An entry of `[retract]`: versions the package's author withdrew, and why.
export struct Retraction {
    var range: VersionRange = VersionRange();
    var reason: String = "";

    construct() {}

    construct(range: VersionRange, reason: String) {
        this.range = range;
        this.reason = reason;
    }
}

# Why `version` is retracted, if one of `retractions` names it.
export retracted(retractions: Array<Retraction>, version: Version): Optional<String> {
    for (var retraction in retractions) {
        if (retraction.range.matches(version)) {
            return Optional<String>.Value(retraction.reason);
        }
    }
    return Optional<String>.Empty;
}

# The versions `text` names in `[retract]` or an advisory: a version is
# that version alone (`1.0.1`), anything else a range as dependencies
# write it (`>=1.1.0, <1.1.3`).
export version_range(text: String): Result<VersionRange> {
    return parse_range(semver.parse(text.trim()).is_ok() ? "=" + text.trim() : text);
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
    # `[retract]`: the versions of this package its author withdrew.
    var retractions: Array<Retraction> = __null;
    # The error at the first `[retract]` key that names no version, which
    # `read_project` reports for the project's own pep.toml: a
    # dependency's retracts nothing there, rather than break resolution.
    var retract_error: String = "";
    # `[audit]`'s `ignore`: the advisories `audit` does not fail on.
    var audit_ignore: Array<String> = __null;

    construct() {
        requirements = Array<Requirement>();
        hosts = ["github", "gitlab", "codeberg"];
        members = Array<String>();
        workspace_requirements = Array<Requirement>();
        member_manifests = Array<Manifest>();
        overrides = Array<Requirement>();
        retractions = Array<Retraction>();
        audit_ignore = Array<String>();
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

    # `message` as `at_key` puts it at a dependency's `value` (its `path`
    # or `package`), else at the dependency's key `name`, which inherits
    # that value from its workspace.
    at_value(severity: String, value: String, message: String, name: String): String {
        var written = text.contains("\"" + value + "\"") or text.contains("'" + value + "'");
        return at_key(severity, written ? value : name, message);
    }

    # `message` as a clang-style `severity` diagnostic at `key`, written
    # quoted (the source of an override, a version `[retract]` names) or
    # bare at the start of a line, looked for after the first `table`
    # (`[retract]`) when it is given; at the file's start when it is not
    # there.
    at_key(severity: String, key: String, message: String, table: String = ""): String {
        var found = table.is_empty ? 0 : text.find(table);
        var from = found < 0 ? 0 : found as ulong;
        var start = text.find("\"" + key + "\"", from);
        var length = key.length + 2;
        if (start < 0) {
            start = text.find("'" + key + "'", from);
        }
        if (start < 0) {
            length = key.length;
            start = text.starts_with(key + " ") ? 0 : text.find("\n" + key + " ", from);
            start = start > 0 ? start + 1 : start;
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

    # The dependency or dev-dependency named `name`, or with `build` the
    # build-dependency: a name may be in both.
    requirement(name: String, build: bool): Optional<Requirement> {
        for (var requirement in requirements) {
            if (requirement.name == name and requirement.build == build) {
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
    for (var name in ["dependencies", "dev-dependencies", "build-dependencies"]) {
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
            requirement.value().build = name == "build-dependencies";
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
    # The compiler checks the types of both, at their keys.
    var retract = root.try_get("retract");
    if (retract.is_value() and retract.value().as_table().is_value()) {
        for (var (versions, reason) in retract.value().as_table().value()) {
            var range = version_range(versions);
            if (range.is_err()) {
                if (manifest.retract_error.is_empty) {
                    manifest.retract_error = manifest.at_key(
                        "error",
                        versions,
                        $"'{versions}' in '[retract]' is not a version or range: {range.error().message}",
                        "retract"
                    );
                }
                continue;
            }
            manifest.retractions.append(Retraction(range.value(), reason.as_string().value_or("")));
        }
    }
    var ignore = root.lookup("audit.ignore");
    if (ignore.is_value() and ignore.value().as_array().is_value()) {
        for (var id in ignore.value().as_array().value()) {
            if (id.as_string().is_value()) {
                manifest.audit_ignore.append(id.as_string().value());
            }
        }
    }
    var targets = root.try_get("target");
    if (targets.is_value()) {
        var conditions = targets.value().as_table();
        if (conditions.is_empty()) {
            return Result<Manifest>.Err($"{path.to_string()}: '[target]' must be a table");
        }
        for (var (condition, tables) in conditions.value()) {
            for (var name in ["dependencies", "build-dependencies"]) {
                var dependencies = tables.try_get(name);
                if (dependencies.is_empty()) {
                    continue;
                }
                var table = dependencies.value().as_table();
                if (table.is_empty()) {
                    return Result<Manifest>.Err($"{path.to_string()}: '[target.'{condition}'.{name}]' must be a table");
                }
                for (var (key, value) in table.value()) {
                    var requirement = _requirement(path, key, value);
                    if (requirement.is_err()) {
                        return Result<Manifest>.Err(requirement.error().message);
                    }
                    requirement.value().target = condition;
                    requirement.value().build = name == "build-dependencies";
                    manifest.requirements.append(requirement.value());
                }
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
        ("fetch.vendor", "0.11.0"),
        ("retract", "0.11.0"),
        ("audit", "0.11.0"),
        ("build-dependencies", "0.11.0"),
        ("native", "0.11.0")
    ];
}

# The first release that reads a dependency's `optional`, `features`,
# `default-features`, `workspace` and `package`, which
# `newer_manifest_features` cannot name: they sit under each dependency's
# own key.
export const DEPENDENCY_FEATURES_RELEASE = "0.11.0";

# One `[dependencies]`, `[dev-dependencies]` or `[build-dependencies]` entry.
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
# checks the workspace itself, reporting its problems at their keys. A
# malformed `[retract]` is an error only when `strict`, for the project:
# a dependency's retracts nothing.
export read_project(path: Path, strict: bool = true): Result<Manifest> {
    var manifest = read_manifest(path);
    if (manifest.is_err()) {
        return manifest;
    }
    if (strict and !manifest.value().retract_error.is_empty) {
        return Result<Manifest>.Err(manifest.value().retract_error);
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
        if (strict and !member.value().retract_error.is_empty) {
            return Result<Manifest>.Err(member.value().retract_error);
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

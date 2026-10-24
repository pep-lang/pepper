## Projects: a
## `pep.toml` marks the root of a project (or of a package, a project other
## projects depend on) and declares its metadata, how it is built, and its
## dependencies. Each key of `[dependencies]` (and of
## `[dev-dependencies]`, which only the project's tests and examples see,
## and of `[target.'<condition>'.dependencies]`, which only a build for a
## target the `[Target(...)]` condition selects sees) is the name source
## code imports. `[features]` names optional parts of a package: turning a
## feature on defines the build option `<package>_<feature>` and turns on
## the optional dependencies and dependency features it lists
## (`Packages.turn_on_features`). `[overrides]`, read only from the
## project's own `pep.toml`, replaces a package wherever the graph reaches
## it: a fork is checked out in the original's folder, and a `path`
## override's folder stands in for it (`Manifest.directory_of`). A fetched
## dependency lives in the
## project's `.pep/deps/<host>/<repository>`, and `Packages` resolves the
## imports of every file of a program against the dependencies of the
## package that file belongs to. A dependency with `package` is a member of
## its repository's workspace, in a checkout of its own
## (`<repository>#<member>`); in a fetched package, a `path` with a
## `version` names a package of the same workspace, which is fetched on
## its own (`Packages._as_fetched`).

import [Attribute, Span] from compiler.ast;
import [Diagnostic, Location, render_all, SourceText] from compiler.diagnostic;
import io;
import [File, Path] from io;
import os;
import compiler.parse;
import process;
import toml;
import [TomlValue] from toml;
import "files" as files;
import [Target, TEST_BUILD_OPTION] from "platform";

## The folder, in a project's `.pep`, that holds its fetched dependencies.
export const DEPS_DIR = "deps";

## The file, beside `pep.toml`, that records the exact revision of every
## dependency in the graph (`pepper package` writes it).
export const LOCK_FILE = "pep.lock";

## The Git hosts a dependency can come from.
export enum Host {
    GitHub,
    GitLab,
    Codeberg,

    ## The key that names it in a dependency: `github`.
    key(): String {
        match (this) {
            GitHub => {
                return "github";
            }
            GitLab => {
                return "gitlab";
            }
            Codeberg => {
                return "codeberg";
            }
        }
    }

    ## Its domain: `github.com`.
    domain(): String {
        match (this) {
            GitHub => {
                return "github.com";
            }
            GitLab => {
                return "gitlab.com";
            }
            Codeberg => {
                return "codeberg.org";
            }
        }
    }

    ## The address git clones `repository` (`owner/name`) from:
    ## `https://github.com/owner/name.git`, or under the address in
    ## `PEPPER_PACKAGE_<HOST>_URL` when that is set (a mirror).
    clone_url(repository: String): String {
        var variable = $"PEPPER_PACKAGE_{key().upper()}_URL";
        var set = os.environment(variable);
        var base = set.is_value() and !set.value().is_empty ? set.value() : $"https://{domain()}";
        while (base.ends_with("/")) {
            base = base.substr_bytes(0, base.size - 1);
        }
        # A workspace member's (`owner/name#member`) is its repository's.
        var member = repository.split_once("#");
        return $"{base}/{member.is_value() ? member.value().0 : repository}.git";
    }
}

## Every host, in the order `pepper package add` tries them by default.
export all_hosts(): Host[] {
    return [Host.GitHub, Host.GitLab, Host.Codeberg];
}

## The host whose key is `key`, if any.
export host_named(key: String): Host? {
    for (var host in all_hosts()) {
        if (host.key() == key) {
            return Optional<Host>.Value(host);
        }
    }
    return Optional<Host>.Empty;
}

## Where a package's files live in the project `project`:
## `<project>/.pep/deps/<host domain>/<owner>/<name>`, and for a member of
## the repository's workspace (`owner/name#member`) its own checkout of the
## repository, `<owner>/<name>#<member>`.
export package_directory(project: Path, host: Host, repository: String): Path {
    var dir = project.join(Path(".pep")).join(Path(DEPS_DIR)).join(Path(host.domain()));
    for (var part in repository.split("/")) {
        dir = dir.join(Path(part));
    }
    return dir;
}

## One package `pep.lock` lists.
export struct LockedPackage {
    var host: Host;
    ## `owner/name`.
    var repository: String;
    ## The full commit to check out.
    var commit: String;
    ## Its `target` condition: the platforms it is needed on, none when it
    ## is needed on every one.
    var condition: Attribute? = Optional<Attribute>.Empty;
    ## The fork `[overrides]` replaces it with, `github:you/name`, which its
    ## commit is cloned from; empty when it is not overridden.
    var override_source: String = "";

    construct(host: Host, repository: String, commit: String) {
        this.host = host;
        this.repository = repository;
        this.commit = commit;
    }

    ## Its source as `pep.lock` writes it: `github:owner/name`.
    source(): String {
        return $"{host.key()}:{repository}";
    }

    ## Whether a build for `build` needs it.
    matches(build: Target): bool {
        return _selects(condition, build);
    }

    ## The address git clones its commit from: its fork's, when overridden.
    clone_url(): String {
        var split = override_source.split_once(":");
        if (split.is_value()) {
            var fork = host_named(split.value().0);
            if (fork.is_value()) {
                return fork.value().clone_url(split.value().1);
            }
        }
        return host.clone_url(repository);
    }
}

## The packages the `pep.lock` at `path` lists; none when it does not
## exist.
##
## @param path the lock file
## @returns the packages, or why the file is not a valid lock
export read_lock(path: Path): Result<LockedPackage[], String> {
    var locked = Array<LockedPackage>();
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<LockedPackage[], String>.ok(locked);
    }
    var root = toml.parse(text.value());
    if (root.is_err()) {
        return Result<LockedPackage[], String>.err($"{path}: {root.error().message}");
    }
    var invalid = $"{path}: 'package' must be an array of tables with a 'source' and a 'commit'";
    var packages = root.value().try_get("package");
    if (!packages.is_value()) {
        return Result<LockedPackage[], String>.ok(locked);
    }
    var items = packages.value().as_array();
    if (!items.is_value()) {
        return Result<LockedPackage[], String>.err(invalid);
    }
    for (var package in items.value()) {
        if (!package.as_table().is_value()) {
            return Result<LockedPackage[], String>.err(invalid);
        }
        var override_source = "";
        var overridden = package.try_get("override");
        if (overridden.is_value()) {
            if (overridden.value() is String(o)) {
                override_source = o;
            }
        }
        # A `path` override has no commit and nothing to fetch.
        if (override_source.starts_with("path:")) {
            continue;
        }
        var source = package.try_get("source");
        var commit = package.try_get("commit");
        if (!source.is_value() or !commit.is_value()) {
            return Result<LockedPackage[], String>.err(invalid);
        }
        var source_string = "";
        var commit_string = "";
        if (source.value() is String(s)) {
            source_string = s;
        } else {
            return Result<LockedPackage[], String>.err(invalid);
        }
        if (commit.value() is String(c)) {
            commit_string = c;
        } else {
            return Result<LockedPackage[], String>.err(invalid);
        }
        var split = source_string.split_once(":");
        if (!split.is_value()) {
            return Result<LockedPackage[], String>.err(invalid);
        }
        var (host_key, repository) = split.value();
        var host = host_named(host_key);
        if (!host.is_value()) {
            return Result<LockedPackage[], String>.err(invalid);
        }
        var entry = LockedPackage(host.value(), repository, commit_string);
        entry.override_source = override_source;
        var target = package.try_get("target");
        if (target.is_value()) {
            if (target.value() is String(t)) {
                # One that does not parse is fetched: building it reports
                # the error, at the key in its pep.toml.
                var condition = target_condition(t);
                if (condition.is_ok()) {
                    entry.condition = Optional<Attribute>.Value(condition.value());
                }
            } else {
                return Result<LockedPackage[], String>.err(invalid);
            }
        }
        locked.append(entry);
    }
    return Result<LockedPackage[], String>.ok(locked);
}

## One entry of `[dependencies]`, `[dev-dependencies]` or
## `[target.'<condition>'.dependencies]`.
export struct Dependency {
    ## The key: the name source code imports.
    var name: String;
    ## The key's span in the manifest's text.
    var name_span: Span;
    ## Its host, for a Git dependency; Empty for a folder.
    var host: Host?;
    ## `owner/name` on the host, or the folder relative to the `pep.toml`.
    var location: String;
    ## `package`: the member of the repository's workspace it is, by its
    ## `[package]` name; empty for the repository's root package.
    var member: String = "";
    ## Whether it gives a `version`, which for a `path` in a fetched
    ## package names a published package of the same workspace
    ## (`Packages` reads it so).
    var has_version: bool = false;
    ## The condition of the `[target.'<condition>'.dependencies]` table it
    ## is in (`OS(Windows)`), or empty for every target.
    var target: String = "";
    ## `target` read as the body of a `[Target(...)]`.
    var condition: Attribute? = Optional<Attribute>.Empty;
    ## `optional = true`: a build sees it only when a feature turns it on
    ## (`dep:name` or `name/feature` in `[features]`).
    var optional: bool = false;
    ## `features`: the dependency's features it turns on.
    var features: String[] = Array<String>();
    ## Where each of `features` is written.
    var feature_spans: Span[] = Array<Span>();
    ## `default-features`: whether it turns on the dependency's `default`
    ## feature.
    var default_features: bool = true;
    ## `workspace = true`: its source and revision are the entry of the same
    ## name in the workspace's `[workspace.dependencies]`, which loading
    ## the manifest fills in (`load_manifest`).
    var inherits: bool = false;

    construct(name: String, name_span: Span, host: Host?, location: String) {
        this.name = name;
        this.name_span = name_span;
        this.host = host;
        this.location = location;
    }

    ## Where the dependency's files are, for a project rooted at `project`
    ## whose manifest (the one naming the dependency) is in `manifest_dir`.
    ## For a workspace member, the checkout of its repository, in which
    ## `Packages` finds the member's folder.
    directory(project: Path, manifest_dir: Path): Path {
        if (host.is_value()) {
            return package_directory(project, host.value(), repository());
        }
        return manifest_dir.join(Path(location));
    }

    ## `location`, with `#` and the member for a workspace member:
    ## `owner/name#member`.
    repository(): String {
        return member.is_empty ? location : $"{location}#{member}";
    }

    ## Whether a build for `build` sees it: always, unless it is in a
    ## `[target.'<condition>'.dependencies]` whose condition `build` does
    ## not satisfy.
    matches(build: Target): bool {
        return _selects(condition, build);
    }

    ## The table it is in, as a message names it:
    ## `target.'OS(Windows)'.dependencies`, else `dependencies`.
    table(): String {
        return target.is_empty ? "dependencies" : $"target.'{target}'.dependencies";
    }

    ## Its source as `pep.lock` writes it (`github:owner/name`, or
    ## `github:owner/name#member`), for a Git dependency.
    locked_source(): String? {
        if (host.is_value()) {
            return Optional<String>.Value($"{host.value().key()}:{repository()}");
        }
        return Optional<String>.Empty;
    }
}

## One entry of `[features]`: a feature, and what turning it on turns on.
export struct Feature {
    ## The key.
    var name: String;
    ## The key's span in the manifest's text.
    var name_span: Span;
    ## What it turns on, as written: another feature (`gzip`), an optional
    ## dependency (`dep:zlib`), or a dependency's feature (`zlib/simd`).
    var enables: String[] = Array<String>();
    ## Where each of `enables` is written.
    var spans: Span[] = Array<Span>();

    construct(name: String, name_span: Span) {
        this.name = name;
        this.name_span = name_span;
    }
}

## A problem with a `pep.toml`, at a byte range of its text.
export struct ManifestError {
    var message: String;
    var span: Span;

    construct(message: String, span: Span) {
        this.message = message;
        this.span = span;
    }
}

## A parsed `pep.toml`.
export struct Manifest {
    ## The `pep.toml` file.
    var path: Path;
    ## Its text, for diagnostics.
    var text: String;
    ## `[package]`'s `name`.
    var name: String = "";
    ## `[build]`'s `entry`, relative to the project, if given.
    var entry_file: String? = Optional<String>.Empty;
    ## `[build]`'s `output`, relative to the project, if given.
    var output_file: String? = Optional<String>.Empty;
    ## `[build]`'s extra module search directories, relative to the project.
    var include: String[] = Array<String>();
    ## `[build]`'s libraries to link.
    var link: String[] = Array<String>();
    ## In the order they are written.
    var dependencies: Dependency[] = Array<Dependency>();
    ## `[dev-dependencies]`, in the order they are written: seen only by a
    ## build of this project's tests or examples (`Packages.dev`).
    var dev_dependencies: Dependency[] = Array<Dependency>();
    ## `[features]`, in the order they are written.
    var features: Feature[] = Array<Feature>();
    ## Whether it has a `[workspace]` table: it is the root of a workspace.
    var is_workspace: bool = false;
    ## `[workspace]`'s `members` as written: folders, or globs of them,
    ## relative to the root.
    var members: String[] = Array<String>();
    ## Where each of `members` is written.
    var member_spans: Span[] = Array<Span>();
    ## `[workspace.dependencies]`, which a member's `workspace = true` entry
    ## takes its source and revision from.
    var workspace_dependencies: Dependency[] = Array<Dependency>();
    ## A workspace root's member packages other than itself, as
    ## `load_manifest` reads them.
    var member_manifests: Manifest[] = Array<Manifest>();
    ## The root folder of the workspace it belongs to (its own, for a
    ## root), whose `.pep/deps` and `pep.lock` serve every member.
    var workspace_dir: Path? = Optional<Path>.Empty;
    ## `[overrides]`: each the package that replaces another, its `name`
    ## the source it replaces (`github:owner/name`). Only the project's own
    ## apply, and in a workspace only the root's.
    var overrides: Dependency[] = Array<Dependency>();

    construct(path: Path, text: String) {
        this.path = path;
        this.text = text;
    }

    ## The folder holding the `pep.toml`: the project's root.
    dir(): Path {
        return files.dir_of(path);
    }

    ## The folder whose `.pep/deps` and `pep.lock` serve it: its
    ## workspace's root, else its own.
    deps_root(): Path {
        return workspace_dir.is_value() ? workspace_dir.value() : dir();
    }

    ## A workspace root's packages: itself when it has a `[package]`, then
    ## its members.
    workspace_packages(): Manifest[] {
        var out = Array<Manifest>();
        if (!name.is_empty) {
            out.append(this);
        }
        out.append_all(member_manifests);
        return out;
    }

    ## The dependency named `name`, if any.
    dependency(name: String): Dependency? {
        return _named(dependencies, name);
    }

    ## The dev-dependency named `name`, if any.
    dev_dependency(name: String): Dependency? {
        return _named(dev_dependencies, name);
    }

    ## The feature named `name`, if any.
    feature(name: String): Feature? {
        for (var f in features) {
            if (f.name == name) {
                return Optional<Feature>.Value(f);
            }
        }
        return Optional<Feature>.Empty;
    }

    ## Where `d`, a dependency of the package whose manifest is in
    ## `manifest_dir`, is in the project this manifest is the root of: the
    ## folder of a `path` override of its source, else `d.directory`. A
    ## fork override is checked out where the original would be.
    ##
    ## @param d the dependency
    ## @param manifest_dir the folder of the `pep.toml` naming it
    ## @returns its folder
    directory_of(d: Dependency, manifest_dir: Path): Path {
        var replacement = path_override(d);
        if (replacement.is_value()) {
            return dir().join(Path(replacement.value().location));
        }
        return d.directory(dir(), manifest_dir);
    }

    ## The `path` override of `d`'s source, if any.
    path_override(d: Dependency): Dependency? {
        var source = d.locked_source();
        if (source.is_value()) {
            var replacement = _named(overrides, source.value());
            if (replacement.is_value() and !replacement.value().host.is_value()) {
                return replacement;
            }
        }
        return Optional<Dependency>.Empty;
    }

    ## The build option the feature `feature` defines when it is on:
    ## `<package>_<feature>`, such as `http_tls`.
    build_option(feature: String): String {
        return $"{name}_{feature}";
    }

    ## Returns its Git dependencies and dev-dependencies, and the Git
    ## dependencies of every `path` dependency they reach, which the
    ## project fetches into its own `.pep/deps`; for a workspace root,
    ## those of every member too. Another package's dev-dependencies are
    ## not part of this project. A Git dependency this manifest's
    ## `[overrides]` replaces with a `path` counts as that folder. A `path`
    ## dependency whose `pep.toml` cannot be read is skipped: importing it
    ## reports why.
    ##
    ## @param build when given, only what a build for this target sees
    ##   (`Dependency.matches`); else every platform's
    ## @returns the Git dependencies, this manifest's first
    git_dependencies(build: Target? = Optional<Target>.Empty): Dependency[] {
        var out = Array<Dependency>();
        var pending = [this];
        pending.append_all(member_manifests);
        # The first `own` are the project's packages: only their
        # dev-dependencies are its own.
        var own = pending.count;
        var seen = HashSet<String>();
        while (!pending.is_empty) {
            var manifest = pending.remove_at(0);
            var is_own = own > 0;
            own = is_own ? own - 1 : 0;
            if (!seen.insert(manifest.dir().normalize().to_string())) {
                continue;
            }
            var named = manifest.dependencies.copy();
            if (is_own) {
                named.append_all(manifest.dev_dependencies);
            }
            for (var d in named) {
                if (build.is_value() and !d.matches(build.value())) {
                    continue;
                }
                if (d.host.is_value() and !path_override(d).is_value()) {
                    out.append(d);
                    continue;
                }
                var folder = directory_of(d, manifest.dir());
                var nested = load_manifest(folder.join(Path(files.MANIFEST_FILE)), Array<Path>());
                if (nested.is_ok()) {
                    pending.append(nested.value());
                }
            }
        }
        return out;
    }

    ## The `[build]` entry file: `entry`, else `main.pep`, in the project.
    entry(): Path {
        return dir().join(Path(entry_file.is_value() ? entry_file.value() : "main.pep"));
    }

    ## The `[build]` executable: `output`, else the package's name, in the
    ## project.
    output(): Path {
        return dir().join(Path(output_file.is_value() ? output_file.value() : name));
    }

    ## The `[build]` include directories, in the project.
    include_dirs(): Path[] {
        var dirs = Array<Path>();
        for (var dir_name in include) {
            dirs.append(dir().join(Path(dir_name)));
        }
        return dirs;
    }
}

## Whether `condition`, a `[Target(...)]` body, holds for `build`; none
## holds everywhere.
_selects(condition: Attribute?, build: Target): bool {
    return !condition.is_value() or build.keeps([condition.value()]);
}

## Reads `text`, a `[target.'<condition>']` key or a `pep.lock` `target`,
## as the body of a `[Target(...)]` attribute: the expressions
## `[Target(...)]` takes, checked as it checks them.
##
## @param text the condition, such as `OS(Windows)`
## @returns the attribute, or why it is not a condition
target_condition(text: String): Result<Attribute, String> {
    var invalid = $"invalid target condition '{text}'; expected what '[Target(...)]' takes, such as 'OS(Windows)'";
    # A declaration to hang the attribute on.
    var parsed = parse.parse_declarations("[Target(" + text + ")]\n_target() {}\n");
    if (parsed.is_err() or parsed.value().declarations.count != 1) {
        return Result<Attribute, String>.err(invalid);
    }
    var attributes = parsed.value().declarations[0].attributes();
    if (attributes.count != 1) {
        return Result<Attribute, String>.err(invalid);
    }
    var checked = Target().check(attributes[0]);
    if (checked.is_value()) {
        return Result<Attribute, String>.err(checked.value().0);
    }
    return Result<Attribute, String>.ok(attributes[0]);
}

## The dependency in `dependencies` named `name`, if any.
_named(dependencies: Dependency[], name: String): Dependency? {
    for (var d in dependencies) {
        if (d.name == name) {
            return Optional<Dependency>.Value(d);
        }
    }
    return Optional<Dependency>.Empty;
}

## Whether `text` names toolchain versions: `latest`, or one to three
## numbers (`0.3.0`, `0.3`, `0`) without leading zeros.
is_toolchain_version(text: String): bool {
    if (text == "latest") {
        return true;
    }
    var parts = text.split(".");
    if (parts.count > 3) {
        return false;
    }
    for (var part in parts) {
        var number = ulong.parse(part);
        if (number.is_empty() or to_string(number.value()) != part) {
            return false;
        }
    }
    return true;
}

## Whether `text` names one toolchain release: three numbers (`0.11.0`),
## with an optional prerelease (`0.11.0-dev`), as `minimum_toolchain` takes.
is_toolchain_release(text: String): bool {
    var split = text.split_once("-");
    if (split.is_value() and split.value().1.is_empty) {
        return false;
    }
    var numbers = split.is_value() ? split.value().0 : text;
    return numbers.split(".").count == 3 and is_toolchain_version(numbers);
}

## Whether `name` can be imported: an identifier.
export is_identifier(name: String): bool {
    if (name.is_empty) {
        return false;
    }
    ulong i = 0;
    for (var b in name.bytes()) {
        var letter = (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_';
        if (!letter and (i == 0 or !(b >= '0' and b <= '9'))) {
            return false;
        }
        i += 1;
    }
    return true;
}

## What a value is, for "expected" messages.
_kind(value: TomlValue): String {
    match (value) {
        String(_) => {
            return "a string";
        }
        Integer(_) => {
            return "an integer";
        }
        Float(_) => {
            return "a float";
        }
        Boolean(_) => {
            return "a boolean";
        }
        DateTime(_) => {
            return "a date-time";
        }
        Array(_) => {
            return "an array";
        }
        Table(_) => {
            return "a table";
        }
    }
}

## `path` with `key` after it.
_at(path: String[], key: String): String[] {
    var out = path.copy();
    out.append(key);
    return out;
}

## Reads a manifest's text, collecting its problems. The parsed tree has no
## positions, so spans are found in the text by the keys that lead to
## them.
struct _Reader {
    var text: String;
    var errors: ManifestError[] = Array<ManifestError>();

    construct(text: String) {
        this.text = text;
    }

    ## Where the key path `keys` is spelled: the byte offsets of its last
    ## key and of the value after it. A first key that heads a table
    ## (`[package]`) is found as the header; each later key as the first
    ## `key =` after the one before it.
    _locate(keys: String[]): (ulong, ulong) {
        ulong at = 0;
        ulong key_at = 0;
        ulong i = 0;
        while (i < keys.count) {
            var key = keys[i];
            if (i == 0 and key == "target" and keys.count > 1) {
                # `[target.'OS(Windows)'.dependencies]`: the condition, then
                # the table after it. Quoted, so `OS(Windows)` is not found
                # inside `'!OS(Windows)'`.
                var condition = text.find("'" + keys[1] + "'");
                if (condition < 0) {
                    condition = text.find("\"" + keys[1] + "\"");
                }
                condition = condition >= 0 ? condition + 1 : text.find(keys[1]);
                if (condition >= 0) {
                    at = condition as ulong + keys[1].size;
                    key_at = condition as ulong;
                    i += 2;
                    if (keys.count > 2) {
                        var table = text.find(keys[2], at);
                        if (table >= 0) {
                            key_at = table as ulong;
                            at = table as ulong + keys[2].size;
                        }
                        i += 1;
                    }
                    continue;
                }
            }
            if (i == 0 and keys.count > 1) {
                # A table header naming two keys: `[workspace.dependencies]`.
                var nested = text.find($"[{key}.{keys[1]}]");
                if (nested >= 0) {
                    key_at = nested as ulong + key.size + 2;
                    at = key_at + keys[1].size;
                    i += 2;
                    continue;
                }
            }
            if (i == 0) {
                var header = text.find($"[{key}]");
                if (header >= 0) {
                    at = header as ulong + 1;
                    key_at = at;
                    i += 1;
                    continue;
                }
            }
            var found = _find_key(key, at);
            if (!found.is_value()) {
                return (key_at, at);
            }
            key_at = found.value();
            at = found.value() + key.size;
            i += 1;
        }
        # The value starts after `=` and any spaces.
        var value_at = at;
        while (value_at < text.size and (text.byte_at(value_at) == ' ' or text.byte_at(value_at) == '\t')) {
            value_at += 1;
        }
        if (value_at < text.size and text.byte_at(value_at) == '=') {
            value_at += 1;
            while (value_at < text.size and (text.byte_at(value_at) == ' ' or text.byte_at(value_at) == '\t')) {
                value_at += 1;
            }
        }
        return (key_at, value_at);
    }

    ## The offset of the first `key` at or after `from` that is a whole key
    ## followed by `=` (or that is quoted).
    _find_key(key: String, from: ulong): ulong? {
        var at = from;
        while (true) {
            var found = text.find(key, at);
            if (found < 0) {
                return Optional<ulong>.Empty;
            }
            var start = found as ulong;
            var end = start + key.size;
            var before = start == 0 ? '\n' : text.byte_at(start - 1);
            var whole_start = before == '\n'
                or before == ' '
                or before == '\t'
                or before == '{'
                or before == ','
                or before == '"';
            var after = end;
            if (after < text.size and text.byte_at(after) == '"') {
                after += 1;
            }
            while (after < text.size and (text.byte_at(after) == ' ' or text.byte_at(after) == '\t')) {
                after += 1;
            }
            if (whole_start and after < text.size and text.byte_at(after) == '=') {
                return Optional<ulong>.Value(start);
            }
            at = end;
        }
        return Optional<ulong>.Empty;
    }

    ## Where the value at `keys` is: a quoted string through its closing
    ## quote, else up to the next space, `,`, `}` or `]` (a table or array
    ## value, its first byte).
    value_span(keys: String[]): Span {
        var (_, value) = _locate(keys);
        return Span(value, _value_end(value));
    }

    ## Where the string `item` of the array at `keys` is written, else the
    ## array's place.
    item_span(keys: String[], item: String): Span {
        var array = value_span(keys);
        var found = text.find($"\"{item}\"", array.start);
        if (found < 0) {
            return array;
        }
        return Span(found as ulong, found as ulong + item.size + 2);
    }

    _value_end(start: ulong): ulong {
        if (start >= text.size) {
            return start;
        }
        var first = text.byte_at(start);
        if (first == '"' or first == '\'') {
            var end = start + 1;
            while (end < text.size and text.byte_at(end) != first and text.byte_at(end) != '\n') {
                if (first == '"' and text.byte_at(end) == '\\') {
                    end += 1;
                }
                end += 1;
            }
            return end < text.size ? end + 1 : end;
        }
        if (first == '{' or first == '[') {
            return start + 1;
        }
        var end = start;
        while (end < text.size) {
            var b = text.byte_at(end);
            if (b == ' ' or b == '\t' or b == '\n' or b == '\r' or b == ',' or b == '}' or b == ']') {
                break;
            }
            end += 1;
        }
        return end;
    }

    ## Where the last key of `keys` is.
    key_span(keys: String[]): Span {
        var (key, _) = _locate(keys);
        return Span(key, key + keys[keys.count - 1].size);
    }

    error(message: String, span: Span) {
        errors.append(ManifestError(message, span));
    }

    table(path: String[], key: String, value: TomlValue): OrderedMap<String, TomlValue>? {
        var members = value.as_table();
        if (!members.is_value()) {
            error($"'{key}' must be a table, not {_kind(value)}", value_span(path));
        }
        return members;
    }

    string(path: String[], key: String, value: TomlValue): String? {
        if (value is String(text_value)) {
            return Optional<String>.Value(text_value);
        }
        error($"'{key}' must be a string, not {_kind(value)}", value_span(path));
        return Optional<String>.Empty;
    }

    boolean(path: String[], key: String, value: TomlValue): bool? {
        if (value is Boolean(flag)) {
            return Optional<bool>.Value(flag);
        }
        error($"'{key}' must be a boolean, not {_kind(value)}", value_span(path));
        return Optional<bool>.Empty;
    }

    strings(path: String[], key: String, value: TomlValue): String[] {
        var out = Array<String>();
        var items = value.as_array();
        if (!items.is_value()) {
            error($"'{key}' must be an array of strings, not {_kind(value)}", value_span(path));
            return out;
        }
        ulong index = 0;
        for (var item in items.value()) {
            if (item is String(s)) {
                out.append(s);
            } else {
                error($"'{key}' must be an array of strings; this is {_kind(item)}", value_span(path));
            }
            index += 1;
        }
        return out;
    }

    unknown_key(path: String[], key: String, table: String, known: String[]) {
        var quoted = Array<String>();
        for (var k in known) {
            quoted.append($"'{k}'");
        }
        error($"unknown key '{key}' in '[{table}]'; expected one of {", ".join(quoted)}", key_span(_at(path, key)));
    }

    package(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        var named = false;
        for (var (key, value) in members) {
            var path = ["package", key];
            if (key == "name") {
                var name = string(path, key, value);
                if (name.is_value()) {
                    named = true;
                    if (!is_identifier(name.value())) {
                        error(
                            $"package name '{name.value()}' is not an identifier: use letters, digits and '_', not starting with a digit",
                            value_span(path)
                        );
                    }
                    manifest.name = name.value();
                }
            } else if (key == "version" or key == "description" or key == "license" or key == "repository") {
                string(path, key, value);
            } else if (key == "authors") {
                strings(path, key, value);
            } else if (key == "toolchain") {
                var toolchain = string(path, key, value);
                if (toolchain.is_value() and !is_toolchain_version(toolchain.value())) {
                    error(
                        $"toolchain '{toolchain.value()}' is not a version such as 0.3.0, 0.3 or latest",
                        value_span(path)
                    );
                }
            } else if (key == "minimum_toolchain") {
                var minimum = string(path, key, value);
                if (minimum.is_value() and !is_toolchain_release(minimum.value())) {
                    error(
                        $"minimum_toolchain '{minimum.value()}' is not a release such as 0.11.0 or 0.11.0-dev",
                        value_span(path)
                    );
                }
            } else {
                unknown_key(
                    ["package"],
                    key,
                    "package",
                    [
                        "name",
                        "version",
                        "description",
                        "authors",
                        "license",
                        "repository",
                        "toolchain",
                        "minimum_toolchain"
                    ]
                );
            }
        }
        if (!named) {
            error("'[package]' needs a 'name'", key_span(["package"]));
        }
    }

    build(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        for (var (key, value) in members) {
            var path = ["build", key];
            if (key == "entry") {
                manifest.entry_file = string(path, key, value);
            } else if (key == "output") {
                manifest.output_file = string(path, key, value);
            } else if (key == "include") {
                manifest.include = strings(path, key, value);
            } else if (key == "link") {
                manifest.link = strings(path, key, value);
            } else {
                unknown_key(["build"], key, "build", ["entry", "output", "include", "link"]);
            }
        }
    }

    fetch(members: OrderedMap<String, TomlValue>) {
        for (var (key, value) in members) {
            var path = ["fetch", key];
            if (key != "hosts") {
                unknown_key(["fetch"], key, "fetch", ["hosts"]);
                continue;
            }
            var items = value.as_array();
            if (!items.is_value()) {
                error($"'hosts' must be an array of strings, not {_kind(value)}", value_span(path));
                continue;
            }
            ulong index = 0;
            for (var item in items.value()) {
                var known = false;
                if (item is String(s)) {
                    known = host_named(s).is_value();
                }
                if (!known) {
                    var at = value_span(path);
                    if (item is String(written)) {
                        at = item_span(path, written);
                    }
                    error("'hosts' lists 'github', 'gitlab' or 'codeberg'", at);
                }
                index += 1;
            }
        }
    }

    ## The entries of the dependency table at `table` (`[dependencies]`,
    ## `[dev-dependencies]`, `[target, condition, dependencies]`), appended
    ## to `into`.
    dependencies(table: String[], into: Dependency[], members: OrderedMap<String, TomlValue>) {
        for (var (name, value) in members) {
            var path = _at(table, name);
            if (!is_identifier(name)) {
                error($"dependency name '{name}' is not an identifier; it is the name 'import' uses", key_span(path));
                continue;
            }
            var fields = value.as_table();
            if (!fields.is_value()) {
                error(
                    $"dependency '{name}' must be a table, not {_kind(value)}: '{name} = "
                        + "{ github = \"owner/name\", version = \"1.0\" }'",
                    value_span(path)
                );
                continue;
            }
            dependency(into, path, name, fields.value());
        }
    }

    dependency(into: Dependency[], path: String[], name: String, fields: OrderedMap<String, TomlValue>) {
        var before = errors.count;
        Host? host = Optional<Host>.Empty;
        String? location;
        var revision = "";
        var optional = false;
        var features = Array<String>();
        var feature_spans = Array<Span>();
        var default_features = true;
        var inherits = false;
        var member = "";
        var in_workspace = path[0] == "workspace";
        for (var (field, value) in fields) {
            var field_path = _at(path, field);
            var field_host = host_named(field);
            if (in_workspace
                and (field == "workspace"
                    or field == "optional"
                    or field == "features"
                    or field == "default-features")) {
                error(
                    $"'{field}' is not for '[workspace.dependencies]', which gives a source and a revision; give it in the member's entry",
                    key_span(field_path)
                );
                continue;
            }
            if (field == "workspace") {
                var given = boolean(field_path, field, value);
                if (given.is_value() and !given.value()) {
                    error(
                        $"'workspace' is true or absent; give dependency '{name}' a source instead",
                        value_span(field_path)
                    );
                }
                inherits = given.value_or(false);
                continue;
            }
            if (field_host.is_value() or field == "path") {
                var given = string(field_path, field, value);
                if (!given.is_value()) {
                    continue;
                }
                if (field_host.is_value()) {
                    # GitLab nests groups: `group/subgroup/name`.
                    var parts = given.value().split("/");
                    var well_formed = parts.count == 2 or (field_host.value() == Host.GitLab and parts.count > 2);
                    for (var part in parts) {
                        if (part.is_empty or part == "." or part == "..") {
                            well_formed = false;
                        }
                    }
                    if (!well_formed) {
                        error(
                            $"'{field}' must name a repository as 'owner/name', not '{given.value()}'",
                            value_span(field_path)
                        );
                        continue;
                    }
                }
                if (location.is_value()) {
                    error(
                        $"'{field}' is a second source; a dependency comes from one of 'github', 'gitlab', 'codeberg' or 'path'",
                        key_span(field_path)
                    );
                    continue;
                }
                host = field_host;
                location = given;
            } else if (field == "version" or field == "branch" or field == "tag" or field == "commit") {
                if (!string(field_path, field, value).is_value()) {
                    continue;
                }
                if (!revision.is_empty) {
                    error(
                        $"'{revision}' and '{field}' both choose a revision; give one of 'version', 'branch', 'tag' or 'commit'",
                        key_span(field_path)
                    );
                    continue;
                }
                revision = field;
            } else if (field == "package") {
                var given = string(field_path, field, value);
                if (given.is_value() and !is_identifier(given.value())) {
                    error(
                        $"'package' names a workspace member by its package name, and '{given.value()}' is not one",
                        value_span(field_path)
                    );
                    continue;
                }
                member = given.value_or("");
            } else if (field == "optional") {
                var given = boolean(field_path, field, value);
                if (given.is_value() and given.value() and path[0] == "dev-dependencies") {
                    error(
                        $"dev-dependency '{name}' cannot be optional; only '[dependencies]' are", key_span(field_path)
                    );
                    continue;
                }
                optional = given.value_or(false);
            } else if (field == "default-features") {
                default_features = boolean(field_path, field, value).value_or(true);
            } else if (field == "features") {
                for (var f in strings(field_path, field, value)) {
                    var at = item_span(field_path, f);
                    if (!is_identifier(f)) {
                        error($"feature name '{f}' is not an identifier", at);
                        continue;
                    }
                    features.append(f);
                    feature_spans.append(at);
                }
            } else {
                unknown_key(
                    path,
                    field,
                    path.count > 2 ? $"target.'{path[1]}'.dependencies" : path[0],
                    [
                        "github",
                        "gitlab",
                        "codeberg",
                        "path",
                        "package",
                        "version",
                        "branch",
                        "tag",
                        "commit",
                        "optional",
                        "features",
                        "default-features",
                        "workspace"
                    ]
                );
            }
        }
        if (!member.is_empty and location.is_value() and !host.is_value()) {
            error(
                "'package' names a member of a Git repository's workspace; a 'path' names the member's folder itself",
                key_span(_at(path, "package"))
            );
            return;
        }
        if (inherits) {
            var given = location.is_value() ?
                (host.is_value() ? host.value().key() : "path") :
                (member.is_empty ? revision : "package");
            if (!given.is_empty) {
                error(
                    $"'{given}' and 'workspace = true' both choose where '{name}' comes from; keep one",
                    key_span(_at(path, given))
                );
                return;
            }
            if (errors.count == before) {
                var inherited = Dependency(name, key_span(path), Optional<Host>.Empty, "");
                inherited.inherits = true;
                inherited.optional = optional;
                inherited.features = features;
                inherited.feature_spans = feature_spans;
                inherited.default_features = default_features;
                into.append(inherited);
            }
            return;
        }
        if (!location.is_value()) {
            if (errors.count == before) {
                error(
                    $"dependency '{name}' needs a source: 'github', 'gitlab' or 'codeberg' (\"owner/name\"), or 'path'",
                    value_span(path)
                );
            }
            return;
        }
        # A `path` may have a `version`: the release `publish` names it by.
        if (!host.is_value() and !revision.is_empty and revision != "version") {
            error(
                $"dependency '{name}' is a 'path'; a folder has no branches, tags or commits, only a 'version' for 'publish'",
                key_span(_at(path, revision))
            );
        }
        if (errors.count != before) {
            return;
        }
        var dependency = Dependency(name, key_span(path), host, location.value());
        dependency.member = member;
        dependency.has_version = revision == "version";
        dependency.optional = optional;
        dependency.features = features;
        dependency.feature_spans = feature_spans;
        dependency.default_features = default_features;
        into.append(dependency);
    }

    ## The `[features]` table: each key a feature, holding the features,
    ## optional dependencies (`dep:name`) and dependency features
    ## (`name/feature`) it turns on, which `check_features` checks once
    ## every table is read.
    features(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        for (var (key, value) in members) {
            var path = ["features", key];
            if (!is_identifier(key)) {
                error(
                    $"feature name '{key}' is not an identifier; it names the build option '<package>_<feature>'",
                    key_span(path)
                );
                continue;
            }
            var feature = Feature(key, key_span(path));
            for (var item in strings(path, key, value)) {
                feature.enables.append(item);
                feature.spans.append(item_span(path, item));
            }
            manifest.features.append(feature);
        }
    }

    ## Checks what each feature of `manifest` turns on: a feature of its
    ## own, an optional dependency, or a feature of a dependency.
    check_features(manifest: Manifest) {
        for (var feature in manifest.features) {
            for (var i in 0..feature.enables.count) {
                var item = feature.enables[i];
                var at = feature.spans[i];
                if (item.starts_with("dep:")) {
                    var name = item.substr_bytes(4, item.size - 4);
                    var d = manifest.dependency(name);
                    if (!d.is_value()) {
                        error($"'{item}' names no dependency; 'dep:' turns on an optional dependency", at);
                    } else if (!d.value().optional) {
                        error(
                            $"dependency '{name}' is not optional; give it 'optional = true' for 'dep:{name}' to turn it on",
                            at
                        );
                    }
                    continue;
                }
                var split = item.split_once("/");
                if (split.is_value()) {
                    var (name, inner) = split.value();
                    if (!manifest.dependency(name).is_value()) {
                        error($"'{item}' names no dependency '{name}'", at);
                    } else if (!is_identifier(inner)) {
                        error($"feature name '{inner}' is not an identifier", at);
                    }
                    continue;
                }
                if (!manifest.feature(item).is_value()) {
                    error(
                        $"no feature named '{item}' in '[features]'; a feature turns on features, 'dep:name' or 'name/feature'",
                        at
                    );
                }
            }
        }
    }

    ## The `[workspace]` table: its `members`, folders or globs of them,
    ## which `load_manifest` reads, and `[workspace.dependencies]`.
    workspace(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        manifest.is_workspace = true;
        for (var (key, value) in members) {
            var path = ["workspace", key];
            if (key == "members") {
                # Each after the one before, so a member listed twice is
                # found where it is listed again.
                var from = value_span(path).start;
                for (var member in strings(path, key, value)) {
                    var at = value_span(path);
                    var found = text.find($"\"{member}\"", from);
                    if (found >= 0) {
                        at = Span(found as ulong, found as ulong + member.size + 2);
                        from = at.end;
                    }
                    manifest.members.append(member);
                    manifest.member_spans.append(at);
                }
            } else if (key == "dependencies") {
                var entries = table(path, key, value);
                if (entries.is_value()) {
                    dependencies(path, manifest.workspace_dependencies, entries.value());
                }
            } else {
                unknown_key(["workspace"], key, "workspace", ["members", "dependencies"]);
            }
        }
    }

    ## The `[overrides]` table: each key the source of a package
    ## (`github:owner/name`), holding the package that replaces it, written
    ## as a dependency is.
    overrides(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        for (var (source, value) in members) {
            var path = ["overrides", source];
            var split = source.split_once(":");
            if (!split.is_value() or !host_named(split.value().0).is_value() or !split.value().1.contains("/")) {
                error(
                    $"override '{source}' does not name a package's source, such as 'github:owner/name'", key_span(path)
                );
                continue;
            }
            var fields = value.as_table();
            if (!fields.is_value()) {
                error(
                    $"override '{source}' must be a table, not {_kind(value)}: '\"{source}\" = "
                        + "{ github = \"you/name\", branch = \"fix\" }'",
                    value_span(path)
                );
                continue;
            }
            var featured = false;
            for (var (field, _) in fields.value()) {
                if (field == "optional" or field == "features" or field == "default-features" or field == "workspace") {
                    error(
                        $"an override takes a source and a revision, not '{field}'; set it on the dependency",
                        key_span(_at(path, field))
                    );
                    featured = true;
                }
            }
            if (!featured) {
                dependency(manifest.overrides, path, source, fields.value());
            }
        }
    }

    ## The `[target]` table: each key a condition, holding a
    ## `dependencies` table whose entries are appended to the manifest's
    ## dependencies, marked with it.
    targets(manifest: Manifest, members: OrderedMap<String, TomlValue>) {
        for (var (condition, value) in members) {
            var at = ["target", condition];
            var parsed = target_condition(condition);
            if (parsed.is_err()) {
                error(parsed.error(), key_span(at));
                continue;
            }
            var tables = table(at, condition, value);
            if (!tables.is_value()) {
                continue;
            }
            for (var (key, inner) in tables.value()) {
                var path = _at(at, key);
                if (key != "dependencies") {
                    unknown_key(at, key, $"target.'{condition}'", ["dependencies"]);
                    continue;
                }
                var entries = table(path, key, inner);
                if (!entries.is_value()) {
                    continue;
                }
                var found = Array<Dependency>();
                dependencies(path, found, entries.value());
                for (var d in found) {
                    d.target = condition;
                    d.condition = Optional<Attribute>.Value(parsed.value());
                    manifest.dependencies.append(d);
                }
            }
        }
    }
}

## Parses `text`, the contents of the `pep.toml` at `path`. Every problem
## found is returned, in the order of the text.
##
## @param path the file
## @param text its contents
## @returns the manifest, or its problems
export parse_manifest(path: Path, text: String): Result<Manifest, ManifestError[]> {
    var root = toml.parse(text);
    if (root.is_err()) {
        var e = root.error();
        var message = e.message;
        var span = Span(e.offset, e.offset);
        if (message.starts_with("duplicate key '")) {
            # Named by the key as written.
            var end = e.offset;
            while (end < text.size
                and text.byte_at(end) != ' '
                and text.byte_at(end) != '='
                and text.byte_at(end) != '\t') {
                end += 1;
            }
            span = Span(e.offset, end);
            var key = text.substr_bytes(e.offset, end - e.offset);
            while (key.starts_with("\"") or key.ends_with("\"")) {
                key = key.starts_with("\"") ? key.substr_bytes(1, key.size - 1) : key.substr_bytes(0, key.size - 1);
            }
            message = $"duplicate key '{key}'";
        }
        return Result<Manifest, ManifestError[]>.err([ManifestError(message, span)]);
    }
    var reader = _Reader(text);
    var manifest = Manifest(path, text);
    var package_seen = false;
    var members = root.value().as_table();
    for (var (key, value) in members.value()) {
        var at = [key];
        if (key == "package") {
            package_seen = true;
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.package(manifest, table.value());
            }
        } else if (key == "build") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.build(manifest, table.value());
            }
        } else if (key == "dependencies" or key == "dev-dependencies") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.dependencies(
                    at, key == "dependencies" ? manifest.dependencies : manifest.dev_dependencies, table.value()
                );
            }
        } else if (key == "target") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.targets(manifest, table.value());
            }
        } else if (key == "fetch") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.fetch(table.value());
            }
        } else if (key == "features") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.features(manifest, table.value());
            }
        } else if (key == "workspace") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.workspace(manifest, table.value());
            }
        } else if (key == "overrides") {
            var table = reader.table(at, key, value);
            if (table.is_value()) {
                reader.overrides(manifest, table.value());
            }
        } else {
            reader.error(
                $"unknown table '{key}'; a pep.toml has '[package]', '[build]', '[dependencies]', '[dev-dependencies]', '[target]', '[features]', '[overrides]', '[fetch]' and '[workspace]'",
                reader.key_span(at)
            );
        }
    }
    # A workspace's root need not be a package itself.
    if (!package_seen and !manifest.is_workspace) {
        reader.error("missing '[package]' table with the project's 'name'", Span(0, 0));
    }
    reader.check_features(manifest);
    for (var d in manifest.dependencies) {
        var first = manifest.dependency(d.name).value();
        if (first !== d) {
            reader.error($"'{d.name}' is in both '[{first.table()}]' and '[{d.table()}]'; keep it in one", d.name_span);
        }
    }
    for (var d in manifest.dev_dependencies) {
        var other = manifest.dependency(d.name);
        if (other.is_value()) {
            reader.error(
                $"'{d.name}' is in both '[{other.value().table()}]' and '[dev-dependencies]'; keep it in one",
                d.name_span
            );
        }
    }
    if (reader.errors.is_empty) {
        return Result<Manifest, ManifestError[]>.ok(manifest);
    }
    reader.errors.sort((a, b) => a.span.start < b.span.start ? -1 : (a.span.start > b.span.start ? 1 : 0));
    return Result<Manifest, ManifestError[]>.err(reader.errors);
}

## `errors` in the `pep.toml` at `path`, whose text is `text`, rendered
## clang-style.
export render_manifest_errors(path: Path, text: String, errors: ManifestError[]): String {
    var diagnostics = Array<Diagnostic>();
    for (var e in errors) {
        diagnostics.append(Diagnostic.error(e.message).at(Location(0, e.span)));
    }
    return render_all(diagnostics, [SourceText(path.to_string(), text)]);
}

## Reads the project file at `path`, puts it in its workspace
## (`join_workspace`), and checks it against the runtime in
## `runtime_dirs`: a dependency may not be named like a runtime module,
## which it would otherwise hide. Problems are rendered clang-style.
##
## @param path the `pep.toml`
## @param runtime_dirs the runtime's folders
## @returns the manifest, or its problems
export load_manifest(path: Path, runtime_dirs: Path[]): Result<Manifest, String> {
    var read = _read_manifest(path);
    if (read.is_err()) {
        return read;
    }
    var joined = join_workspace(read.value());
    if (joined.is_err()) {
        return Result<Manifest, String>.err(joined.error());
    }
    var manifest = read.value();
    var errors = Array<ManifestError>();
    for (var d in _all_dependencies(manifest)) {
        for (var dir in runtime_dirs) {
            if (dir.join(Path(d.name)).join(Path(files.MODULE_FILE)).is_file()) {
                errors.append(
                    ManifestError(
                        $"dependency '{d.name}' has the name of the runtime module '{d.name}'; give it another name, which source code then imports",
                        d.name_span
                    )
                );
                break;
            }
        }
    }
    if (errors.is_empty) {
        return Result<Manifest, String>.ok(manifest);
    }
    return Result<Manifest, String>.err(render_manifest_errors(path, manifest.text, errors));
}

## Reads and parses the `pep.toml` at `path`, its problems rendered
## clang-style.
_read_manifest(path: Path): Result<Manifest, String> {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        return Result<Manifest, String>.err($"cannot read {path}: {text.error().message}");
    }
    var parsed = parse_manifest(path, text.value());
    if (parsed.is_err()) {
        return Result<Manifest, String>.err(render_manifest_errors(path, text.value(), parsed.error()));
    }
    return Result<Manifest, String>.ok(parsed.value());
}

## Puts `manifest` in its workspace. A workspace's root reads its members
## (`Manifest.member_manifests`); any other package looks for the nearest
## `[workspace]` above it, not past a `.pep` folder, and is a member when
## that workspace lists it. A root and its members get `workspace_dir`,
## and their `workspace = true` dependencies the source the root's
## `[workspace.dependencies]` gives.
##
## @param manifest the parsed `pep.toml`, which this changes
## @returns nothing, or the problems of the workspace, rendered clang-style:
##   a member that is not a package, is listed twice or is a workspace
##   itself, or a `workspace = true` with nothing to inherit
join_workspace(manifest: Manifest): Result<void, String> {
    var problems = "";
    if (manifest.is_workspace) {
        problems = _load_members(manifest);
    } else {
        var root = _enclosing_workspace(manifest.dir());
        if (root.is_err()) {
            return Result<void, String>.err(root.error());
        }
        if (root.value().is_value()) {
            manifest.workspace_dir = root.value().value().workspace_dir;
            problems = _inherit(manifest, root.value().value());
        } else {
            var errors = Array<ManifestError>();
            for (var d in _all_dependencies(manifest)) {
                if (d.inherits) {
                    errors.append(
                        ManifestError(
                            $"dependency '{d.name}' has 'workspace = true', and no workspace lists this package; give it a source",
                            d.name_span
                        )
                    );
                }
            }
            if (!errors.is_empty) {
                problems = render_manifest_errors(manifest.path, manifest.text, errors);
            }
        }
    }
    return problems.is_empty ? Result<void, String>.ok() : Result<void, String>.err(problems);
}

## `manifest`'s dependencies and dev-dependencies.
_all_dependencies(manifest: Manifest): Dependency[] {
    var named = manifest.dependencies.clone();
    named.append_all(manifest.dev_dependencies);
    return named;
}

## The workspace above `dir` that lists it: the nearest folder above it
## whose `pep.toml` has `[workspace]`, read with its members, when one of
## them is `dir`. None past a `.pep` folder: a fetched package is in no
## workspace of the project's.
_enclosing_workspace(dir: Path): Result<Manifest?, String> {
    var at = files.absolute(dir).normalize();
    var key = at.to_string();
    while (true) {
        var parent = at.parent();
        if (!parent.is_value() or parent.value().to_string() == at.to_string()) {
            return Result<Manifest?, String>.ok(Optional<Manifest>.Empty);
        }
        var name = at.file_name();
        if (name.is_value() and name.value() == ".pep") {
            return Result<Manifest?, String>.ok(Optional<Manifest>.Empty);
        }
        at = parent.value();
        var file = at.join(Path(files.MANIFEST_FILE));
        var text = File.read_to_string(file);
        # Only a `pep.toml` that may have the table is parsed.
        if (text.is_err() or !text.value().contains("[workspace")) {
            continue;
        }
        var root = _read_manifest(file);
        if (root.is_err()) {
            return Result<Manifest?, String>.err(root.error());
        }
        if (!root.value().is_workspace) {
            continue;
        }
        var problems = _load_members(root.value());
        if (!problems.is_empty) {
            return Result<Manifest?, String>.err(problems);
        }
        for (var member in root.value().member_manifests) {
            if (member.dir().to_string() == key) {
                return Result<Manifest?, String>.ok(Optional<Manifest>.Value(root.value()));
            }
        }
        return Result<Manifest?, String>.ok(Optional<Manifest>.Empty);
    }
    return Result<Manifest?, String>.ok(Optional<Manifest>.Empty);
}

## Reads the members of `root`, a workspace's root, into its
## `member_manifests`, and fills in the `workspace = true` dependencies of
## each and of the root. A member is a folder or a glob of folders
## (`crates/*`), relative to the root; the root itself, when a package,
## is one without being listed.
##
## @returns the problems, rendered clang-style; empty when there are none
_load_members(root: Manifest): String {
    var root_dir = files.absolute(root.dir()).normalize();
    root.workspace_dir = Optional<Path>.Value(root_dir);
    var errors = Array<ManifestError>();
    var others = _inherit(root, root);
    var seen = HashSet<String>();
    for (var i in 0..root.members.count) {
        var pattern = root.members[i];
        var at = root.member_spans[i];
        var dirs = Array<Path>();
        if (pattern.contains("*") or pattern.contains("?") or pattern.contains("[") or pattern.contains("{")) {
            # The glob's separators are `/` on every platform.
            for (var found in io.glob(root_dir.to_string().replace("\\", "/") + "/" + pattern)) {
                if (found.is_directory()) {
                    dirs.append(found.normalize());
                }
            }
        } else {
            dirs.append(root_dir.join(Path(pattern)).normalize());
        }
        for (var dir in dirs) {
            if (dir.to_string() == root_dir.to_string()) {
                continue;
            }
            if (!seen.insert(dir.to_string())) {
                errors.append(ManifestError($"workspace member '{pattern}' is listed twice", at));
                continue;
            }
            var file = dir.join(Path(files.MANIFEST_FILE));
            if (!file.is_file()) {
                errors.append(ManifestError($"workspace member '{pattern}' is not a package: no {file}", at));
                continue;
            }
            var member = _read_manifest(file);
            if (member.is_err()) {
                others += member.error();
                continue;
            }
            if (member.value().is_workspace) {
                errors.append(
                    ManifestError($"workspace member '{pattern}' is a workspace itself; workspaces do not nest", at)
                );
                continue;
            }
            member.value().workspace_dir = root.workspace_dir;
            others += _inherit(member.value(), root);
            root.member_manifests.append(member.value());
        }
    }
    var problems = errors.is_empty ? "" : render_manifest_errors(root.path, root.text, errors);
    return problems + others;
}

## Fills in each `workspace = true` dependency of `manifest` from the
## entry of the same name in `root`'s `[workspace.dependencies]`; a
## `path` there is relative to the root.
##
## @returns the problems, rendered clang-style; empty when there are none
_inherit(manifest: Manifest, root: Manifest): String {
    var errors = Array<ManifestError>();
    for (var d in _all_dependencies(manifest)) {
        if (!d.inherits) {
            continue;
        }
        var from = _named(root.workspace_dependencies, d.name);
        if (!from.is_value()) {
            errors.append(
                ManifestError(
                    $"dependency '{d.name}' has 'workspace = true', and '[workspace.dependencies]' of {root.path} has no '{d.name}'",
                    d.name_span
                )
            );
            continue;
        }
        d.host = from.value().host;
        d.location = from.value().location;
        d.member = from.value().member;
        d.has_version = from.value().has_version;
        if (!d.host.is_value()) {
            d.location = files.absolute(root.dir()).join(Path(d.location)).normalize().to_string();
        }
    }
    return errors.is_empty ? "" : render_manifest_errors(manifest.path, manifest.text, errors);
}

## The 1-based line and column of byte `offset` in `text`.
export line_column(text: String, offset: ulong): (ulong, ulong) {
    ulong line = 1;
    ulong line_start = 0;
    ulong i = 0;
    while (i < offset and i < text.size) {
        if (text.byte_at(i) == '\n') {
            line += 1;
            line_start = i + 1;
        }
        i += 1;
    }
    return (line, i - line_start + 1);
}

## What `Packages.resolve` found for `import name`.
export enum Resolution {
    ## The first part of the name is not a dependency of the importing
    ## file's package: search the search paths.
    NotADependency,
    ## The module's `module.pep`.
    Found(path: Path),
    ## A dependency names it, but its module is not on disk, or the
    ## importing file's `pep.toml` cannot be used: what is wrong.
    Missing(message: String),
}

## The packages of a program: which `pep.toml` each file falls under, and
## where the dependencies it names are.
export struct Packages {
    ## The project's root folder: the package whose files see its
    ## dev-dependencies and whose features `--features` turns on.
    var project: Path?;
    ## The folder whose `.pep/deps` holds fetched dependencies: the
    ## project's workspace's root, else the project's own.
    var deps_root: Path?;
    ## Whether the project's own files see its `[dev-dependencies]`: in a
    ## test build, and a build of a file in its `examples` folder.
    var dev: bool = false;
    ## What the program is built for, which picks the
    ## `[target.'<condition>'.dependencies]` it sees.
    var target: Target = Target();
    ## Folder -> the manifest governing it, or why it could not be used, or
    ## Empty when none does.
    var _by_dir: HashMap<String, Result<Manifest, String>?> = HashMap<String, Result<Manifest, String>?>();
    ## `<package folder>\n<feature>` for each feature turned on.
    var _enabled: HashSet<String> = HashSet<String>();
    ## `<package folder>\n<dependency>` for each dependency turned on.
    var _on: HashSet<String> = HashSet<String>();
    ## The package folders whose dependencies are turned on.
    var _visited: HashSet<String> = HashSet<String>();
    ## The first feature a dependency asks for that its package lacks.
    var _feature_error: String? = Optional<String>.Empty;

    ## The packages of a program rooted at the file `root`.
    ##
    ## @param root the program's root file
    ## @param target what it is built for: a test build (`TEST_BUILD_OPTION`)
    ##   sees the project's dev-dependencies, as a build of a file in its
    ##   `examples` folder does
    construct(root: Path, target: Target = Target()) {
        this.target = target;
        project = files.find_project(root);
        deps_root = project;
        if (project.is_value()) {
            var manifest = _manifest_at(project.value());
            if (manifest.is_value()) {
                deps_root = Optional<Path>.Value(manifest.value().deps_root());
            }
        }
        dev = target.build_options.contains(TEST_BUILD_OPTION)
            or (project.is_value() and _in_examples(project.value(), root));
    }

    ## Turns on the features the build asks for, and those they and every
    ## dependency turned on ask for in turn, across the whole graph: the
    ## project's package's `target.features`, with its `default` feature
    ## unless `target.default_features` is false; each dependency's
    ## `features`, with its `default` unless `default-features = false`;
    ## and what each feature on lists. Each feature on defines its build
    ## option (`Manifest.build_option`) in `target`, and an optional
    ## dependency is seen (`resolve`) only once a feature turns it on. A
    ## dependency not on disk yet is skipped. The workspace members
    ## `target.members` names are built with the project, so their
    ## features are unified with its: their defaults and dependencies are
    ## turned on too, and `target.features` in each that has them.
    ##
    ## @returns nothing, or why a feature cannot be turned on
    turn_on_features(): Result<void, String> {
        if (!project.is_value()) {
            if (!target.features.is_empty) {
                return Result<void, String>.err(
                    $"'--features' turns on features of a project's package, and there is no {files.MANIFEST_FILE} here"
                );
            }
            return Result<void, String>.ok();
        }
        var root = _manifest_at(project.value());
        if (!root.is_value()) {
            return Result<void, String>.ok();
        }
        var manifest = root.value();
        var built = [manifest];
        var workspace = _manifest_at(deps_root.value());
        if (!target.members.is_empty and workspace.is_value()) {
            for (var member in workspace.value().workspace_packages()) {
                if (target.members.contains(member.name) and _key(member) != _key(manifest)) {
                    built.append(member);
                }
            }
        }
        for (var package in built) {
            _visit(package);
            if (target.default_features and package.feature("default").is_value()) {
                _enable(package, "default");
            }
        }
        for (var name in target.features) {
            var found = false;
            for (var package in built) {
                if (package.feature(name).is_value()) {
                    _enable(package, name);
                    found = true;
                }
            }
            if (!found) {
                var known = Array<String>();
                for (var f in manifest.features) {
                    known.append($"'{f.name}'");
                }
                return Result<void, String>.err(
                    $"unknown feature '{name}' in '--features': package '{manifest.name}' has "
                        + (known.is_empty ? "no features" : ", ".join(known))
                );
            }
        }
        if (_feature_error.is_value()) {
            return Result<void, String>.err(_feature_error.value());
        }
        return Result<void, String>.ok();
    }

    ## The manifest in `dir` itself, when it has one that parses.
    _manifest_at(dir: Path): Manifest? {
        if (!dir.join(Path(files.MANIFEST_FILE)).is_file()) {
            return Optional<Manifest>.Empty;
        }
        var found = _manifest_for(dir);
        if (!found.is_value() or found.value().is_err()) {
            return Optional<Manifest>.Empty;
        }
        return Optional<Manifest>.Value(found.value().value());
    }

    ## Turns on the dependencies of `manifest` that are not optional (and
    ## the project's dev-dependencies, in a dev build).
    _visit(manifest: Manifest) {
        var key = _key(manifest);
        if (!_visited.insert(key)) {
            return;
        }
        var named = manifest.dependencies.copy();
        if (dev and key == project.value().normalize().to_string()) {
            named.append_all(manifest.dev_dependencies);
        }
        for (var d in named) {
            if (!d.optional) {
                _turn_on(manifest, d);
            }
        }
    }

    ## Turns on `d`, a dependency of `manifest`, with the features it asks
    ## for, when the build's target sees it; returns its manifest, when it
    ## is on disk.
    _turn_on(manifest: Manifest, d: Dependency): Manifest? {
        if (!d.matches(target)) {
            return Optional<Manifest>.Empty;
        }
        var first = _on.insert(_key(manifest) + "\n" + d.name);
        var found = _manifest_at(_directory(manifest, d));
        if (found.is_value() and first) {
            _visit(found.value());
            if (d.default_features and found.value().feature("default").is_value()) {
                _enable(found.value(), "default");
            }
            for (var i in 0..d.features.count) {
                _enable_in(found.value(), d.features[i], manifest, d.feature_spans[i]);
            }
        }
        return found;
    }

    ## Turns on `feature` of `package`, which `manifest` asks for at `at`;
    ## a feature `package` lacks is the error.
    _enable_in(package: Manifest, feature: String, manifest: Manifest, at: Span) {
        if (package.feature(feature).is_value()) {
            _enable(package, feature);
        } else if (!_feature_error.is_value()) {
            var message = $"package '{package.name}' has no feature '{feature}'";
            _feature_error = Optional<String>.Value(
                render_manifest_errors(manifest.path, manifest.text, [ManifestError(message, at)])
            );
        }
    }

    ## Turns on `name`, a feature of `manifest`, and what it lists.
    _enable(manifest: Manifest, name: String) {
        if (!_enabled.insert(_key(manifest) + "\n" + name)) {
            return;
        }
        target.build_options[manifest.build_option(name)] = "1";
        var feature = manifest.feature(name).value();
        for (var i in 0..feature.enables.count) {
            var item = feature.enables[i];
            var split = item.split_once("/");
            if (item.starts_with("dep:")) {
                _turn_on(manifest, manifest.dependency(item.substr_bytes(4, item.size - 4)).value());
            } else if (split.is_value()) {
                var (dependency, inner) = split.value();
                var found = _turn_on(manifest, manifest.dependency(dependency).value());
                if (found.is_value()) {
                    _enable_in(found.value(), inner, manifest, feature.spans[i]);
                }
            } else {
                _enable(manifest, item);
            }
        }
    }

    ## Where `d`, a dependency of `manifest`, is: as the project's own
    ## `[overrides]` place it (`Manifest.directory_of`).
    ## A workspace member's folder is the one its repository's checkout
    ## lists with its name.
    _directory(manifest: Manifest, d: Dependency): Path {
        # In a workspace, only the root's `[overrides]` apply.
        var root = _manifest_at(deps_root.value());
        if (root.is_value() and (d.member.is_empty or root.value().path_override(d).is_value())) {
            return root.value().directory_of(d, manifest.dir());
        }
        var checkout = d.directory(deps_root.value(), manifest.dir());
        if (d.member.is_empty) {
            return checkout;
        }
        var workspace = _manifest_at(checkout);
        if (workspace.is_value()) {
            for (var member in workspace.value().member_manifests) {
                if (member.name == d.member) {
                    return member.dir();
                }
            }
        }
        # Not fetched, or no such member, which `pepper package` reports.
        return checkout.join(Path(d.member));
    }

    ## Reads `manifest`'s `path` dependencies with a `version` as a
    ## dependent sees them when it is a fetched package of a workspace, in
    ## `.pep/deps`: each names a package of that workspace, published by
    ## its own tags, so it becomes the dependency on that member (or the
    ## root) of the same repository, which `pep.lock` locks on its own.
    _as_fetched(manifest: Manifest) {
        if (!manifest.workspace_dir.is_value() or !deps_root.is_value()) {
            return;
        }
        var checkout = manifest.workspace_dir.value();
        var deps = files.absolute(deps_root.value()).join(Path(".pep")).join(Path(DEPS_DIR)).normalize();
        var prefix = deps.to_string().replace("\\", "/") + "/";
        var inside = checkout.to_string().replace("\\", "/");
        if (!inside.starts_with(prefix)) {
            return;
        }
        # `<host domain>/<owner>/<name>[#<member>]`.
        var split = inside.substr_bytes(prefix.size, inside.size - prefix.size).split_once("/");
        if (!split.is_value()) {
            return;
        }
        var (domain, repository) = split.value();
        Host? host = Optional<Host>.Empty;
        for (var candidate in all_hosts()) {
            if (candidate.domain() == domain) {
                host = Optional<Host>.Value(candidate);
            }
        }
        var own = repository.split_once("#");
        if (own.is_value()) {
            repository = own.value().0;
        }
        var root = files.absolute(manifest.dir()).normalize().to_string() == checkout.to_string() ?
            Optional<Manifest>.Value(manifest) :
            _manifest_at(checkout);
        if (!host.is_value() or !root.is_value()) {
            return;
        }
        for (var d in manifest.dependencies) {
            if (d.host.is_value() or !d.has_version) {
                continue;
            }
            var folder = files.absolute(manifest.dir()).join(Path(d.location)).normalize().to_string();
            String? member = folder == checkout.to_string() ?
                Optional<String>.Value("") :
                Optional<String>.Empty;
            for (var m in root.value().member_manifests) {
                if (files.absolute(m.dir()).normalize().to_string() == folder) {
                    member = Optional<String>.Value(m.name);
                }
            }
            if (member.is_value()) {
                d.host = host;
                d.location = repository;
                d.member = member.value();
            }
        }
    }

    ## A package's key in the feature sets: its normalized folder.
    _key(manifest: Manifest): String {
        return manifest.dir().normalize().to_string();
    }

    _manifest_for(dir: Path): Result<Manifest, String>? {
        var key = dir.to_string();
        if (_by_dir.contains(key)) {
            return _by_dir[key];
        }
        var found = Optional<Result<Manifest, String>>.Empty;
        var path = dir.join(Path(files.MANIFEST_FILE));
        if (path.is_file()) {
            var text = File.read_to_string(path);
            if (text.is_err()) {
                found = Optional<Result<Manifest, String>>.Value(
                    Result<Manifest, String>.err($"cannot read {path}: {text.error().message}")
                );
            } else {
                var parsed = parse_manifest(path, text.value());
                if (parsed.is_err()) {
                    var first = parsed.error()[0];
                    var (line, column) = line_column(text.value(), first.span.start);
                    found = Optional<Result<Manifest, String>>.Value(
                        Result<Manifest, String>.err($"{path}:{line}:{column}: {first.message}")
                    );
                } else {
                    # shortcut: each member reads its workspace's root again; cache the root when
                    # workspaces grow large.
                    var joined = join_workspace(parsed.value());
                    if (joined.is_ok()) {
                        _as_fetched(parsed.value());
                    }
                    found = Optional<Result<Manifest, String>>.Value(
                        joined.is_err() ?
                            Result<Manifest, String>.err(joined.error()) :
                            Result<Manifest, String>.ok(parsed.value())
                    );
                }
            }
        } else {
            var parent = dir.parent();
            if (parent.is_value() and parent.value().to_string() != dir.to_string()) {
                found = _manifest_for(parent.value());
            }
        }
        _by_dir[key] = found;
        return found;
    }

    ## `import name` (`a`, or `a.b.c` for a module inside a package) in the
    ## file `from`: when `a` is a dependency of `from`'s package, the module
    ## `a` names there (its root `module.pep`, or `b/c/module.pep` inside
    ## it).
    ##
    ## @param from the importing file
    ## @param name the module name
    ## @returns what it resolves to
    resolve(from: Path, name: String): Resolution {
        if (!project.is_value()) {
            return Resolution.NotADependency;
        }
        var file = from;
        if (!file.is_absolute()) {
            var cwd = process.working_directory();
            if (cwd.is_ok()) {
                file = cwd.value().join(from).normalize();
            }
        }
        var governing = _manifest_for(files.dir_of(file));
        if (!governing.is_value()) {
            return Resolution.NotADependency;
        }
        if (governing.value().is_err()) {
            return Resolution.Missing(governing.value().error());
        }
        var manifest = governing.value().value();
        var parts = name.split(".");
        var first = parts[0];
        var dependency = manifest.dependency(first);
        if (!dependency.is_value()) {
            dependency = manifest.dev_dependency(first);
            if (!dependency.is_value()) {
                return Resolution.NotADependency;
            }
            if (manifest.dir().normalize().to_string() != project.value().normalize().to_string()) {
                return Resolution.Missing(
                    $"'{first}' is a dev-dependency of the package '{manifest.name}', which only its own tests and examples import"
                );
            }
            if (!dev) {
                return Resolution.Missing(
                    $"'{first}' is a dev-dependency, which only tests and the files in examples/ import; move it to '[dependencies]' to import it here"
                );
            }
        } else if (!dependency.value().matches(target)) {
            var condition = dependency.value().target;
            return Resolution.Missing(
                $"'{first}' is a dependency only for targets where '{condition}' holds, which this build's does not; put '[Target({condition})]' on the import"
            );
        } else if (dependency.value().optional and !_on.contains(_key(manifest) + "\n" + first)) {
            return Resolution.Missing(
                $"'{first}' is an optional dependency, which no feature this build turns on lists; put the '[BuildOption(...)]' of a feature that lists 'dep:{first}' on the import"
            );
        }
        var package = _directory(manifest, dependency.value());
        if (!package.is_directory()) {
            if (dependency.value().host.is_value()) {
                return Resolution.Missing(
                    $"dependency '{first}' is not fetched: no {package}; run 'pepper package fetch'"
                );
            }
            return Resolution.Missing($"dependency '{first}' names the folder {package}, which does not exist");
        }
        var module = package;
        ulong i = 1;
        while (i < parts.count) {
            module = module.join(Path(parts[i]));
            i += 1;
        }
        var module_file = module.join(Path(files.MODULE_FILE));
        if (module_file.is_file()) {
            return Resolution.Found(module_file);
        }
        if (parts.count == 1) {
            return Resolution.Missing($"package '{first}' has no root module: no {module_file}");
        }
        return Resolution.Missing($"package '{first}' has no module '{name}': no {module_file}");
    }
}

## Whether `file` is in the `examples` folder of the project at `project`,
## or a folder below it.
_in_examples(project: Path, file: Path): bool {
    var absolute = file;
    if (!absolute.is_absolute()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            absolute = cwd.value().join(file).normalize();
        }
    }
    var at = files.dir_of(absolute);
    while (true) {
        var parent = at.parent();
        if (!parent.is_value() or parent.value().to_string() == at.to_string()) {
            return false;
        }
        if (parent.value().to_string() == project.to_string()) {
            var name = at.file_name();
            return name.is_value() and name.value() == "examples";
        }
        at = parent.value();
    }
    return false;
}

## The `pep.toml` nearest `dir`: in it, or in the closest folder above it
## that has one.
export find_manifest(dir: Path): Path? {
    var start = dir;
    if (!start.is_absolute()) {
        var cwd = process.working_directory();
        if (cwd.is_ok()) {
            start = cwd.value().join(dir).normalize();
        }
    }
    Path? at = Optional<Path>.Value(start);
    while (at.is_value()) {
        var candidate = at.value().join(Path(files.MANIFEST_FILE));
        if (candidate.is_file()) {
            return Optional<Path>.Value(candidate);
        }
        var parent = at.value().parent();
        if (!parent.is_value() or parent.value().to_string() == at.value().to_string()) {
            break;
        }
        at = parent;
    }
    return Optional<Path>.Empty;
}

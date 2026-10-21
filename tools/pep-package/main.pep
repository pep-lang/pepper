# pep-package: the package manager, run as `pepper package`. It reads a
# project's pep.toml, fetches its dependencies with git (or, without git,
# as the host's archive of each locked commit) into the project's
# `.pep/deps`, and records the exact revision of each in pep.lock.
#
#     pepper package fetch                      # what pep.lock lists, resolving pep.toml's changes
#     pepper package add someone/geometry       # the newest version, as 'geometry'
#     pepper package add other/json@2.x --name fast_json
#     pepper package add --dev someone/fixtures  # only for tests and examples
#     pepper package add --target 'OS(Windows)' someone/winapi  # only on Windows
#     pepper package remove geometry
#     pepper package update [geometry]          # newer versions the ranges allow
#     pepper package update --verify            # one at a time, keeping those that build
#     pepper package fetch --locked             # fail rather than change pep.lock
#     pepper package fetch --offline            # only what .pep/deps holds; --frozen is both
#     pepper package fetch github:someone/geometry  # only that locked package, without resolving
#
# Build it from the repository root; its pep.toml names the toml package it
# needs, which `pepper build` fetches:
#
#     pepper build tools/pep-package/main.pep -o pep-package

import cli;
import [Directory, File, Path] from io;
import os;
import process;
import [parse_range] from semver;
import syntax;
import toml;
import "git";
import "lock";
import "manifest";
import "resolve";

# The release this tool belongs to. `pep-doc check` keeps it equal to the
# version in VERSION.
version(): String {
    return "0.11.0-dev";
}

main(args: String[]): int {
    var parser = cli.Parser(
        "pep-package", "Fetches a project's dependencies and keeps pep.toml and pep.lock.", version = version()
    );
    var directory = parser.option(
        "directory",
        "C",
        "the project: a folder at or below its pep.toml (default: the current one)",
        value_name = "DIR"
    );
    var locked = parser.flag(
        "locked",
        help = "fail, leaving pep.lock as it is, when the command would change it (also PEPPER_LOCKED=1)",
        global = true
    );
    var offline = parser.flag(
        "offline",
        help = "use only what .pep/deps holds, and fail on what needs the network (also PEPPER_OFFLINE=1)",
        global = true
    );
    var frozen = parser.flag("frozen", help = "both --locked and --offline", global = true);
    var fetch = parser.command("fetch", "Fetches what pep.lock lists, resolving what pep.toml changed since");
    var fetch_packages = fetch.positionals(
        "packages",
        "only these locked packages (their sources, github:owner/name), at the commits pep.lock records, without resolving: what a build fetches for its target"
    );
    var add = parser.command("add", "Adds a dependency at its newest version, or at a range given after @");
    var add_package = add.positional(
        "package", "[host:]owner/name[@range]; without a host, the first of pep.toml's [fetch] hosts that has it"
    );
    var add_name = add.option(
        "name", "n", "the name source code imports it by (default: the repository's name)", value_name = "NAME"
    );
    var add_dev = add.flag(
        "dev", help = "add it to [dev-dependencies], which only the project's tests and examples import"
    );
    var add_target = add.option(
        "target",
        "t",
        "add it to [target.'CONDITION'.dependencies], which only builds for the targets CONDITION selects use; CONDITION is what [Target(...)] takes, such as OS(Windows)",
        value_name = "CONDITION"
    );
    var remove = parser.command("remove", "Removes a dependency");
    var remove_package = remove.positional("package", "the dependency's name, or its owner/name");
    var update = parser.command("update", "Moves dependencies to the newest versions their ranges allow");
    var update_packages = update.positionals("packages", "the dependencies to update (default: every one)");
    var verify = update.flag(
        "verify", help = "update one dependency at a time and build after each, keeping only the updates that build"
    );
    if (!parser.parse(args)) {
        return 2;
    }
    var start = directory.is_set ? Path(directory.value()) : Path(".");
    var found = find_manifest(start);
    if (found.is_empty()) {
        return fail($"no pep.toml in {start.to_string()} or a folder above it");
    }
    var project = Project(found.value());
    project.locked = locked.is_set or frozen.is_set or os.environment_flag("PEPPER_LOCKED");
    project.offline = offline.is_set or frozen.is_set or os.environment_flag("PEPPER_OFFLINE");
    if (fetch.is_selected) {
        return fetch_packages.values().is_empty ? project.fetch() : project.fetch_locked(fetch_packages.values());
    }
    if (add.is_selected) {
        if (add_dev.is_set and add_target.is_set) {
            return fail("--dev and --target name different tables; give one");
        }
        return project.add(add_package.value(), add_name.value_or(""), add_dev.is_set, add_target.value_or(""));
    }
    if (remove.is_selected) {
        return project.remove(remove_package.value());
    }
    if (update.is_selected) {
        return verify.is_set ?
            project.update_verified(update_packages.values()) :
            project.update(update_packages.values());
    }
    print(parser.help());
    return 2;
}

# Prints `message` as an error; returns the exit status for one.
fail(message: String): int {
    File.stderr().write_all($"pep-package: error: {message}\n");
    return 1;
}

# Prints `message` as progress.
say(message: String) {
    File.stderr().write_all($"pep-package: {message}\n");
}

# The runtime modules, which a dependency may not be named like: the
# folders with a `module.pep` in the runtime the compiler would find.
runtime_has_module(name: String): bool {
    var candidates = Array<Path>();
    var variable = os.environment("PEPPER_RUNTIME");
    if (variable.is_value() and !variable.value().is_empty) {
        candidates.append(Path(variable.value()));
    } else {
        var executable = process.executable_path();
        if (executable.is_ok() and executable.value().parent().is_value()) {
            var dir = executable.value().parent().value();
            candidates.append(dir.join("runtime"));
            for (var level in 0..5) {
                dir = dir.join("..");
                candidates.append(dir.join("runtime"));
            }
        }
    }
    for (var dir in candidates) {
        if (dir.join(name).join("module.pep").is_file()) {
            return true;
        }
    }
    return false;
}

# The default name of a dependency on `repository`: its last part, with
# what an identifier cannot hold turned into `_`.
default_name(repository: String): String {
    var parts = repository.split("/");
    var name = parts[parts.count - 1];
    if (name.ends_with(".pep")) {
        name = name.substr(0, name.length - 4);
    }
    return syntax.to_identifier(name);
}

# A project: its pep.toml, pep.lock and `.pep/deps`.
struct Project {
    var manifest_path: Path = Path("pep.toml");
    var dir: Path = Path(".");
    # `--locked`: fail rather than change pep.lock.
    var locked: bool = false;
    # `--offline`: use only what `.pep/deps` holds.
    var offline: bool = false;

    construct(manifest_path: Path) {
        this.manifest_path = manifest_path;
        var parent = manifest_path.parent();
        dir = parent.is_value() ? parent.value() : Path(".");
    }

    # Resolves the graph, keeping locked revisions unless `update_all` or
    # `update` names them, checks every package out and writes pep.lock.
    # Returns the graph, or prints why it failed.
    _resolve(update_all: bool, update: Array<String>): Result<Graph> {
        var manifest = read_manifest(manifest_path);
        if (manifest.is_err()) {
            return Result<Graph>.Err(manifest.error().message);
        }
        var previous = read_lock(lock_path(dir));
        if (previous.is_err()) {
            return Result<Graph>.Err(previous.error().message);
        }
        var resolver = Resolver(dir, manifest.value(), previous.value());
        resolver.update_all = update_all;
        resolver.update = update;
        resolver.offline = offline;
        resolver.toolchain = version();
        var graph = resolver.resolve();
        if (graph.is_err()) {
            return graph;
        }
        var changes = _changes(previous.value(), graph.value().packages);
        # Unchanged, pep.lock is left as it is, line endings and all.
        if (lock_text(graph.value().packages) == lock_text(previous.value())) {
            return graph;
        }
        if (locked) {
            return Result<Graph>.Err(
                "pep.lock would change, and --locked keeps it as it is:\n  "
                    + "\n  ".join(changes)
                    + "\nrun the command without --locked (or PEPPER_LOCKED), then commit pep.lock"
            );
        }
        var written = write_lock(lock_path(dir), graph.value().packages);
        if (written.is_err()) {
            return Result<Graph>.Err(written.error().message);
        }
        for (var change in changes) {
            say(change);
        }
        return graph;
    }

    # What changed between two locks, one line each.
    _changes(before: Array<Locked>, after: Array<Locked>): Array<String> {
        var lines = Array<String>();
        for (var locked in after) {
            var old = Optional<Locked>.Empty;
            for (var candidate in before) {
                if (candidate.source == locked.source) {
                    old = Optional<Locked>.Value(candidate);
                }
            }
            if (old.is_empty()) {
                lines.append($"added {locked.describe()} ({locked.source})");
            } else if (old.value().commit != locked.commit) {
                lines.append($"updated {locked.name}: {old.value().describe()} -> {locked.describe()}");
            } else if (lock_text([old.value()]) != lock_text([locked])) {
                lines.append($"rewrote the entry of {locked.describe()} ({locked.source})");
            }
        }
        for (var locked in before) {
            var kept = false;
            for (var candidate in after) {
                if (candidate.source == locked.source) {
                    kept = true;
                }
            }
            if (!kept) {
                lines.append($"removed {locked.describe()} ({locked.source})");
            }
        }
        return lines;
    }

    fetch(): int {
        # The locked packages not on disk yet, to say they were fetched.
        var missing = Array<Locked>();
        var locked = read_lock(lock_path(dir));
        if (locked.is_ok()) {
            for (var package in locked.value()) {
                var (host, repository) = split_source(package.source);
                if (!package_dir(dir, host, repository).is_directory()) {
                    missing.append(package);
                }
            }
        }
        var graph = _resolve(false, Array<String>());
        if (graph.is_err()) {
            return fail(graph.error().message);
        }
        for (var package in graph.value().packages) {
            for (var was in missing) {
                if (was.source == package.source and was.commit == package.commit) {
                    say($"fetched {package.describe()} ({package.source})");
                }
            }
        }
        _notes(graph.value());
        return 0;
    }

    # Fetches the locked packages `sources` names at their locked commits,
    # resolving nothing: a build that needs only them (its target's) and
    # whose pep.lock lists every dependency.
    fetch_locked(sources: Array<String>): int {
        var locked = read_lock(lock_path(dir));
        if (locked.is_err()) {
            return fail(locked.error().message);
        }
        var resolver = Resolver(dir, Manifest(), locked.value());
        resolver.offline = offline;
        for (var source in sources) {
            var found = Optional<Locked>.Empty;
            for (var package in locked.value()) {
                if (package.source == source) {
                    found = Optional<Locked>.Value(package);
                }
            }
            if (found.is_empty()) {
                return fail($"pep.lock does not list '{source}'");
            }
            var (host, repository) = split_source(source);
            var package = package_dir(dir, host, repository);
            var was_there = package.is_directory();
            var fetched = resolver.fetch(host, repository, package, found.value().commit);
            if (fetched.is_err()) {
                return fail($"cannot fetch {source}: {fetched.error().message}");
            }
            if (!was_there) {
                say($"fetched {found.value().describe()} ({source})");
            }
        }
        return 0;
    }

    add(spec: String, given_name: String, dev: bool, target: String): int {
        if (offline) {
            return fail(
                $"--offline, and adding '{spec}' reads which versions it offers over the network; run 'pepper package add' without --offline (or PEPPER_OFFLINE)"
            );
        }
        var host = "";
        var rest = spec;
        var prefixed = spec.split_once(":");
        if (prefixed.is_value() and is_host(prefixed.value().0)) {
            host = prefixed.value().0;
            rest = prefixed.value().1;
        }
        var range = "";
        var at = rest.split_once("@");
        if (at.is_value()) {
            rest = at.value().0;
            range = at.value().1;
            var parsed = parse_range(range);
            if (parsed.is_err()) {
                return fail(parsed.error().message);
            }
        }
        var parts = rest.split("/");
        if (parts.count < 2 or (parts.count > 2 and host != "gitlab" and !host.is_empty) or parts.contains("")) {
            return fail($"'{spec}' must name a repository as owner/name");
        }
        var name = given_name.is_empty ? default_name(rest) : given_name;
        if (!syntax.is_identifier(name)) {
            return fail($"'{name}' is not a name 'import' can use; give one with --name");
        }
        var manifest = read_manifest(manifest_path);
        if (manifest.is_err()) {
            return fail(manifest.error().message);
        }
        var taken = manifest.value().requirement(name);
        if (taken.is_value()) {
            return fail(
                $"a dependency named '{name}' already exists ({taken.value().source()}); add this one with --name"
            );
        }
        if (runtime_has_module(name)) {
            return fail($"'{name}' is the name of a runtime module; add the dependency with --name");
        }
        var refs = Array<RemoteRef>();
        if (host.is_empty) {
            var found = _look_up(rest, manifest.value().hosts);
            if (found.is_err()) {
                return fail(found.error().message);
            }
            var (found_host, found_refs) = found.value();
            host = found_host;
            refs = found_refs;
        } else if (range.is_empty) {
            var read = remote_refs(repository_url(host, rest));
            if (read.is_err()) {
                return fail($"cannot read {host}:{rest}: {read.error().message}");
            }
            refs = read.value();
        }
        # With no range, any release resolves, and pep.toml then names the
        # one chosen (the newest this toolchain builds) as a caret range;
        # with no version tags, the default branch.
        var pin = false;
        if (range.is_empty) {
            for (var ref in refs) {
                if (ref.name.starts_with("refs/tags/")) {
                    var version = tag_version(ref.name.substr(10, ref.name.length));
                    if (version.is_value() and version.value().prerelease.is_empty) {
                        pin = true;
                    }
                }
            }
            if (pin) {
                range = "*";
            }
        }
        var entry = toml.TomlValue.table();
        entry[host] = toml.TomlValue.String(rest);
        if (!range.is_empty) {
            entry["version"] = toml.TomlValue.String(range);
        }
        var original = manifest.value().text;
        var document = toml.parse_document(original, path = manifest_path.to_string());
        if (document.is_err()) {
            return fail(document.error().to_string());
        }
        var edited = document.value();
        var added = Requirement();
        added.name = name;
        added.dev = dev;
        added.target = target;
        var set = edited.set(added.key(), entry, inline = true);
        if (set.is_err()) {
            return fail(set.error().to_string());
        }
        var written = File.write_text(manifest_path, edited.to_string());
        if (written.is_err()) {
            return fail($"cannot write {manifest_path.to_string()}: {written.error().message}");
        }
        var source = host + ":" + rest;
        var graph = _resolve(false, [source]);
        if (graph.is_err()) {
            # Leave pep.toml as it was.
            File.write_text(manifest_path, original);
            return fail(graph.error().message);
        }
        if (pin) {
            for (var package in graph.value().packages) {
                if (package.source == source) {
                    entry["version"] = toml.TomlValue.String(package.version);
                }
            }
            var reset = edited.set(added.key(), entry, inline = true);
            if (reset.is_err()) {
                File.write_text(manifest_path, original);
                return fail(reset.error().to_string());
            }
            var pinned = File.write_text(manifest_path, edited.to_string());
            if (pinned.is_err()) {
                File.write_text(manifest_path, original);
                return fail($"cannot write {manifest_path.to_string()}: {pinned.error().message}");
            }
        }
        _notes(graph.value());
        say($"'import {name};' now imports {host}:{rest}");
        return 0;
    }

    # The first of `hosts` that has `repository`, and what it offers. Says
    # so when another host has it too.
    _look_up(repository: String, hosts: Array<String>): Result<(String, Array<RemoteRef>)> {
        if (!has_git()) {
            return Result<(String, Array<RemoteRef>)>.Err(
                $"git is not on the PATH: looking {repository} up needs it; install git"
            );
        }
        var found = Array<String>();
        var chosen = Array<RemoteRef>();
        var failures = Array<String>();
        for (var host in hosts) {
            # Only GitLab has nested groups.
            if (repository.split("/").count > 2 and host != "gitlab") {
                continue;
            }
            var refs = remote_refs(repository_url(host, repository));
            if (refs.is_err()) {
                failures.append($"{host}: {refs.error().message}");
                continue;
            }
            if (found.is_empty) {
                chosen = refs.value();
            }
            found.append(host);
        }
        if (found.is_empty) {
            var text = $"no host has {repository} (looked on {", ".join(hosts)})";
            for (var failure in failures) {
                text += "\n  " + failure;
            }
            return Result<(String, Array<RemoteRef>)>.Err(text);
        }
        if (found.count > 1) {
            say(
                $"{repository} is on {" and ".join(found)}; adding {found[0]}:{repository} (prefix it with '{found[1]}:' for another)"
            );
        }
        return Result<(String, Array<RemoteRef>)>.Ok((found[0], chosen));
    }

    remove(spec: String): int {
        var manifest = read_manifest(manifest_path);
        if (manifest.is_err()) {
            return fail(manifest.error().message);
        }
        var keys = Array<Array<String>>();
        for (var requirement in manifest.value().requirements) {
            if (requirement.name == spec or requirement.repository == spec or requirement.source() == spec) {
                keys.append(requirement.key());
            }
        }
        if (keys.is_empty) {
            return fail($"pep.toml has no dependency '{spec}'");
        }
        var original = manifest.value().text;
        var document = toml.parse_document(original, path = manifest_path.to_string());
        if (document.is_err()) {
            return fail(document.error().to_string());
        }
        var edited = document.value();
        for (var key in keys) {
            var removed = edited.remove(key);
            if (removed.is_err()) {
                return fail(removed.error().to_string());
            }
        }
        var written = File.write_text(manifest_path, edited.to_string());
        if (written.is_err()) {
            return fail($"cannot write {manifest_path.to_string()}: {written.error().message}");
        }
        var graph = _resolve(false, Array<String>());
        if (graph.is_err()) {
            File.write_text(manifest_path, original);
            return fail(graph.error().message);
        }
        return 0;
    }

    # The sources `specs` name: dependencies of pep.toml by name, owner/name
    # or source, or packages pep.lock lists by name. Fails on one that
    # names nothing.
    _sources(specs: Array<String>): Result<Array<String>> {
        var sources = Array<String>();
        var manifest = read_manifest(manifest_path);
        if (manifest.is_err()) {
            return Result<Array<String>>.Err(manifest.error().message);
        }
        var locked = read_lock(lock_path(dir));
        if (locked.is_err()) {
            return Result<Array<String>>.Err(locked.error().message);
        }
        for (var spec in specs) {
            var found = false;
            for (var requirement in manifest.value().requirements) {
                if (requirement.name == spec or requirement.repository == spec or requirement.source() == spec) {
                    sources.append(requirement.source());
                    found = true;
                }
            }
            for (var package in locked.value()) {
                if (!found
                    and (package.name == spec or package.source == spec or package.source.ends_with(":" + spec))) {
                    sources.append(package.source);
                    found = true;
                }
            }
            if (!found) {
                return Result<Array<String>>.Err($"no dependency '{spec}' in pep.toml or pep.lock");
            }
        }
        return Result<Array<String>>.Ok(sources);
    }

    _notes(graph: Graph) {
        for (var note in graph.notes) {
            say(note);
        }
    }

    update(specs: Array<String>): int {
        var sources = _sources(specs);
        if (sources.is_err()) {
            return fail(sources.error().message);
        }
        var graph = _resolve(specs.is_empty, sources.value());
        if (graph.is_err()) {
            return fail(graph.error().message);
        }
        _notes(graph.value());
        return 0;
    }

    # Updates one dependency at a time, building the project after each,
    # and keeps only the updates that build.
    update_verified(specs: Array<String>): int {
        var sources = _sources(specs);
        if (sources.is_err()) {
            return fail(sources.error().message);
        }
        var chosen = sources.value();
        if (specs.is_empty) {
            var locked = read_lock(lock_path(dir));
            if (locked.is_err()) {
                return fail(locked.error().message);
            }
            for (var package in locked.value()) {
                chosen.append(package.source);
            }
        }
        var rolled_back = Array<String>();
        for (var source in chosen) {
            var before = read_lock(lock_path(dir));
            if (before.is_err()) {
                return fail(before.error().message);
            }
            var graph = _resolve(false, [source]);
            if (graph.is_err()) {
                return fail(graph.error().message);
            }
            var after = read_lock(lock_path(dir)).value();
            if (lock_text(after) == lock_text(before.value())) {
                continue;
            }
            if (_builds()) {
                _notes(graph.value());
                continue;
            }
            say($"{source}: the build failed after updating it; rolling back");
            rolled_back.append(source);
            var restored = write_lock(lock_path(dir), before.value());
            if (restored.is_err()) {
                return fail(restored.error().message);
            }
            var refetched = _resolve(false, Array<String>());
            if (refetched.is_err()) {
                return fail(refetched.error().message);
            }
        }
        if (!rolled_back.is_empty) {
            say("rolled back, because the project did not build with them: " + ", ".join(rolled_back));
        }
        return 0;
    }

    # Whether the project builds: `pep-build` (beside this program, else on
    # the PATH) run in the project's folder with no file.
    _builds(): bool {
        var compiler = "pep-build";
        var executable = process.executable_path();
        if (executable.is_ok() and executable.value().parent().is_value()) {
            var name = Path.separator() == "\\" ? "pep-build.exe" : "pep-build";
            var beside = executable.value().parent().value().join(name);
            if (beside.is_file()) {
                compiler = beside.to_string();
            }
        }
        var built = process.Command(compiler).working_directory(dir).run();
        if (built.is_err()) {
            say($"cannot run {compiler}: {built.error().message}");
            return false;
        }
        if (!built.value().status.success()) {
            File.stderr().write_all(built.value().stderr);
            return false;
        }
        return true;
    }
}

# Resolution: one revision of every package in the dependency graph.
#
# Each package is identified by its source (`github:owner/name`), whatever
# key each dependent imports it by. A version range picks the newest tag
# every dependent accepts; a branch, tag or commit must be the same for
# every dependent. The project's own pep.toml overrides what dependencies
# ask for: when it names a package, only its requirement counts. A locked
# revision is kept while it still satisfies every requirement, unless the
# package is being updated. A range skips each version whose pep.toml's
# `minimum_toolchain` is newer than the toolchain resolving; any other
# revision that needs a newer one is an error. Only the project's own
# `[dev-dependencies]` are in its graph, not those of its dependencies, and
# a package only they lead to is locked as `dev`. Every platform's
# `[target.'<condition>'.dependencies]` are in the graph, so pep.lock is
# the same on each; a package only they lead to is locked with the
# condition under which a build needs it (`target`). The project's
# `[overrides]` replace a package wherever the graph reaches it, whatever
# its dependents ask: a fork's revision is chosen as the override asks and
# checked out where the original's would be, and a `path` override's
# folder is read in its place; either is locked with `override`.

import [Path] from io;
import semver;
import [Version, VersionRange, parse_range] from semver;
import "archive";
import "git";
import "lock";
import "manifest";

# What a dependent asks of a package.
export struct Wanted {
    # Who asks: the project's name, or `geometry 1.2.0`.
    var requirer: String = "";
    # Whether the project's own pep.toml asks it.
    var from_root: bool = false;
    # Whether a dev-dependency of the project leads to it.
    var dev: bool = false;
    # The source of the package whose pep.toml asks; empty for the
    # project's.
    var parent: String = "";
    var requirement: Requirement = Requirement();

    construct() {}

    construct(requirer: String, from_root: bool, dev: bool, parent: String, requirement: Requirement) {
        this.requirer = requirer;
        this.from_root = from_root;
        this.dev = dev;
        this.parent = parent;
        this.requirement = requirement;
    }

    describe(): String {
        return $"{requirer} wants {requirement.describe()}";
    }
}

# A resolved graph: the lock's packages, and notes on packages held back.
export struct Graph {
    var packages: Array<Locked> = __null;
    var notes: Array<String> = __null;
    # Clang-style warnings on pep.toml: overrides that match no package.
    var warnings: Array<String> = __null;

    construct() {
        packages = Array<Locked>();
        notes = Array<String>();
        warnings = Array<String>();
    }
}

# Where a package from `host` lives in the project `project`.
export package_dir(project: Path, host: String, repository: String): Path {
    var dir = project.join(".pep").join("deps").join(host_domain(host));
    for (var part in repository.split("/")) {
        dir = dir.join(part);
    }
    return dir;
}

# The host and repository of a source (`github:owner/name`).
export split_source(source: String): (String, String) {
    var split = source.split_once(":");
    if (split.is_empty()) {
        return ("github", source);
    }
    return split.value();
}

export struct Resolver {
    # The project's root folder.
    var project: Path = Path(".");
    var root: Manifest = Manifest();
    # The lock before this resolution.
    var previous: Array<Locked> = __null;
    # Update every package, rather than keep locked revisions.
    var update_all: bool = false;
    # The sources to update.
    var update: Array<String> = __null;
    # `--offline`: use only what `.pep/deps` holds, and fail on what needs
    # the network.
    var offline: bool = false;
    # The toolchain release resolving, which each package's
    # `minimum_toolchain` is checked against; empty checks none.
    var toolchain: String = "";
    # What each repository offers, read once.
    var _refs: HashMap<String, Array<RemoteRef>> = __null;
    # The `minimum_toolchain` each commit's pep.toml declares, read once.
    var _minimums: HashMap<String, String> = __null;

    construct(project: Path, root: Manifest, previous: Array<Locked>) {
        this.project = project;
        this.root = root;
        this.previous = previous;
        update = Array<String>();
        _refs = HashMap<String, Array<RemoteRef>>();
        _minimums = HashMap<String, String>();
    }

    # Why this toolchain cannot build a package declaring `minimum`; empty
    # when it can.
    _shortfall(minimum: String): String {
        if (minimum.is_empty or toolchain.is_empty) {
            return "";
        }
        var needed = semver.parse(minimum);
        if (needed.is_err()) {
            return $"its minimum_toolchain '{minimum}' is not a version";
        }
        var active = semver.parse(toolchain);
        if (active.is_err() or active.value().compare(needed.value()) >= 0) {
            return "";
        }
        return $"needs toolchain {minimum}";
    }

    # Where the code of `source` comes from: the fork that overrides it, or
    # itself.
    _origin(source: String): String {
        var replacement = root.override_of(source);
        if (replacement.is_value() and !replacement.value().is_path()) {
            return replacement.value().source();
        }
        return source;
    }

    # What pep.lock records `[overrides]` replaces `source` with: the fork's
    # source, or `path:` and the folder; empty when nothing does.
    _replaced_by(source: String): String {
        var replacement = root.override_of(source);
        return replacement.is_value() ? replacement.value().source() : "";
    }

    # The folder holding `source`'s files: a `path` override's, else its
    # checkout in `.pep/deps`.
    _dir(source: String): Path {
        var replacement = root.override_of(source);
        if (replacement.is_value() and replacement.value().is_path()) {
            return project.join(replacement.value().repository);
        }
        var (host, repository) = split_source(source);
        return package_dir(project, host, repository);
    }

    # Fails, at the override's key, when the package `name` that overrides
    # `source` is not the one pep.lock records for it.
    _check_name(source: String, name: String): Result<void> {
        for (var locked in previous) {
            if (locked.source == source and !locked.name.is_empty and locked.name != name) {
                return Result<void>.Err(
                    root.at_override(
                        "error",
                        source,
                        $"'{_replaced_by(source)}' is the package '{name}', not '{locked.name}', which it overrides; name a fork or copy of '{locked.name}'"
                    )
                );
            }
        }
        return Result<void>.ok();
    }

    # The `minimum_toolchain` the pep.toml at `commit` of `source` declares,
    # read from its clone in `.pep/deps` without checking it out.
    _minimum_at(source: String, commit: String): Result<String> {
        var known = _minimums.try_get(commit);
        if (known.is_value()) {
            return Result<String>.Ok(known.value());
        }
        var (host, repository) = split_source(_origin(source));
        var text = file_at(repository_url(host, repository), _dir(source), commit, "pep.toml", offline);
        if (text.is_err()) {
            return Result<String>.Err(
                $"cannot read the pep.toml of {source} {commit.substr(0, 12)}: {text.error().message}"
            );
        }
        var minimum = "";
        if (text.value().is_value()) {
            # One the compiler rejects is its concern, at the build.
            var manifest = parse_manifest(Path("pep.toml"), text.value().value());
            if (manifest.is_ok()) {
                minimum = manifest.value().minimum_toolchain;
            }
        }
        _minimums[commit] = minimum;
        return Result<String>.Ok(minimum);
    }

    # Chooses a revision of every package, checking each out into
    # `.pep/deps` to read its own dependencies.
    resolve(): Result<Graph> {
        var chosen = OrderedMap<String, Locked>();
        var notes = Array<String>();
        for (var round in 0..100) {
            var gathered = _gather(chosen);
            if (gathered.is_err()) {
                return Result<Graph>.Err(gathered.error().message);
            }
            var wanted = gathered.value();
            var changed = false;
            notes = Array<String>();
            for (var (source, asks) in wanted) {
                if (source.starts_with("path:")) {
                    continue;
                }
                var replacement = root.override_of(source);
                if (replacement.is_value() and replacement.value().is_path()) {
                    if (chosen.contains(source)) {
                        continue;
                    }
                    var folder = _dir(source);
                    if (!folder.join("pep.toml").is_file()) {
                        return Result<Graph>.Err(
                            root.at_override(
                                "error", source, $"the folder {folder.to_string()} overriding '{source}' has no pep.toml"
                            )
                        );
                    }
                    var (folder_name, _) = _name_and_minimum(folder, source);
                    var named = _check_name(source, folder_name);
                    if (named.is_err()) {
                        return Result<Graph>.Err(named.error().message);
                    }
                    var local = Locked(folder_name, source, "", "");
                    local.replaced_by = _replaced_by(source);
                    chosen[source] = local;
                    changed = true;
                    continue;
                }
                # An override replaces what every dependent asks.
                var asking = asks;
                if (replacement.is_value()) {
                    asking = [Wanted(root.name, true, false, "", replacement.value())];
                }
                var picked = _choose(source, asking, notes);
                if (picked.is_err()) {
                    return Result<Graph>.Err(picked.error().message);
                }
                var pick = picked.value();
                var had = chosen.try_get(source);
                if (had.is_value() and had.value().commit == pick.commit) {
                    continue;
                }
                var (host, repository) = split_source(source);
                var dir = package_dir(project, host, repository);
                var fetched = fetch(host, repository, dir, pick.commit, _replaced_by(source));
                if (fetched.is_err()) {
                    return Result<Graph>.Err($"cannot fetch {source}: {fetched.error().message}");
                }
                var (commit, sha256) = fetched.value();
                pick.commit = commit;
                pick.sha256 = sha256;
                pick.replaced_by = _replaced_by(source);
                var (name, minimum) = _name_and_minimum(dir, repository);
                if (replacement.is_value()) {
                    var named = _check_name(source, name);
                    if (named.is_err()) {
                        return Result<Graph>.Err(named.error().message);
                    }
                }
                pick.name = name;
                var shortfall = _shortfall(minimum);
                if (!shortfall.is_empty) {
                    var kept = _kept(source);
                    if (kept.is_value() and kept.value().commit == commit) {
                        return Result<Graph>.Err(
                            $"pep.lock holds {pick.describe()} ({source}), which {shortfall}; this is {toolchain}: run 'pepper package update {name}', or use a newer toolchain"
                        );
                    }
                    return Result<Graph>.Err(
                        $"{pick.describe()} ({source}) {shortfall}; this is {toolchain}: choose another revision in pep.toml, or use a newer toolchain"
                    );
                }
                chosen[source] = pick;
                changed = true;
            }
            # A package nothing asks for any more leaves the graph.
            var stale = Array<String>();
            for (var (source, _) in chosen) {
                if (!wanted.contains(source)) {
                    stale.append(source);
                }
            }
            for (var source in stale) {
                chosen.remove(source);
                changed = true;
            }
            if (changed) {
                continue;
            }
            var graph = Graph();
            var targets = lock_targets(wanted);
            for (var (source, locked) in chosen) {
                locked.dev = true;
                for (var ask in wanted[source]) {
                    locked.dev = locked.dev and ask.dev;
                }
                locked.target = targets.try_get(source).value_or("");
                graph.packages.append(locked);
            }
            graph.notes = notes;
            for (var replacement in root.overrides) {
                if (!wanted.contains(replacement.name)) {
                    graph.warnings.append(
                        root.at_override(
                            "warning",
                            replacement.name,
                            $"override of '{replacement.name}' matches no package in the dependency graph"
                        )
                    );
                }
            }
            return Result<Graph>.Ok(graph);
        }
        return Result<Graph>.Err(
            "the dependency graph did not settle; check for packages that require each other in a cycle"
        );
    }

    # Every requirement in the graph, by source: the project's, then those
    # of each package chosen so far (and of folders `path` names). What the
    # project's dependencies lead to is read first, then what only its
    # dev-dependencies do, which is marked `dev`.
    _gather(chosen: OrderedMap<String, Locked>): Result<OrderedMap<String, Array<Wanted>>> {
        var wanted = OrderedMap<String, Array<Wanted>>();
        var name = root.name.is_empty ? "pep.toml" : root.name;
        # Each manifest to read, who it is, whether it is the project's,
        # whether a dev-dependency leads to it, and its source.
        var queue = Array<(Manifest, String, bool, bool, String)>();
        queue.append((root, name, true, false, ""));
        var read = HashSet<String>();
        ulong next = 0;
        var dev_queued = false;
        while (true) {
            if (next == queue.count) {
                if (dev_queued) {
                    break;
                }
                dev_queued = true;
                queue.append((root, name, true, true, ""));
            }
            var (manifest, requirer, from_root, dev, parent) = queue[next];
            next += 1;
            for (var requirement in manifest.requirements) {
                # The project's dev-dependencies once, last; never another
                # package's.
                if (requirement.dev != (from_root and dev)) {
                    continue;
                }
                var source = requirement.source();
                var package = Path(".");
                if (requirement.is_path()) {
                    package = manifest.dir().join(requirement.repository);
                    var canonical = package.canonicalize();
                    if (canonical.is_err()) {
                        return Result<OrderedMap<String, Array<Wanted>>>.Err(
                            $"{manifest.path.to_string()}: dependency '{requirement.name}' names the folder {package.to_string()}, which does not exist"
                        );
                    }
                    package = canonical.value();
                    source = "path:" + package.to_string();
                }
                if (!wanted.contains(source)) {
                    wanted[source] = Array<Wanted>();
                }
                wanted[source].append(Wanted(requirer, from_root, dev, parent, requirement));
                if (read.contains(source)) {
                    continue;
                }
                var label = "";
                if (requirement.is_path()) {
                    label = requirement.name;
                } else {
                    var locked = chosen.try_get(source);
                    if (locked.is_empty()) {
                        continue;
                    }
                    package = _dir(source);
                    label = locked.value().describe();
                }
                read.insert(source);
                var file = package.join("pep.toml");
                if (!file.is_file()) {
                    continue;
                }
                var dependency = read_manifest(file);
                if (dependency.is_err()) {
                    return Result<OrderedMap<String, Array<Wanted>>>.Err(dependency.error().message);
                }
                queue.append((dependency.value(), label, false, dev, source));
            }
        }
        return Result<OrderedMap<String, Array<Wanted>>>.Ok(wanted);
    }

    # The checksum pep.lock records for `commit` of `source`, if any.
    _locked_sha256(source: String, commit: String): String {
        for (var locked in previous) {
            if (locked.source == source and !locked.commit.is_empty and locked.commit.starts_with(commit)) {
                return locked.sha256;
            }
        }
        return "";
    }

    # Puts `commit` of `repository` on `host` in `dir`: a git checkout when
    # git is on the PATH, else the host's archive of it, from the fork
    # `from` (`github:you/name`) when it is given. Returns the full commit
    # and the checksum of its files, which must match the one pep.lock
    # records for that commit.
    fetch(host: String, repository: String, dir: Path, commit: String, from: String = ""): Result<(String, String)> {
        var source = host + ":" + repository;
        var (from_host, from_repository) = split_source(from.is_empty ? source : from);
        var expected = _locked_sha256(source, commit);
        var at = unpacked(dir);
        # Offline, an unpacked archive serves even once git is installed.
        if (at.is_value() and at.value() == commit and (offline or (!expected.is_empty and !has_git()))) {
            return Result<(String, String)>.Ok((commit, expected));
        }
        if (!has_git()) {
            if (offline) {
                return Result<(String, String)>.Err(not_held_offline(dir, commit));
            }
            if (commit.length != 40) {
                return Result<(String, String)>.Err(
                    $"git is not on the PATH, and fetching the commit '{commit}' without it needs all 40 digits"
                );
            }
            var fetched = fetch_archive(from_host, from_repository, dir, commit, expected);
            if (fetched.is_err()) {
                return Result<(String, String)>.Err(fetched.error().message);
            }
            return Result<(String, String)>.Ok((commit, fetched.value()));
        }
        var checked = check_out(repository_url(from_host, from_repository), dir, commit, offline);
        if (checked.is_err()) {
            return Result<(String, String)>.Err(checked.error().message);
        }
        var full = checked.value();
        var sha256 = checkout_sha256(dir, full);
        if (sha256.is_err()) {
            return Result<(String, String)>.Err(sha256.error().message);
        }
        var recorded = _locked_sha256(source, full);
        if (!recorded.is_empty and sha256.value() != recorded) {
            return Result<(String, String)>.Err(
                $"the files of {source} {full.substr(0, 12)} do not match pep.lock: sha256 {sha256.value()}, expected {recorded}"
            );
        }
        return Result<(String, String)>.Ok((full, sha256.value()));
    }

    # What `url`'s repository offers, read once per source.
    _remote(source: String): Result<Array<RemoteRef>> {
        var known = _refs.try_get(source);
        if (known.is_value()) {
            return Result<Array<RemoteRef>>.Ok(known.value());
        }
        if (offline) {
            return Result<Array<RemoteRef>>.Err(
                $"--offline, and choosing a revision of {source} reads which ones it offers over the network; run the command without --offline (or PEPPER_OFFLINE) once to update pep.lock"
            );
        }
        if (!has_git()) {
            return Result<Array<RemoteRef>>.Err(
                $"git is not on the PATH: reading which revisions {source} offers needs it (fetching what pep.lock lists does not); install git"
            );
        }
        var (host, repository) = split_source(_origin(source));
        var refs = remote_refs(repository_url(host, repository));
        if (refs.is_err()) {
            return Result<Array<RemoteRef>>.Err($"cannot read {source}: {refs.error().message}");
        }
        _refs[source] = refs.value();
        return refs;
    }

    # The locked revision of `source`, unless it is being updated or its
    # override changed.
    _kept(source: String): Optional<Locked> {
        if (update_all or update.contains(source)) {
            return Optional<Locked>.Empty;
        }
        for (var locked in previous) {
            if (locked.source == source and locked.replaced_by == _replaced_by(source)) {
                return Optional<Locked>.Value(locked);
            }
        }
        return Optional<Locked>.Empty;
    }

    # The revision of `source` every requirement in `asks` accepts.
    _choose(source: String, all_asks: Array<Wanted>, notes: Array<String>): Result<Locked> {
        # The project's own pep.toml overrides its dependencies.
        var asks = Array<Wanted>();
        for (var ask in all_asks) {
            if (ask.from_root) {
                asks.append(ask);
            }
        }
        if (asks.is_empty) {
            asks = all_asks;
        }
        var first = asks[0].requirement;
        var kept = _kept(source);
        if (first.kind != "version") {
            for (var ask in asks) {
                if (ask.requirement.kind != first.kind or ask.requirement.value != first.value) {
                    return Result<Locked>.Err(_conflict(source, asks, ""));
                }
            }
            if (first.kind == "commit") {
                var commit = first.value;
                if (kept.is_value() and kept.value().commit.starts_with(commit)) {
                    commit = kept.value().commit;
                }
                return Result<Locked>.Ok(Locked("", source, "", commit));
            }
            # A tag can move, so it is looked up again when git can.
            if (kept.is_value() and (first.kind != "tag" or offline or !has_git())) {
                return Result<Locked>.Ok(Locked("", source, "", kept.value().commit));
            }
            var refs = _remote(source);
            if (refs.is_err()) {
                return Result<Locked>.Err(refs.error().message);
            }
            var wanted_ref = first.kind == "branch" ?
                "refs/heads/" + first.value :
                first.kind == "tag" ? "refs/tags/" + first.value : "HEAD";
            for (var ref in refs.value()) {
                if (ref.name != wanted_ref) {
                    continue;
                }
                var version = "";
                if (first.kind == "tag") {
                    var parsed = tag_version(first.value);
                    version = parsed.is_value() ? parsed.value().to_string() : "";
                }
                return Result<Locked>.Ok(Locked("", source, version, ref.commit));
            }
            return Result<Locked>.Err($"{_origin(source)} has no {first.describe()}");
        }
        var ranges = Array<VersionRange>();
        for (var ask in asks) {
            if (ask.requirement.kind != "version") {
                return Result<Locked>.Err(_conflict(source, asks, ""));
            }
            var range = parse_range(ask.requirement.value);
            if (range.is_err()) {
                return Result<Locked>.Err(
                    $"{ask.requirer}: dependency '{ask.requirement.name}': {range.error().message}"
                );
            }
            ranges.append(range.value());
        }
        if (kept.is_value()) {
            var locked_version = tag_version(kept.value().version);
            if (locked_version.is_value() and _accepted(ranges, locked_version.value())) {
                return Result<Locked>.Ok(kept.value());
            }
        }
        var refs = _remote(source);
        if (refs.is_err()) {
            return Result<Locked>.Err(refs.error().message);
        }
        var accepted = Array<(Version, String)>();
        var newest = Optional<Version>.Empty;
        var offered = Array<String>();
        for (var ref in refs.value()) {
            if (!ref.name.starts_with("refs/tags/")) {
                continue;
            }
            var parsed = tag_version(ref.name.substr(10, ref.name.length));
            if (parsed.is_empty()) {
                continue;
            }
            var version = parsed.value();
            if (version.prerelease.is_empty) {
                offered.append(version.to_string());
                if (newest.is_empty() or version.compare(newest.value()) > 0) {
                    newest = Optional<Version>.Value(version);
                }
            }
            if (_accepted(ranges, version)) {
                accepted.append((version, ref.commit));
            }
        }
        if (accepted.is_empty) {
            var available = offered.is_empty ? "it has no version tags" : "it offers " + ", ".join(offered);
            return Result<Locked>.Err(_conflict(source, asks, available));
        }
        # The newest accepted version this toolchain builds: only the
        # pep.toml of each newer one is read.
        accepted.sort((a: (Version, String), b: (Version, String)) => b.0.compare(a.0));
        var skipped = Array<String>();
        var best = Optional<(Version, String)>.Empty;
        for (var candidate in accepted) {
            var minimum = toolchain.is_empty ? Result<String>.Ok("") : _minimum_at(source, candidate.1);
            if (minimum.is_err()) {
                return Result<Locked>.Err(minimum.error().message);
            }
            var shortfall = _shortfall(minimum.value());
            if (shortfall.is_empty) {
                best = Optional<(Version, String)>.Value(candidate);
                break;
            }
            skipped.append($"{candidate.0.to_string()} ({shortfall})");
        }
        if (best.is_empty()) {
            return Result<Locked>.Err(
                $"no version of {source} that every package accepts builds with toolchain {toolchain}: "
                    + ", ".join(skipped)
            );
        }
        var (version, commit) = best.value();
        if (!skipped.is_empty) {
            notes.append($"{source} skipped {", ".join(skipped)}; this is {toolchain}");
        }
        # Why an updated package is not at its newest version.
        if ((update_all or update.contains(source)) and newest.is_value() and newest.value().compare(version) > 0) {
            var holders = Array<String>();
            for (var index in 0..asks.count) {
                if (!ranges[index].matches(newest.value())) {
                    holders.append(asks[index].describe());
                }
            }
            if (!holders.is_empty) {
                notes.append(
                    $"{source} stays at {version.to_string()}, not {newest.value().to_string()}: " + "; ".join(holders)
                );
            }
        }
        if (asks.count < all_asks.count) {
            for (var ask in all_asks) {
                if (!ask.from_root and ask.requirement.kind == "version") {
                    var range = parse_range(ask.requirement.value);
                    if (range.is_ok() and !range.value().matches(version)) {
                        notes.append(
                            $"{source} {version.to_string()} overrides what {ask.requirer} asks ({ask.requirement.value})"
                        );
                    }
                }
            }
        }
        return Result<Locked>.Ok(Locked("", source, version.to_string(), commit));
    }
}

# The version a tag names: `1.2.3` or `v1.2.3`, with an optional
# prerelease (`v1.0.0-rc.1`); none for any other tag.
export tag_version(tag: String): Optional<Version> {
    var parsed = semver.parse(tag.starts_with("v") ? tag.substr(1, tag.length) : tag);
    return parsed.is_ok() ? Optional<Version>.Value(parsed.value()) : Optional<Version>.Empty;
}

# The condition under which a build needs each source of `wanted`: the
# `[target.'<condition>']` of each requirement on a way to it, all of
# which must hold, or else those of another way. Empty when a way has
# none: every build needs it.
export lock_targets(wanted: OrderedMap<String, Array<Wanted>>): HashMap<String, String> {
    # Each source's ways, each its conditions sorted; a way that holds
    # another's conditions and more adds nothing, so a cycle settles.
    var ways = HashMap<String, Array<Array<String>>>();
    var changed = true;
    while (changed) {
        changed = false;
        for (var (source, asks) in wanted) {
            for (var ask in asks) {
                var from = ask.parent.is_empty ?
                    [Array<String>()] :
                    ways.try_get(ask.parent).value_or(Array<Array<String>>());
                for (var way in from) {
                    var conditions = way.copy();
                    var condition = ask.requirement.target;
                    if (!condition.is_empty and !conditions.contains(condition)) {
                        conditions.append(condition);
                        conditions.sort((a, b) => a.compare(b));
                    }
                    if (!ways.contains(source)) {
                        ways[source] = Array<Array<String>>();
                    }
                    changed = _add_way(ways[source], conditions) or changed;
                }
            }
        }
    }
    var targets = HashMap<String, String>();
    for (var (source, alternatives) in ways) {
        var texts = Array<String>();
        for (var conditions in alternatives) {
            if (conditions.is_empty) {
                texts = Array<String>();
                break;
            }
            texts.append(conditions.count == 1 ? conditions[0] : " && ".join(_parenthesized(conditions)));
        }
        texts.sort((a, b) => a.compare(b));
        targets[source] = texts.count == 1 ? texts[0] : " || ".join(_parenthesized(texts));
    }
    return targets;
}

# Adds `way` to `ways` unless one of them needs no more than it does,
# dropping those that need more; whether `ways` changed.
_add_way(ways: Array<Array<String>>, way: Array<String>): bool {
    for (var other in ways) {
        if (_all_in(other, way)) {
            return false;
        }
    }
    var index = ways.count;
    while (index > 0) {
        index -= 1;
        if (_all_in(way, ways[index])) {
            ways.remove_at(index);
        }
    }
    ways.append(way);
    return true;
}

# Whether every item of `some` is in `all`.
_all_in(some: Array<String>, all: Array<String>): bool {
    for (var item in some) {
        if (!all.contains(item)) {
            return false;
        }
    }
    return true;
}

# Each of `texts` in parentheses.
_parenthesized(texts: Array<String>): Array<String> {
    var out = Array<String>();
    for (var text in texts) {
        out.append("(" + text + ")");
    }
    return out;
}

_accepted(ranges: Array<VersionRange>, version: Version): bool {
    for (var range in ranges) {
        if (!range.matches(version)) {
            return false;
        }
    }
    return true;
}

# Why no revision of `source` satisfies `asks`.
_conflict(source: String, asks: Array<Wanted>, available: String): String {
    var text = $"no revision of {source} satisfies every package that needs it:";
    for (var ask in asks) {
        text += "\n  " + ask.describe();
    }
    if (!available.is_empty) {
        text += "\n  " + available;
    }
    return text + "\nset its revision in pep.toml to choose one for the whole project";
}

# The `[package]` name in `dir`'s pep.toml, else the repository's name,
# and its `minimum_toolchain`.
_name_and_minimum(dir: Path, repository: String): (String, String) {
    var file = dir.join("pep.toml");
    var minimum = "";
    if (file.is_file()) {
        var manifest = read_manifest(file);
        if (manifest.is_ok()) {
            minimum = manifest.value().minimum_toolchain;
            if (!manifest.value().name.is_empty) {
                return (manifest.value().name, minimum);
            }
        }
    }
    var parts = repository.split("/");
    return (parts[parts.count - 1], minimum);
}

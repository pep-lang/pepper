# Resolution: one revision of every package in the dependency graph.
#
# Each package is identified by its source (`github:owner/name`), whatever
# key each dependent imports it by. A version range picks the newest tag
# every dependent accepts; a branch, tag or commit must be the same for
# every dependent. The project's own pep.toml overrides what dependencies
# ask for: when it names a package, only its requirement counts. A locked
# revision is kept while it still satisfies every requirement, unless the
# package is being updated.

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
    var requirement: Requirement = Requirement();

    construct() {}

    construct(requirer: String, from_root: bool, requirement: Requirement) {
        this.requirer = requirer;
        this.from_root = from_root;
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

    construct() {
        packages = Array<Locked>();
        notes = Array<String>();
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
    # What each repository offers, read once.
    var _refs: HashMap<String, Array<RemoteRef>> = __null;

    construct(project: Path, root: Manifest, previous: Array<Locked>) {
        this.project = project;
        this.root = root;
        this.previous = previous;
        update = Array<String>();
        _refs = HashMap<String, Array<RemoteRef>>();
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
                var picked = _choose(source, asks, notes);
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
                var fetched = _fetch(host, repository, dir, pick.commit);
                if (fetched.is_err()) {
                    return Result<Graph>.Err($"cannot fetch {source}: {fetched.error().message}");
                }
                var (commit, sha256) = fetched.value();
                pick.commit = commit;
                pick.sha256 = sha256;
                pick.name = _package_name(dir, repository);
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
            for (var (_, locked) in chosen) {
                graph.packages.append(locked);
            }
            graph.notes = notes;
            return Result<Graph>.Ok(graph);
        }
        return Result<Graph>.Err(
            "the dependency graph did not settle; check for packages that require each other in a cycle"
        );
    }

    # Every requirement in the graph, by source: the project's, then those
    # of each package chosen so far (and of folders `path` names).
    _gather(chosen: OrderedMap<String, Locked>): Result<OrderedMap<String, Array<Wanted>>> {
        var wanted = OrderedMap<String, Array<Wanted>>();
        var queue = Array<(Manifest, String, bool)>();
        queue.append((root, root.name.is_empty ? "pep.toml" : root.name, true));
        var read = HashSet<String>();
        ulong next = 0;
        while (next < queue.count) {
            var (manifest, requirer, from_root) = queue[next];
            next += 1;
            for (var requirement in manifest.requirements) {
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
                wanted[source].append(Wanted(requirer, from_root, requirement));
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
                    package = package_dir(project, requirement.host, requirement.repository);
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
                queue.append((dependency.value(), label, false));
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
    # git is on the PATH, else the host's archive of it. Returns the full
    # commit and the checksum of its files, which must match the one
    # pep.lock records for that commit.
    _fetch(host: String, repository: String, dir: Path, commit: String): Result<(String, String)> {
        var source = host + ":" + repository;
        if (!has_git()) {
            var expected = _locked_sha256(source, commit);
            var at = unpacked(dir);
            if (at.is_value() and at.value() == commit and !expected.is_empty) {
                return Result<(String, String)>.Ok((commit, expected));
            }
            if (commit.length != 40) {
                return Result<(String, String)>.Err(
                    $"git is not on the PATH, and fetching the commit '{commit}' without it needs all 40 digits"
                );
            }
            var fetched = fetch_archive(host, repository, dir, commit, expected);
            if (fetched.is_err()) {
                return Result<(String, String)>.Err(fetched.error().message);
            }
            return Result<(String, String)>.Ok((commit, fetched.value()));
        }
        var checked = check_out(repository_url(host, repository), dir, commit);
        if (checked.is_err()) {
            return Result<(String, String)>.Err(checked.error().message);
        }
        var full = checked.value();
        var sha256 = checkout_sha256(dir, full);
        if (sha256.is_err()) {
            return Result<(String, String)>.Err(sha256.error().message);
        }
        var expected = _locked_sha256(source, full);
        if (!expected.is_empty and sha256.value() != expected) {
            return Result<(String, String)>.Err(
                $"the files of {source} {full.substr(0, 12)} do not match pep.lock: sha256 {sha256.value()}, expected {expected}"
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
        if (!has_git()) {
            return Result<Array<RemoteRef>>.Err(
                $"git is not on the PATH: reading which revisions {source} offers needs it (fetching what pep.lock lists does not); install git"
            );
        }
        var (host, repository) = split_source(source);
        var refs = remote_refs(repository_url(host, repository));
        if (refs.is_err()) {
            return Result<Array<RemoteRef>>.Err($"cannot read {source}: {refs.error().message}");
        }
        _refs[source] = refs.value();
        return refs;
    }

    # The locked revision of `source`, unless it is being updated.
    _kept(source: String): Optional<Locked> {
        if (update_all or update.contains(source)) {
            return Optional<Locked>.Empty;
        }
        for (var locked in previous) {
            if (locked.source == source) {
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
            if (kept.is_value() and (first.kind != "tag" or !has_git())) {
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
            return Result<Locked>.Err($"{source} has no {first.describe()}");
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
        var best = Optional<(Version, String)>.Empty;
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
            if (_accepted(ranges, version) and (best.is_empty() or version.compare(best.value().0) > 0)) {
                best = Optional<(Version, String)>.Value((version, ref.commit));
            }
        }
        if (best.is_empty()) {
            var available = offered.is_empty ? "it has no version tags" : "it offers " + ", ".join(offered);
            return Result<Locked>.Err(_conflict(source, asks, available));
        }
        var (version, commit) = best.value();
        # Why an updated package is not at its newest version.
        if ((update_all or update.contains(source)) and newest.is_value() and newest.value().compare(version) > 0) {
            var holders = Array<String>();
            for (var index in 0..asks.count) {
                if (!ranges[index].matches(newest.value())) {
                    holders.append(asks[index].describe());
                }
            }
            notes.append(
                $"{source} stays at {version.to_string()}, not {newest.value().to_string()}: " + "; ".join(holders)
            );
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

# The `[package]` name in `dir`'s pep.toml, else the repository's name.
_package_name(dir: Path, repository: String): String {
    var file = dir.join("pep.toml");
    if (file.is_file()) {
        var manifest = read_manifest(file);
        if (manifest.is_ok() and !manifest.value().name.is_empty) {
            return manifest.value().name;
        }
    }
    var parts = repository.split("/");
    return parts[parts.count - 1];
}

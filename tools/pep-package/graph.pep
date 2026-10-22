# The dependency graph pep.lock records, and the reports on it: `tree`,
# `why` and `outdated`. The edges are what the resolver gathers
# (`Resolver.gather`) from the pep.toml of each locked package, so the
# graph is the one `fetch` locked, and no report changes pep.lock.

import [Path] from io;
import [Version] from semver;
import "git";
import "lock";
import "manifest";
import "resolve";

# A requirement in the graph: the source it leads to and what asks for it.
export struct Edge {
    var source: String = "";
    var wanted: Wanted = Wanted();

    construct() {}

    construct(source: String, wanted: Wanted) {
        this.source = source;
        this.wanted = wanted;
    }
}

# The locked graph of a project.
export struct LockedGraph {
    # The project's name, which the reports start from.
    var name: String = "";
    # Each locked package, by source.
    var packages: OrderedMap<String, Locked> = __null;
    # What asks for each source (`Resolver.gather`).
    var wanted: OrderedMap<String, Array<Wanted>> = __null;
    # The requirements in each package's pep.toml, by its source; the
    # project's under "".
    var edges: HashMap<String, Array<Edge>> = __null;
    var resolver: Resolver = __null;

    construct(resolver: Resolver, packages: OrderedMap<String, Locked>, wanted: OrderedMap<String, Array<Wanted>>) {
        this.resolver = resolver;
        this.packages = packages;
        this.wanted = wanted;
        name = resolver.root.name.is_empty ? "pep.toml" : resolver.root.name;
        edges = HashMap<String, Array<Edge>>();
        for (var (source, asks) in wanted) {
            for (var ask in asks) {
                if (!edges.contains(ask.parent)) {
                    edges[ask.parent] = Array<Edge>();
                }
                edges[ask.parent].append(Edge(source, ask));
            }
        }
    }

    # The requirements in the pep.toml of `source` ("" for the project's).
    children(source: String): Array<Edge> {
        return edges.try_get(source).value_or(Array<Edge>());
    }

    # `geometry 1.2.0`, or the name and folder of a path dependency.
    short(edge: Edge): String {
        var locked = packages.try_get(edge.source);
        return locked.is_value() ? locked.value().describe() : edge.wanted.requirement.name;
    }

    # A line of `tree`: the name it is imported by when that is not the
    # package's own, its version and source, whether it is dev- or
    # platform-only, and the features the dependent turns on.
    label(edge: Edge): String {
        var requirement = edge.wanted.requirement;
        var locked = packages.try_get(edge.source);
        var text = requirement.name + " (" + edge.source + ")";
        if (locked.is_value()) {
            var package = locked.value();
            text = (package.name == requirement.name ? "" : requirement.name + ": ")
                + package.describe()
                + " ("
                + edge.source
                + ")";
            if (package.dev) {
                text += " [dev]";
            }
            if (!package.target.is_empty) {
                text += $" [target: {package.target}]";
            }
        }
        if (requirement.optional) {
            text += " [optional]";
        }
        if (!requirement.features.is_empty) {
            text += $" [features: {", ".join(requirement.features)}]";
        }
        return text;
    }

    # The graph as `tree` prints it, `depth` levels deep: a package whose
    # dependencies were listed already ends in `(*)`.
    tree(depth: ulong): String {
        var lines = [name];
        _tree("", "", 1, depth, lines, HashSet<String>());
        return "\n".join(lines) + "\n";
    }

    _tree(parent: String, prefix: String, level: ulong, depth: ulong, lines: Array<String>, shown: HashSet<String>) {
        if (level > depth) {
            return;
        }
        var edges = children(parent);
        for (var index in 0..edges.count) {
            var edge = edges[index];
            var last = index + 1 == edges.count;
            var line = prefix + (last ? "`-- " : "|-- ") + label(edge);
            var below = !children(edge.source).is_empty;
            if (below and shown.contains(edge.source)) {
                lines.append(line + " (*)");
                continue;
            }
            lines.append(line);
            # Only a package whose dependencies are listed here is marked.
            if (below and level < depth) {
                shown.insert(edge.source);
                _tree(edge.source, prefix + (last ? "    " : "|   "), level + 1, depth, lines, shown);
            }
        }
    }

    # The sources `spec` names: a locked package by its name, source or
    # owner/name, or a dependency by the name it is imported by.
    find(spec: String): HashSet<String> {
        var found = HashSet<String>();
        for (var (source, package) in packages) {
            if (package.name == spec or source == spec or source.ends_with(":" + spec)) {
                found.insert(source);
            }
        }
        for (var (source, asks) in wanted) {
            for (var ask in asks) {
                if (ask.requirement.name == spec) {
                    found.insert(source);
                }
            }
        }
        return found;
    }

    # Every path from the project to one of `targets`, one per line.
    why(targets: HashSet<String>): Array<String> {
        var paths = Array<String>();
        _why("", [name], HashSet<String>(), targets, paths);
        return paths;
    }

    _why(
        parent: String, path: Array<String>, on_path: HashSet<String>, targets: HashSet<String>, paths: Array<String>
    ) {
        for (var edge in children(parent)) {
            if (on_path.contains(edge.source)) {
                continue;
            }
            var longer = path.copy();
            longer.append(short(edge));
            if (targets.contains(edge.source)) {
                paths.append(" -> ".join(longer));
                continue;
            }
            on_path.insert(edge.source);
            _why(edge.source, longer, on_path, targets, paths);
            on_path.remove(edge.source);
        }
    }

    # A row of `outdated` for each locked package that is behind the
    # revision its requirements now choose (`Resolver.choose`, as `update`
    # would) or the newest version it offers: its name, locked revision,
    # that choice, the newest version, and its source. Reads what each
    # package offers over the network.
    outdated(): Result<Array<Array<String>>> {
        resolver.update_all = true;
        var rows = Array<Array<String>>();
        for (var (source, package) in packages) {
            var asks = wanted.try_get(source);
            if (asks.is_empty()) {
                continue;
            }
            var chosen = resolver.choose(source, asks.value(), Array<String>());
            if (chosen.is_err()) {
                return Result<Array<Array<String>>>.Err(chosen.error().message);
            }
            var refs = resolver.remote(source);
            if (refs.is_err()) {
                return Result<Array<Array<String>>>.Err(refs.error().message);
            }
            var newest = Optional<Version>.Empty;
            for (var ref in refs.value()) {
                if (ref.name.starts_with("refs/tags/")) {
                    var version = tag_version(ref.name.substr(10, ref.name.length));
                    if (version.is_value()
                        and version.value().prerelease.is_empty
                        and (newest.is_empty() or version.value().compare(newest.value()) > 0)) {
                        newest = version;
                    }
                }
            }
            var locked_version = tag_version(package.version);
            var behind = chosen.value().commit != package.commit
                or (locked_version.is_value()
                    and newest.is_value()
                    and newest.value().compare(locked_version.value()) > 0);
            if (behind) {
                var wanted_text = chosen.value().version.is_empty ?
                    chosen.value().commit.substr(0, 12) :
                    chosen.value().version;
                rows.append(
                    [
                        package.name,
                        _revision(package),
                        wanted_text,
                        newest.is_value() ? newest.value().to_string() : "-",
                        source
                    ]
                );
            }
        }
        return Result<Array<Array<String>>>.Ok(rows);
    }
}

# A locked package's version, else its short commit.
_revision(package: Locked): String {
    return package.version.is_empty ? package.commit.substr(0, 12) : package.version;
}

# Reads the graph pep.lock records for the project in `dir`, whose
# pep.toml is `manifest`, checking each locked package out at its commit
# (only from `.pep/deps` when `offline`). Fails when pep.toml needs a
# package pep.lock does not list: `fetch` resolves it.
export read_graph(dir: Path, manifest: Manifest, offline: bool): Result<LockedGraph> {
    var locked = read_lock(lock_path(dir));
    if (locked.is_err()) {
        return Result<LockedGraph>.Err(locked.error().message);
    }
    var resolver = Resolver(dir, manifest, locked.value());
    resolver.offline = offline;
    var packages = OrderedMap<String, Locked>();
    for (var package in locked.value()) {
        var (host, repository) = split_source(package.source);
        var fetched = resolver.fetch(host, repository, package_dir(dir, host, repository), package.commit);
        if (fetched.is_err()) {
            return Result<LockedGraph>.Err($"cannot fetch {package.source}: {fetched.error().message}");
        }
        packages[package.source] = package;
    }
    var wanted = resolver.gather(packages);
    if (wanted.is_err()) {
        return Result<LockedGraph>.Err(wanted.error().message);
    }
    for (var (source, _) in wanted.value()) {
        if (!source.starts_with("path:") and !packages.contains(source)) {
            return Result<LockedGraph>.Err(
                $"pep.lock does not list {source}, which the graph needs; run 'pepper package fetch' to resolve it"
            );
        }
    }
    return Result<LockedGraph>.Ok(LockedGraph(resolver, packages, wanted.value()));
}

# `rows` as columns padded to their widest cell, under `header`.
export table(header: Array<String>, rows: Array<Array<String>>): String {
    var all = [header];
    all.append_all(rows);
    var widths = Array<ulong>();
    for (var cell in header) {
        widths.append(0);
    }
    for (var row in all) {
        for (var index in 0..row.count) {
            if (row[index].length > widths[index]) {
                widths[index] = row[index].length;
            }
        }
    }
    var text = "";
    for (var row in all) {
        var line = "";
        for (var index in 0..row.count) {
            line += index + 1 == row.count ?
                row[index] :
                row[index] + " ".repeat(widths[index] - row[index].length + 2);
        }
        text += line + "\n";
    }
    return text;
}

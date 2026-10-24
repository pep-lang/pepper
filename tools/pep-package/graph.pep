# The dependency graph pep.lock records, and the reports on it: `tree`,
# `why` and `outdated`. The edges are what the resolver gathers
# (`Resolver.gather`) from the pep.toml of each locked package, so the
# graph is the one `fetch` locked, and no report changes pep.lock.

import [Path] from io;
import [JsonValue] from json;
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

    # `geometry 1.2.0`, or the name and folder of a path dependency, with
    # what overrides it.
    short(edge: Edge): String {
        var locked = packages.try_get(edge.source);
        if (!locked.is_value()) {
            return edge.wanted.requirement.name;
        }
        return locked.value().describe() + _overridden(locked.value());
    }

    # A line of `tree`: the name it is imported by when that is not the
    # package's own, the package (`_describe`), and the marks of the
    # dependent's entry for it (`_marks`).
    label(edge: Edge): String {
        var requirement = edge.wanted.requirement;
        var locked = packages.try_get(edge.source);
        var renamed = locked.is_value() and locked.value().name != requirement.name;
        return (renamed ? requirement.name + ": " : "")
            + _describe(edge.source, requirement.name)
            + _marks(requirement);
    }

    # The package at `source` as `tree` lists it: its version (or short
    # commit) and source, and whether it is dev- or platform-only or
    # overridden. The project ("") is its name; a package pep.lock does
    # not list is `name` and its source.
    _describe(source: String, name: String): String {
        if (source.is_empty) {
            return this.name;
        }
        var locked = packages.try_get(source);
        if (!locked.is_value()) {
            return name + " (" + source + ")";
        }
        var package = locked.value();
        var text = package.describe() + " (" + source + ")";
        if (package.dev) {
            text += " [dev]";
        }
        if (!package.target.is_empty) {
            text += $" [target: {package.target}]";
        }
        return text + _overridden(package);
    }

    # Whether a dependent's entry is optional, and the features it turns on.
    _marks(requirement: Requirement): String {
        var text = requirement.optional ? " [optional]" : "";
        if (!requirement.features.is_empty) {
            text += $" [features: {", ".join(requirement.features)}]";
        }
        return text;
    }

    # `edge` as `--json` writes it: the package it leads to, and the entry
    # that asks for it (see docs/src/tools/pep-package.md).
    _json(edge: Edge): JsonValue {
        var requirement = edge.wanted.requirement;
        var locked = packages.try_get(edge.source);
        var package = locked.is_value() ? locked.value() : Locked(requirement.name, edge.source, "", "");
        var features = JsonValue.array();
        for (var feature in requirement.features) {
            features.append(JsonValue.String(feature));
        }
        var node = JsonValue.object();
        node["name"] = JsonValue.String(requirement.name);
        node["package"] = JsonValue.String(edge.source.is_empty ? name : package.name);
        node["version"] = _text(package.version);
        node["commit"] = _text(package.commit);
        node["source"] = JsonValue.String(edge.source);
        node["dev"] = JsonValue.Bool(package.dev);
        node["target"] = _text(package.target);
        node["override"] = _text(package.replaced_by);
        node["optional"] = JsonValue.Bool(requirement.optional);
        node["features"] = features;
        return node;
    }

    # The graph as `tree` prints it, `depth` levels deep: a package whose
    # dependencies were listed already ends in `(*)`. With `json`, the
    # same tree as `--json` writes it.
    tree(depth: ulong, json: bool): String {
        var lines = [name];
        var nodes = _tree("", "", 1, depth, false, lines, HashSet<String>());
        if (json) {
            var root = JsonValue.object();
            root["name"] = JsonValue.String(name);
            root["dependencies"] = nodes;
            return root.to_pretty_string() + "\n";
        }
        return "\n".join(lines) + "\n";
    }

    # What depends on each of `targets`, as `tree --invert` prints it: the
    # package, then each package whose pep.toml asks for it, down to the
    # project, `depth` levels deep, with `(*)` as in `tree`.
    inverted(targets: HashSet<String>, depth: ulong, json: bool): String {
        var lines = Array<String>();
        var roots = JsonValue.array();
        var shown = HashSet<String>();
        # Locked packages, even one nothing asks for, then path dependencies.
        var sources = Array<String>();
        for (var (source, _) in packages) {
            if (targets.contains(source)) {
                sources.append(source);
            }
        }
        for (var (source, _) in wanted) {
            if (targets.contains(source) and !packages.contains(source)) {
                sources.append(source);
            }
        }
        for (var source in sources) {
            # The package itself, which no entry asks for here.
            var root = Wanted();
            var locked = packages.try_get(source);
            root.requirement.name = locked.is_value() ? locked.value().name : wanted[source][0].requirement.name;
            lines.append(_describe(source, root.requirement.name));
            shown.insert(source);
            var node = _json(Edge(source, root));
            node["dependents"] = _tree(source, "", 1, depth, true, lines, shown);
            roots.append(node);
        }
        if (json) {
            var result = JsonValue.object();
            result["name"] = JsonValue.String(name);
            result["packages"] = roots;
            return result.to_pretty_string() + "\n";
        }
        return "\n".join(lines) + "\n";
    }

    # What `tree` lists below `source`: its dependencies, or with `invert`
    # the packages whose pep.toml asks for it. Each is the edge of the
    # dependent's entry.
    _below(source: String, invert: bool): Array<Edge> {
        if (!invert) {
            return children(source);
        }
        var edges = Array<Edge>();
        if (!source.is_empty) {
            for (var ask in wanted.try_get(source).value_or(Array<Wanted>())) {
                edges.append(Edge(ask.parent, ask));
            }
        }
        return edges;
    }

    # Appends the lines below `parent` to `lines`, and returns them as the
    # nodes `--json` writes, each holding what is below it under `key`.
    _tree(
        parent: String,
        prefix: String,
        level: ulong,
        depth: ulong,
        invert: bool,
        lines: Array<String>,
        shown: HashSet<String>
    ): JsonValue {
        var nodes = JsonValue.array();
        if (level > depth) {
            return nodes;
        }
        var key = invert ? "dependents" : "dependencies";
        var listed = _below(parent, invert);
        for (var index in 0..listed.count) {
            var edge = listed[index];
            var last = index + 1 == listed.count;
            # Inverted, the line is the dependent, with its entry's marks.
            var text = invert ?
                _describe(edge.source, edge.wanted.requirement.name) + _marks(edge.wanted.requirement) :
                label(edge);
            var line = prefix + (last ? "`-- " : "|-- ") + text;
            var below = !_below(edge.source, invert).is_empty;
            var repeated = below and shown.contains(edge.source);
            var node = _json(edge);
            node["repeated"] = JsonValue.Bool(repeated);
            node[key] = JsonValue.array();
            nodes.append(node);
            if (repeated) {
                lines.append(line + " (*)");
                continue;
            }
            lines.append(line);
            # Only a package whose dependencies are listed here is marked.
            if (below and level < depth) {
                shown.insert(edge.source);
                node[key] = _tree(
                    edge.source, prefix + (last ? "    " : "|   "), level + 1, depth, invert, lines, shown
                );
            }
        }
        return nodes;
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

    # The paths from the project to one of `targets`, one per line: the
    # first `limit`, then how many more there are. With `json`, those
    # paths as `--json` writes them.
    why(targets: HashSet<String>, limit: ulong, json: bool): String {
        var paths = Array<Array<Edge>>();
        _why("", Array<Edge>(), HashSet<String>(), targets, limit, paths);
        var (total, _) = _count("", HashSet<String>(), targets, HashMap<String, ulong>());
        var count = paths.count;
        if (json) {
            var list = JsonValue.array();
            for (var index in 0..count) {
                var steps = JsonValue.array();
                for (var edge in paths[index]) {
                    steps.append(_json(edge));
                }
                list.append(steps);
            }
            var result = JsonValue.object();
            result["paths"] = list;
            result["total"] = JsonValue.Integer(total as long);
            return result.to_pretty_string() + "\n";
        }
        var text = "";
        for (var index in 0..count) {
            var steps = [name];
            for (var edge in paths[index]) {
                steps.append(short(edge));
            }
            text += " -> ".join(steps) + "\n";
        }
        if (total > count) {
            var more = total - count;
            text += $"and {more} more {more == 1 ? "path" : "paths"}; --all prints every one\n";
        }
        return text;
    }

    # Appends the paths below `parent` that reach one of `targets` to
    # `paths`, depth first, until it holds `limit`.
    _why(
        parent: String,
        path: Array<Edge>,
        on_path: HashSet<String>,
        targets: HashSet<String>,
        limit: ulong,
        paths: Array<Array<Edge>>
    ) {
        for (var edge in children(parent)) {
            if (paths.count >= limit) {
                return;
            }
            if (on_path.contains(edge.source)) {
                continue;
            }
            var longer = path.clone();
            longer.append(edge);
            if (targets.contains(edge.source)) {
                paths.append(longer);
                continue;
            }
            on_path.insert(edge.source);
            _why(edge.source, longer, on_path, targets, limit, paths);
            on_path.remove(edge.source);
        }
    }

    # How many paths `_why` finds below `parent`, without listing them, and
    # whether that number depends on `on_path` (it skipped a package on
    # it, so the graph has a cycle there). Only a number that does not is
    # kept in `counted`, so a graph without cycles takes one pass.
    _count(
        parent: String, on_path: HashSet<String>, targets: HashSet<String>, counted: HashMap<String, ulong>
    ): (ulong, bool) {
        var known = counted.try_get(parent);
        if (known.is_value()) {
            return (known.value(), false);
        }
        ulong total = 0;
        var cut = false;
        for (var edge in children(parent)) {
            if (on_path.contains(edge.source)) {
                cut = true;
                continue;
            }
            if (targets.contains(edge.source)) {
                total += 1;
                continue;
            }
            on_path.insert(edge.source);
            var (below, below_cut) = _count(edge.source, on_path, targets, counted);
            on_path.remove(edge.source);
            total += below;
            cut = cut or below_cut;
        }
        if (!cut) {
            counted[parent] = total;
        }
        return (total, cut);
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
            # An override's revision is the project's own choice.
            if (asks.is_empty() or !package.replaced_by.is_empty) {
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
                    var version = member_tag_version(source_member(source), ref.name.substr(10, ref.name.length));
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

    # The rows of `outdated` as `--json` writes them.
    outdated_json(rows: Array<Array<String>>): String {
        var list = JsonValue.array();
        for (var row in rows) {
            var package = packages[row[4]];
            var entry = JsonValue.object();
            entry["package"] = JsonValue.String(row[0]);
            entry["locked"] = JsonValue.String(row[1]);
            entry["wanted"] = JsonValue.String(row[2]);
            entry["latest"] = row[3] == "-" ? JsonValue.Null : JsonValue.String(row[3]);
            entry["source"] = JsonValue.String(row[4]);
            entry["dev"] = JsonValue.Bool(package.dev);
            entry["target"] = _text(package.target);
            list.append(entry);
        }
        var result = JsonValue.object();
        result["packages"] = list;
        return result.to_pretty_string() + "\n";
    }
}

# `text` as a JSON string, or `null` when it is empty.
_text(text: String): JsonValue {
    return text.is_empty ? JsonValue.Null : JsonValue.String(text);
}

# A locked package's version, else its short commit.
_revision(package: Locked): String {
    return package.version.is_empty ? package.commit.substr(0, 12) : package.version;
}

# Reads the graph pep.lock records for the project in `dir`, whose
# pep.toml is `manifest`, checking each locked package out at its commit
# (only from `.pep/deps` when `offline`), or from the vendor folder of a
# vendored project. Fails when pep.toml needs a
# package pep.lock does not list: `fetch` resolves it.
export read_graph(dir: Path, manifest: Manifest, offline: bool): Result<LockedGraph> {
    var locked = read_lock(lock_path(dir));
    if (locked.is_err()) {
        return Result<LockedGraph>.Err(locked.error().message);
    }
    var resolver = Resolver(dir, manifest, locked.value());
    resolver.offline = offline;
    resolver.vendor = manifest.vendor;
    var packages = OrderedMap<String, Locked>();
    for (var package in locked.value()) {
        var (host, repository) = split_source(package.source);
        var at = package_dir(dir, host, repository, manifest.vendor);
        # A checkout at the commit already is used as it is, without
        # hashing its files again.
        if (checked_out(at).value_or("") == package.commit) {
            packages[package.source] = package;
            continue;
        }
        var fetched = resolver.fetch(host, repository, at, package.commit);
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

# ` [override: github:you/name]` for a package `[overrides]` replaces, else
# nothing.
_overridden(package: Locked): String {
    return package.replaced_by.is_empty ? "" : $" [override: {package.replaced_by}]";
}

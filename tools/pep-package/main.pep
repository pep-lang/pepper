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
#     pepper package add --optional --features simd someone/zlib  # for a feature to turn on
#     pepper package remove geometry
#     pepper package update [geometry]          # newer versions the ranges allow
#     pepper package update --verify            # one at a time, keeping those that build
#     pepper package fetch --locked             # fail rather than change pep.lock
#     pepper package fetch --offline            # only what .pep/deps and the cache hold; --frozen is both
#     pepper package fetch github:someone/geometry  # only that locked package, without resolving
#     pepper package publish [--dry-run]        # check, test, tag v<version> and push the tag
#     pepper package tree [--depth 1] [--json]  # the locked graph
#     pepper package tree --invert numbers      # what depends on numbers
#     pepper package why numbers [--all]        # the paths from the project to it
#     pepper package outdated [--exit-code]     # what is behind its range, or the newest version
#     pepper package install someone/tool@1     # builds its program into the Pepper home's bin
#     pepper package install --path .           # the package in a folder
#     pepper package install --list             # what is installed, and from where
#     pepper package uninstall tool
#     pepper package cache info                 # the download cache every project shares
#     pepper package cache clean
#
# Build it from the repository root; its pep.toml names the toml package it
# needs, which `pepper build` fetches:
#
#     pepper build tools/pep-package/main.pep -o pep-package

import cli;
import [Directory, File, Path] from io;
import io;
import os;
import process;
import semver;
import [parse_range] from semver;
import syntax;
import toml;
import toolchain;
import "git";
import "graph";
import "install";
import "lock";
import "manifest";
import "resolve";
import "tree";

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
        help = "use only what .pep/deps and the download cache hold, and fail on what needs the network (also PEPPER_OFFLINE=1)",
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
    var add_optional = add.flag(
        "optional", help = "mark it 'optional = true': a build uses it only when a feature in [features] turns it on"
    );
    var add_features = add.multiple(
        "features",
        "F",
        "the dependency's features to turn on, written to its 'features': a comma-separated list, or repeat the option",
        value_name = "NAMES"
    );
    var add_no_default_features = add.flag(
        "no-default-features", help = "leave the dependency's default feature off: 'default-features = false'"
    );
    var remove = parser.command("remove", "Removes a dependency");
    var remove_package = remove.positional("package", "the dependency's name, or its owner/name");
    var update = parser.command("update", "Moves dependencies to the newest versions their ranges allow");
    var update_packages = update.positionals("packages", "the dependencies to update (default: every one)");
    var verify = update.flag(
        "verify", help = "update one dependency at a time and build after each, keeping only the updates that build"
    );
    var publish = parser.command(
        "publish", "Checks the package and runs its tests, then tags its version and pushes the tag"
    );
    var dry_run = publish.flag("dry-run", help = "check and test, but neither tag nor push");
    var tree = parser.command("tree", "Prints the dependency graph pep.lock records");
    var depth = tree.option<ulong>(
        "depth", "d", "print only N levels of dependencies below the project", value_name = "N"
    );
    var invert = tree.option(
        "invert", "i", "print what depends on a package instead, down to the project", value_name = "NAME"
    );
    var tree_json = tree.flag("json", help = "print the tree as JSON");
    var why = parser.command("why", "Prints the paths from the project to a package, the first 20 unless --all");
    var why_package = why.positional(
        "package", "the package's name, owner/name or source, or the name a dependency is imported by"
    );
    var all_paths = why.flag("all", help = "print every path, not only the first 20");
    var why_json = why.flag("json", help = "print the paths as JSON");
    var outdated = parser.command(
        "outdated",
        "Lists the packages behind the newest version their ranges allow, or the newest overall, without changing pep.lock"
    );
    var exit_code = outdated.flag("exit-code", help = "exit with status 1 when a package is outdated");
    var outdated_json = outdated.flag("json", help = "print the outdated packages as JSON");
    var install = parser.command(
        "install", "Builds a package's program optimized and puts it in the Pepper home's bin, which is on the PATH"
    );
    var install_package = install.positional(
        "package",
        "[host:]owner/name[@range]: the newest version the range allows (default: the newest release); install it again to upgrade",
        required = false
    );
    var install_path = install.option("path", "", "install the package in this folder instead", value_name = "DIR");
    var install_list = install.flag("list", help = "list what is installed, and from where, instead");
    var install_force = install.flag(
        "force",
        "f",
        "replace a program in bin that was installed from another source, or not by 'pepper package install'"
    );
    var install_features = install.multiple(
        "features",
        "F",
        "the package's features to turn on: a comma-separated list, or repeat the option",
        value_name = "NAMES"
    );
    var install_no_default_features = install.flag(
        "no-default-features", help = "leave the package's default feature off"
    );
    var uninstall = parser.command("uninstall", "Removes a program 'install' put in the Pepper home's bin");
    var uninstall_name = uninstall.positional("name", "the program's name, as 'install --list' shows it");
    var cache = parser.command("cache", "Shows or empties the download cache every project shares");
    var cache_info = cache.command("info", "Prints the cache's folder and the packages it holds");
    cache.command("clean", "Removes what the cache holds, except packages a fetch is using; projects keep .pep/deps");
    if (!parser.parse(args)) {
        return 2;
    }
    if (cache.is_selected) {
        return cache_info.is_selected ? show_cache() : clean_cache();
    }
    if (install.is_selected) {
        if (install_list.is_set) {
            return list_installed();
        }
        var options = Array<String>();
        for (var names in install_features.values()) {
            options.append_all(["--features", names]);
        }
        if (install_no_default_features.is_set) {
            options.append("--no-default-features");
        }
        # These are for the build, and its package's own pep.lock;
        # `PEPPER_LOCKED` and `PEPPER_OFFLINE` reach it as they are.
        if (locked.is_set or frozen.is_set) {
            options.append("--locked");
        }
        if (offline.is_set or frozen.is_set) {
            options.append("--offline");
        }
        return install_tool(
            install_package.value_or(""),
            install_path.value_or(""),
            install_force.is_set,
            options,
            offline.is_set or frozen.is_set or os.environment_flag("PEPPER_OFFLINE")
        );
    }
    if (uninstall.is_selected) {
        var removed = uninstall_program(uninstall_name.value());
        if (removed.is_err()) {
            return fail(removed.error().message);
        }
        say(removed.value());
        return 0;
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
        if (add_dev.is_set and add_optional.is_set) {
            return fail("a dev-dependency cannot be optional; give --dev or --optional");
        }
        var features = Array<toml.TomlValue>();
        for (var names in add_features.values()) {
            for (var name in names.split(",")) {
                if (!name.trim().is_empty) {
                    features.append(toml.TomlValue.String(name.trim()));
                }
            }
        }
        var extra = toml.TomlValue.table();
        if (add_optional.is_set) {
            extra["optional"] = toml.TomlValue.Boolean(true);
        }
        if (!features.is_empty) {
            extra["features"] = toml.TomlValue.array(features);
        }
        if (add_no_default_features.is_set) {
            extra["default-features"] = toml.TomlValue.Boolean(false);
        }
        return project.add(add_package.value(), add_name.value_or(""), add_dev.is_set, add_target.value_or(""), extra);
    }
    if (remove.is_selected) {
        return project.remove(remove_package.value());
    }
    if (update.is_selected) {
        return verify.is_set ?
            project.update_verified(update_packages.values()) :
            project.update(update_packages.values());
    }
    if (publish.is_selected) {
        return project.publish(dry_run.is_set);
    }
    if (tree.is_selected) {
        return project.tree(depth.is_set ? depth.value() : 0xFFFFFFFFFFFFFFFF, invert.value_or(""), tree_json.is_set);
    }
    if (why.is_selected) {
        return project.why(why_package.value(), all_paths.is_set ? 0xFFFFFFFFFFFFFFFF : 20, why_json.is_set);
    }
    if (outdated.is_selected) {
        return project.outdated(exit_code.is_set, outdated_json.is_set);
    }
    print(parser.help());
    return 2;
}

# Prints `message` as an error; returns the exit status for one.
fail(message: String): int {
    # A clang-style diagnostic (`pep.toml:3:1: error: ...`) names itself.
    var first = message.split_once("\n");
    var located = (first.is_value() ? first.value().0 : message).split_once(": error: ");
    var place = located.is_value() ? located.value().0.split(":") : Array<String>();
    if (place.count >= 3
        and ulong.parse(place[place.count - 1]).is_value()
        and ulong.parse(place[place.count - 2]).is_value()) {
        File.stderr().write_all(message.ends_with("\n") ? message : message + "\n");
        return 1;
    }
    File.stderr().write_all($"pep-package: error: {message}\n");
    return 1;
}

# Prints the download cache's folder, then each package it holds
# (`github.com/other/numbers`).
show_cache(): int {
    var root = cache_dir();
    print(root.to_string());
    var packages = Array<String>();
    _list_cached(root, "", packages);
    packages.sort((a, b) => a.compare(b));
    for (var package in packages) {
        var base = _cached_base(root, package);
        if (Path(base.to_string() + ".git").is_directory() or base.is_directory()) {
            print(package);
        }
    }
    return 0;
}

# Adds to `packages` each package under `dir`, the cache's folder `prefix`
# (`github.com/other`), that has a lock file (`numbers.lock`): a fetch
# takes its package's lock before it writes anything.
_list_cached(dir: Path, prefix: String, packages: Array<String>) {
    var opened = Directory.open(dir);
    if (opened.is_err()) {
        return;
    }
    var listed = opened.value().entries();
    if (listed.is_err()) {
        return;
    }
    for (var entry in listed.value()) {
        var name = entry.path.file_name().value_or("");
        var path = prefix.is_empty ? name : prefix + "/" + name;
        if (entry.is_file and name.ends_with(".lock")) {
            packages.append(path.substr(0, path.length - 5));
        } else if (entry.is_directory and !name.ends_with(".git") and !name.ends_with(".partial")) {
            # Not into a bare repository, whose own `.lock` files are git's.
            _list_cached(entry.path, path, packages);
        }
    }
}

# The cache's path for `package` (`github.com/other/numbers`) under `root`:
# its lock file and bare repository add `.lock` and `.git`.
_cached_base(root: Path, package: String): Path {
    var base = root;
    for (var part in package.split("/")) {
        base = base.join(part);
    }
    return base;
}

# Removes what the download cache holds, one package at a time, each under
# its lock, and keeps a package a fetch holds the lock of, saying so. The
# lock files stay: removing one a fetch waits on would let a second fetch
# lock a new file beside it.
clean_cache(): int {
    var root = cache_dir();
    var packages = Array<String>();
    _list_cached(root, "", packages);
    packages.sort((a, b) => a.compare(b));
    var removed = 0;
    for (var package in packages) {
        var base = _cached_base(root, package);
        var lock = io.OpenOptions().write(true).open(Path(base.to_string() + ".lock"));
        if (lock.is_err()) {
            return fail($"cannot open the lock of {package}: {lock.error().message}");
        }
        var held = lock.value().try_lock();
        if (held.is_err() or !held.value()) {
            say($"kept {package}: a fetch holds its lock");
            continue;
        }
        for (var path in [Path(base.to_string() + ".git"), Path(base.to_string() + ".git.partial"), base]) {
            if (path.exists()) {
                var gone = remove_tree(path);
                if (gone.is_err()) {
                    return fail($"cannot remove {path.to_string()}: {gone.error().message}");
                }
            }
        }
        removed += 1;
    }
    say($"removed {removed} packages from {root.to_string()}");
    return 0;
}

# `install`: builds the program of the package `spec` names, or of the one
# in the folder `path`, with `-O` and `options`, and puts it in the Pepper
# home's `bin`.
install_tool(spec: String, path: String, force: bool, options: Array<String>, offline: bool): int {
    if (spec.is_empty == path.is_empty) {
        return fail("give 'install' a package or --path, and not both");
    }
    var record = InstalledTool();
    record.toolchain_version = version();
    if (!path.is_empty) {
        var dir = Path(path).canonicalize();
        if (dir.is_err()) {
            return fail($"cannot find {path}: {dir.error().message}");
        }
        record.source = "path:" + dir.value().to_string();
        var text = File.read_to_string(dir.value().join("pep.toml"));
        var parsed = toml.parse(text.is_ok() ? text.value() : "");
        if (parsed.is_ok()) {
            record.version = _package_string(parsed.value(), "version");
        }
        return _report(install_program(dir.value(), record, force, options));
    }
    if (offline) {
        return fail(
            "--offline, and installing a package looks its versions up over the network; run it without --offline (or PEPPER_OFFLINE), or install a folder with --path"
        );
    }
    # A folder per process, so that two installs at once stay apart.
    var staging = toolchain.find_home().root.join("cache").join($"install-{process.id()}");
    if (staging.exists()) {
        var cleared = remove_tree(staging);
        if (cleared.is_err()) {
            return fail($"cannot remove {staging.to_string()}: {cleared.error().message}");
        }
    }
    var result = _install_through(staging, spec, record, force, options);
    remove_tree(staging);
    return result;
}

# Installs the package `spec` names, at the newest version its range
# allows that this toolchain builds, fetched through the download cache
# into `staging`.
_install_through(staging: Path, spec: String, record: InstalledTool, force: bool, options: Array<String>): int {
    var parsed = parse_package(spec);
    if (parsed.is_err()) {
        return fail(parsed.error().message);
    }
    var (host, repository, range) = parsed.value();
    var found = find_package(host, repository, range, Manifest().hosts);
    if (found.is_err()) {
        return fail(found.error().message);
    }
    var requirement = found.value().0;
    requirement.name = default_name(requirement.repository);
    # Only the package's own revision: its dependencies are its pep.lock's.
    var resolver = Resolver(staging, Manifest(), Array<Locked>());
    resolver.toolchain = version();
    var notes = Array<String>();
    var chosen = resolver.choose(requirement.source(), [Wanted("install", true, false, "", requirement)], notes);
    if (chosen.is_err()) {
        return fail(chosen.error().message);
    }
    for (var note in notes) {
        say(note);
    }
    record.source = requirement.source();
    record.version = chosen.value().version;
    record.commit = chosen.value().commit;
    # Built in a folder of its own: under `.pep`, it would build as part
    # of the project outside. Reading which toolchain a version needs
    # checked it out in `.pep/deps`, which then only moves.
    var package_folder = staging.join("package");
    var read = package_dir(staging, requirement.host, requirement.repository);
    if (read.is_directory()) {
        File.rename(read, package_folder);
    }
    var fetched = resolver.fetch(requirement.host, requirement.repository, package_folder, record.commit);
    if (fetched.is_err()) {
        return fail($"cannot fetch {record.source}: {fetched.error().message}");
    }
    return _report(install_program(package_folder, record, force, options));
}

# Says what `done` did, or fails with why it could not.
_report(done: Result<String>): int {
    if (done.is_err()) {
        return fail(done.error().message);
    }
    say(done.value());
    return 0;
}

# `install --list`: each program `install` put in the home's `bin`, with
# its version and source.
list_installed(): int {
    var records = read_installed();
    if (records.is_err()) {
        return fail(records.error().message);
    }
    for (var (name, record) in records.value()) {
        print($"{name} {record.describe()}");
    }
    return 0;
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

# The host (or empty), `owner/name` and range (or empty) that `spec`,
# `[host:]owner/name[@range]`, names.
parse_package(spec: String): Result<(String, String, String)> {
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
            return Result<(String, String, String)>.Err(parsed.error().message);
        }
    }
    var parts = rest.split("/");
    if (parts.count < 2 or (parts.count > 2 and host != "gitlab" and !host.is_empty) or parts.contains("")) {
        return Result<(String, String, String)>.Err($"'{spec}' must name a repository as owner/name");
    }
    return Result<(String, String, String)>.Ok((host, rest, range));
}

# The requirement on `repository` at `range`, on `host` or, when that is
# empty, the first of `hosts` that has it. With no range it asks for any
# release (`*`), and says so with true, or the default branch when there
# is no release.
find_package(host: String, repository: String, range: String, hosts: Array<String>): Result<(Requirement, bool)> {
    var requirement = Requirement();
    requirement.host = host;
    requirement.repository = repository;
    var refs = Array<RemoteRef>();
    if (host.is_empty) {
        var found = look_up(repository, hosts);
        if (found.is_err()) {
            return Result<(Requirement, bool)>.Err(found.error().message);
        }
        var (found_host, found_refs) = found.value();
        requirement.host = found_host;
        refs = found_refs;
    } else if (range.is_empty) {
        var read = remote_refs(repository_url(host, repository));
        if (read.is_err()) {
            return Result<(Requirement, bool)>.Err($"cannot read {host}:{repository}: {read.error().message}");
        }
        refs = read.value();
    }
    var any = false;
    if (range.is_empty) {
        for (var ref in refs) {
            if (ref.name.starts_with("refs/tags/")) {
                var version = tag_version(ref.name.substr(10, ref.name.length));
                any = any or (version.is_value() and version.value().prerelease.is_empty);
            }
        }
    }
    if (any or !range.is_empty) {
        requirement.kind = "version";
        requirement.value = any ? "*" : range;
    }
    return Result<(Requirement, bool)>.Ok((requirement, any));
}

# The first of `hosts` that has `repository`, and what it offers. Says so
# when another host has it too.
look_up(repository: String, hosts: Array<String>): Result<(String, Array<RemoteRef>)> {
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

# A project: its pep.toml, pep.lock and `.pep/deps`. In a workspace, the
# pep.toml is the member's or root's the command runs in, which `add`,
# `remove` and `publish` read, and pep.lock and `.pep/deps` are the
# root's, resolved for every member.
struct Project {
    var manifest_path: Path = Path("pep.toml");
    # The folder holding pep.lock and `.pep/deps`: the workspace's root,
    # else the package's own.
    var dir: Path = Path(".");
    # The pep.toml in `dir`.
    var root_path: Path = Path("pep.toml");
    # Whether `root_path` is a workspace's root.
    var is_workspace: bool = false;
    # `--locked`: fail rather than change pep.lock.
    var locked: bool = false;
    # `--offline`: use only what `.pep/deps` and the download cache hold.
    var offline: bool = false;

    construct(manifest_path: Path) {
        this.manifest_path = manifest_path;
        var workspace = find_workspace(manifest_path);
        is_workspace = workspace.is_value();
        root_path = workspace.value_or(manifest_path);
        var parent = root_path.parent();
        dir = parent.is_value() ? parent.value() : Path(".");
    }

    # The folder of `manifest_path`: the package the command is about.
    _package_dir(): Path {
        var parent = manifest_path.parent();
        return parent.is_value() ? parent.value() : Path(".");
    }

    # Resolves the graph, keeping locked revisions unless `update_all` or
    # `update` names them, checks every package out and writes pep.lock.
    # Returns the graph, or prints why it failed.
    _resolve(update_all: bool, update: Array<String>): Result<Graph> {
        var manifest = read_project(root_path);
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
        for (var warning in graph.value().warnings) {
            File.stderr().write_all(warning);
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
                if (!package.commit.is_empty and !package_dir(dir, host, repository).is_directory()) {
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
            # A folder overrides it: nothing to fetch.
            if (found.value().commit.is_empty) {
                continue;
            }
            var (host, repository) = split_source(source);
            var package = package_dir(dir, host, repository);
            var was_there = package.is_directory();
            var fetched = resolver.fetch(host, repository, package, found.value().commit, found.value().replaced_by);
            if (fetched.is_err()) {
                return fail($"cannot fetch {source}: {fetched.error().message}");
            }
            if (!was_there) {
                say($"fetched {found.value().describe()} ({source})");
            }
        }
        return 0;
    }

    # `extra` holds the entry's keys beyond its source and version
    # (`optional`, `features`, `default-features`).
    add(spec: String, given_name: String, dev: bool, target: String, extra: toml.TomlValue): int {
        if (offline) {
            return fail(
                $"--offline, and adding '{spec}' reads which versions it offers over the network; run 'pepper package add' without --offline (or PEPPER_OFFLINE)"
            );
        }
        var parsed = parse_package(spec);
        if (parsed.is_err()) {
            return fail(parsed.error().message);
        }
        var (given_host, rest, given_range) = parsed.value();
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
        var found = find_package(given_host, rest, given_range, manifest.value().hosts);
        if (found.is_err()) {
            return fail(found.error().message);
        }
        var (requirement, pin) = found.value();
        var host = requirement.host;
        var range = requirement.value;
        # With no range, any release resolves, and pep.toml then names the
        # one chosen (the newest this toolchain builds) as a caret range.
        var entry = toml.TomlValue.table();
        entry[host] = toml.TomlValue.String(rest);
        if (!range.is_empty) {
            entry["version"] = toml.TomlValue.String(range);
        }
        for (var (key, value) in extra.as_table().value()) {
            entry[key] = value;
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
        var manifest = read_project(manifest_path);
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
    # the PATH) run in the project's folder with no file, and `--all` in a
    # workspace.
    _builds(): bool {
        var command = process.Command(pep_build()).working_directory(dir);
        if (is_workspace) {
            command.argument("--all");
        }
        return _succeeds(command);
    }

    # Runs `command`, and whether it succeeded; prints what it printed when
    # it did not.
    _succeeds(command: process.Command): bool {
        var ran = command.run();
        if (ran.is_err()) {
            say($"cannot run {command.program}: {ran.error().message}");
            return false;
        }
        if (!ran.value().status.success()) {
            File.stderr().write_all(ran.value().stdout);
            File.stderr().write_all(ran.value().stderr);
            return false;
        }
        return true;
    }

    # The graph pep.lock records, for the reports.
    _graph(): Result<LockedGraph> {
        var manifest = read_project(root_path);
        if (manifest.is_err()) {
            return Result<LockedGraph>.Err(manifest.error().message);
        }
        var graph = read_graph(dir, manifest.value(), offline);
        if (graph.is_ok()) {
            graph.value().resolver.toolchain = version();
        }
        return graph;
    }

    # Prints the graph, or with `invert` what depends on that package.
    tree(depth: ulong, invert: String, json: bool): int {
        var graph = _graph();
        if (graph.is_err()) {
            return fail(graph.error().message);
        }
        if (invert.is_empty) {
            File.stdout().write_all(graph.value().tree(depth, json));
            return 0;
        }
        var targets = graph.value().find(invert);
        if (targets.is_empty) {
            return fail($"no package '{invert}' in pep.lock");
        }
        File.stdout().write_all(graph.value().inverted(targets, depth, json));
        return 0;
    }

    # Prints the first `limit` paths from the project to `spec`.
    why(spec: String, limit: ulong, json: bool): int {
        var graph = _graph();
        if (graph.is_err()) {
            return fail(graph.error().message);
        }
        var targets = graph.value().find(spec);
        if (targets.is_empty) {
            return fail($"no package '{spec}' in pep.lock");
        }
        File.stdout().write_all(graph.value().why(targets, limit, json));
        return 0;
    }

    # Lists what is outdated; with `exit_code`, any is status 1.
    outdated(exit_code: bool, json: bool): int {
        if (offline) {
            return fail(
                "--offline, and 'outdated' reads which versions each package offers over the network, so it cannot check; run it without --offline (or PEPPER_OFFLINE)"
            );
        }
        var graph = _graph();
        if (graph.is_err()) {
            return fail(graph.error().message);
        }
        var rows = graph.value().outdated();
        if (rows.is_err()) {
            return fail(rows.error().message);
        }
        if (json) {
            File.stdout().write_all(graph.value().outdated_json(rows.value()));
            return exit_code and !rows.value().is_empty ? 1 : 0;
        }
        if (rows.value().is_empty) {
            print("every package is at the newest version");
            return 0;
        }
        File.stdout().write_all(table(["package", "locked", "wanted", "latest", "source"], rows.value()));
        return exit_code ? 1 : 0;
    }

    # Checks that the package is ready to release at pep.toml's `version`
    # and runs its tests with its `minimum_toolchain` and the newest
    # toolchain installed; then, unless `dry_run`, tags the commit
    # `v<version>` and pushes the tag to `origin`.
    publish(dry_run: bool): int {
        if (offline) {
            return fail(
                "--offline, and publishing reads and pushes to the repository's remote; run 'pepper package publish' without --offline (or PEPPER_OFFLINE)"
            );
        }
        var manifest = read_project(manifest_path);
        if (manifest.is_err()) {
            return fail(manifest.error().message);
        }
        # read_project parsed it already.
        var root = toml.parse(manifest.value().text).value();
        var problems = Array<String>();
        var package_version = _package_string(root, "version");
        var parsed = semver.parse(package_version);
        if (package_version.is_empty) {
            problems.append("'[package]' has no 'version'");
        } else if (parsed.is_err()) {
            problems.append($"'version' '{package_version}' is not a version such as 1.2.0");
        }
        for (var key in ["description", "license", "repository"]) {
            if (_package_string(root, key).is_empty) {
                problems.append($"'[package]' has no '{key}'");
            }
        }
        for (var requirement in manifest.value().requirements) {
            # A dependent ignores dev-dependencies, so they may be anything;
            # a `path` (a workspace sibling) needs the `version` it is
            # published with.
            if (requirement.dev or requirement.kind == "version") {
                continue;
            }
            if (requirement.is_path()) {
                problems.append(
                    $"dependency '{requirement.name}' names path {requirement.repository} and no 'version', so a dependent cannot resolve it; give it the version of the package there"
                );
                continue;
            }
            problems.append(
                $"dependency '{requirement.name}' names {requirement.describe()}, not a version range, so a dependent cannot resolve it"
            );
        }
        # A dependent gets the packages it overrides, not the overrides it
        # was tested with.
        if (!manifest.value().overrides.is_empty) {
            problems.append(
                "'[overrides]' replaces packages for this project only, so a dependent would build with the originals; remove it"
            );
        }
        var minimum = manifest.value().minimum_toolchain;
        for (var (key, release) in newer_manifest_features()) {
            if (root.lookup(key).is_value() and !_at_least(minimum, release)) {
                problems.append(
                    $"'{key}' needs toolchain {release}, and older ones reject it; set '[package]' minimum_toolchain = \"{release}\" or later"
                );
            }
        }
        for (var requirement in manifest.value().requirements) {
            if (!requirement.feature_keys.is_empty and !_at_least(minimum, DEPENDENCY_FEATURES_RELEASE)) {
                problems.append(
                    $"'{requirement.feature_keys[0]}' of dependency '{requirement.name}' needs toolchain {DEPENDENCY_FEATURES_RELEASE}, and older ones reject it; set '[package]' minimum_toolchain = \"{DEPENDENCY_FEATURES_RELEASE}\" or later"
                );
            }
        }
        var at = _package_dir().to_string();
        var changes = git(["status", "--porcelain"], at);
        if (changes.is_err()) {
            return fail(changes.error().message);
        }
        if (!changes.value().trim().is_empty) {
            problems.append("the work tree has changes that are not committed:\n    " + changes.value().trim());
        }
        var head = git(["rev-parse", "HEAD"], at);
        if (head.is_err()) {
            return fail(head.error().message);
        }
        var commit = head.value().trim();
        var refs = remote_refs("origin", at);
        if (refs.is_err()) {
            return fail(refs.error().message);
        }
        var newest = Optional<semver.Version>.Empty;
        var has_head = false;
        for (var ref in refs.value()) {
            has_head = has_head or ref.name == "HEAD";
            if (ref.name == "HEAD" and ref.commit != commit) {
                problems.append(
                    $"HEAD ({commit.substr(0, 12)}) is not the tip of origin's default branch ({ref.commit.substr(0, 12)}); push it, or check that branch out"
                );
            }
            if (ref.name.starts_with("refs/tags/")) {
                var tagged = tag_version(ref.name.substr(10, ref.name.length));
                if (tagged.is_value() and (newest.is_empty() or tagged.value().compare(newest.value()) > 0)) {
                    newest = tagged;
                }
            }
        }
        if (!has_head) {
            problems.append("origin has no default branch (HEAD), so nothing shows the commit is pushed; push one");
        }
        if (parsed.is_ok() and newest.is_value() and parsed.value().compare(newest.value()) <= 0) {
            problems.append(
                $"'version' {package_version} is not newer than the newest tag, {newest.value().to_string()}; raise it in pep.toml"
            );
        }
        var name = manifest.value().name;
        if (!problems.is_empty) {
            return fail($"cannot publish {name} {package_version}:\n  " + "\n  ".join(problems));
        }
        # The home's own `pepper`, by its path: only it picks toolchains with
        # `+`, and a search by name may find another (Windows looks beside
        # this program before the PATH).
        var pepper = toolchain.find_home().root.join("bin").join("pepper" + toolchain.executable_suffix());
        if (!pepper.is_file()) {
            return fail(
                $"publish tests with the Pepper home's pepper, and {pepper.to_string()} does not exist; install Pepper with pep-install, or set PEPPER_HOME to its home"
            );
        }
        var releases = minimum.is_empty ? ["latest"] : [minimum, "latest"];
        for (var release in releases) {
            say($"running 'pepper +{release} test'");
            if (!_succeeds(
                process.Command(pepper.to_string()).arguments(["+" + release, "test"]).working_directory(_package_dir())
            )) {
                return fail($"'pepper +{release} test' failed, so {name} {package_version} is not published");
            }
        }
        var tag = "v" + package_version;
        if (dry_run) {
            say(
                $"{name} {package_version} is ready: without --dry-run, publish tags {commit.substr(0, 12)} {tag} and pushes it"
            );
            return 0;
        }
        var tagged = git(["tag", tag], at);
        if (tagged.is_err()) {
            return fail(tagged.error().message);
        }
        var pushed = git(["push", "--quiet", "origin", "refs/tags/" + tag], at);
        if (pushed.is_err()) {
            # Leave no tag behind that a retry would trip over.
            git(["tag", "-d", tag], at);
            return fail(pushed.error().message);
        }
        say($"published {name} {package_version}: tagged {commit.substr(0, 12)} {tag} and pushed it to origin");
        return 0;
    }
}

# The string `[package]` gives `key`, or empty.
_package_string(root: toml.TomlValue, key: String): String {
    var value = root.lookup("package." + key);
    if (value.is_empty() or value.value().as_string().is_empty()) {
        return "";
    }
    return value.value().as_string().value();
}

# Whether `minimum`, a `minimum_toolchain`, is `release` or later; an empty
# or malformed one is not.
_at_least(minimum: String, release: String): bool {
    var given = semver.parse(minimum);
    return given.is_ok() and given.value().compare(semver.parse(release).value()) >= 0;
}

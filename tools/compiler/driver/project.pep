## Projects: what building in a folder with a `pep.toml` takes from it, and
## fetching its dependencies.

import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import toolchain;

## What a build takes from the project it is in.
export struct ProjectSetup {
    ## The file to build: the one given, else the project's entry.
    var entry: Path;
    ## The executable to write, when the project names it (no file given).
    var output: Path? = Optional<Path>.Empty;
    ## The project's folder, when building the project itself (no file
    ## given): where `.pep/build` goes.
    var dir: Path? = Optional<Path>.Empty;
    ## `[build]`'s `link` libraries.
    var libraries: String[] = Array<String>();
    ## The package's name, when building the project itself (no file
    ## given): it names a library the build makes (`--lib`).
    var name: String = "";

    construct(entry: Path) {
        this.entry = entry;
    }
}

## What building `file`, or with no file the project around the current
## directory, takes from the project: the entry and output when no file is
## given, and `[build]`'s `link` libraries.
##
## @param file the file given, if any
## @param target the compile target: a Windows executable's name ends in
##   `.exe`
## @returns the setup, or why the project cannot be used
export apply_project(file: Path?, target: link.Target): Result<ProjectSetup, String> {
    var cwd = process.working_directory();
    var here = cwd.is_ok() ? cwd.value() : Path(".");
    Path? manifest_path;
    if (file.is_value()) {
        var project = link.find_project(here.join(file.value()));
        if (project.is_value()) {
            manifest_path = Optional<Path>.Value(project.value().join(Path(link.MANIFEST_FILE)));
        }
    } else {
        manifest_path = link.find_manifest(here);
        if (!manifest_path.is_value()) {
            return Result<ProjectSetup, String>.err(
                $"no source files provided, and no {link.MANIFEST_FILE} in {here} or a folder above it"
            );
        }
    }
    var setup = ProjectSetup(file.is_value() ? file.value() : Path(""));
    if (!manifest_path.is_value()) {
        return Result<ProjectSetup, String>.ok(setup);
    }
    var read = link.load_manifest(manifest_path.value(), Array<Path>());
    if (read.is_err()) {
        return Result<ProjectSetup, String>.err(read.error());
    }
    var manifest = read.value();
    if (!file.is_value()) {
        var entry = manifest.entry();
        if (!entry.is_file()) {
            return Result<ProjectSetup, String>.err(
                $"cannot find the project's entry file {entry}; set 'entry' in '[build]' of {manifest.path}"
            );
        }
        setup.entry = entry;
        var output = manifest.output();
        # A Windows executable needs its extension to run.
        if (target.os == "windows" and output.extension().is_empty()) {
            output = Path(output.to_string() + ".exe");
        }
        setup.output = Optional<Path>.Value(output);
        setup.dir = Optional<Path>.Value(manifest.dir());
        setup.name = manifest.name;
    }
    for (var library in manifest.link) {
        if (!setup.libraries.contains(library)) {
            setup.libraries.append(library);
        }
    }
    return Result<ProjectSetup, String>.ok(setup);
}

## Fetches what the project of `entry` needs and is missing: what
## `pep.lock` lists, or a dependency `pep.toml` names that the lock does
## not. With `pep-package` beside the compiler or on the PATH, it fetches
## (and locks); without it, git checks out each missing locked package.
## Only what a build for `target` needs: a package `pep.lock` locks for
## other targets (`target = "OS(Windows)"`) is left out, unless pep.toml
## names a package the lock does not list, which resolves the whole graph.
## A lock with no such package runs a full `pep-package fetch`, as before.
##
## Builds run side by side (`pepper test` builds every test program at
## once), and each would fetch into the same `.partial` folders: one at a
## time fetches, holding an exclusive lock on `.pep/fetch.lock`, and the
## rest find the packages there afterwards.
##
## `locked` fails rather than change `pep.lock`: a dependency `pep.toml`
## names that the lock does not list is an error, and `pep-package fetch
## --locked` checks the rest of the lock even when nothing is missing.
## `offline` passes `--offline` to `pep-package`, which takes a locked
## package `.pep/deps` lacks from the download cache or fails; without
## `pep-package`, such a package is an error.
##
## A vendored project (`[fetch] vendor`) fetches nothing, so it needs
## neither the network nor the download cache: every Git dependency must
## be in `pep.lock`, and every locked package the build needs must be in
## the vendor folder at its locked commit, its files as vendored
## (`toolchain.check_vendored`).
##
## @param entry the file being built
## @param locked whether a stale `pep.lock` is an error (`--locked`)
## @param offline whether fetching over the network is an error (`--offline`)
## @param target what the build is for (`--target`), which picks the
##   packages it needs
## @returns nothing, or why fetching failed
export fetch_dependencies(
    entry: Path, locked: bool = false, offline: bool = false, target: link.Target = link.Target()
): Result<void, String> {
    var project = link.find_project(entry);
    if (!project.is_value()) {
        return Result<void, String>.ok();
    }
    var manifest = link.load_manifest(project.value().join(Path(link.MANIFEST_FILE)), Array<Path>());
    if (manifest.is_err()) {
        return Result<void, String>.ok();
    }
    var needed = _needs_fetch(project.value(), manifest.value(), target);
    if (needed.is_err()) {
        return Result<void, String>.err(needed.error());
    }
    if (!manifest.value().vendor.is_empty) {
        return _check_vendor(project.value(), manifest.value(), needed.value(), target);
    }
    var refused = _refuse(project.value(), needed.value(), locked, offline);
    if (refused.is_err()) {
        return refused;
    }
    # A project with no Git dependency and no lock has nothing to check.
    var checks = locked
        and (!manifest.value().git_dependencies().is_empty or project.value().join(Path(link.LOCK_FILE)).is_file());
    if (needed.value().is_empty() and !checks) {
        return Result<void, String>.ok();
    }
    var lock_dir = project.value().join(Path(".pep"));
    var created = Directory.create_all(lock_dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {lock_dir}: {created.error().message}");
    }
    var lock_path = lock_dir.join(Path("fetch.lock"));
    var opened = io.OpenOptions().write(true).create(true).open(lock_path);
    if (opened.is_err()) {
        return Result<void, String>.err($"cannot open {lock_path}: {opened.error().message}");
    }
    var lock = opened.value();
    var held = lock.lock();
    if (held.is_err()) {
        return Result<void, String>.err($"cannot lock {lock_dir}: {held.error().message}");
    }
    var fetched = _fetch_locked(project.value(), manifest.value(), checks, offline, target);
    lock.close();
    return fetched;
}

## What a project lacks for a build: the locked packages it needs that are
## missing from `.pep/deps` or checked out there at another commit, and the
## Git dependencies `pep.toml`, or a `path` dependency's, names that
## `pep.lock` does not list.
struct _Missing {
    var packages: link.LockedPackage[] = Array<link.LockedPackage>();
    ## The sources of the Git dependencies `pep.lock` does not list, fetched
    ## or not.
    var not_locked: String[] = Array<String>();
    ## Those of `not_locked` that the build needs and `.pep/deps` does not
    ## hold.
    var not_fetched: String[] = Array<String>();
    ## Whether `pep.lock` holds a package the build's target does not need.
    var skipped: bool = false;

    is_empty(): bool {
        return packages.is_empty and not_fetched.is_empty;
    }
}

## What `project`, whose manifest is `manifest`, lacks for a build for
## `target`, read afresh.
_needs_fetch(project: Path, manifest: link.Manifest, target: link.Target): Result<_Missing, String> {
    var locked = link.read_lock(project.join(Path(link.LOCK_FILE)));
    if (locked.is_err()) {
        return Result<_Missing, String>.err(locked.error());
    }
    var missing = _Missing();
    for (var package in locked.value()) {
        var dir = link.package_directory(project, package.host, package.repository, manifest.vendor);
        if (!package.matches(target)) {
            missing.skipped = true;
        } else if (!dir.is_directory() or _is_stale(dir, package)) {
            missing.packages.append(package);
        }
    }
    # pep.lock covers every target, so any dependency it lacks makes it stale.
    var needed = HashSet<String>();
    for (var d in manifest.git_dependencies(Optional<link.Target>.Value(target))) {
        needed.insert(d.locked_source().value());
    }
    # A `path` dependency's own Git dependencies are fetched into this
    # project too.
    for (var d in manifest.git_dependencies()) {
        var source = d.locked_source().value();
        var is_locked = false;
        for (var package in locked.value()) {
            if (package.source() == source) {
                is_locked = true;
            }
        }
        if (!is_locked) {
            missing.not_locked.append(source);
            if (needed.contains(source) and !d.directory(project, project, manifest.vendor).is_directory()) {
                missing.not_fetched.append(source);
            }
        }
    }
    return Result<_Missing, String>.ok(missing);
}

## Checks the vendored `project` for a build for `target`, which lacks
## `missing`: no dependency `pep.lock` does not list, and each locked
## package the build needs vendored, unedited.
_check_vendor(project: Path, manifest: link.Manifest, missing: _Missing, target: link.Target): Result<void, String> {
    if (!missing.not_locked.is_empty) {
        return Result<void, String>.err(
            $"{project.join(Path(link.MANIFEST_FILE))} names {", ".join(missing.not_locked)}, which {link.LOCK_FILE} does not list, and the project is vendored ('[fetch] vendor'); run 'pepper package vendor'"
        );
    }
    var locked = link.read_lock(project.join(Path(link.LOCK_FILE)));
    if (locked.is_err()) {
        return Result<void, String>.err(locked.error());
    }
    for (var package in locked.value()) {
        if (package.matches(target)) {
            var dir = link.package_directory(project, package.host, package.repository, manifest.vendor);
            var checked = toolchain.check_vendored(dir, package.commit);
            if (checked.is_err()) {
                return checked;
            }
        }
    }
    return Result<void, String>.ok();
}

## Why `--locked` or `--offline` refuses what `project` lacks, `missing`:
## under `locked`, a dependency `pep.lock` does not list; under `offline`,
## with no `pep-package` to take it from the download cache, a package
## `.pep/deps` does not hold at all.
_refuse(project: Path, missing: _Missing, locked: bool, offline: bool): Result<void, String> {
    if (locked and !missing.not_locked.is_empty) {
        return Result<void, String>.err(
            $"{project.join(Path(link.LOCK_FILE))} is out of date: {project.join(Path(link.MANIFEST_FILE))} names {", ".join(missing.not_locked)}, which pep.lock does not list; run 'pepper package fetch' without --locked, and commit pep.lock"
        );
    }
    if (!offline or process.find_companion("pep-package").is_value()) {
        return Result<void, String>.ok();
    }
    var absent = Array<String>();
    for (var package in missing.packages) {
        if (!link.package_directory(project, package.host, package.repository).is_directory()) {
            var short = package.commit.size > 12 ? package.commit.substr_bytes(0, 12) : package.commit;
            absent.append($"{package.source()} {short}");
        }
    }
    absent.append_all(missing.not_fetched);
    if (absent.is_empty) {
        return Result<void, String>.ok();
    }
    return Result<void, String>.err(
        $"--offline, and {project.join(Path(".pep")).join(Path("deps"))} lacks {", ".join(absent)}; run 'pepper package fetch' without --offline first"
    );
}

## Whether `dir`, a checkout of `package`, is at another commit than
## pep.lock's: a detached git checkout's HEAD, or an unpacked
## archive's `.pep-commit`. A checkout on a branch is someone's work, so it
## stays as it is.
_is_stale(dir: Path, package: link.LockedPackage): bool {
    var head = File.read_to_string(dir.join(Path(".git")).join(Path("HEAD")));
    if (head.is_err()) {
        head = File.read_to_string(dir.join(Path(".pep-commit")));
    }
    if (head.is_err()) {
        return false;
    }
    var at = head.value().trim();
    if (at.starts_with("ref:")) {
        return false;
    }
    return at != package.commit;
}

## Fetches what `project` lacks, holding the fetch lock: another build may
## have fetched it while this one waited. `checks` runs `pep-package fetch
## --locked` even when nothing is missing. With a lock that lists every
## dependency, only the locked packages `target` needs are fetched.
_fetch_locked(
    project: Path, manifest: link.Manifest, checks: bool, offline: bool, target: link.Target
): Result<void, String> {
    var needed = _needs_fetch(project, manifest, target);
    if (needed.is_err()) {
        return Result<void, String>.err(needed.error());
    }
    if (needed.value().is_empty() and !checks) {
        return Result<void, String>.ok();
    }
    var missing = needed.value().packages;
    var unlocked = !needed.value().not_fetched.is_empty;
    var tool = process.find_companion("pep-package");
    if (tool.is_value()) {
        var arguments = ["-C", project.to_string(), "fetch"];
        if (checks) {
            arguments.append("--locked");
        }
        if (offline) {
            arguments.append("--offline");
        }
        # A current lock with packages for other targets: only those this
        # build needs, which resolving the graph would not leave out.
        if (!checks and needed.value().not_locked.is_empty and needed.value().skipped) {
            for (var package in missing) {
                arguments.append(package.source());
            }
        }
        var ran = process.Command(tool.value().to_string()).arguments(arguments).run();
        if (ran.is_err()) {
            return Result<void, String>.err($"cannot run {tool.value()}: {ran.error().message}");
        }
        if (!ran.value().status.success()) {
            # What pep-package said names the dependency and git's error.
            var said = (ran.value().stderr + ran.value().stdout).trim();
            var manifest_path = project.join(Path(link.MANIFEST_FILE));
            return Result<void, String>.err(
                $"fetching the dependencies of {manifest_path} failed ({tool.value()} {" ".join(arguments)} exited with {ran.value().status.to_string()})"
                    + (said.is_empty ? "" : $":\n{said}")
            );
        }
        return Result<void, String>.ok();
    }
    if (unlocked) {
        return Result<void, String>.err(
            $"the dependencies in {project.join(Path(link.MANIFEST_FILE))} are not fetched; run 'pepper package fetch'"
        );
    }
    for (var package in missing) {
        var dir = link.package_directory(project, package.host, package.repository);
        if (dir.is_directory()) {
            # A stale checkout may hold edits: pep-package moves it, never deletes it.
            return Result<void, String>.err(
                $"{dir} is not at the commit {project.join(Path(link.LOCK_FILE))} locks; run 'pepper package fetch'"
            );
        }
        var checked = _check_out(project, package);
        if (checked.is_err()) {
            return checked;
        }
    }
    return Result<void, String>.ok();
}

## Clones `package` at its locked commit into the project's `.pep/deps`,
## through a `.partial` folder so an interrupted fetch leaves no package.
_check_out(project: Path, package: link.LockedPackage): Result<void, String> {
    var dir = link.package_directory(project, package.host, package.repository);
    var url = package.clone_url();
    var short = package.commit.size > 12 ? package.commit.substr_bytes(0, 12) : package.commit;
    io.File.stderr().write_all($"pepc: fetching {package.source()} {short}\n");
    var partial = Path(dir.to_string() + ".partial");
    Directory.remove_all(partial);
    var parent = partial.parent();
    if (parent.is_value()) {
        var created = Directory.create_all(parent.value());
        if (created.is_err()) {
            return Result<void, String>.err($"cannot create {parent.value()}: {created.error().message}");
        }
    }
    var cloned = _git(["clone", "--quiet", "--no-checkout", url, partial.to_string()], Optional<Path>.Empty);
    if (cloned.is_err()) {
        return cloned;
    }
    var checked = _git(["checkout", "--quiet", "--detach", package.commit], Optional<Path>.Value(partial));
    if (checked.is_err()) {
        return checked;
    }
    var moved = io.File.rename(partial, dir);
    if (moved.is_err()) {
        return Result<void, String>.err($"cannot move {partial} to {dir}: {moved.error().message}");
    }
    return Result<void, String>.ok();
}

## Runs git with `arguments`, in `dir` when given.
_git(arguments: String[], dir: Path?): Result<void, String> {
    # No fsmonitor daemon, which would outlive the build, for a dependency's checkout.
    var command = process
        .Command("git")
        .arguments(["-c", "core.fsmonitor=false"])
        .arguments(arguments)
        .environment("GIT_TERMINAL_PROMPT", "0");
    if (dir.is_value()) {
        command.working_directory(dir.value());
    }
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    if (ran.is_err()) {
        return Result<void, String>.err($"cannot run git, which fetching dependencies needs: {ran.error().message}");
    }
    if (ran.value().status.success()) {
        return Result<void, String>.ok();
    }
    return Result<void, String>.err($"git {" ".join(arguments)} failed: {ran.value().stderr.trim()}");
}

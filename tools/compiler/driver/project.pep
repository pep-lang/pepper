## Projects: what building in a folder with a `pep.toml` takes from it, and
## fetching its dependencies.

import io;
import [Directory, File, Path] from io;
import compiler.link;
import process;

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
##
## Builds run side by side (`pepper test` builds every test program at
## once), and each would fetch into the same `.partial` folders: one at a
## time fetches, holding an exclusive lock on `.pep/fetch.lock`, and the
## rest find the packages there afterwards.
##
## @param entry the file being built
## @returns nothing, or why fetching failed
export fetch_dependencies(entry: Path): Result<void, String> {
    var project = link.find_project(entry);
    if (!project.is_value()) {
        return Result<void, String>.ok();
    }
    var manifest = link.load_manifest(project.value().join(Path(link.MANIFEST_FILE)), Array<Path>());
    if (manifest.is_err()) {
        return Result<void, String>.ok();
    }
    var needed = _needs_fetch(project.value(), manifest.value());
    if (needed.is_err()) {
        return Result<void, String>.err(needed.error());
    }
    if (needed.value().is_empty()) {
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
    var locked = lock.lock();
    if (locked.is_err()) {
        return Result<void, String>.err($"cannot lock {lock_dir}: {locked.error().message}");
    }
    var fetched = _fetch_locked(project.value(), manifest.value());
    lock.close();
    return fetched;
}

## What a project lacks: the locked packages missing from `.pep/deps` or
## checked out there at another commit, and whether `pep.toml`, or a `path`
## dependency's, names a Git dependency `pep.lock` does not list.
struct _Missing {
    var packages: link.LockedPackage[] = Array<link.LockedPackage>();
    var unlocked: bool = false;

    is_empty(): bool {
        return packages.is_empty and !unlocked;
    }
}

## What `project`, whose manifest is `manifest`, lacks, read afresh.
_needs_fetch(project: Path, manifest: link.Manifest): Result<_Missing, String> {
    var locked = link.read_lock(project.join(Path(link.LOCK_FILE)));
    if (locked.is_err()) {
        return Result<_Missing, String>.err(locked.error());
    }
    var missing = _Missing();
    for (var package in locked.value()) {
        var dir = link.package_directory(project, package.host, package.repository);
        if (!dir.is_directory() or _is_stale(dir, package)) {
            missing.packages.append(package);
        }
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
        if (!is_locked and !d.directory(project, project).is_directory()) {
            missing.unlocked = true;
        }
    }
    return Result<_Missing, String>.ok(missing);
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
## have fetched it while this one waited.
_fetch_locked(project: Path, manifest: link.Manifest): Result<void, String> {
    var needed = _needs_fetch(project, manifest);
    if (needed.is_err()) {
        return Result<void, String>.err(needed.error());
    }
    if (needed.value().is_empty()) {
        return Result<void, String>.ok();
    }
    var missing = needed.value().packages;
    var unlocked = needed.value().unlocked;
    var tool = process.find_companion("pep-package");
    if (tool.is_value()) {
        var ran = process
            .Command(tool.value().to_string())
            .argument("-C")
            .argument(project.to_string())
            .argument("fetch")
            .run();
        if (ran.is_err()) {
            return Result<void, String>.err($"cannot run {tool.value()}: {ran.error().message}");
        }
        if (!ran.value().status.success()) {
            # What pep-package said names the dependency and git's error.
            var said = (ran.value().stderr + ran.value().stdout).trim();
            var manifest_path = project.join(Path(link.MANIFEST_FILE));
            return Result<void, String>.err(
                $"fetching the dependencies of {manifest_path} failed ({tool.value()} -C {project} fetch exited with {ran.value().status.to_string()})"
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
    var url = package.host.clone_url(package.repository);
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

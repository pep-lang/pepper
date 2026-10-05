## Projects: what building in a folder with a `pep.toml` takes from it, and
## fetching its dependencies, as `crates/pepper-driver/src/options.rs`
## (`apply_project`) and `fetch.rs` do.

import io;
import [Directory, Path] from io;
import compiler.link;
import os;
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

    construct(entry: Path) {
        this.entry = entry;
    }
}

## What building `file`, or with no file the project around the current
## directory, takes from the project: the entry and output when no file is
## given, and `[build]`'s `link` libraries.
##
## @param file the file given, if any
## @returns the setup, or why the project cannot be used
export apply_project(file: Path?): Result<ProjectSetup, String> {
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
        if (os.system_os() == os.OperatingSystem.Windows and output.extension().is_empty()) {
            output = Path(output.to_string() + ".exe");
        }
        setup.output = Optional<Path>.Value(output);
        setup.dir = Optional<Path>.Value(manifest.dir());
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
    var locked = link.read_lock(project.value().join(Path(link.LOCK_FILE)));
    if (locked.is_err()) {
        return Result<void, String>.err(locked.error());
    }
    var missing = Array<link.LockedPackage>();
    for (var package in locked.value()) {
        if (!link.package_directory(project.value(), package.host, package.repository).is_directory()) {
            missing.append(package);
        }
    }
    var unlocked = false;
    for (var d in manifest.value().dependencies) {
        var source = d.locked_source();
        if (!source.is_value()) {
            continue;
        }
        var is_locked = false;
        for (var package in locked.value()) {
            if (package.source() == source.value()) {
                is_locked = true;
            }
        }
        if (!is_locked and !d.directory(project.value(), project.value()).is_directory()) {
            unlocked = true;
        }
    }
    if (missing.is_empty and !unlocked) {
        return Result<void, String>.ok();
    }
    var tool = process.find_companion("pep-package");
    if (tool.is_value()) {
        var ran = process
            .Command(tool.value().to_string())
            .argument("-C")
            .argument(project.value().to_string())
            .argument("fetch")
            .run();
        if (ran.is_err()) {
            return Result<void, String>.err($"cannot run {tool.value()}: {ran.error().message}");
        }
        if (!ran.value().status.success()) {
            return Result<void, String>.err("fetching the project's dependencies failed");
        }
        return Result<void, String>.ok();
    }
    if (unlocked) {
        return Result<void, String>.err(
            $"the dependencies in {project.value().join(Path(link.MANIFEST_FILE))} are not fetched; run 'pepper package fetch'"
        );
    }
    for (var package in missing) {
        var checked = _check_out(project.value(), package);
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
    var command = process.Command("git").arguments(arguments).environment("GIT_TERMINAL_PROMPT", "0");
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

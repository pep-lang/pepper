# pep-package end to end, the one beside the test program or on the PATH
# (scripts/pepper-tests.sh builds it, beside the `pep-build` that runs
# it): it adds, removes, updates and fetches a project's dependencies, and
# `pep-build` fetches what `pep.lock` lists and `.pep/deps` lacks. The
# packages come from bare git repositories in a test folder, which
# `PEPPER_PACKAGE_GITHUB_URL` points the tools at. The tests skip when
# git is missing.

import async;
import [Directory, File, Path] from io;
import process;
import [serve_folder] from tool_testing.server;
import [TempFolder] from testing;
import [expect_contains, expect_exit, read_file, run, tool, write_file] from tool_testing;
import toolchain;

# The folder of bare repositories that stands in for github.com:
# `other/numbers` (versions 1.0.0, 1.3.1, 2.0.0 and 3.0.0, which drops
# `numbers_version`) and `someone/geometry` (1.0.0 and 1.1.0, which need
# `other/numbers` 1).
struct Hosts {
    var folder: TempFolder;
    # `file://` and the folder.
    var url: String;

    construct(name: String) {
        folder = TempFolder($"package_hosts_{name}");
        url = $"file://{folder.path}";
        for (var version in ["1.0.0", "1.3.1", "2.0.0", "3.0.0"]) {
            var function = version == "3.0.0" ? "renamed" : "numbers_version";
            add_version(
                folder.path,
                "other/numbers",
                version,
                ["module.pep", "export " + function + "(): String {\n    return \"" + version + "\";\n}\n"]
            );
        }
        for (var version in ["1.0.0", "1.1.0"]) {
            add_version(
                folder.path,
                "someone/geometry",
                version,
                [
                    "module.pep",
                    "import numbers;\n\nexport area(w: int, h: int): int {\n    return w * h;\n}\n\n"
                        + "export geometry_version(): String {\n    return \""
                        + version
                        + " \" + numbers.numbers_version();\n}\n",
                    "pep.toml",
                    "[package]\nname = \"geometry\"\n\n[dependencies]\n"
                        + "numbers = { github = \"other/numbers\", version = \"1\" }\n"
                ]
            );
        }
        publish(folder.path, "other/numbers");
        publish(folder.path, "someone/geometry");
    }

    # The command that runs `program` with `arguments` in `dir`, with this
    # stand-in for github.com, and GitLab and Codeberg in folders that do not
    # exist, so a lookup never leaves the machine (`add` asks every host).
    command(program: String, dir: Path, arguments: Array<String>): process.Command {
        return process
            .Command(program)
            .arguments(arguments)
            .working_directory(dir)
            .environment("PEPPER_PACKAGE_GITHUB_URL", url)
            .environment("PEPPER_PACKAGE_GITLAB_URL", url + "/gitlab")
            .environment("PEPPER_PACKAGE_CODEBERG_URL", url + "/codeberg");
    }

    # Runs pep-package with `arguments` in `dir`.
    package(dir: Path, arguments: Array<String>): process.Output {
        return run(command(tool("pep-package").to_string(), dir, arguments));
    }

    # Builds the project in `dir` as `pep-build` with no file does, which
    # fetches what it lacks, and returns what the program prints, or the
    # build's output when it fails.
    build_and_run(dir: Path): String {
        var built = run(command(tool("pep-build").to_string(), dir, Array<String>()));
        if (!built.status.success()) {
            return $"the build failed:\n{built.stdout}{built.stderr}";
        }
        return run(process.Command(dir.join("app" + toolchain.executable_suffix()).to_string())).stdout;
    }

    # The full commit `revision` names in the bare repository `name`.
    commit_of(name: String, revision: String): String {
        var output = run(
            process.Command("git").arguments(["rev-parse", revision + "^{commit}"]).working_directory(bare(name))
        );
        return output.stdout.trim();
    }

    # The bare repository `name`.
    bare(name: String): Path {
        return folder.path.join(name + ".git");
    }
}

# Whether git runs here; says the test skips when not.
has_git(): bool {
    var ran = process.Command("git").argument("--version").run();
    if (ran.is_ok() and ran.value().status.success()) {
        return true;
    }
    print("skipped: git is not on the PATH");
    return false;
}

# Runs git with `arguments` in `dir`, as a test author.
git(dir: Path, arguments: Array<String>) {
    var output = run(
        process
            .Command("git")
            .arguments(["-c", "core.fsmonitor=false"])
            .arguments(arguments)
            .working_directory(dir)
            .environment("GIT_AUTHOR_NAME", "test")
            .environment("GIT_AUTHOR_EMAIL", "test@example.com")
            .environment("GIT_COMMITTER_NAME", "test")
            .environment("GIT_COMMITTER_EMAIL", "test@example.com")
    );
    if (!output.status.success()) {
        panic($"git {" ".join(arguments)}: {output.stderr}");
    }
}

# Commits `files` (file names and their texts, in turn) to the work tree
# of the repository `name` under `root`, tagged `v<version>`.
add_version(root: Path, name: String, version: String, files: Array<String>) {
    var work = root.join("work").join(name);
    if (!work.exists()) {
        Directory.create_all(work);
        git(work, ["init", "--quiet", "--initial-branch=main"]);
    }
    ulong index = 0;
    while (index + 1 < files.count) {
        write_file(work.join(files[index]), files[index + 1]);
        index += 2;
    }
    git(work, ["add", "-A"]);
    git(work, ["commit", "--quiet", "-m", version]);
    git(work, ["tag", "v" + version]);
}

# Clones the work tree of the repository `name` under `root` to the bare
# repository `<root>/<name>.git`.
publish(root: Path, name: String) {
    git(
        root,
        ["clone", "--quiet", "--bare", root.join("work").join(name).to_string(), root.join(name + ".git").to_string()]
    );
}

# A fresh project in a test folder: `pep.toml` with `dependencies` (lines
# of the table) and a `main.pep` that prints `geometry_version()`.
struct Project {
    var folder: TempFolder;
    var dir: Path;

    construct(name: String, dependencies: String) {
        folder = TempFolder($"package_{name}");
        dir = folder.path;
        write_file(dir.join("pep.toml"), "[package]\nname = \"app\"  # the app\n\n[dependencies]\n" + dependencies);
        write_file(
            dir.join("main.pep"),
            "import geometry;\n\nmain(): int {\n    print(geometry.geometry_version());\n    return 0;\n}\n"
        );
    }

    manifest(): String {
        return read_file(dir.join("pep.toml"));
    }

    lock(): String {
        return read_file(dir.join("pep.lock"));
    }
}

[Test]
add_fetches_the_newest_version_and_its_dependencies() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("add");
    var project = Project("add", "");
    expect_exit(hosts.package(project.dir, ["add", "someone/geometry"]), 0);
    # pep.toml keeps its comment and gains the dependency at the newest
    # version.
    expect_equal(
        project.manifest(),
        "[package]\nname = \"app\"  # the app\n\n[dependencies]\n"
            + "geometry = { github = \"someone/geometry\", version = \"1.1.0\" }\n"
    );
    # One version of numbers, the newest geometry accepts.
    expect_contains(project.lock(), "source = \"github:someone/geometry\"\nversion = \"1.1.0\"");
    expect_contains(project.lock(), "source = \"github:other/numbers\"\nversion = \"1.3.1\"");
    expect_equal(hosts.build_and_run(project.dir), "1.1.0 1.3.1\n");

    # A taken name, and a runtime module's name.
    var taken = hosts.package(project.dir, ["add", "other/geometry"]);
    expect_exit(taken, 1);
    expect_contains(
        taken.stderr, "a dependency named 'geometry' already exists (github:someone/geometry); add this one with --name"
    );
    var runtime = hosts.package(project.dir, ["add", "other/io"]);
    expect_contains(runtime.stderr, "'io' is the name of a runtime module; add the dependency with --name");

    # Removing it drops numbers too.
    expect_exit(hosts.package(project.dir, ["remove", "geometry"]), 0);
    expect_false(project.dir.join("pep.lock").exists());
}

[Test]
builds_fetch_what_pep_lock_lists() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("build_fetch");
    var project = Project("build_fetch", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    # A fresh clone has pep.toml and pep.lock, and no .pep: the build
    # fetches the locked commits.
    Directory.remove_all(project.dir.join(".pep"));
    expect_equal(hosts.build_and_run(project.dir), "1.1.0 1.3.1\n");
}

[Test]
builds_move_a_checkout_pep_lock_has_moved_past() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("build_stale");
    var project = Project("build_stale", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    # A checkout from before pep.lock moved to 1.1.0: the build
    # moves it to the locked commit.
    var geometry = project.dir.join(".pep").join("deps").join("github.com").join("someone").join("geometry");
    git(geometry, ["checkout", "--quiet", "--detach", "v1.0.0"]);
    expect_equal(hosts.build_and_run(project.dir), "1.1.0 1.3.1\n");
}

[Test]
builds_side_by_side_fetch_once() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("parallel_fetch");
    var project = Project("parallel_fetch", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    Directory.remove_all(project.dir.join(".pep"));
    # `pepper test` builds its test programs at once: each build
    # fetches what `.pep/deps` lacks, and none trips over another's
    # checkout.
    var children = Array<process.Child>();
    for (var build in 0..8) {
        var arguments = ["main.pep", "-o", $"app_{build}", "--build", project.dir.join($"build_{build}").to_string()];
        children.append(
            hosts
                .command(tool("pep-build").to_string(), project.dir, arguments)
                .stdout(process.Stream.Null)
                .stderr(process.Stream.Pipe)
                .spawn()
                .value()
        );
    }
    ulong failed = 0;
    for (var child in children) {
        var errors = child.stderr().read_string().ok_or("");
        if (!child.wait().value().success()) {
            print(errors);
            failed += 1;
        }
    }
    expect_equal(failed, 0 as ulong);
    expect_equal(hosts.build_and_run(project.dir), "1.1.0 1.3.1\n");
}

[Test]
fetches_start_no_fsmonitor_daemon() {
    if (!has_git()) {
        return;
    }
    # As with `core.fsmonitor = true` in a user's git config, where
    # every checkout would start a daemon that outlives the command.
    var hosts = Hosts("fsmonitor");
    var project = Project("fsmonitor", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    var fetch = hosts
        .command(tool("pep-package").to_string(), project.dir, ["fetch"])
        .environment("GIT_CONFIG_COUNT", "1")
        .environment("GIT_CONFIG_KEY_0", "core.fsmonitor")
        .environment("GIT_CONFIG_VALUE_0", "true");
    expect_exit(run(fetch), 0);
    var geometry = project.dir.join(".pep").join("deps").join("github.com").join("someone").join("geometry");
    # `status` fails when no daemon runs, and where git has no fsmonitor.
    var status = run(process.Command("git").arguments(["fsmonitor--daemon", "status"]).working_directory(geometry));
    if (status.status.success()) {
        run(process.Command("git").arguments(["fsmonitor--daemon", "stop"]).working_directory(geometry));
        panic($"pep-package fetch left an fsmonitor daemon running for {geometry}");
    }
}

[Test]
the_project_overrides_a_dependency_and_update_says_what_holds_one_back() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("override");
    var project = Project("override", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    var updated = hosts.package(project.dir, ["update", "numbers"]);
    expect_exit(updated, 0);
    expect_contains(updated.stderr, "github:other/numbers stays at 1.3.1, not 3.0.0: geometry 1.1.0 wants 1");
    # Naming numbers in pep.toml overrides geometry's range.
    write_file(
        project.dir.join("pep.toml"), project.manifest() + "numbers = { github = \"other/numbers\", version = \"2\" }\n"
    );
    var fetched = hosts.package(project.dir, ["fetch"]);
    expect_exit(fetched, 0);
    expect_contains(fetched.stderr, "github:other/numbers 2.0.0 overrides what geometry 1.1.0 asks (1)");
    expect_equal(hosts.build_and_run(project.dir), "1.1.0 2.0.0\n");
    # A range nothing satisfies names the requirement and what is offered.
    var failed = hosts.package(project.dir, ["add", "other/numbers@4", "--name", "more"]);
    expect_exit(failed, 1);
    expect_contains(
        failed.stderr,
        "no revision of github:other/numbers satisfies every package that needs it:\n  app wants 2\n  app wants 4\n"
            + "  it offers 1.0.0, 1.3.1, 2.0.0, 3.0.0"
    );
    # A failed add leaves pep.toml as it was.
    expect_false(project.manifest().contains("more"));
}

[Test]
update_verify_keeps_only_updates_that_build() {
    if (!has_git()) {
        return;
    }
    # Lock the oldest versions, then widen the ranges and let verify try
    # the newest: geometry 1.1.0 builds, numbers 3.0.0 (which drops
    # numbers_version) does not. pep-package finds pep-build beside it or
    # on the PATH.
    var hosts = Hosts("verify");
    var project = Project(
        "verify",
        "geometry = { github = \"someone/geometry\", version = \"=1.0.0\" }\n"
            + "numbers = { github = \"other/numbers\", version = \"=1.0.0\" }\n"
    );
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    var widened = project.manifest().replace(
        "geometry = { github = \"someone/geometry\", version = \"=1.0.0\" }",
        "geometry = { github = \"someone/geometry\", version = \"1.0\" }"
    );
    write_file(project.dir.join("pep.toml"), widened.replace("\"=1.0.0\"", "\">=1\""));
    var verified = hosts.package(project.dir, ["update", "--verify"]);
    expect_exit(verified, 0);
    expect_contains(verified.stderr, "rolled back, because the project did not build with them: github:other/numbers");
    # numbers stays at 1.0.0.
    expect_contains(project.lock(), "source = \"github:other/numbers\"\nversion = \"1.0.0\"");
    expect_contains(project.lock(), "source = \"github:someone/geometry\"\nversion = \"1.1.0\"");
}

# Writes GitHub's archive of `revision` of `name` (a `.tar.gz` whose files
# sit in one top-level folder) where the archive server serves the
# archive of `commit`: `<root>/<name>/<commit>.tar.gz`. Like the host's,
# its files keep the line endings they were committed with, whatever this
# machine's `core.autocrlf` (Git for Windows turns it on).
write_archive(hosts: Hosts, root: Path, name: String, revision: String, commit: String) {
    var file = root.join(name).join(commit + ".tar.gz");
    Directory.create_all(file.parent().value());
    var short = name.split("/")[1];
    git(
        hosts.bare(name),
        [
            "-c",
            "core.autocrlf=false",
            "-c",
            "core.eol=lf",
            "archive",
            "--format=tar.gz",
            $"--prefix={short}-{commit}/",
            $"--output={file}",
            revision
        ]
    );
}

# Runs pep-package with `arguments` in `dir`, with no git on the PATH and
# archives downloaded from `archives`.
package_without_git(hosts: Hosts, dir: Path, arguments: Array<String>, archives: String): process.Output {
    var empty = dir.join("no_git_bin");
    Directory.create_all(empty);
    return run(
        hosts
            .command(tool("pep-package").to_string(), dir, arguments)
            .environment("PATH", empty.to_string())
            .environment("PEPPER_PACKAGE_GITHUB_ARCHIVE_URL", archives)
    );
}

[Test]
a_locked_project_fetches_archives_without_git_and_checks_their_files() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("no_git");
    var project = Project("no_git", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    # Fetching with git records the checksum of each package's files.
    var locked = project.lock();
    expect_equal(locked.split("\nsha256 = \"").count, 3 as ulong);

    var archives = project.dir.join("archives");
    var geometry = hosts.commit_of("someone/geometry", "v1.1.0");
    var numbers = hosts.commit_of("other/numbers", "v1.3.1");
    write_archive(hosts, archives, "someone/geometry", geometry, geometry);
    write_archive(hosts, archives, "other/numbers", numbers, numbers);
    async.run(
        () => {
            var served = serve_folder(archives);
            var server = served.substr(0, served.length - 1);

            # A fresh clone on a machine with no git: the archives of the
            # locked commits, whose files match pep.lock's checksums.
            Directory.remove_all(project.dir.join(".pep"));
            expect_exit(package_without_git(hosts, project.dir, ["fetch"], server), 0);
            # The lock stays as it was.
            expect_equal(project.lock(), locked);
            expect_equal(hosts.build_and_run(project.dir), "1.1.0 1.3.1\n");
            # Fetching again finds them in place.
            expect_exit(package_without_git(hosts, project.dir, ["fetch"], server), 0);

            # A tampered archive: 1.3.1's commit serves 2.0.0's files.
            write_archive(hosts, archives, "other/numbers", "v2.0.0", numbers);
            Directory.remove_all(project.dir.join(".pep"));
            var tampered = package_without_git(hosts, project.dir, ["fetch"], server);
            expect_exit(tampered, 1);
            var expected = locked.split("source = \"github:other/numbers\"")[1].split("sha256 = \"")[1].split("\"")[0];
            expect_contains(
                tampered.stderr,
                $"cannot fetch github:other/numbers: the files of github:other/numbers {numbers.substr(0, 12)} do not match pep.lock: sha256 "
            );
            expect_contains(tampered.stderr, $", expected {expected}");

            # Resolving what pep.lock does not pin needs git.
            var added = package_without_git(hosts, project.dir, ["add", "other/numbers", "--name", "more"], server);
            expect_exit(added, 1);
            expect_contains(added.stderr, "git is not on the PATH");
        }
    );
}

[Test]
a_stale_lock_fails_under_locked() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("locked");
    var project = Project("locked", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    var lock = project.lock();
    # An up-to-date lock passes.
    expect_exit(hosts.package(project.dir, ["fetch", "--locked"]), 0);

    # pep.toml now asks for numbers 2, which pep.lock does not have.
    write_file(
        project.dir.join("pep.toml"), project.manifest() + "numbers = { github = \"other/numbers\", version = \"2\" }\n"
    );
    var refused = hosts.package(project.dir, ["fetch", "--locked"]);
    expect_exit(refused, 1);
    expect_contains(
        refused.stderr,
        "pep.lock would change, and --locked keeps it as it is:\n  updated numbers: numbers 1.3.1 -> numbers 2.0.0\n"
            + "run the command without --locked (or PEPPER_LOCKED), then commit pep.lock"
    );
    expect_equal(project.lock(), lock);
    var by_variable = run(
        hosts.command(tool("pep-package").to_string(), project.dir, ["fetch"]).environment("PEPPER_LOCKED", "1")
    );
    expect_exit(by_variable, 1);
    expect_contains(by_variable.stderr, "pep.lock would change");
    # `pep-build --locked` checks the lock too, though nothing is missing.
    var built = run(hosts.command(tool("pep-build").to_string(), project.dir, ["--locked"]));
    expect_exit(built, 1);
    expect_contains(built.stderr, "pep.lock would change");
    expect_equal(project.lock(), lock);
    # Without --locked, fetch updates it.
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    expect_contains(project.lock(), "source = \"github:other/numbers\"\nversion = \"2.0.0\"");
}

[Test]
an_unfetched_dependency_fails_under_offline() {
    if (!has_git()) {
        return;
    }
    var hosts = Hosts("offline");
    var project = Project("offline", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    expect_exit(hosts.package(project.dir, ["fetch"]), 0);
    # Every host is a folder that does not exist: a network attempt fails
    # with git's error, not --offline's.
    var unreachable = (program: String, arguments: Array<String>) => {
        return run(
            hosts.command(
                tool(program).to_string(), project.dir, arguments
            ).environment("PEPPER_PACKAGE_GITHUB_URL", hosts.url + "/nowhere")
        );
    };
    # What .pep/deps holds is enough.
    expect_exit(unreachable("pep-package", ["fetch", "--offline"]), 0);
    expect_exit(unreachable("pep-package", ["fetch", "--frozen"]), 0);

    Directory.remove_all(project.dir.join(".pep"));
    var refused = unreachable("pep-package", ["fetch", "--offline"]);
    expect_exit(refused, 1);
    expect_contains(refused.stderr, "--offline, and ");
    expect_contains(refused.stderr, " does not hold the commit ");
    expect_contains(refused.stderr, "; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first");
    expect_false(refused.stderr.contains("git clone"));
    var built = unreachable("pep-build", ["--offline"]);
    expect_exit(built, 1);
    expect_contains(built.stderr, "lacks github:other/numbers ");
    expect_false(project.dir.join(".pep").join("deps").exists());
    var added = unreachable("pep-package", ["add", "other/numbers", "--name", "more", "--offline"]);
    expect_exit(added, 1);
    expect_contains(
        added.stderr, "--offline, and adding 'other/numbers' reads which versions it offers over the network"
    );
}

[Test]
add_looks_a_repository_up_on_each_host() {
    if (!has_git()) {
        return;
    }
    # A Codeberg with `third/shapes`, and a GitLab with nothing, so no
    # lookup leaves the machine.
    var hosts = Hosts("lookup");
    var codeberg = TempFolder("package_codeberg");
    var gitlab = TempFolder("package_gitlab");
    add_version(codeberg.path, "third/shapes", "0.2.0", ["module.pep", "export sides(): int {\n    return 4;\n}\n"]);
    publish(codeberg.path, "third/shapes");
    add_version(codeberg.path, "other/numbers", "9.0.0", ["module.pep", ""]);
    publish(codeberg.path, "other/numbers");
    var add = (dir: Path, spec: String) => {
        return run(
            hosts
                .command(tool("pep-package").to_string(), dir, ["add", spec])
                .environment("PEPPER_PACKAGE_CODEBERG_URL", $"file://{codeberg.path}")
                .environment("PEPPER_PACKAGE_GITLAB_URL", $"file://{gitlab.path}")
        );
    };

    # Only Codeberg has it: no prefix needed.
    var project = Project("lookup", "");
    var added = add(project.dir, "third/shapes");
    expect_exit(added, 0);
    expect_contains(project.manifest(), "shapes = { codeberg = \"third/shapes\", version = \"0.2.0\" }");
    expect_contains(added.stderr, "'import shapes;' now imports codeberg:third/shapes");

    # On two hosts: the first in the order wins, and add says so.
    var both = add(project.dir, "other/numbers");
    expect_exit(both, 0);
    expect_contains(
        both.stderr,
        "other/numbers is on github and codeberg; adding github:other/numbers (prefix it with 'codeberg:' for another)"
    );

    # pep.toml's [fetch] hosts changes the order.
    var ordered = Project("lookup_order", "");
    write_file(ordered.dir.join("pep.toml"), ordered.manifest() + "\n[fetch]\nhosts = [\"codeberg\", \"github\"]\n");
    expect_exit(add(ordered.dir, "other/numbers"), 0);
    expect_contains(ordered.manifest(), "numbers = { codeberg = \"other/numbers\", version = \"9.0.0\" }");

    # On no host.
    var missing = add(project.dir, "nobody/nothing");
    expect_exit(missing, 1);
    expect_contains(missing.stderr, "no host has nobody/nothing (looked on github, gitlab, codeberg)");
}

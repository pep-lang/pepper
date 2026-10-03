//! `pep-package` (`tools/pep-package`, run as `pepper package`, #217): it
//! adds, removes, updates and fetches a project's dependencies, and `pep-build`
//! fetches what `pep.lock` lists and `.pep/deps` lacks. The packages come
//! from local git repositories, which `PEPPER_PACKAGE_GITHUB_URL` points the
//! tool (and the compiler) at. The tests skip when git is missing.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::OnceLock;

use crate::support;
use crate::support::{repo_root, run_program, stdout_of};
use clap::Parser;

/// The folder of bare repositories that stands in for github.com:
/// `other/numbers` (versions 1.0.0, 1.3.1, 2.0.0 and 3.0.0, which drops
/// `numbers_version`) and `someone/geometry` (1.0.0 and 1.1.0, which need
/// `other/numbers` 1). `None` without git.
fn hosts() -> Option<&'static Path> {
    static HOSTS: OnceLock<Option<PathBuf>> = OnceLock::new();
    HOSTS
        .get_or_init(|| {
            Command::new("git").arg("--version").output().ok().filter(|o| o.status.success())?;
            let root = std::env::temp_dir().join(format!("pepper_package_hosts_{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&root);
            let numbers = |v: &str| {
                let function = if v == "3.0.0" { "renamed" } else { "numbers_version" };
                vec![("module.pep", format!("export {function}(): String {{\n    return \"{v}\";\n}}\n"))]
            };
            repository(&root, "other/numbers", &["1.0.0", "1.3.1", "2.0.0", "3.0.0"], numbers);
            let geometry = |v: &str| {
                vec![
                    (
                        "module.pep",
                        format!(
                            "import numbers;\n\nexport area(w: int, h: int): int {{\n    return w * h;\n}}\n\n\
                             export geometry_version(): String {{\n    return \"{v} \" + numbers.numbers_version();\n}}\n"
                        ),
                    ),
                    (
                        "pep.toml",
                        "[package]\nname = \"geometry\"\n\n[dependencies]\nnumbers = { github = \"other/numbers\", version = \"1\" }\n"
                            .to_string(),
                    ),
                ]
            };
            repository(&root, "someone/geometry", &["1.0.0", "1.1.0"], geometry);
            // The compiler's own fetching (no pep-package beside the test)
            // reads the same variable. Nothing else reads it.
            unsafe { std::env::set_var("PEPPER_PACKAGE_GITHUB_URL", format!("file://{}", root.display())) };
            Some(root)
        })
        .as_deref()
}

/// A bare repository `<root>/<name>.git` with one commit per version,
/// tagged `v<version>`, holding the files `files` gives for it.
fn repository(root: &Path, name: &str, versions: &[&str], files: impl Fn(&str) -> Vec<(&'static str, String)>) {
    let work = root.join("work").join(name);
    std::fs::create_dir_all(&work).unwrap();
    git(&work, &["init", "--quiet", "--initial-branch=main"]);
    for version in versions {
        for (file, text) in files(version) {
            std::fs::write(work.join(file), text).unwrap();
        }
        git(&work, &["add", "-A"]);
        git(&work, &["commit", "--quiet", "-m", version]);
        git(&work, &["tag", &format!("v{version}")]);
    }
    let bare = root.join(format!("{name}.git"));
    git(root, &["clone", "--quiet", "--bare", &work.to_string_lossy(), &bare.to_string_lossy()]);
}

fn git(dir: &Path, arguments: &[&str]) {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(dir)
        .env("GIT_AUTHOR_NAME", "test")
        .env("GIT_AUTHOR_EMAIL", "test@example.com")
        .env("GIT_COMMITTER_NAME", "test")
        .env("GIT_COMMITTER_EMAIL", "test@example.com")
        .output()
        .unwrap();
    assert!(output.status.success(), "git {:?}: {}", arguments, String::from_utf8_lossy(&output.stderr));
}

/// A fresh project for `test`: `pep.toml` with `dependencies` (lines of the
/// table) and a `main.pep` that prints `geometry_version()`.
fn project(test: &str, dependencies: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_package_{}_{}", test, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("pep.toml"), format!("[package]\nname = \"app\"  # the app\n\n[dependencies]\n{dependencies}")).unwrap();
    std::fs::write(
        dir.join("main.pep"),
        "import geometry;\n\nmain(): int {\n    print(geometry.geometry_version());\n    return 0;\n}\n",
    )
    .unwrap();
    dir
}

/// Runs `pep-package` with `arguments` in `dir`.
fn package(dir: &Path, arguments: &[&str]) -> Output {
    // The tool is built outside the repository, so name the runtime whose
    // modules a dependency may not be named like.
    Command::new(support::pepper_tool("pep-package"))
        .args(arguments)
        .current_dir(dir)
        .env("PEPPER_RUNTIME", repo_root().join("runtime"))
        .output()
        .unwrap()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).replace('\r', "")
}

/// Builds the project in `dir` as `pep-build` with no file does, and runs it.
fn build_and_run(dir: &Path) -> Result<String, String> {
    std::env::set_current_dir(repo_root()).unwrap();
    let mut options = pepper_driver::Options::parse_from(["pep-build"]);
    options.apply_project_in(dir)?;
    pepper_driver::run(options)?;
    let app = dir.join(if cfg!(windows) { "app.exe" } else { "app" });
    Ok(stdout_of(&run_program(&mut Command::new(app), "").unwrap()))
}

fn lock(dir: &Path) -> String {
    std::fs::read_to_string(dir.join("pep.lock")).unwrap_or_default()
}

#[test]
fn pep_package_version_is_the_workspace_version() {
    let output = Command::new(support::pepper_tool("pep-package")).arg("--version").output().unwrap();
    assert_eq!(stdout_of(&output), format!("pep-package {}\n", env!("CARGO_PKG_VERSION")));
}

#[test]
fn add_fetches_the_newest_version_and_its_dependencies() {
    if hosts().is_none() {
        return;
    }
    let dir = project("add", "");
    let added = package(&dir, &["add", "someone/geometry"]);
    assert!(added.status.success(), "{}", stderr(&added));
    // pep.toml keeps its comment and gains the dependency at the newest version.
    assert_eq!(
        std::fs::read_to_string(dir.join("pep.toml")).unwrap(),
        "[package]\nname = \"app\"  # the app\n\n[dependencies]\ngeometry = { github = \"someone/geometry\", version = \"1.1.0\" }\n"
    );
    // One version of numbers, the newest geometry accepts.
    let locked = lock(&dir);
    assert!(locked.contains("source = \"github:someone/geometry\"\nversion = \"1.1.0\""), "{}", locked);
    assert!(locked.contains("source = \"github:other/numbers\"\nversion = \"1.3.1\""), "{}", locked);
    assert_eq!(build_and_run(&dir), Ok("1.1.0 1.3.1\n".to_string()));

    // A taken name, and a runtime module's name.
    let taken = package(&dir, &["add", "other/geometry"]);
    assert_eq!(taken.status.code(), Some(1));
    assert!(stderr(&taken).contains("a dependency named 'geometry' already exists (github:someone/geometry); add this one with --name"));
    let runtime = package(&dir, &["add", "other/io"]);
    assert!(stderr(&runtime).contains("'io' is the name of a runtime module; add the dependency with --name"), "{}", stderr(&runtime));

    // Removing it drops numbers too.
    let removed = package(&dir, &["remove", "geometry"]);
    assert!(removed.status.success(), "{}", stderr(&removed));
    assert!(!dir.join("pep.lock").exists());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn builds_fetch_what_pep_lock_lists() {
    if hosts().is_none() {
        return;
    }
    let dir = project("build_fetch", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    let fetched = package(&dir, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    // A fresh clone has pep.toml and pep.lock, and no .pep: the build
    // fetches the locked commits.
    std::fs::remove_dir_all(dir.join(".pep")).unwrap();
    assert_eq!(build_and_run(&dir), Ok("1.1.0 1.3.1\n".to_string()));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn the_project_overrides_a_dependency_and_update_says_what_holds_one_back() {
    if hosts().is_none() {
        return;
    }
    let dir = project("override", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    assert!(package(&dir, &["fetch"]).status.success());
    let updated = package(&dir, &["update", "numbers"]);
    assert!(updated.status.success(), "{}", stderr(&updated));
    assert!(
        stderr(&updated).contains("github:other/numbers stays at 1.3.1, not 3.0.0: geometry 1.1.0 wants 1"),
        "{}",
        stderr(&updated)
    );
    // Naming numbers in pep.toml overrides geometry's range.
    let mut toml = std::fs::read_to_string(dir.join("pep.toml")).unwrap();
    toml.push_str("numbers = { github = \"other/numbers\", version = \"2\" }\n");
    std::fs::write(dir.join("pep.toml"), toml).unwrap();
    let fetched = package(&dir, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    assert!(stderr(&fetched).contains("github:other/numbers 2.0.0 overrides what geometry 1.1.0 asks (1)"), "{}", stderr(&fetched));
    assert_eq!(build_and_run(&dir), Ok("1.1.0 2.0.0\n".to_string()));
    // A range nothing satisfies names the requirement and what is offered.
    let failed = package(&dir, &["add", "other/numbers@4", "--name", "more"]);
    assert_eq!(failed.status.code(), Some(1));
    assert!(stderr(&failed).contains("no revision of github:other/numbers satisfies every package that needs it:\n  app wants 2\n  app wants 4\n  it offers 1.0.0, 1.3.1, 2.0.0, 3.0.0"), "{}", stderr(&failed));
    assert!(!std::fs::read_to_string(dir.join("pep.toml")).unwrap().contains("more"), "a failed add leaves pep.toml as it was");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn update_verify_keeps_only_updates_that_build() {
    if hosts().is_none() {
        return;
    }
    // Lock the oldest versions, then widen the ranges and let verify try
    // the newest: geometry 1.1.0 builds, numbers 3.0.0 (which drops
    // numbers_version) does not.
    let dir = project(
        "verify",
        "geometry = { github = \"someone/geometry\", version = \"=1.0.0\" }\nnumbers = { github = \"other/numbers\", version = \"=1.0.0\" }\n",
    );
    let fetched = package(&dir, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    let pinned = std::fs::read_to_string(dir.join("pep.toml")).unwrap();
    std::fs::write(dir.join("pep.toml"), pinned.replacen("\"=1.0.0\"", "\"1.0\"", 1).replace("\"=1.0.0\"", "\">=1\"")).unwrap();
    let path = std::env::join_paths(std::iter::once(pep_build_dir()).chain(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()))).unwrap();
    let verified = Command::new(support::pepper_tool("pep-package"))
        .args(["update", "--verify"])
        .current_dir(&dir)
        .env("PATH", path)
        // CI's build folder is outside the repository, where pep-build
        // would not find the runtime on its own.
        .env("PEPPER_RUNTIME", repo_root().join("runtime"))
        .output()
        .unwrap();
    assert!(verified.status.success(), "{}", stderr(&verified));
    assert!(stderr(&verified).contains("rolled back, because the project did not build with them: github:other/numbers"), "{}", stderr(&verified));
    let locked = lock(&dir);
    assert!(locked.contains("source = \"github:other/numbers\"\nversion = \"1.0.0\""), "numbers stays at 1.0.0: {}", locked);
    assert!(locked.contains("source = \"github:someone/geometry\"\nversion = \"1.1.0\""), "{}\n{}", locked, stderr(&verified));
    let _ = std::fs::remove_dir_all(&dir);
}

/// The folder holding `pep-build`, for `update --verify` to find on the
/// PATH: this build's own, beside the `deps` folder this test runs from.
/// `cargo test --workspace` builds it (for `tests/pep_build.rs`).
fn pep_build_dir() -> PathBuf {
    let dir = std::env::current_exe().unwrap().parent().unwrap().parent().unwrap().to_path_buf();
    let exe = dir.join(if cfg!(windows) { "pep-build.exe" } else { "pep-build" });
    assert!(exe.is_file(), "{} is missing; build it with `cargo build` (or run `cargo test --workspace`)", exe.display());
    dir
}

/// An HTTP server on 127.0.0.1 that stands in for the hosts' archive
/// downloads: `GET /<path>` answers with the file `<root>/<path>`, or 404.
/// Returns its address, `http://127.0.0.1:<port>`.
fn archive_server(root: PathBuf) -> String {
    use std::io::{Read, Write};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = format!("http://{}", listener.local_addr().unwrap());
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut request = vec![];
            let mut byte = [0u8; 1];
            while !request.ends_with(b"\r\n\r\n") && stream.read(&mut byte).is_ok_and(|n| n == 1) {
                request.push(byte[0]);
            }
            let request = String::from_utf8_lossy(&request).to_string();
            let path = request.split(' ').nth(1).unwrap_or("/").trim_start_matches('/').to_string();
            let response = match std::fs::read(root.join(&path)) {
                Ok(body) => {
                    let mut response = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).into_bytes();
                    response.extend(body);
                    response
                }
                Err(_) => b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_vec(),
            };
            let _ = stream.write_all(&response);
        }
    });
    address
}

/// The full commit `revision` names in the bare repository `name` of the
/// test hosts.
fn commit_of(name: &str, revision: &str) -> String {
    let output = Command::new("git")
        .args(["rev-parse", &format!("{revision}^{{commit}}")])
        .current_dir(hosts().unwrap().join(format!("{name}.git")))
        .output()
        .unwrap();
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

/// Writes GitHub's archive of `revision` of `name` (a `.tar.gz` whose files
/// sit in one top-level folder) where the archive server serves the
/// archive of `commit`: `<root>/<name>/<commit>.tar.gz`.
fn write_archive(root: &Path, name: &str, revision: &str, commit: &str) {
    let file = root.join(name).join(format!("{commit}.tar.gz"));
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    let short = name.rsplit('/').next().unwrap();
    let prefix = format!("--prefix={short}-{commit}/");
    let output = format!("--output={}", file.display());
    git(&hosts().unwrap().join(format!("{name}.git")), &["archive", "--format=tar.gz", &prefix, &output, revision]);
}

/// Runs `pep-package` with `arguments` in `dir`, with no git on the PATH
/// and archives downloaded from `archives`.
fn package_without_git(dir: &Path, arguments: &[&str], archives: &str) -> Output {
    let empty = dir.join("no_git_bin");
    std::fs::create_dir_all(&empty).unwrap();
    Command::new(support::pepper_tool("pep-package"))
        .args(arguments)
        .current_dir(dir)
        .env("PATH", &empty)
        .env("PEPPER_RUNTIME", repo_root().join("runtime"))
        .env("PEPPER_PACKAGE_GITHUB_ARCHIVE_URL", archives)
        .output()
        .unwrap()
}

#[test]
fn a_locked_project_fetches_archives_without_git_and_checks_their_files() {
    if hosts().is_none() {
        return;
    }
    let dir = project("no_git", "geometry = { github = \"someone/geometry\", version = \"1.0\" }\n");
    let fetched = package(&dir, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    // Fetching with git records the checksum of each package's files.
    let locked = lock(&dir);
    assert_eq!(locked.matches("\nsha256 = \"").count(), 2, "{}", locked);

    let archives = dir.join("archives");
    let geometry = commit_of("someone/geometry", "v1.1.0");
    let numbers = commit_of("other/numbers", "v1.3.1");
    write_archive(&archives, "someone/geometry", &geometry, &geometry);
    write_archive(&archives, "other/numbers", &numbers, &numbers);
    let server = archive_server(archives.clone());

    // A fresh clone on a machine with no git: the archives of the locked
    // commits, whose files match pep.lock's checksums.
    std::fs::remove_dir_all(dir.join(".pep")).unwrap();
    let unpacked = package_without_git(&dir, &["fetch"], &server);
    assert!(unpacked.status.success(), "{}", stderr(&unpacked));
    assert_eq!(lock(&dir), locked, "the lock stays as it was");
    assert_eq!(build_and_run(&dir), Ok("1.1.0 1.3.1\n".to_string()));
    // Fetching again finds them in place.
    let again = package_without_git(&dir, &["fetch"], &server);
    assert!(again.status.success(), "{}", stderr(&again));

    // A tampered archive: 1.3.1's commit serves 2.0.0's files.
    write_archive(&archives, "other/numbers", "v2.0.0", &numbers);
    std::fs::remove_dir_all(dir.join(".pep")).unwrap();
    let tampered = package_without_git(&dir, &["fetch"], &server);
    assert_eq!(tampered.status.code(), Some(1));
    let message = stderr(&tampered);
    let expected = locked.split("source = \"github:other/numbers\"").nth(1).unwrap().split("sha256 = \"").nth(1).unwrap().split('"').next().unwrap();
    assert!(
        message.contains(&format!("cannot fetch github:other/numbers: the files of github:other/numbers {} do not match pep.lock: sha256 ", &numbers[..12]))
            && message.contains(&format!(", expected {expected}")),
        "{}",
        message
    );

    // Resolving what pep.lock does not pin needs git.
    let added = package_without_git(&dir, &["add", "other/numbers", "--name", "more"], &server);
    assert_eq!(added.status.code(), Some(1));
    assert!(stderr(&added).contains("git is not on the PATH"), "{}", stderr(&added));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn add_looks_a_repository_up_on_each_host() {
    if hosts().is_none() {
        return;
    }
    // A Codeberg with `third/shapes`, and a GitLab with nothing, so no
    // lookup leaves the machine.
    let codeberg = std::env::temp_dir().join(format!("pepper_package_codeberg_{}", std::process::id()));
    let gitlab = std::env::temp_dir().join(format!("pepper_package_gitlab_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&codeberg);
    std::fs::create_dir_all(&gitlab).unwrap();
    repository(&codeberg, "third/shapes", &["0.2.0"], |_| vec![("module.pep", "export sides(): int {\n    return 4;\n}\n".to_string())]);
    repository(&codeberg, "other/numbers", &["9.0.0"], |_| vec![("module.pep", String::new())]);
    let add = |dir: &Path, spec: &str| {
        Command::new(support::pepper_tool("pep-package"))
            .args(["add", spec])
            .current_dir(dir)
            .env("PEPPER_RUNTIME", repo_root().join("runtime"))
            .env("PEPPER_PACKAGE_CODEBERG_URL", format!("file://{}", codeberg.display()))
            .env("PEPPER_PACKAGE_GITLAB_URL", format!("file://{}", gitlab.display()))
            .output()
            .unwrap()
    };

    // Only Codeberg has it: no prefix needed.
    let dir = project("lookup", "");
    let added = add(&dir, "third/shapes");
    assert!(added.status.success(), "{}", stderr(&added));
    assert!(
        std::fs::read_to_string(dir.join("pep.toml")).unwrap().contains("shapes = { codeberg = \"third/shapes\", version = \"0.2.0\" }"),
        "{}",
        std::fs::read_to_string(dir.join("pep.toml")).unwrap()
    );
    assert!(stderr(&added).contains("'import shapes;' now imports codeberg:third/shapes"), "{}", stderr(&added));

    // On two hosts: the first in the order wins, and add says so.
    let both = add(&dir, "other/numbers");
    assert!(both.status.success(), "{}", stderr(&both));
    assert!(
        stderr(&both).contains("other/numbers is on github and codeberg; adding github:other/numbers (prefix it with 'codeberg:' for another)"),
        "{}",
        stderr(&both)
    );

    // pep.toml's [fetch] hosts changes the order.
    let ordered = project("lookup_order", "");
    let toml = std::fs::read_to_string(ordered.join("pep.toml")).unwrap();
    std::fs::write(ordered.join("pep.toml"), toml + "\n[fetch]\nhosts = [\"codeberg\", \"github\"]\n").unwrap();
    let first = add(&ordered, "other/numbers");
    assert!(first.status.success(), "{}", stderr(&first));
    assert!(std::fs::read_to_string(ordered.join("pep.toml")).unwrap().contains("numbers = { codeberg = \"other/numbers\", version = \"9.0.0\" }"));

    // On no host.
    let missing = add(&dir, "nobody/nothing");
    assert_eq!(missing.status.code(), Some(1));
    assert!(stderr(&missing).contains("no host has nobody/nothing (looked on github, gitlab, codeberg)"), "{}", stderr(&missing));
    for dir in [&dir, &ordered, &codeberg, &gitlab] {
        let _ = std::fs::remove_dir_all(dir);
    }
}

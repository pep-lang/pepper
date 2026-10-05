//! Builds fetch their dependencies: before compiling a program in a project,
//! the driver fetches whatever `pep.lock` lists and `.pep/deps` lacks, so a
//! fresh clone builds with `pepper build` alone. `pep-package fetch` does the
//! work (it also resolves dependencies `pep.toml` gained since `pep.lock` was
//! written, and downloads the hosts' archives where git is missing); without
//! `pep-package`, the driver checks the locked commits out with git itself,
//! which is how `pep-package` builds its own dependencies.

use pepper_files::project::{LOCK_FILE, LockedPackage, MANIFEST_FILE, Manifest, find_project, package_directory, read_lock};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Fetch the dependencies of the project the program rooted at `entry`
/// belongs to, if any are missing.
pub fn fetch_dependencies(entry: &Path) -> Result<(), String> {
    let Some(project) = find_project(entry) else { return Ok(()) };
    // A broken pep.toml is reported when the program loads.
    let Ok(manifest) = Manifest::read(&project.join(MANIFEST_FILE)) else { return Ok(()) };
    if !needs_fetch(&project, &manifest)? {
        return Ok(());
    }
    // Builds run side by side (`pepper test` builds every test program at
    // once), and each would fetch into the same `.partial` folders: one at
    // a time fetches, and the rest find the packages there afterwards.
    let lock = lock_file(&project.join(".pep").join("fetch.lock"))?;
    lock.lock().map_err(|e| format!("cannot lock {}: {}", project.join(".pep").display(), e))?;
    if !needs_fetch(&project, &manifest)? {
        return Ok(());
    }
    let locked = read_lock(&project.join(LOCK_FILE))?;
    if let Some(tool) = find_tool("pep-package") {
        let status = Command::new(&tool)
            .arg("-C")
            .arg(&project)
            .arg("fetch")
            .status()
            .map_err(|e| format!("cannot run {}: {}", tool.display(), e))?;
        return if status.success() { Ok(()) } else { Err("fetching the project's dependencies failed".to_string()) };
    }
    if unlocked(&project, &manifest, &locked) {
        return Err(format!(
            "the dependencies in {} are not fetched; run 'pepper package fetch'",
            project.join(MANIFEST_FILE).display()
        ));
    }
    for package in locked.iter().filter(|p| !package_directory(&project, p.host, &p.repository).is_dir()) {
        check_out(&project, package)?;
    }
    Ok(())
}

/// Whether a package pep.lock lists is missing from `.pep/deps`, or
/// pep.toml names one pep.lock does not list yet.
fn needs_fetch(project: &Path, manifest: &Manifest) -> Result<bool, String> {
    let locked = read_lock(&project.join(LOCK_FILE))?;
    let missing = locked.iter().any(|p| !package_directory(project, p.host, &p.repository).is_dir());
    Ok(missing || unlocked(project, manifest, &locked))
}

/// Whether pep.toml names a Git dependency that pep.lock does not yet list
/// and that is not in `.pep/deps` either.
fn unlocked(project: &Path, manifest: &Manifest, locked: &[LockedPackage]) -> bool {
    manifest.dependencies.iter().any(|d| {
        d.locked_source().is_some_and(|source| !locked.iter().any(|p| p.source() == source))
            && !d.directory(project, project).is_dir()
    })
}

/// Opens (creating it and its folder) the file at `path` that fetches lock.
fn lock_file(path: &Path) -> Result<std::fs::File, String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
    }
    std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(path)
        .map_err(|e| format!("cannot open {}: {}", path.display(), e))
}

/// `name` (`name.exe` on Windows) beside the running compiler, else on the
/// `PATH`.
fn find_tool(name: &str) -> Option<PathBuf> {
    let file = if cfg!(windows) { format!("{}.exe", name) } else { name.to_string() };
    let beside = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|dir| dir.join(&file)));
    let on_path = std::env::var_os("PATH").into_iter().flat_map(|paths| std::env::split_paths(&paths).collect::<Vec<_>>()).map(|dir| dir.join(&file));
    beside.into_iter().chain(on_path).find(|p| p.is_file())
}

/// Clone `package` into the project's `.pep/deps` and check its commit out.
fn check_out(project: &Path, package: &LockedPackage) -> Result<(), String> {
    let dir = package_directory(project, package.host, &package.repository);
    let url = package.host.clone_url(&package.repository);
    eprintln!("pep-build: fetching {} {}", package.source(), &package.commit[..package.commit.len().min(12)]);
    let partial = dir.with_extension("partial");
    let _ = std::fs::remove_dir_all(&partial);
    if let Some(parent) = partial.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
    }
    git(&["clone", "--quiet", "--no-checkout", &url, &partial.to_string_lossy()], None)?;
    git(&["checkout", "--quiet", "--detach", &package.commit], Some(&partial))?;
    // Only a complete checkout takes the package's place.
    std::fs::rename(&partial, &dir).map_err(|e| format!("cannot move {} to {}: {}", partial.display(), dir.display(), e))
}

fn git(arguments: &[&str], dir: Option<&Path>) -> Result<(), String> {
    let mut command = Command::new("git");
    command.args(arguments).env("GIT_TERMINAL_PROMPT", "0");
    if let Some(dir) = dir {
        command.current_dir(dir);
    }
    let output = command.output().map_err(|e| format!("cannot run git, which fetching dependencies needs: {}", e))?;
    if output.status.success() {
        return Ok(());
    }
    Err(format!("git {} failed: {}", arguments.join(" "), String::from_utf8_lossy(&output.stderr).trim()))
}

//! Runtime discovery: port of `source/Compiler/Compiler.cpp:195-254`.

use std::path::{Path, PathBuf};

/// The environment variable that names the runtime directory outright.
pub const RUNTIME_ENV: &str = "PEPPER_RUNTIME";

/// Find the runtime. `PEPPER_RUNTIME`, when set, names its directory and
/// nothing else is searched. Otherwise the search starts from the current
/// directory, then from the running executable's directory, so `pepper`
/// finds the runtime of the checkout or install it came from wherever it is
/// run. Returns its `.pep` sources + `.a` libs, plus the existing dirs
/// scanned up to it, for import search paths.
pub fn discover() -> (Vec<PathBuf>, Vec<PathBuf>, Vec<PathBuf>) {
    if let Some(dir) = std::env::var_os(RUNTIME_ENV).filter(|d| !d.is_empty()) {
        return scan(vec![PathBuf::from(dir)]);
    }
    let cwd = std::env::current_dir().unwrap_or_default();
    let exe_dir = std::env::current_exe().ok().and_then(|exe| exe.parent().map(Path::to_path_buf));
    discover_from(&cwd, exe_dir.as_deref())
}

/// [`discover`] from explicit starting directories.
pub fn discover_from(cwd: &Path, exe_dir: Option<&Path>) -> (Vec<PathBuf>, Vec<PathBuf>, Vec<PathBuf>) {
    let mut candidates = candidates(cwd);
    if let Some(exe_dir) = exe_dir {
        candidates.extend(candidates_below(exe_dir));
    }
    scan(candidates)
}

/// `runtime`, `.pep/runtime`, then 1..5 levels of `../runtime` from `start`.
fn candidates(start: &Path) -> Vec<PathBuf> {
    let mut candidates = vec![start.join("runtime"), start.join(".pep").join("runtime")];
    candidates.extend(candidates_below(start).into_iter().skip(1));
    candidates
}

/// `runtime` beside `start` and in up to 5 of its ancestors.
fn candidates_below(start: &Path) -> Vec<PathBuf> {
    let mut candidates = vec![start.join("runtime")];
    let mut dir = PathBuf::new();
    for _ in 1..=5 {
        dir.push("..");
        candidates.push(start.join(&dir).join("runtime"));
    }
    candidates
}

/// The first candidate with `.pep` sources wins.
fn scan(candidates: Vec<PathBuf>) -> (Vec<PathBuf>, Vec<PathBuf>, Vec<PathBuf>) {
    let mut sources: Vec<PathBuf> = vec![];
    let mut libs: Vec<PathBuf> = vec![];
    let mut import_dirs: Vec<PathBuf> = vec![];
    for candidate in candidates {
        let dir = candidate.canonicalize().unwrap_or(candidate.clone());
        if !dir.is_dir() {
            continue;
        }
        if !import_dirs.contains(&dir) {
            import_dirs.push(dir.clone());
        }
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) == Some("pep") {
                sources.push(path);
            } else if path.extension().and_then(|e| e.to_str()) == Some("a") {
                libs.push(path);
            }
        }
        // The nearest runtime wins: merging a second copy (say, a checkout's
        // runtime inside a worktree nested under another checkout) would
        // declare every runtime symbol twice.
        if !sources.is_empty() {
            break;
        }
    }
    (sources, libs, import_dirs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_runtime_beside_the_executable_from_anywhere() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().unwrap();
        let elsewhere = std::env::temp_dir().join("pepper_runtime_discovery");
        std::fs::create_dir_all(&elsewhere).unwrap();
        let (none, _, _) = discover_from(&elsewhere, None);
        assert!(none.is_empty(), "no runtime above {}", elsewhere.display());
        // Any directory inside the checkout stands in for the executable's
        // (`target/debug` need not exist when CARGO_TARGET_DIR is elsewhere).
        let (sources, _, dirs) = discover_from(&elsewhere, Some(&repo.join("crates").join("pepper-files")));
        assert!(sources.iter().any(|s| s.ends_with("runtime/string.pep")), "{sources:?}");
        assert_eq!(dirs.last().unwrap(), &repo.join("runtime"));
    }
}

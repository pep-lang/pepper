//! Shared helpers for the driver's integration tests.

use std::path::PathBuf;

/// Absolute path to the pepper-support static library, building it if needed.
///
/// `cargo test` only builds pepper-support's rlib — that is all dependent
/// crates need — so the staticlib both link tests consume has to be requested
/// explicitly. Without this, a test passes only when an artifact from some
/// earlier run happens to be lying around.
///
/// `PEPPER_SUPPORT_LIB` overrides the lookup for callers that stage the
/// artifact themselves.
pub fn support_staticlib() -> PathBuf {
    if let Ok(path) = std::env::var("PEPPER_SUPPORT_LIB") {
        return PathBuf::from(path);
    }

    // The test executable lives in <target>/[<triple>/]<profile>/deps, so the
    // profile dir is two levels up. Deriving it (rather than assuming `debug`)
    // keeps `--release` and custom profiles honest.
    let exe = std::env::current_exe().expect("current_exe");
    let profile_dir = exe
        .parent()
        .and_then(|deps| deps.parent())
        .expect("<target>/<profile>/deps/<exe>")
        .to_path_buf();
    let profile = profile_dir
        .file_name()
        .expect("profile dir name")
        .to_string_lossy()
        .into_owned();
    // Under an explicit --target the layout is <target>/<triple>/<profile>, and
    // the nested build has to write where this then reads from.
    let triple = profile_dir
        .parent()
        .filter(|parent| parent.file_name().map(|n| n != "target").unwrap_or(false))
        .and_then(|parent| parent.file_name())
        .map(|triple| triple.to_string_lossy().into_owned());

    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".to_string());
    let mut command = std::process::Command::new(cargo);
    command.args(["build", "-p", "pepper-support"]);
    // Cargo's dev profile builds into `debug` but is named `dev`, and
    // `--profile debug` is rejected outright, so leave it implicit.
    if profile != "debug" {
        command.args(["--profile", &profile]);
    }
    if let Some(triple) = &triple {
        command.args(["--target", triple]);
    }
    let built = command.status().expect("run cargo build -p pepper-support");
    assert!(built.success(), "building pepper-support staticlib failed");

    let staticlib = profile_dir.join(pepper_driver::linker::support_staticlib_name());
    assert!(
        staticlib.is_file(),
        "support staticlib not found at {}",
        staticlib.display()
    );
    staticlib
}

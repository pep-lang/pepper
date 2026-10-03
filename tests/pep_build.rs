//! The `pep-build` binary itself. The compiler's tests live in
//! `crates/pepper-driver/tests`; this one also makes `cargo test` build
//! `pep-build`, which tests that run it (`pep-package update --verify`)
//! find beside their own binaries.

use std::process::Command;

#[test]
fn pep_build_prints_the_workspace_version() {
    let output = Command::new(env!("CARGO_BIN_EXE_pep-build")).arg("--version").output().unwrap();
    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout), format!("pep-build {}\n", env!("CARGO_PKG_VERSION")));
}

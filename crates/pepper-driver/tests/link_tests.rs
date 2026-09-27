//! `[Link("name")]` end-to-end: the attribute on a surviving extern must add
//! `-l{name}` to the real link command, and the linked binary must resolve
//! the symbol. The probe library is deliberately *not* in the default link
//! set (version.dll on Windows, libpthread elsewhere), so a missing flag
//! fails the link with an unresolved symbol; a green test proves the flag
//! reached the linker and the call ran.

use clap::Parser;
use std::path::PathBuf;
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

#[test]
fn link_attribute_reaches_linker() {
    // chdir so `Options` paths and runtime discovery resolve like the CLI.
    let root = repo_root();
    std::env::set_current_dir(&root).unwrap();

    let dir = std::env::temp_dir().join("pepper_link_attr_test");
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join("link_probe.pep");
    let out_path = dir.join(if cfg!(windows) { "link_probe.exe" } else { "link_probe" });
    let source = if cfg!(windows) {
        r#"
[Target(OS(Windows))] [Link("gdi32")] extern ulong GetStockObject(int objid);

main(): int {
    # gdi32 is not in the default link set: without -lgdi32 this module
    # fails to link. NULL_BRUSH (5) is a stock object with a nonzero handle
    # on any system, headless included.
    return GetStockObject(5) != 0 ? 0 : 1;
}"#
    } else {
        r#"
[Target(!OS(Windows))] [Link("pthread")] extern long pthread_self();

main(): int {
    # A live thread id is never zero.
    return pthread_self() != 0 ? 0 : 1;
}"#
    };
    std::fs::write(&src_path, source).unwrap();

    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options).expect("compile + link");
    assert_eq!(code, 0);

    // The binary only runs (and exits 0) if the symbol resolved from the
    // library named by [Link].
    let status = Command::new(&out_path).status().expect("spawn linked binary");
    assert!(status.success(), "linked binary exited with {}", status);
}

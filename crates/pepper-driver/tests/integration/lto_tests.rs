//! Link-time optimization (`--lto`, on by default at `-O2` and `-O3`): each
//! unit is kept as bitcode, and the program is optimized as one module
//! before it links (see INTERNALS.md §4.1).

use clap::Parser;
use pepper_driver::cache::Outcome;
use std::path::{Path, PathBuf};

use crate::support::repo_root;

/// A fresh directory holding a program whose `main` calls into another file.
fn project(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_lto_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("lib.pep"), "export twice(x: int): int { return x + x; }\n").unwrap();
    std::fs::write(
        dir.join("main.pep"),
        "import \"lib\";\nmain(): int {\n    var words = Array<String>();\n    words.append(\"lto\");\n    return twice(21) - 42 + (words.count as int) - 1;\n}\n",
    )
    .unwrap();
    dir
}

/// The options for building `dir/main.pep` with `extra`, cached in
/// `dir/cache`, into `dir/build`.
fn options(dir: &Path, extra: &[&str]) -> pepper_driver::Options {
    // Runtime discovery searches from the working directory.
    std::env::set_current_dir(repo_root()).unwrap();
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let mut args: Vec<String> = ["pepper", dir.join("main.pep").to_str().unwrap(), "-o", exe.to_str().unwrap()]
        .iter()
        .map(|a| a.to_string())
        .collect();
    args.extend(["--build", dir.join("build").to_str().unwrap(), "--cache", dir.join("cache").to_str().unwrap()].map(String::from));
    args.extend(extra.iter().map(|a| a.to_string()));
    pepper_driver::Options::parse_from(args)
}

#[test]
fn the_default_at_o2_is_lto_and_the_program_runs() {
    let dir = project("run");
    assert!(options(&dir, &["-O2"]).effective_build().unwrap().lto);
    assert!(!options(&dir, &["-O2", "--lto=off"]).effective_build().unwrap().lto);
    assert!(!options(&dir, &["-O1"]).effective_build().unwrap().lto);
    assert!(options(&dir, &["-O1", "--lto=full"]).effective_build().unwrap().lto);
    assert!(options(&dir, &["-O0", "--lto=full"]).effective_build().is_err());
    assert_eq!(pepper_driver::run(options(&dir, &["-O2"])), Ok(0));
    assert!(dir.join("build").join("main.lto.o").is_file(), "no whole-program object");
    let status = std::process::Command::new(dir.join(if cfg!(windows) { "main.exe" } else { "main" })).status().unwrap();
    assert!(status.success(), "{status}");
    let _ = std::fs::remove_dir_all(&dir);
}

/// With LTO each unit's cached file is bitcode, kept apart from the objects
/// of builds without it.
#[test]
fn lto_units_are_cached_bitcode() {
    let dir = project("cache");
    let build = |extra: &[&str]| {
        let options = options(&dir, extra);
        let compiled = pepper_driver::compiler::compile_for_objects(&options, &pepper_driver::units_dir(&dir.join("build"), "main")).unwrap();
        pepper_driver::objects(&options, &compiled.module, None, &compiled.interfaces, &compiled.program, &dir.join("build"), "main").unwrap()
    };
    let lto = build(&["-O2"]);
    assert!(lto.iter().all(|o| o.path.extension().is_some_and(|e| e == "bc")), "{:?}", lto);
    let bitcode = std::fs::read(&lto.iter().find(|o| o.unit == "main").unwrap().path).unwrap();
    // On Apple targets LLVM wraps bitcode in a header of its own.
    assert!(bitcode.starts_with(b"BC\xC0\xDE") || bitcode.starts_with(b"\xDE\xC0\x17\x0B"), "the unit's file is not bitcode");
    let objects = build(&["-O2", "--lto=off"]);
    assert!(objects.iter().all(|o| o.path.extension().is_some_and(|e| e == "o")), "{:?}", objects);
    // Switching back reuses the bitcode.
    let again = build(&["-O2"]);
    assert_eq!(again.iter().find(|o| o.unit == "main").unwrap().outcome, Some(Outcome::Hit));
    let _ = std::fs::remove_dir_all(&dir);
}

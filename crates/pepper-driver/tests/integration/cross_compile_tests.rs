//! Cross-compiling (`--target <triple>`): every supported triple emits its
//! own object format and architecture from any host, `[Target(...)]`
//! selects the target's code, and a link for another platform without its
//! system libraries says what is missing (see INTERNALS.md §2.5 and §4.1).

use clap::Parser;
use pepper_sema::passes::platform::SUPPORTED_TRIPLES;
use std::path::{Path, PathBuf};

use crate::support::{parallel_map, repo_root};

const PROGRAM: &str = "main(): int {
    [Target(OS(Windows))]
    {
        print(\"built for windows\");
    }
    [Target(OS(Mac))]
    {
        print(\"built for macos\");
    }
    [Target(OS(Linux))]
    {
        print(\"built for linux\");
    }
    var squares = Array<int>();
    for (var i in 0..10) {
        squares.append(i * i);
    }
    return squares[3] - 9;
}
";

/// A fresh directory holding `main.pep` (`PROGRAM`).
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pepper_cross_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("main.pep"), PROGRAM).unwrap();
    dir
}

/// Run the compiler on `dir/main.pep` for `triple` with `extra` options,
/// building `dir/main` in `dir/build` with no cache.
fn compile(dir: &Path, triple: &str, extra: &[&str]) -> Result<i32, String> {
    // Runtime discovery searches from the working directory.
    std::env::set_current_dir(repo_root()).unwrap();
    let mut args = vec![
        "pep-build".to_string(),
        dir.join("main.pep").to_string_lossy().into_owned(),
        "--target".to_string(),
        triple.to_string(),
        "-o".to_string(),
        dir.join("main").to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
        "--no-cache".to_string(),
    ];
    args.extend(extra.iter().map(|a| a.to_string()));
    pepper_driver::run(pepper_driver::Options::parse_from(args))
}

/// The object format and architecture `bytes` (an object file's start)
/// declare, as `"ELF x86_64"`, `"Mach-O aarch64"` or `"COFF x86_64"`.
fn object_kind(bytes: &[u8]) -> String {
    let u16_at = |at: usize| u16::from_le_bytes([bytes[at], bytes[at + 1]]);
    let u32_at = |at: usize| u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]);
    if bytes.starts_with(b"\x7fELF") {
        let arch = match u16_at(18) {
            62 => "x86_64",
            183 => "aarch64",
            other => return format!("ELF machine {}", other),
        };
        format!("ELF {}", arch)
    } else if u32_at(0) == 0xfeed_facf {
        let arch = match u32_at(4) {
            0x0100_0007 => "x86_64",
            0x0100_000c => "aarch64",
            other => return format!("Mach-O cputype {:#x}", other),
        };
        format!("Mach-O {}", arch)
    } else {
        let arch = match u16_at(0) {
            0x8664 => "x86_64",
            0xaa64 => "aarch64",
            other => return format!("unknown object (first bytes {:#x})", other),
        };
        format!("COFF {}", arch)
    }
}

/// The object kind `triple` should produce.
fn expected_kind(triple: &str) -> String {
    let target = pepper_sema::Target::parse(triple).unwrap();
    let format = match target.os.as_str() {
        "linux" => "ELF",
        "macos" => "Mach-O",
        _ => "COFF",
    };
    format!("{} {}", format, target.arch)
}

#[test]
fn every_supported_target_emits_its_own_objects() {
    let failures: Vec<String> = parallel_map(SUPPORTED_TRIPLES, |&triple| {
        let dir = scratch(&format!("objects_{}", triple));
        // Linking another platform's executable needs its sysroot, which a
        // test machine need not have; the objects come first either way.
        if let Err(error) = compile(&dir, triple, &[]) {
            if !error.contains("Link failed") {
                return vec![format!("{}: did not compile:\n{}", triple, error)];
            }
        }
        let mut objects = vec![dir.join("build").join("main.o")];
        let units = std::fs::read_dir(dir.join("build").join("main.units")).unwrap();
        objects.extend(units.flatten().map(|entry| entry.path()).filter(|path| path.extension().is_some_and(|e| e == "o")));
        assert!(objects.len() > 1, "{}: no unit objects", triple);
        let expected = expected_kind(triple);
        let wrong: Vec<String> = objects
            .iter()
            .map(|path| (path, object_kind(&std::fs::read(path).unwrap())))
            .filter(|(_, kind)| *kind != expected)
            .map(|(path, kind)| format!("{}: {} is {}, expected {}", triple, path.display(), kind, expected))
            .collect();
        let _ = std::fs::remove_dir_all(&dir);
        wrong
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn target_selection_follows_the_target_not_the_host() {
    for (triple, kept, dropped) in [
        ("x86_64-pc-windows-msvc", "built for windows", ["built for macos", "built for linux"]),
        ("aarch64-apple-darwin", "built for macos", ["built for windows", "built for linux"]),
        ("aarch64-unknown-linux-gnu", "built for linux", ["built for windows", "built for macos"]),
    ] {
        let dir = scratch(&format!("selection_{}", triple));
        compile(&dir, triple, &["--emit-llvm"]).unwrap_or_else(|e| panic!("{}: {}", triple, e));
        let ir = std::fs::read_to_string(dir.join("build").join("main.ll")).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert!(ir.contains(&format!("target triple = \"{}\"", triple)), "{}: wrong triple", triple);
        assert!(ir.contains(kept), "{}: '{}' was dropped", triple, kept);
        for text in dropped {
            assert!(!ir.contains(text), "{}: '{}' was kept", triple, text);
        }
    }
}

#[test]
fn a_cross_link_without_a_sysroot_names_what_is_missing() {
    // Windows and macOS executables need their SDKs, which no test machine
    // of another OS has; pick the one that is not this host.
    let triple = if cfg!(windows) { "aarch64-apple-darwin" } else { "x86_64-pc-windows-msvc" };
    let variable = pepper_driver::options::sysroot_variable(triple);
    if std::env::var_os(&variable).is_some() {
        return;
    }
    let dir = scratch("no_sysroot");
    let error = compile(&dir, triple, &[]).expect_err("linking without a sysroot");
    let _ = std::fs::remove_dir_all(&dir);
    let note = format!(
        "note: linking for '{}' needs that platform's system libraries and LLVM's linker (lld): pass '--sysroot <dir>' or set {}",
        triple, variable
    );
    assert!(error.contains(&note), "no note naming the sysroot in:\n{}", error);
}

#[test]
fn an_unsupported_target_lists_the_supported_ones() {
    let dir = scratch("unsupported");
    let error = compile(&dir, "wasm32-unknown-wasi", &[]).expect_err("an unsupported target");
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(error, format!("unsupported target 'wasm32-unknown-wasi'; expected one of: {}", SUPPORTED_TRIPLES.join(", ")));
}

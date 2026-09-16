//! Windows LLVM linkage.
//!
//! The official LLVM release libraries are compiled against the *static* CRT
//! (`/MT`: they carry `DEFAULTLIB:libcmt.lib` + `libcpmt.lib`), while Rust's
//! MSVC targets use the dynamic CRT. Linking LLVM's static libs into a Rust
//! binary therefore puts two CRTs -- two heaps -- in one process, and LLVM
//! faults at random points inside the verifier/printer (LNK4098 warns about it).
//!
//! Linking `LLVM-C.dll` instead keeps LLVM's CRT inside the DLL: the only
//! boundary is the LLVM-C API, which passes plain pointers and frees its own
//! allocations via LLVMDisposeMessage. `inkwell`'s `*-no-llvm-linking` feature
//! suppresses llvm-sys's own link directives so these take effect.
//!
//! Unix builds link LLVM's static libs as usual (one libc, no conflict), so
//! this script does nothing there.

use std::env;
use std::path::{Path, PathBuf};

/// Cargo feature -> llvm-sys major, for every LLVM this crate can build
/// against. Keep in sync with the `[features]` table in Cargo.toml; a feature
/// missing from here would fall through to the "no version selected" panic.
const LLVM_SYS_MAJORS: &[(&str, &str)] = &[
    ("CARGO_FEATURE_LLVM18_1", "181"),
    ("CARGO_FEATURE_LLVM19_1", "191"),
    ("CARGO_FEATURE_LLVM20_1", "201"),
    ("CARGO_FEATURE_LLVM21_1", "211"),
    ("CARGO_FEATURE_LLVM22_1", "221"),
];

/// The llvm-sys major implied by the enabled version feature.
///
/// Cargo sets `CARGO_FEATURE_<NAME>` for each enabled feature, so the selected
/// version is readable here without duplicating the pin. Two enabled at once
/// is rejected rather than silently taking the first: inkwell would fail later
/// with an error about conflicting llvm-sys crates, which does not point here.
fn llvm_sys_major() -> &'static str {
    let enabled: Vec<&(&str, &str)> = LLVM_SYS_MAJORS
        .iter()
        .filter(|(feature, _)| env::var_os(feature).is_some())
        .collect();

    match enabled.as_slice() {
        [(_, major)] => major,
        [] => panic!(
            "no LLVM version feature enabled -- build with one of \
             --features llvm18-1|llvm19-1|llvm20-1|llvm21-1|llvm22-1"
        ),
        many => panic!(
            "{} LLVM version features enabled ({}) -- exactly one is allowed",
            many.len(),
            // The flags to change, not the llvm-sys majors they imply:
            // CARGO_FEATURE_LLVM20_1 -> llvm20-1.
            many.iter()
                .map(|(feature, _)| feature
                    .trim_start_matches("CARGO_FEATURE_")
                    .to_ascii_lowercase()
                    .replacen('_', "-", 1))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

fn main() {
    let llvm_sys_major = llvm_sys_major();
    println!("cargo:rerun-if-env-changed=LLVM_SYS_{llvm_sys_major}_PREFIX");

    let target = env::var("TARGET").unwrap_or_default();
    if !target.contains("windows") {
        return;
    }

    // The major here is the one the selected feature implies, so this names
    // the LLVM the build actually wants rather than whatever is installed.
    let var = format!("LLVM_SYS_{llvm_sys_major}_PREFIX");
    let Ok(prefix) = env::var(&var) else {
        panic!(
            "{var} is not set. Provision LLVM with:\n    \
             cargo run -p xtask -- setup\n  \
             (or `cargo setup` once that has run). \
             `cargo run -p xtask -- --check` reports what is configured."
        );
    };
    let prefix = PathBuf::from(prefix);

    let lib_dir = prefix.join("lib");
    let dll = prefix.join("bin").join("LLVM-C.dll");
    assert!(
        lib_dir.join("LLVM-C.lib").is_file() && dll.is_file(),
        "{} does not look like an LLVM install: expected lib/LLVM-C.lib and bin/LLVM-C.dll",
        prefix.display()
    );

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=dylib=LLVM-C");

    // Windows resolves DLLs next to the executable, so place LLVM-C.dll beside
    // every artifact cargo produces (binaries, test harnesses, examples).
    // OUT_DIR is target/<profile>/build/<pkg>-<hash>/out.
    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let Some(profile_dir) = out_dir.ancestors().nth(3) else {
        return;
    };
    for sub in ["", "deps", "examples"] {
        let dir = profile_dir.join(sub);
        if std::fs::create_dir_all(&dir).is_err() {
            continue;
        }
        copy_if_stale(&dll, &dir.join("LLVM-C.dll"));
    }
}

/// Copy only when the destination is missing or older, so incremental builds
/// don't re-copy 68 MB every time.
///
/// A failed copy must not pass silently: the destination can be locked by a
/// still-running test binary, and every artifact in the profile dir would then
/// die at startup with STATUS_DLL_NOT_FOUND and no output at all.
fn copy_if_stale(src: &Path, dst: &Path) {
    let fresh = match (src.metadata(), dst.metadata()) {
        (Ok(s), Ok(d)) => match (s.modified(), d.modified()) {
            (Ok(sm), Ok(dm)) => dm >= sm && d.len() == s.len(),
            _ => false,
        },
        _ => false,
    };
    if !fresh {
        if let Err(e) = std::fs::copy(src, dst) {
            panic!(
                "cannot stage {} -> {}: {e}",
                src.display(),
                dst.display()
            );
        }
    }
}

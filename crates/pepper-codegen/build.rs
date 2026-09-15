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

const LLVM_SYS_MAJOR: &str = "221";

fn main() {
    println!("cargo:rerun-if-env-changed=LLVM_SYS_{LLVM_SYS_MAJOR}_PREFIX");

    let target = env::var("TARGET").unwrap_or_default();
    if !target.contains("windows") {
        return;
    }

    let var = format!("LLVM_SYS_{LLVM_SYS_MAJOR}_PREFIX");
    let Ok(prefix) = env::var(&var) else {
        panic!("{var} is not set -- run scripts/setup-llvm.ps1 (see the build skill)");
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

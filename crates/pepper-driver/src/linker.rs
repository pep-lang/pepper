//! Link objects into an executable.
//!
//! `clang` is used as the link driver rather than invoking `ld`/`lld-link`
//! directly: it knows each platform's startup objects and libc, and on Windows
//! it locates the MSVC toolchain and Windows SDK itself, so linking works
//! without a Developer Command Prompt. The clang from the LLVM install this
//! compiler links against is preferred so the two always agree on the target.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Matches the `LLVM_SYS_<major>_PREFIX` that `pepper-codegen` builds against.
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_221_PREFIX";

/// Filename of the pepper-support static library for the host platform.
pub fn support_staticlib_name() -> &'static str {
    if cfg!(windows) {
        "pepper_support.lib"
    } else {
        "libpepper_support.a"
    }
}

/// The link driver to invoke.
pub fn link_driver() -> PathBuf {
    let exe = if cfg!(windows) { "clang.exe" } else { "clang" };
    if let Ok(prefix) = std::env::var(LLVM_PREFIX_ENV) {
        let candidate = Path::new(&prefix).join("bin").join(exe);
        if candidate.is_file() {
            return candidate;
        }
    }
    PathBuf::from(exe)
}

/// System libraries every Pepper executable needs on this platform.
///
/// The runtime support library is a Rust staticlib, so linking it drags in the
/// Rust standard library's own native dependencies. clang supplies the C
/// runtime and, on macOS, libSystem plus the SDK/platform flags itself; these
/// are the ones it does not add.
fn default_system_libraries() -> &'static [&'static str] {
    if cfg!(windows) {
        &[
            // Pepper's documented Windows defaults (docs/pepper.md).
            "kernel32", "user32", "shell32",
            // Required by the Rust standard library inside pepper-support:
            // sockets, user profile paths, NT syscalls, crypto RNG.
            "ws2_32", "userenv", "ntdll", "advapi32", "bcrypt", "ole32", "oleaut32",
        ]
    } else if cfg!(target_os = "linux") {
        // rustc's own native-static-libs line for a staticlib asks for these;
        // clang's default link line supplies libc but not libm, and not
        // libdl/libpthread before glibc 2.34 folded them in.
        &["m", "dl", "pthread"]
    } else {
        &[]
    }
}

/// Link obj files into an executable.
pub fn link(
    objects: &[PathBuf],
    output: &Path,
    libraries: &[String],
    library_dirs: &[PathBuf],
) -> Result<(), String> {
    let driver = link_driver();

    let mut args: Vec<String> = vec!["-o".to_string(), output.to_string_lossy().into_owned()];
    for obj in objects {
        args.push(obj.to_string_lossy().into_owned());
    }
    for dir in library_dirs {
        args.push(format!("-L{}", dir.display()));
    }
    for lib in libraries {
        args.push(format!("-l{}", lib));
    }
    for lib in default_system_libraries() {
        args.push(format!("-l{}", lib));
    }

    let output_result = Command::new(&driver).args(&args).output();
    match output_result {
        // Capturing the streams (rather than inheriting them) is what lets the
        // failure branch report unresolved symbols, but link *warnings* matter
        // too -- LNK4098 is how a reintroduced CRT mismatch would announce
        // itself -- so forward anything the driver said.
        Ok(out) if out.status.success() => {
            let stdout = String::from_utf8_lossy(&out.stdout);
            if !stdout.trim().is_empty() {
                print!("{}", stdout);
            }
            let stderr = String::from_utf8_lossy(&out.stderr);
            if !stderr.trim().is_empty() {
                eprint!("{}", stderr);
            }
            Ok(())
        }
        Ok(out) => {
            // MSVC's link.exe reports unresolved symbols on stdout, so both
            // streams are needed for the message to be actionable.
            let mut detail = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&out.stderr);
            if !stderr.trim().is_empty() {
                if !detail.is_empty() {
                    detail.push('\n');
                }
                detail.push_str(stderr.trim());
            }
            Err(format!(
                "Link failed: {} exited with {}\n{}",
                driver.display(),
                out.status,
                detail
            ))
        }
        Err(e) => Err(format!(
            "Link failed: cannot run {}: {}",
            driver.display(),
            e
        )),
    }
}

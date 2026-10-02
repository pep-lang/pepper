//! Link objects into an executable.
//!
//! `clang` is used as the link driver rather than invoking `ld`/`lld-link`
//! directly: it knows each platform's startup objects and libc, and on Windows
//! it locates the MSVC toolchain and Windows SDK itself, so linking works
//! without a Developer Command Prompt. The clang from the LLVM install this
//! compiler links against is preferred so the two always agree on the target.
//!
//! For another platform (`--target`), clang links with `--target=<triple>`,
//! LLVM's own linker (`lld`, since the host's system linker knows only the
//! host's formats; named with `--ld-path` when `find_lld` finds it), and the
//! target's system root (`--sysroot`, or `/winsysroot` for a Windows target,
//! which `lld-link` reads).
//!
//! WebAssembly (`wasm32-wasip1`) links with `wasm-ld` against wasi-libc, from
//! a wasi-sdk: `--sysroot` (or `PEPPER_SYSROOT_WASM32_WASIP1`, or the
//! conventional `WASI_SDK_PATH`) names the SDK or its `share/wasi-sysroot`,
//! and the SDK's `lib/clang/<version>` supplies the compiler-rt builtins
//! that LLVM's own clang does not ship for WebAssembly (see [`WasiSdk`]).

use std::path::{Path, PathBuf};
use std::process::Command;

/// Matches the `LLVM_SYS_<major>_PREFIX` that `pepper-codegen` builds against,
/// which depends on the selected LLVM version feature. Getting this wrong is
/// silent: `link_driver()` simply falls through to whatever `clang` is on PATH,
/// which may be a different LLVM than the one this compiler links against.
#[cfg(feature = "llvm18-1")]
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_181_PREFIX";
#[cfg(feature = "llvm19-1")]
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_191_PREFIX";
#[cfg(feature = "llvm20-1")]
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_201_PREFIX";
#[cfg(feature = "llvm21-1")]
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_211_PREFIX";
#[cfg(feature = "llvm22-1")]
const LLVM_PREFIX_ENV: &str = "LLVM_SYS_221_PREFIX";

/// The LLVM major the compiler links against, for finding a versioned
/// `ld.lld-<major>` (what Ubuntu's `lld-<major>` puts on the PATH).
#[cfg(feature = "llvm18-1")]
const LLVM_MAJOR: &str = "18";
#[cfg(feature = "llvm19-1")]
const LLVM_MAJOR: &str = "19";
#[cfg(feature = "llvm20-1")]
const LLVM_MAJOR: &str = "20";
#[cfg(feature = "llvm21-1")]
const LLVM_MAJOR: &str = "21";
#[cfg(feature = "llvm22-1")]
const LLVM_MAJOR: &str = "22";

#[cfg(not(any(
    feature = "llvm18-1",
    feature = "llvm19-1",
    feature = "llvm20-1",
    feature = "llvm21-1",
    feature = "llvm22-1"
)))]
compile_error!(
    "no LLVM version feature enabled -- build with one of \
     --features llvm18-1|llvm19-1|llvm20-1|llvm21-1|llvm22-1"
);

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

/// System libraries every Pepper executable (or shared library) needs on the
/// target's OS; a C program that links a static library links them too.
///
/// clang supplies the C runtime and, on macOS, libSystem plus the SDK/platform
/// flags itself; these are the ones it does not add.
pub fn default_system_libraries(os: &str) -> &'static [&'static str] {
    match os {
        // Pepper's documented Windows defaults (docs/src/language/linking.md).
        "windows" => &["kernel32", "user32", "shell32"],
        // A floating-point `**` calls `pow`, which glibc keeps in libm
        // (macOS has it in libSystem, Windows in the UCRT).
        "linux" => &["m"],
        // wasi-libc keeps `pow` in libc, and `getpid` in an emulation
        // library of its own.
        "wasi" => &["wasi-emulated-getpid"],
        _ => &[],
    }
}

/// LLVM's linker for an ELF, Mach-O or WebAssembly target (`ld.lld`,
/// `ld64.lld`, `wasm-ld`), when one is found: beside the link driver, in the
/// LLVM install the compiler links against, or on the PATH, plain or with
/// this LLVM's major (`ld.lld-20`). clang finds a plain one beside itself or
/// on the PATH unaided, but not the versioned name Ubuntu's `lld-20`
/// installs.
fn find_lld(os: &str, driver: &Path) -> Option<PathBuf> {
    let name = match os {
        "macos" => "ld64.lld",
        "wasi" => "wasm-ld",
        _ => "ld.lld",
    };
    let versioned = format!("{}-{}", name, LLVM_MAJOR);
    let mut directories: Vec<PathBuf> = driver.parent().filter(|d| !d.as_os_str().is_empty()).map(Path::to_path_buf).into_iter().collect();
    if let Ok(prefix) = std::env::var(LLVM_PREFIX_ENV) {
        directories.push(Path::new(&prefix).join("bin"));
    }
    directories.extend(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()));
    let exe = |n: &str| if cfg!(windows) { format!("{}.exe", n) } else { n.to_string() };
    [exe(name), exe(&versioned)]
        .iter()
        .flat_map(|n| directories.iter().map(move |d| d.join(n)))
        .find(|candidate| candidate.is_file())
}

/// A wasi-sdk's two parts the link needs: the wasi-libc system root and
/// the clang resource directory holding `libclang_rt.builtins-wasm32.a`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WasiSdk {
    /// `share/wasi-sysroot`: wasi-libc's headers and libraries.
    pub sysroot: PathBuf,
    /// `lib/clang/<version>`, when the SDK has one: its compiler-rt builtins
    /// are for its own clang's version, which any clang links with.
    pub resource_dir: Option<PathBuf>,
}

impl WasiSdk {
    /// The SDK `dir` names: a wasi-sdk (holding `share/wasi-sysroot`), or a
    /// system root itself (a wasi-sdk's `share/wasi-sysroot`, whose SDK is
    /// two directories up, or a stand-alone wasi-libc). `None` for no
    /// directory: then `WASI_SDK_PATH`, wasi-sdk's own variable, names it.
    pub fn locate(dir: Option<&Path>) -> Option<WasiSdk> {
        let dir = match dir {
            Some(dir) => dir.to_path_buf(),
            None => PathBuf::from(std::env::var_os("WASI_SDK_PATH").filter(|d| !d.is_empty())?),
        };
        let (sdk, sysroot) = if dir.join("share").join("wasi-sysroot").is_dir() {
            (Some(dir.clone()), dir.join("share").join("wasi-sysroot"))
        } else {
            (dir.parent().and_then(Path::parent).map(Path::to_path_buf), dir)
        };
        let resource_dir = sdk.and_then(|sdk| {
            let mut versions: Vec<PathBuf> = std::fs::read_dir(sdk.join("lib").join("clang")).ok()?.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.is_dir()).collect();
            versions.sort();
            versions.pop()
        });
        Some(WasiSdk { sysroot, resource_dir })
    }
}

/// The link driver's options that choose the platform: none for the host;
/// for another target, its triple, LLVM's linker (`lld`, the one at `lld`
/// when given), and its system root.
fn target_arguments(target: &pepper_sema::Target, sysroot: Option<&Path>, lld: Option<&Path>) -> Vec<String> {
    let mut args = vec![];
    if let Some(triple) = &target.triple {
        args.push(format!("--target={}", triple));
    }
    if !target.is_host() {
        // clang's MSVC toolchain picks `lld-link` by `-fuse-ld` alone.
        match lld.filter(|_| target.os != "windows") {
            // clang's WebAssembly toolchain reads only `-fuse-ld`, which
            // takes a path there.
            Some(path) if target.os == "wasi" => args.push(format!("-fuse-ld={}", path.display())),
            Some(path) => args.push(format!("--ld-path={}", path.display())),
            None => args.push("-fuse-ld=lld".to_string()),
        }
    }
    if target.os == "wasi" {
        if let Some(sdk) = WasiSdk::locate(sysroot) {
            args.push(format!("--sysroot={}", sdk.sysroot.display()));
            if let Some(resource_dir) = sdk.resource_dir {
                args.push(format!("-resource-dir={}", resource_dir.display()));
            }
        }
        return args;
    }
    if let Some(sysroot) = sysroot {
        if target.os == "windows" {
            // clang's MSVC toolchain takes the Windows SDK and MSVC
            // libraries from `/winsysroot` only in clang-cl mode, so hand
            // it to lld-link, which finds `kernel32.lib` and the CRT there.
            args.extend(["-Xlinker".to_string(), format!("/winsysroot:{}", sysroot.display())]);
        } else {
            args.push(format!("--sysroot={}", sysroot.display()));
        }
    }
    args
}

/// Link obj files into an executable for the target
/// (`pepper_sema::current_target`), or with `shared` a shared library
/// (`--lib shared`), with its system root `sysroot` when it is given; with
/// `debug`, keep their debug info (for Windows, clang then has the linker
/// write `<output>.pdb`, with the visualizers in `natvis`).
#[allow(clippy::too_many_arguments)]
pub fn link(
    objects: &[PathBuf],
    output: &Path,
    libraries: &[String],
    library_dirs: &[PathBuf],
    debug: bool,
    natvis: Option<&Path>,
    sysroot: Option<&Path>,
    shared: bool,
) -> Result<(), String> {
    let driver = link_driver();
    let target = pepper_sema::current_target();

    let mut args: Vec<String> = vec!["-o".to_string(), output.to_string_lossy().into_owned()];
    if shared {
        args.push("-shared".to_string());
        let name = output.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if target.os == "macos" {
            // Programs that link it find it on their run path.
            args.push(format!("-Wl,-install_name,@rpath/{}", name));
        } else if target.os != "windows" {
            args.push(format!("-Wl,-soname,{}", name));
        }
    }
    let lld = if target.is_host() { None } else { find_lld(&target.os, &driver) };
    args.extend(target_arguments(&target, sysroot, lld.as_deref()));
    if debug {
        args.push("-g".to_string());
        if target.os == "windows" {
            // `-g` makes link.exe link incrementally, which announces a full
            // link on every fresh build and leaves a `.ilk` beside the output.
            args.extend(["-Xlinker".to_string(), "/INCREMENTAL:NO".to_string()]);
        }
        if let Some(natvis) = natvis {
            // link.exe records the path as given; a canonical path's `\?\`
            // prefix would show in the PDB.
            let natvis = natvis.to_string_lossy();
            let natvis = natvis.strip_prefix(r"\?\").unwrap_or(&natvis);
            args.extend(["-Xlinker".to_string(), format!("/NATVIS:{}", natvis)]);
        }
    }
    for obj in objects {
        args.push(obj.to_string_lossy().into_owned());
    }
    for dir in library_dirs {
        args.push(format!("-L{}", dir.display()));
    }
    for lib in libraries {
        args.push(format!("-l{}", lib));
    }
    for lib in default_system_libraries(&target.os) {
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
                "Link failed: {} exited with {}\n{}{}",
                driver.display(),
                out.status,
                detail,
                cross_link_note(&target, sysroot)
            ))
        }
        Err(e) => Err(format!(
            "Link failed: cannot run {}: {}",
            driver.display(),
            e
        )),
    }
}

/// What a failed link for another platform needs, after the linker's own
/// messages: the target's system root, unless one was given, and LLVM's
/// linker. Empty for the host.
fn cross_link_note(target: &pepper_sema::Target, sysroot: Option<&Path>) -> String {
    if target.is_host() {
        return String::new();
    }
    let triple = target.triple.as_deref().unwrap_or_default();
    if target.os == "wasi" {
        return match WasiSdk::locate(sysroot) {
            None => format!(
                "\nnote: linking for '{}' needs a wasi-sdk (https://github.com/WebAssembly/wasi-sdk/releases) and LLVM's wasm-ld: \
                 pass '--sysroot <wasi-sdk>' or set {} or WASI_SDK_PATH",
                triple,
                crate::options::sysroot_variable(triple)
            ),
            Some(sdk) => format!(
                "\nnote: linking for '{}' with the wasi-sdk system root '{}' needs LLVM's wasm-ld (lld) beside clang or on the PATH",
                triple,
                sdk.sysroot.display()
            ),
        };
    }
    match sysroot {
        None => format!(
            "\nnote: linking for '{}' needs that platform's system libraries and LLVM's linker (lld): \
             pass '--sysroot <dir>' or set {}",
            triple,
            crate::options::sysroot_variable(triple)
        ),
        Some(sysroot) => format!(
            "\nnote: linking for '{}' with the system root '{}' needs LLVM's linker (lld) beside clang",
            triple,
            sysroot.display()
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_links_with_no_target_options() {
        assert!(target_arguments(&pepper_sema::Target::host(), None, None).is_empty());
    }

    #[test]
    fn another_platform_links_with_its_triple_lld_and_sysroot() {
        let other = if cfg!(target_os = "linux") { "aarch64-apple-darwin" } else { "x86_64-unknown-linux-gnu" };
        let target = pepper_sema::Target::parse(other).unwrap();
        assert_eq!(
            target_arguments(&target, Some(Path::new("/sdk")), None),
            [format!("--target={}", other), "-fuse-ld=lld".to_string(), "--sysroot=/sdk".to_string()]
        );
        // A found lld is named outright.
        let args = target_arguments(&target, None, Some(Path::new("/usr/bin/ld.lld-20")));
        assert_eq!(args[1], "--ld-path=/usr/bin/ld.lld-20");
        let windows = pepper_sema::Target::parse("x86_64-pc-windows-msvc").unwrap();
        let args = target_arguments(&windows, Some(Path::new("/xwin")), Some(Path::new("/usr/bin/ld.lld")));
        if !windows.is_host() {
            assert!(args.contains(&"-fuse-ld=lld".to_string()), "{args:?}");
        }
        assert_eq!(args.last().map(String::as_str), Some("/winsysroot:/xwin"));
        let note = cross_link_note(&target, None);
        assert!(note.contains("pass '--sysroot <dir>' or set PEPPER_SYSROOT_"), "{note}");
    }

    /// A wasi-sdk is found from its own directory or its system root, and
    /// lends the link its compiler-rt builtins.
    #[test]
    fn webassembly_links_with_the_wasi_sdk() {
        let sdk = std::env::temp_dir().join(format!("pepper-wasi-sdk-{}", std::process::id()));
        let sysroot = sdk.join("share").join("wasi-sysroot");
        let resource_dir = sdk.join("lib").join("clang").join("19");
        std::fs::create_dir_all(&sysroot).unwrap();
        std::fs::create_dir_all(&resource_dir).unwrap();
        let expected = WasiSdk { sysroot: sysroot.clone(), resource_dir: Some(resource_dir.clone()) };
        assert_eq!(WasiSdk::locate(Some(&sdk)), Some(expected.clone()));
        assert_eq!(WasiSdk::locate(Some(&sysroot)), Some(expected));
        let target = pepper_sema::Target::parse("wasm32-wasi").unwrap();
        let args = target_arguments(&target, Some(&sdk), Some(Path::new("/usr/bin/wasm-ld-20")));
        assert_eq!(
            args,
            [
                "--target=wasm32-wasip1".to_string(),
                "-fuse-ld=/usr/bin/wasm-ld-20".to_string(),
                format!("--sysroot={}", sysroot.display()),
                format!("-resource-dir={}", resource_dir.display()),
            ]
        );
        std::fs::remove_dir_all(&sdk).unwrap();
    }
}

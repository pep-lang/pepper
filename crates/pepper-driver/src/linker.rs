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
//!
//! iOS links with `ld64.lld` against an iOS SDK: `--sysroot` (or
//! `PEPPER_SYSROOT_<TRIPLE>`), else on a Mac the SDK `xcrun` reports for
//! the device or the simulator (see [`apple_sdk`]). Android links with the
//! NDK's own clang, which knows its system root, compiler-rt and unwinder:
//! `--sysroot` names the NDK (or its `sysroot`), else `ANDROID_NDK_HOME`,
//! `ANDROID_NDK_ROOT` or the newest NDK in the Android SDK (see
//! [`AndroidNdk`]).

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

/// The link driver to invoke: [`find_link_driver`]'s, or plain `clang`
/// (which then fails to start) when there is none.
pub fn link_driver() -> PathBuf {
    find_link_driver().unwrap_or_else(|| PathBuf::from(executable_name("clang")))
}

/// The `clang` to link with, the first that exists of: the one in the LLVM
/// install this compiler links against (`LLVM_SYS_<major>_PREFIX`, set in a
/// development checkout), the one beside the running compiler, the first on
/// the PATH (`clang`, then this LLVM's `clang-<major>`, which is all
/// Ubuntu's `clang-<major>` package puts there), and then one in a folder
/// where the platform's LLVM packages install it ([`llvm_install_dirs`]).
/// An installed compiler has no prefix variable, so it relies on the rest.
pub fn find_link_driver() -> Option<PathBuf> {
    let exe = executable_name("clang");
    let mut candidates: Vec<PathBuf> = vec![];
    if let Ok(prefix) = std::env::var(LLVM_PREFIX_ENV) {
        candidates.push(Path::new(&prefix).join("bin").join(&exe));
    }
    if let Some(dir) = std::env::current_exe().ok().and_then(|e| e.parent().map(Path::to_path_buf)) {
        candidates.push(dir.join(&exe));
    }
    let path: Vec<PathBuf> = std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()).collect();
    for name in [exe.clone(), executable_name(&format!("clang-{}", LLVM_MAJOR))] {
        candidates.extend(path.iter().map(|dir| dir.join(&name)));
    }
    candidates.extend(llvm_install_dirs().into_iter().map(|dir| dir.join(&exe)));
    candidates.into_iter().find(|candidate| candidate.is_file())
}

/// `name` as an executable's file name on the host: `name.exe` on Windows.
fn executable_name(name: &str) -> String {
    if cfg!(windows) { format!("{}.exe", name) } else { name.to_string() }
}

/// The folders LLVM's packages install `clang` in when they leave it off the
/// PATH: the llvm.org Windows installer's (which winget and Chocolatey run)
/// and Scoop's; Homebrew's keg-only `llvm` and `llvm@<major>` on Apple
/// silicon and Intel; Debian and Ubuntu's `/usr/lib/llvm-<major>`, this
/// LLVM's major first, then the newest.
fn llvm_install_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = vec![];
    if cfg!(windows) {
        for variable in ["ProgramFiles", "ProgramW6432"] {
            if let Some(dir) = std::env::var_os(variable) {
                dirs.push(Path::new(&dir).join("LLVM").join("bin"));
            }
        }
        if let Some(home) = std::env::var_os("USERPROFILE") {
            dirs.push(Path::new(&home).join("scoop").join("apps").join("llvm").join("current").join("bin"));
        }
    } else if cfg!(target_os = "macos") {
        for root in ["/opt/homebrew/opt", "/usr/local/opt"] {
            dirs.push(Path::new(root).join("llvm").join("bin"));
            dirs.push(Path::new(root).join(format!("llvm@{}", LLVM_MAJOR)).join("bin"));
        }
    } else {
        dirs.push(PathBuf::from(format!("/usr/lib/llvm-{}/bin", LLVM_MAJOR)));
        let mut others: Vec<(u32, PathBuf)> = std::fs::read_dir("/usr/lib")
            .into_iter()
            .flatten()
            .filter_map(|e| e.ok())
            .filter_map(|e| {
                let name = e.file_name().to_string_lossy().into_owned();
                let major = name.strip_prefix("llvm-")?.parse().ok()?;
                Some((major, e.path().join("bin")))
            })
            .collect();
        others.sort_by(|a, b| b.0.cmp(&a.0));
        dirs.extend(others.into_iter().map(|(_, dir)| dir));
    }
    dirs
}

/// Why a link cannot start when [`find_link_driver`] finds no clang, and
/// what to install on this platform.
fn missing_link_driver() -> String {
    let install = if cfg!(windows) {
        "install LLVM with 'winget install LLVM.LLVM' (or 'scoop install llvm', or 'choco install llvm'), \
         and the Visual Studio Build Tools' C++ workload, which supplies the MSVC libraries and Windows SDK"
    } else if cfg!(target_os = "macos") {
        "install Xcode's command line tools with 'xcode-select --install'"
    } else {
        "install it with 'sudo apt install clang' (Debian, Ubuntu), 'sudo dnf install clang' (Fedora, RHEL), \
         'sudo pacman -S clang' (Arch) or 'sudo zypper install clang' (openSUSE)"
    };
    format!(
        "Link failed: no clang found to link with: none beside the compiler, on the PATH, or where LLVM's packages install it\n\
         note: {}; or put the folder holding clang on the PATH",
        install
    )
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
        // (macOS has it in libSystem, Windows in the UCRT). Before glibc
        // 2.34, threads and `dlsym` lived in libpthread and libdl, so a
        // host with an older glibc (the prebuilt toolchain supports 2.28)
        // links those too. A newer glibc has them in libc, and a system
        // root for another machine may not carry them at all.
        "linux" if host_glibc_before_2_34() => &["m", "pthread", "dl"],
        "linux" => &["m"],
        // bionic keeps `pow` in libm too, and threads and `dlsym` in libc.
        "android" => &["m"],
        // wasi-libc keeps `pow` in libc, and `getpid` in an emulation
        // library of its own.
        "wasi" => &["wasi-emulated-getpid"],
        _ => &[],
    }
}

/// Whether `lib` is a library whose functions `os` keeps in its C library,
/// with no library of that name to link: Android's bionic has threads and
/// real-time clocks in libc, and the NDK ships no `libpthread` or `librt`.
/// Dropping them lets one `[Link("pthread")]` serve Linux and Android.
fn is_built_into_libc(os: &str, lib: &str) -> bool {
    os == "android" && matches!(lib, "pthread" | "rt")
}

/// Whether this compiler runs on a glibc older than 2.34, from its own
/// version (`gnu_get_libc_version`). False on any other C library.
#[cfg(all(target_os = "linux", target_env = "gnu"))]
fn host_glibc_before_2_34() -> bool {
    unsafe extern "C" {
        fn gnu_get_libc_version() -> *const std::ffi::c_char;
    }
    // SAFETY: glibc returns a static NUL-terminated string such as "2.28".
    let version = unsafe { std::ffi::CStr::from_ptr(gnu_get_libc_version()) }.to_string_lossy().into_owned();
    glibc_before_2_34(&version)
}

#[cfg(not(all(target_os = "linux", target_env = "gnu")))]
fn host_glibc_before_2_34() -> bool {
    false
}

/// Whether the glibc `version` ("2.28") is older than 2.34.
#[cfg_attr(not(all(target_os = "linux", target_env = "gnu")), allow(dead_code))]
fn glibc_before_2_34(version: &str) -> bool {
    let mut parts = version.split('.').map(|part| part.parse::<u32>().unwrap_or(0));
    let major = parts.next().unwrap_or(0);
    let minor = parts.next().unwrap_or(0);
    (major, minor) < (2, 34)
}

/// LLVM's linker for an ELF, Mach-O or WebAssembly target (`ld.lld`,
/// `ld64.lld`, `wasm-ld`), when one is found: beside the link driver, in the
/// LLVM install the compiler links against, or on the PATH, plain or with
/// this LLVM's major (`ld.lld-20`). clang finds a plain one beside itself or
/// on the PATH unaided, but not the versioned name Ubuntu's `lld-20`
/// installs.
fn find_lld(os: &str, driver: &Path) -> Option<PathBuf> {
    let name = match os {
        "macos" | "ios" => "ld64.lld",
        "wasi" => "wasm-ld",
        _ => "ld.lld",
    };
    let versioned = format!("{}-{}", name, LLVM_MAJOR);
    let mut directories: Vec<PathBuf> = driver.parent().filter(|d| !d.as_os_str().is_empty()).map(Path::to_path_buf).into_iter().collect();
    if let Ok(prefix) = std::env::var(LLVM_PREFIX_ENV) {
        directories.push(Path::new(&prefix).join("bin"));
    }
    directories.extend(std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default()));
    [executable_name(name), executable_name(&versioned)]
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

/// An Android NDK's link driver and system root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AndroidNdk {
    /// `toolchains/llvm/prebuilt/<host>/bin/clang`, which links with the
    /// NDK's `lld`, compiler-rt and libunwind, and finds `sysroot` itself.
    pub clang: PathBuf,
    /// `toolchains/llvm/prebuilt/<host>/sysroot`: bionic's headers and the
    /// stub libraries of every API level.
    pub sysroot: PathBuf,
}

impl AndroidNdk {
    /// The NDK `dir` names: the NDK itself (holding `toolchains/llvm`), or
    /// its `toolchains/llvm/prebuilt/<host>/sysroot`. `None` for no
    /// directory: then `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT` (the NDK's
    /// conventional variables), else the newest NDK the Android SDK
    /// (`ANDROID_HOME` or `ANDROID_SDK_ROOT`) holds in `ndk/<version>`.
    pub fn locate(dir: Option<&Path>) -> Option<AndroidNdk> {
        let variable = |name: &str| std::env::var_os(name).filter(|d| !d.is_empty()).map(PathBuf::from);
        let dir = match dir {
            Some(dir) => dir.to_path_buf(),
            None => variable("ANDROID_NDK_HOME").or_else(|| variable("ANDROID_NDK_ROOT")).or_else(|| {
                let sdk = variable("ANDROID_HOME").or_else(|| variable("ANDROID_SDK_ROOT"))?;
                let mut versions: Vec<PathBuf> = std::fs::read_dir(sdk.join("ndk")).ok()?.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.is_dir()).collect();
                versions.sort_by_key(|p| p.file_name().and_then(|n| n.to_str()).map(|n| n.split('.').map(|part| part.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>()));
                versions.pop()
            })?,
        };
        // The prebuilt toolchain: the one folder under `prebuilt` (named for
        // the host, `linux-x86_64`; macOS's is universal but named
        // `darwin-x86_64`), or `dir`'s parent when `dir` is its sysroot.
        let prebuilt = if dir.join("toolchains").join("llvm").join("prebuilt").is_dir() {
            std::fs::read_dir(dir.join("toolchains").join("llvm").join("prebuilt")).ok()?.filter_map(|e| e.ok().map(|e| e.path())).find(|p| p.join("sysroot").is_dir())?
        } else {
            dir.parent()?.to_path_buf()
        };
        let clang = prebuilt.join("bin").join(if cfg!(windows) { "clang.exe" } else { "clang" });
        let sysroot = prebuilt.join("sysroot");
        (clang.is_file() && sysroot.is_dir()).then_some(AndroidNdk { clang, sysroot })
    }
}

/// The iOS SDK for `target` that Xcode's `xcrun` reports (`iphoneos`, or
/// `iphonesimulator` for the simulator), on a Mac with Xcode; `None`
/// elsewhere.
pub fn apple_sdk(target: &pepper_sema::Target) -> Option<PathBuf> {
    if target.os != "ios" || !cfg!(target_os = "macos") {
        return None;
    }
    let simulator = target.triple.as_deref().is_some_and(|t| t.ends_with("-simulator"));
    let sdk = if simulator { "iphonesimulator" } else { "iphoneos" };
    let out = Command::new("xcrun").args(["--sdk", sdk, "--show-sdk-path"]).output().ok()?;
    let path = String::from_utf8(out.stdout).ok()?.trim().to_string();
    (out.status.success() && !path.is_empty()).then(|| PathBuf::from(path))
}

/// The folders of a Windows system root (`--sysroot` for a Windows target)
/// that hold the MSVC CRT, the Windows SDK's `um` libraries and the
/// Universal CRT for `arch`: laid out like a Visual Studio install
/// (`VC/Tools/MSVC/<version>/lib/x64`, `Windows Kits/10/Lib/<version>/um/x64`,
/// as `xwin splat --use-winsysroot-style` writes it), or as `xwin splat`
/// writes it by default (`crt/lib/x86_64`, `sdk/lib/um/x86_64`). Each name
/// matches without regard to case, and the highest version wins.
fn windows_library_dirs(sysroot: &Path, arch: &str) -> Vec<PathBuf> {
    // The folder in `dir` named `name` in any case.
    fn child(dir: &Path, name: &str) -> Option<PathBuf> {
        let exact = dir.join(name);
        if exact.is_dir() {
            return Some(exact);
        }
        std::fs::read_dir(dir).ok()?.filter_map(|e| e.ok()).map(|e| e.path()).find(|p| p.is_dir() && p.file_name().is_some_and(|n| n.to_string_lossy().eq_ignore_ascii_case(name)))
    }
    // The folder in `dir` with the highest dotted version number.
    fn highest_version(dir: &Path) -> Option<PathBuf> {
        let version = |p: &Path| -> Option<Vec<u64>> { p.file_name()?.to_str()?.split('.').map(|part| part.parse().ok()).collect() };
        std::fs::read_dir(dir).ok()?.filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.is_dir()).filter_map(|p| version(&p).map(|v| (v, p))).max().map(|(_, p)| p)
    }
    fn walk(start: Option<PathBuf>, names: &[&str]) -> Option<PathBuf> {
        names.iter().try_fold(start?, |dir, name| child(&dir, name))
    }
    let arches: &[&str] = match arch {
        "aarch64" => &["arm64", "aarch64"],
        _ => &["x64", "x86_64"],
    };
    let vc = walk(Some(sysroot.to_path_buf()), &["VC", "Tools", "MSVC"]).and_then(|d| highest_version(&d));
    let kits = walk(Some(sysroot.to_path_buf()), &["Windows Kits", "10", "Lib"]).and_then(|d| highest_version(&d));
    let mut dirs = vec![];
    for arch in arches {
        let candidates = [
            walk(vc.clone(), &["lib", arch]),
            walk(kits.clone(), &["um", arch]),
            walk(kits.clone(), &["ucrt", arch]),
            walk(Some(sysroot.to_path_buf()), &["crt", "lib", arch]),
            walk(Some(sysroot.to_path_buf()), &["sdk", "lib", "um", arch]),
            walk(Some(sysroot.to_path_buf()), &["sdk", "lib", "ucrt", arch]),
        ];
        dirs.extend(candidates.into_iter().flatten());
    }
    dirs
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
        match lld {
            // clang's WebAssembly toolchain reads only `-fuse-ld`, which
            // takes a path there.
            Some(path) if target.os == "wasi" => args.push(format!("-fuse-ld={}", path.display())),
            // `-fuse-ld=lld` even with `--ld-path`: it is how clang knows
            // the linker is lld, and for Mach-O, lld then gets the
            // `-platform_version` it requires instead of old ld64's flags.
            // clang's MSVC toolchain reads neither path: it runs the
            // `lld-link` beside it or on the PATH (`find_lld` finds none).
            Some(path) => args.extend(["-fuse-ld=lld".to_string(), format!("--ld-path={}", path.display())]),
            None => args.push("-fuse-ld=lld".to_string()),
        }
    }
    if target.os == "android" {
        // The NDK's clang finds its own system root; any other clang is
        // pointed at the one given.
        if AndroidNdk::locate(sysroot).is_none() {
            if let Some(sysroot) = sysroot {
                args.push(format!("--sysroot={}", sysroot.display()));
            }
        }
        return args;
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
            // it to lld-link, which finds `kernel32.lib` and the CRT there
            // when the layout is exactly Visual Studio's. Name the library
            // folders too, found without regard to case, for a root that
            // differs (xwin's own layout, or a lowercase `include`).
            args.extend(["-Xlinker".to_string(), format!("/winsysroot:{}", sysroot.display())]);
            for dir in windows_library_dirs(sysroot, &target.arch) {
                args.push(format!("-L{}", dir.display()));
            }
        } else {
            args.push(format!("--sysroot={}", sysroot.display()));
            if target.os == "ios" {
                // clang's Darwin toolchain prefers `-isysroot`, which a
                // clang configuration file (Homebrew's) may set to the
                // macOS SDK.
                args.push(format!("-isysroot{}", sysroot.display()));
            }
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
    let target = pepper_sema::current_target();
    let ndk = if target.os == "android" { AndroidNdk::locate(sysroot) } else { None };
    let driver = match &ndk {
        Some(ndk) => ndk.clang.clone(),
        None => find_link_driver().ok_or_else(missing_link_driver)?,
    };
    let sdk = if sysroot.is_none() { apple_sdk(&target) } else { None };
    let sysroot = sysroot.or(sdk.as_deref());

    let mut args: Vec<String> = vec!["-o".to_string(), output.to_string_lossy().into_owned()];
    if shared {
        args.push("-shared".to_string());
        let name = output.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if target.is_apple() {
            // Programs that link it find it on their run path.
            args.push(format!("-Wl,-install_name,@rpath/{}", name));
        } else if target.os != "windows" {
            args.push(format!("-Wl,-soname,{}", name));
        }
    }
    // The NDK's clang runs the NDK's own lld.
    let lld = if target.is_host() || target.os == "windows" || ndk.is_some() { None } else { find_lld(&target.os, &driver) };
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
    } else if target.os == "windows" {
        // A PE image has no symbol table of its own: the `debug`
        // module's backtraces name functions through DbgHelp, which reads
        // them from a `.pdb`. Without `-g` the objects carry no CodeView, so
        // this `.pdb` holds only the public symbols. `/DEBUG` turns off
        // `/OPT:REF`, which a release link wants, so ask for it again.
        for flag in ["/DEBUG", "/INCREMENTAL:NO", "/OPT:REF"] {
            args.extend(["-Xlinker".to_string(), flag.to_string()]);
        }
    }
    for obj in objects {
        args.push(obj.to_string_lossy().into_owned());
    }
    for dir in library_dirs {
        args.push(format!("-L{}", dir.display()));
    }
    for lib in libraries {
        if !is_built_into_libc(&target.os, lib) {
            args.push(format!("-l{}", lib));
        }
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
            if debug && target.os == "macos" && target.is_host() {
                write_dsym(output);
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

/// Gather a macOS executable's DWARF into `<output>.dSYM` beside it, as
/// clang does when it compiles and links in one step. The linker leaves
/// the DWARF in the object files, which the build cache may replace; the
/// bundle is what lldb and the `debug` module's backtraces read source
/// lines from. Without `dsymutil` (Xcode's command line tools) the program
/// still runs and its backtraces name functions, so a failure is ignored.
fn write_dsym(output: &Path) {
    let _ = Command::new("dsymutil").arg(output).output();
}

/// What a failed link for another platform needs, after the linker's own
/// messages: the target's system root, unless one was given, and LLVM's
/// linker. Empty for the host.
fn cross_link_note(target: &pepper_sema::Target, sysroot: Option<&Path>) -> String {
    if target.is_host() {
        return String::new();
    }
    let triple = target.triple.as_deref().unwrap_or_default();
    if target.os == "android" && AndroidNdk::locate(sysroot).is_none() {
        return format!(
            "\nnote: linking for '{}' needs the Android NDK (https://developer.android.com/ndk/downloads): \
             pass '--sysroot <ndk>' or set {}, ANDROID_NDK_HOME or ANDROID_HOME",
            triple,
            crate::options::sysroot_variable(&target.platform_triple().unwrap_or_default())
        );
    }
    if target.os == "ios" && sysroot.is_none() {
        return format!(
            "\nnote: linking for '{}' needs an iOS SDK (Xcode's): pass '--sysroot <sdk>' or set {}; on a Mac, `xcrun --sdk {} --show-sdk-path` names it",
            triple,
            crate::options::sysroot_variable(&target.platform_triple().unwrap_or_default()),
            if triple.ends_with("-simulator") { "iphonesimulator" } else { "iphoneos" }
        );
    }
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
            crate::options::sysroot_variable(&target.platform_triple().unwrap_or_default())
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
    fn only_a_glibc_before_2_34_needs_libpthread_and_libdl() {
        assert!(glibc_before_2_34("2.28"));
        assert!(glibc_before_2_34("2.33"));
        assert!(!glibc_before_2_34("2.34"));
        assert!(!glibc_before_2_34("2.39"));
    }

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
        // A found lld is named outright, and still announced as lld.
        let args = target_arguments(&target, None, Some(Path::new("/usr/bin/ld.lld-20")));
        assert_eq!(args[1..], ["-fuse-ld=lld".to_string(), "--ld-path=/usr/bin/ld.lld-20".to_string()]);
        let windows = pepper_sema::Target::parse("x86_64-pc-windows-msvc").unwrap();
        let args = target_arguments(&windows, Some(Path::new("/xwin")), None);
        if !windows.is_host() {
            assert!(args.contains(&"-fuse-ld=lld".to_string()), "{args:?}");
        }
        assert!(args.contains(&"/winsysroot:/xwin".to_string()), "{args:?}");
        let note = cross_link_note(&target, None);
        assert!(note.contains("pass '--sysroot <dir>' or set PEPPER_SYSROOT_"), "{note}");
    }

    /// A Windows system root's library folders are found in Visual
    /// Studio's layout and in xwin's, whatever their case.
    #[test]
    fn windows_library_dirs_follow_either_layout() {
        let root = std::env::temp_dir().join(format!("pepper-winsysroot-{}", std::process::id()));
        let vc = root.join("VC").join("Tools").join("MSVC");
        let kits = root.join("Windows Kits").join("10").join("lib");
        let sdk = kits.join("10.0.22621.0");
        for dir in [vc.join("14.29.30133").join("lib").join("x64"), vc.join("14.40.33807").join("lib").join("x64"), sdk.join("um").join("x64"), sdk.join("ucrt").join("x64"), root.join("sdk").join("lib").join("um").join("x86_64")] {
            std::fs::create_dir_all(dir).unwrap();
        }
        // Compared without regard to case: on a file system that ignores
        // case (Windows, macOS) the lookup finds `lib` under the name `Lib`.
        let lowercase = |dirs: &[PathBuf]| dirs.iter().map(|d| d.to_string_lossy().to_lowercase()).collect::<Vec<_>>();
        assert_eq!(
            lowercase(&windows_library_dirs(&root, "x86_64")),
            lowercase(&[vc.join("14.40.33807").join("lib").join("x64"), sdk.join("um").join("x64"), sdk.join("ucrt").join("x64"), root.join("sdk").join("lib").join("um").join("x86_64")])
        );
        assert!(windows_library_dirs(&root, "aarch64").is_empty());
        let windows = pepper_sema::Target::parse("x86_64-pc-windows-msvc").unwrap();
        let args = target_arguments(&windows, Some(&root), None);
        let expected = format!("-L{}", sdk.join("um").join("x64").display()).to_lowercase();
        assert!(args.iter().any(|a| a.to_lowercase() == expected), "{args:?}");
        std::fs::remove_dir_all(&root).unwrap();
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

    /// An Android NDK is found from its own directory or its system root,
    /// and its clang links with no other target options than the triple.
    #[test]
    fn android_links_with_the_ndk_clang() {
        let ndk = std::env::temp_dir().join(format!("pepper-ndk-{}", std::process::id()));
        let prebuilt = ndk.join("toolchains").join("llvm").join("prebuilt").join("linux-x86_64");
        let clang = prebuilt.join("bin").join(if cfg!(windows) { "clang.exe" } else { "clang" });
        std::fs::create_dir_all(prebuilt.join("sysroot")).unwrap();
        std::fs::create_dir_all(clang.parent().unwrap()).unwrap();
        std::fs::write(&clang, "").unwrap();
        let expected = AndroidNdk { clang: clang.clone(), sysroot: prebuilt.join("sysroot") };
        assert_eq!(AndroidNdk::locate(Some(&ndk)), Some(expected.clone()));
        assert_eq!(AndroidNdk::locate(Some(&prebuilt.join("sysroot"))), Some(expected));
        let target = pepper_sema::Target::parse("aarch64-linux-android").unwrap();
        assert_eq!(target_arguments(&target, Some(&ndk), None), ["--target=aarch64-linux-android30".to_string(), "-fuse-ld=lld".to_string()]);
        // Without an NDK, another clang is pointed at the system root.
        let other = std::env::temp_dir().join(format!("pepper-android-sysroot-{}", std::process::id()));
        assert_eq!(target_arguments(&target, Some(&other), None)[2], format!("--sysroot={}", other.display()));
        assert!(cross_link_note(&target, Some(&other)).contains("needs the Android NDK"));
        // bionic keeps threads in libc, and the NDK has no libpthread.
        assert!(is_built_into_libc("android", "pthread"));
        assert!(!is_built_into_libc("linux", "pthread"));
        std::fs::remove_dir_all(&ndk).unwrap();
    }

    /// iOS links with ld64.lld, like macOS, and its libraries are Darwin's.
    #[test]
    fn ios_links_like_macos() {
        let target = pepper_sema::Target::parse("aarch64-apple-ios-simulator").unwrap();
        assert!(target.is_apple());
        assert_eq!(
            target_arguments(&target, Some(Path::new("/sdk")), None),
            ["--target=aarch64-apple-ios15.0-simulator".to_string(), "-fuse-ld=lld".to_string(), "--sysroot=/sdk".to_string(), "-isysroot/sdk".to_string()]
        );
        assert!(cross_link_note(&target, None).contains("needs an iOS SDK"));
        assert!(default_system_libraries("ios").is_empty());
        assert_eq!(default_system_libraries("android"), ["m"]);
    }
}

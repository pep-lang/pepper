## Linking: the objects and libraries into an executable, with clang as
## the link driver.
##
## For another platform (`--target`), clang links with `--target=<triple>`,
## LLVM's own linker (`lld`, since the host's system linker knows only the
## host's formats; named with `--ld-path` when `find_lld` finds it), and the
## target's system root (`--sysroot`, or `/winsysroot` for a Windows target,
## which `lld-link` reads).
##
## WebAssembly (`wasm32-wasip1`) links with `wasm-ld` against wasi-libc, from
## a wasi-sdk (`WasiSdk`). iOS links with `ld64.lld` against an iOS SDK:
## `--sysroot`, else on a Mac the SDK `xcrun` reports (`apple_sdk`). Android
## links with the NDK's own clang, which knows its system root, compiler-rt
## and unwinder (`AndroidNdk`).

import io;
import [Directory, File, Path] from io;
import compiler.link;
import os;
import process;

## The LLVM major the compiler is built against, whose clang links.
export const LLVM_MAJOR = "20";

## The environment variable that names the LLVM install, besides
## `PEPPER_LLVM_PREFIX`: the name LLVM's Rust bindings read, which the
## setup scripts once exported.
export const LLVM_PREFIX_ENV = "LLVM_SYS_201_PREFIX";

## Pepper's own name for the LLVM install, which wins over
## `LLVM_PREFIX_ENV`.
export const PEPPER_LLVM_PREFIX_ENV = "PEPPER_LLVM_PREFIX";

## The LLVM install whose tools link: `$PEPPER_LLVM_PREFIX`, else
## `$LLVM_SYS_201_PREFIX`.
##
## @returns its folder, or Empty when neither is set
export llvm_prefix(): String? {
    var prefix = os.environment(PEPPER_LLVM_PREFIX_ENV);
    if (prefix.is_value() and !prefix.value().is_empty) {
        return prefix;
    }
    return os.environment(LLVM_PREFIX_ENV);
}

## `name` as an executable's file name on the host: `name.exe` on Windows.
executable_name(name: String): String {
    return os.system_os() == os.OperatingSystem.Windows ? name + ".exe" : name;
}

## The environment variable naming `triple`'s system root:
## `PEPPER_SYSROOT_AARCH64_APPLE_DARWIN` for `aarch64-apple-darwin`.
##
## @param triple the triple, without an OS version (`Target.platform_triple`)
## @returns the variable's name
export sysroot_variable(triple: String): String {
    var name = StringBuilder();
    for (var i in 0..triple.size) {
        var b = triple.byte_at(i);
        bool alphanumeric = (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9');
        name.append(alphanumeric ? triple.substr_bytes(i, 1).upper() : "_");
    }
    return $"PEPPER_SYSROOT_{name.to_string()}";
}

## The target's system root: `sysroot` (`--sysroot`) when given, else
## `$PEPPER_SYSROOT_<TRIPLE>` for a `--target` triple, without its OS
## version (`wasm32-wasi` reads `PEPPER_SYSROOT_WASM32_WASIP1`, and
## `arm64-apple-ios17.0` `PEPPER_SYSROOT_AARCH64_APPLE_IOS`).
##
## @param target the compile target
## @param sysroot the folder `--sysroot` names, if any
## @returns the system root, or none
export effective_sysroot(target: link.Target, sysroot: Path?): Path? {
    if (sysroot.is_value()) {
        return sysroot;
    }
    var triple = target.platform_triple();
    if (triple.is_empty) {
        return Optional<Path>.Empty;
    }
    return _variable_dir(sysroot_variable(triple));
}

## The folders LLVM's packages install `clang` in when they leave it off the
## PATH: the llvm.org Windows installer's and Scoop's; Homebrew's keg-only
## `llvm` and `llvm@<major>`; Debian and Ubuntu's `/usr/lib/llvm-<major>`,
## this LLVM's major first, then the newest.
llvm_install_dirs(): Path[] {
    var dirs = Array<Path>();
    var system = os.system_os();
    if (system == os.OperatingSystem.Windows) {
        for (var variable in ["ProgramFiles", "ProgramW6432"]) {
            var dir = os.environment(variable);
            if (dir.is_value()) {
                dirs.append(Path(dir.value()).join(Path("LLVM")).join(Path("bin")));
            }
        }
        var home = os.environment("USERPROFILE");
        if (home.is_value()) {
            dirs.append(
                Path(home.value())
                    .join(Path("scoop"))
                    .join(Path("apps"))
                    .join(Path("llvm"))
                    .join(Path("current"))
                    .join(Path("bin"))
            );
        }
    } else if (system == os.OperatingSystem.Mac) {
        for (var root in ["/opt/homebrew/opt", "/usr/local/opt"]) {
            dirs.append(Path(root).join(Path("llvm")).join(Path("bin")));
            dirs.append(Path(root).join(Path($"llvm@{LLVM_MAJOR}")).join(Path("bin")));
        }
    } else {
        dirs.append(Path($"/usr/lib/llvm-{LLVM_MAJOR}/bin"));
        var others = Array<(ulong, Path)>();
        var listed = Directory.open(Path("/usr/lib"));
        if (listed.is_ok()) {
            var entries = listed.value().entries();
            if (entries.is_ok()) {
                for (var entry in entries.value()) {
                    if (entry.name.starts_with("llvm-")) {
                        var major = ulong.parse(entry.name.substr_bytes(5, entry.name.size - 5));
                        if (major.is_value()) {
                            others.append((major.value(), entry.path.join(Path("bin"))));
                        }
                    }
                }
            }
        }
        # The newest first.
        others.sort((a, b) => b.0 > a.0 ? 1 : (b.0 < a.0 ? -1 : 0));
        for (var other in others) {
            dirs.append(other.1);
        }
    }
    return dirs;
}

## Finds clang, the link driver: in the `bin` folder of `llvm_prefix()`
## (`$PEPPER_LLVM_PREFIX`, else `$LLVM_SYS_201_PREFIX`), beside the
## running compiler, on the PATH (plain, then with this LLVM's major), then
## in the folders LLVM's packages install it in.
##
## @returns its path, or Empty when there is none
export find_link_driver(): Path? {
    var exe = executable_name("clang");
    var candidates = Array<Path>();
    var prefix = llvm_prefix();
    if (prefix.is_value()) {
        candidates.append(Path(prefix.value()).join(Path("bin")).join(Path(exe)));
    }
    var running = process.executable_path();
    if (running.is_ok()) {
        var parent = running.value().parent();
        if (parent.is_value()) {
            candidates.append(parent.value().join(Path(exe)));
        }
    }
    for (var candidate in candidates) {
        if (candidate.is_file()) {
            return Optional<Path>.Value(candidate);
        }
    }
    for (var name in [exe, executable_name($"clang-{LLVM_MAJOR}")]) {
        var found = process.find_executable(name);
        if (found.is_value()) {
            return found;
        }
    }
    for (var dir in llvm_install_dirs()) {
        if (dir.join(Path(exe)).is_file()) {
            return Optional<Path>.Value(dir.join(Path(exe)));
        }
    }
    return Optional<Path>.Empty;
}

# Why a link cannot start when `find_link_driver` finds no clang, and what
# to install on this platform.
_missing_link_driver(): String {
    var system = os.system_os();
    var install = "install it with 'sudo apt install clang' (Debian, Ubuntu), 'sudo dnf install clang' (Fedora, RHEL), 'sudo pacman -S clang' (Arch) or 'sudo zypper install clang' (openSUSE)";
    if (system == os.OperatingSystem.Windows) {
        install = "install LLVM with 'winget install LLVM.LLVM' (or 'scoop install llvm', or 'choco install llvm'), and the Visual Studio Build Tools' C++ workload, which supplies the MSVC libraries and Windows SDK";
    } else if (system == os.OperatingSystem.Mac) {
        install = "install Xcode's command line tools with 'xcode-select --install'";
    }
    return $"Link failed: no clang found to link with: none beside the compiler, on the PATH, or where LLVM's packages install it\nnote: {install}; or put the folder holding clang on the PATH";
}

## System libraries every Pepper executable needs on the target's OS:
## those clang does not add itself. A floating-point `**` calls `pow`,
## which glibc and bionic keep in libm (macOS has it in libSystem, Windows
## in the UCRT). Before glibc 2.34, threads and `dlsym` lived in libpthread
## and libdl, so a host with an older glibc links those too; a newer glibc
## has them in libc, and a system root for another machine may not carry
## them at all. wasi-libc keeps `getpid` in an emulation library of its own.
##
## @param system the target's OS, as `Target.os` spells it
## @returns the libraries, by name
export default_system_libraries(system: String): String[] {
    if (system == "windows") {
        return ["kernel32", "user32", "shell32"];
    }
    if (system == "linux") {
        return _host_glibc_before_2_34() ? ["m", "pthread", "dl"] : ["m"];
    }
    if (system == "android") {
        return ["m"];
    }
    if (system == "wasi") {
        return ["wasi-emulated-getpid"];
    }
    return Array<String>();
}

## Whether `library` is one whose functions `system` keeps in its C library,
## with no library of that name to link: Android's bionic has threads and
## real-time clocks in libc, and the NDK ships no `libpthread` or `librt`.
## Dropping them lets one `[Link("pthread")]` serve Linux and Android.
##
## @param system the target's OS
## @param library the library, by name
## @returns true when it is not linked
export is_built_into_libc(system: String, library: String): bool {
    return system == "android" and (library == "pthread" or library == "rt");
}

[Target(OS(Linux) && !OS(Android))]
extern char* gnu_get_libc_version();

# Whether this compiler runs on a glibc older than 2.34, from its own
# version.
[Target(OS(Linux) && !OS(Android))]
_host_glibc_before_2_34(): bool {
    return glibc_before_2_34(String(gnu_get_libc_version()));
}

# False on any C library but glibc.
[Target(!OS(Linux) || OS(Android))]
_host_glibc_before_2_34(): bool {
    return false;
}

## Whether the glibc `version` (`"2.28"`) is older than 2.34.
##
## @param version the version
## @returns true before 2.34
export glibc_before_2_34(version: String): bool {
    var parts = version.split(".");
    ulong major = 0;
    ulong minor = 0;
    if (parts.count > 0 and ulong.parse(parts[0]).is_value()) {
        major = ulong.parse(parts[0]).value();
    }
    if (parts.count > 1 and ulong.parse(parts[1]).is_value()) {
        minor = ulong.parse(parts[1]).value();
    }
    return major < 2 or (major == 2 and minor < 34);
}

## LLVM's linker for an ELF, Mach-O or WebAssembly target (`ld.lld`,
## `ld64.lld`, `wasm-ld`), when one is found: beside the link driver, in the
## LLVM install the compiler links against, or on the PATH, plain or with
## this LLVM's major (`ld.lld-20`). clang finds a plain one beside itself or
## on the PATH unaided, but not the versioned name Ubuntu's `lld-20`
## installs.
##
## @param system the target's OS
## @param driver the link driver
## @returns the linker, or none
export find_lld(system: String, driver: Path): Path? {
    var name = "ld.lld";
    if (system == "macos" or system == "ios") {
        name = "ld64.lld";
    } else if (system == "wasi") {
        name = "wasm-ld";
    }
    var dirs = Array<Path>();
    var parent = driver.parent();
    if (parent.is_value() and !parent.value().to_string().is_empty) {
        dirs.append(parent.value());
    }
    var prefix = llvm_prefix();
    if (prefix.is_value()) {
        dirs.append(Path(prefix.value()).join(Path("bin")));
    }
    for (var candidate in [executable_name(name), executable_name($"{name}-{LLVM_MAJOR}")]) {
        for (var dir in dirs) {
            if (dir.join(Path(candidate)).is_file()) {
                return Optional<Path>.Value(dir.join(Path(candidate)));
            }
        }
        var found = process.find_executable(candidate);
        if (found.is_value()) {
            return found;
        }
    }
    return Optional<Path>.Empty;
}

# The folders in `dir`; none when it cannot be read.
_subdirectories(dir: Path): Path[] {
    var out = Array<Path>();
    var listed = Directory.open(dir);
    if (listed.is_err()) {
        return out;
    }
    var entries = listed.value().entries();
    if (entries.is_err()) {
        return out;
    }
    for (var entry in entries.value()) {
        if (entry.path.is_directory()) {
            out.append(entry.path);
        }
    }
    return out;
}

# `name`'s dotted version numbers (`10.0.22621.0`), a part that is not a
# number read as 0; with `strict`, none when a part is not a number.
_version(name: String, strict: bool): ulong[]? {
    var out = Array<ulong>();
    for (var part in name.split(".")) {
        var number = ulong.parse(part);
        if (!number.is_value() and strict) {
            return Optional<ulong[]>.Empty;
        }
        out.append(number.is_value() ? number.value() : 0);
    }
    return Optional<ulong[]>.Value(out);
}

# Compares two versions part by part; of two that agree as far as the
# shorter goes, the shorter is first.
_compare_versions(a: ulong[], b: ulong[]): int {
    var common = a.count < b.count ? a.count : b.count;
    for (var i in 0..common) {
        if (a[i] != b[i]) {
            return a[i] < b[i] ? -1 : 1;
        }
    }
    return a.count < b.count ? -1 : (a.count > b.count ? 1 : 0);
}

# The folder in `dir` with the highest dotted version number (see
# `_version`).
_highest_version(dir: Path, strict: bool): Path? {
    var best = Optional<Path>.Empty;
    var best_version = Array<ulong>();
    for (var sub in _subdirectories(dir)) {
        var name = sub.file_name();
        if (!name.is_value()) {
            continue;
        }
        var version = _version(name.value(), strict);
        if (!version.is_value()) {
            continue;
        }
        if (!best.is_value() or _compare_versions(version.value(), best_version) > 0) {
            best = Optional<Path>.Value(sub);
            best_version = version.value();
        }
    }
    return best;
}

# The folder the environment variable `name` names, when it is set and not
# empty.
_variable_dir(name: String): Path? {
    var value = os.environment(name);
    if (!value.is_value() or value.value().is_empty) {
        return Optional<Path>.Empty;
    }
    return Optional<Path>.Value(Path(value.value()));
}

## A wasi-sdk's two parts the link needs: the wasi-libc system root and the
## clang resource directory holding `libclang_rt.builtins-wasm32.a`.
export struct WasiSdk {
    ## `share/wasi-sysroot`: wasi-libc's headers and libraries.
    var sysroot: Path;
    ## `lib/clang/<version>`, when the SDK has one: its compiler-rt builtins
    ## are for its own clang's version, which any clang links with.
    var resource_dir: Path? = Optional<Path>.Empty;

    construct(sysroot: Path) {
        this.sysroot = sysroot;
    }

    ## The SDK `dir` names: a wasi-sdk (holding `share/wasi-sysroot`), or a
    ## system root itself (a wasi-sdk's `share/wasi-sysroot`, whose SDK is
    ## two directories up, or a stand-alone wasi-libc). Without a
    ## directory, `WASI_SDK_PATH`, wasi-sdk's own variable, names it.
    ##
    ## @param dir the folder `--sysroot` names, if any
    ## @returns the SDK, or none
    static locate(dir: Path?): WasiSdk? {
        var root = dir.is_value() ? dir : _variable_dir("WASI_SDK_PATH");
        if (!root.is_value()) {
            return Optional<WasiSdk>.Empty;
        }
        var given = root.value();
        var nested = given.join(Path("share")).join(Path("wasi-sysroot"));
        var found = WasiSdk(given);
        var sdk = Optional<Path>.Empty;
        if (nested.is_directory()) {
            found = WasiSdk(nested);
            sdk = root;
        } else {
            var up = given.parent();
            if (up.is_value()) {
                sdk = up.value().parent();
            }
        }
        if (sdk.is_value()) {
            # The last version by name.
            var versions = _subdirectories(sdk.value().join(Path("lib")).join(Path("clang")));
            versions.sort((a, b) => a.to_string().compare(b.to_string()));
            if (!versions.is_empty) {
                found.resource_dir = Optional<Path>.Value(versions[versions.count - 1]);
            }
        }
        return Optional<WasiSdk>.Value(found);
    }
}

## An Android NDK's link driver and system root.
export struct AndroidNdk {
    ## `toolchains/llvm/prebuilt/<host>/bin/clang`, which links with the
    ## NDK's `lld`, compiler-rt and libunwind, and finds `sysroot` itself.
    var clang: Path;
    ## `toolchains/llvm/prebuilt/<host>/sysroot`: bionic's headers and the
    ## stub libraries of every API level.
    var sysroot: Path;

    construct(clang: Path, sysroot: Path) {
        this.clang = clang;
        this.sysroot = sysroot;
    }

    ## The NDK `dir` names: the NDK itself (holding `toolchains/llvm`), or
    ## its `toolchains/llvm/prebuilt/<host>/sysroot`. Without a directory,
    ## `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT` (the NDK's conventional
    ## variables), else the newest NDK the Android SDK (`ANDROID_HOME` or
    ## `ANDROID_SDK_ROOT`) holds in `ndk/<version>`.
    ##
    ## @param dir the folder `--sysroot` names, if any
    ## @returns the NDK, or none
    static locate(dir: Path?): AndroidNdk? {
        var root = dir;
        for (var variable in ["ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"]) {
            if (!root.is_value()) {
                root = _variable_dir(variable);
            }
        }
        if (!root.is_value()) {
            var sdk = _variable_dir("ANDROID_HOME");
            if (!sdk.is_value()) {
                sdk = _variable_dir("ANDROID_SDK_ROOT");
            }
            if (sdk.is_value()) {
                root = _highest_version(sdk.value().join(Path("ndk")), false);
            }
        }
        if (!root.is_value()) {
            return Optional<AndroidNdk>.Empty;
        }
        # The prebuilt toolchain: the one folder under `prebuilt` (named for
        # the host, `linux-x86_64`; macOS's is universal but named
        # `darwin-x86_64`), or `dir`'s parent when `dir` is its sysroot.
        var prebuilt = Optional<Path>.Empty;
        var toolchains = root.value().join(Path("toolchains")).join(Path("llvm")).join(Path("prebuilt"));
        if (toolchains.is_directory()) {
            for (var sub in _subdirectories(toolchains)) {
                if (!prebuilt.is_value() and sub.join(Path("sysroot")).is_directory()) {
                    prebuilt = Optional<Path>.Value(sub);
                }
            }
        } else {
            prebuilt = root.value().parent();
        }
        if (!prebuilt.is_value()) {
            return Optional<AndroidNdk>.Empty;
        }
        var clang = prebuilt.value().join(Path("bin")).join(Path(executable_name("clang")));
        var sysroot = prebuilt.value().join(Path("sysroot"));
        if (!clang.is_file() or !sysroot.is_directory()) {
            return Optional<AndroidNdk>.Empty;
        }
        return Optional<AndroidNdk>.Value(AndroidNdk(clang, sysroot));
    }
}

## The iOS SDK for `target` that Xcode's `xcrun` reports (`iphoneos`, or
## `iphonesimulator` for the simulator), on a Mac with Xcode; none
## elsewhere.
##
## @param target the compile target
## @returns the SDK's folder, or none
export apple_sdk(target: link.Target): Path? {
    if (target.os != "ios" or os.system_os() != os.OperatingSystem.Mac) {
        return Optional<Path>.Empty;
    }
    var sdk = target.triple.ends_with("-simulator") ? "iphonesimulator" : "iphoneos";
    var command = process.Command("xcrun");
    command.argument("--sdk").argument(sdk).argument("--show-sdk-path");
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    if (ran.is_err() or !ran.value().status.success() or ran.value().stdout.trim().is_empty) {
        return Optional<Path>.Empty;
    }
    return Optional<Path>.Value(Path(ran.value().stdout.trim()));
}

# The folder in `dir` named `name` in any case.
_child(dir: Path, name: String): Path? {
    var exact = dir.join(Path(name));
    if (exact.is_directory()) {
        return Optional<Path>.Value(exact);
    }
    for (var sub in _subdirectories(dir)) {
        var found = sub.file_name();
        if (found.is_value() and found.value().lower() == name.lower()) {
            return Optional<Path>.Value(sub);
        }
    }
    return Optional<Path>.Empty;
}

# The folder reached from `start` through `names`, each in any case.
_walk(start: Path?, names: String[]): Path? {
    var at = start;
    for (var name in names) {
        if (!at.is_value()) {
            return at;
        }
        at = _child(at.value(), name);
    }
    return at;
}

## The folders of a Windows system root (`--sysroot` for a Windows target)
## that hold the MSVC CRT, the Windows SDK's `um` libraries and the
## Universal CRT for `arch`: laid out like a Visual Studio install
## (`VC/Tools/MSVC/<version>/lib/x64`, `Windows Kits/10/Lib/<version>/um/x64`,
## as `xwin splat --use-winsysroot-style` writes it), or as `xwin splat`
## writes it by default (`crt/lib/x86_64`, `sdk/lib/um/x86_64`). Each name
## matches without regard to case, and the highest version wins.
##
## @param sysroot the system root
## @param arch the target's architecture
## @returns the folders
export windows_library_dirs(sysroot: Path, arch: String): Path[] {
    var root = Optional<Path>.Value(sysroot);
    var vc = Optional<Path>.Empty;
    var msvc = _walk(root, ["VC", "Tools", "MSVC"]);
    if (msvc.is_value()) {
        vc = _highest_version(msvc.value(), true);
    }
    var kits = Optional<Path>.Empty;
    var lib = _walk(root, ["Windows Kits", "10", "Lib"]);
    if (lib.is_value()) {
        kits = _highest_version(lib.value(), true);
    }
    var dirs = Array<Path>();
    for (var name in arch == "aarch64" ? ["arm64", "aarch64"] : ["x64", "x86_64"]) {
        var candidates = [
            _walk(vc, ["lib", name]),
            _walk(kits, ["um", name]),
            _walk(kits, ["ucrt", name]),
            _walk(root, ["crt", "lib", name]),
            _walk(root, ["sdk", "lib", "um", name]),
            _walk(root, ["sdk", "lib", "ucrt", name]),
        ];
        for (var candidate in candidates) {
            if (candidate.is_value()) {
                dirs.append(candidate.value());
            }
        }
    }
    return dirs;
}

## The link driver's options that choose the platform: for the host, none
## but LLVM's linker on Linux when `lld` is found (much faster than the
## system's BFD `ld`); for another target,
## its triple, LLVM's linker (`lld`, the one at `lld` when given), and its
## system root.
##
## @param target the compile target
## @param sysroot its system root, if any
## @param lld LLVM's linker, if found
## @returns the options
export target_arguments(target: link.Target, sysroot: Path?, lld: Path?): String[] {
    var args = Array<String>();
    if (!target.triple.is_empty) {
        args.append($"--target={target.triple}");
    }
    if (target.is_host()) {
        if (lld.is_value() and target.os == "linux") {
            args.append("-fuse-ld=lld");
            args.append($"--ld-path={lld.value()}");
        }
    } else {
        if (lld.is_value() and target.os == "wasi") {
            # clang's WebAssembly toolchain reads only `-fuse-ld`, which
            # takes a path there.
            args.append($"-fuse-ld={lld.value()}");
        } else {
            # `-fuse-ld=lld` even with `--ld-path`: it is how clang knows the
            # linker is lld, and for Mach-O, lld then gets the
            # `-platform_version` it requires instead of old ld64's flags.
            # clang's MSVC toolchain reads neither: it runs the `lld-link`
            # beside it or on the PATH.
            args.append("-fuse-ld=lld");
            if (lld.is_value()) {
                args.append($"--ld-path={lld.value()}");
            }
        }
    }
    if (target.os == "android") {
        # The NDK's clang finds its own system root; any other clang is
        # pointed at the one given.
        if (sysroot.is_value() and !AndroidNdk.locate(sysroot).is_value()) {
            args.append($"--sysroot={sysroot.value()}");
        }
        return args;
    }
    if (target.os == "wasi") {
        var sdk = WasiSdk.locate(sysroot);
        if (sdk.is_value()) {
            args.append($"--sysroot={sdk.value().sysroot}");
            if (sdk.value().resource_dir.is_value()) {
                args.append($"-resource-dir={sdk.value().resource_dir.value()}");
            }
        }
        return args;
    }
    if (!sysroot.is_value()) {
        return args;
    }
    if (target.os == "windows") {
        # clang's MSVC toolchain takes the Windows SDK and MSVC libraries
        # from `/winsysroot` only in clang-cl mode, so hand it to lld-link,
        # which finds `kernel32.lib` and the CRT there when the layout is
        # exactly Visual Studio's. Name the library folders too, found
        # without regard to case, for a root that differs (xwin's own
        # layout, or a lowercase `include`).
        args.append("-Xlinker");
        args.append($"/winsysroot:{sysroot.value()}");
        for (var dir in windows_library_dirs(sysroot.value(), target.arch)) {
            args.append($"-L{dir}");
        }
    } else {
        args.append($"--sysroot={sysroot.value()}");
        if (target.os == "ios") {
            # clang's Darwin toolchain prefers `-isysroot`, which a clang
            # configuration file (Homebrew's) may set to the macOS SDK.
            args.append($"-isysroot{sysroot.value()}");
        }
    }
    return args;
}

## What a failed link for another platform needs, after the linker's own
## messages: the target's system root, unless one was given, and LLVM's
## linker. Empty for the host.
##
## @param target the compile target
## @param sysroot its system root, if any
## @returns the note, from a newline, or empty
export cross_link_note(target: link.Target, sysroot: Path?): String {
    if (target.is_host()) {
        return "";
    }
    var triple = target.triple;
    var variable = sysroot_variable(target.platform_triple());
    if (target.os == "android" and !AndroidNdk.locate(sysroot).is_value()) {
        return $"\nnote: linking for '{triple}' needs the Android NDK (https://developer.android.com/ndk/downloads): pass '--sysroot <ndk>' or set {variable}, ANDROID_NDK_HOME or ANDROID_HOME";
    }
    if (target.os == "ios" and !sysroot.is_value()) {
        var sdk = triple.ends_with("-simulator") ? "iphonesimulator" : "iphoneos";
        return $"\nnote: linking for '{triple}' needs an iOS SDK (Xcode's): pass '--sysroot <sdk>' or set {variable}; on a Mac, `xcrun --sdk {sdk} --show-sdk-path` names it";
    }
    if (target.os == "wasi") {
        var sdk = WasiSdk.locate(sysroot);
        if (!sdk.is_value()) {
            return $"\nnote: linking for '{triple}' needs a wasi-sdk (https://github.com/WebAssembly/wasi-sdk/releases) and LLVM's wasm-ld: pass '--sysroot <wasi-sdk>' or set {variable} or WASI_SDK_PATH";
        }
        return $"\nnote: linking for '{triple}' with the wasi-sdk system root '{sdk.value().sysroot}' needs LLVM's wasm-ld (lld) beside clang or on the PATH";
    }
    if (!sysroot.is_value()) {
        return $"\nnote: linking for '{triple}' needs that platform's system libraries and LLVM's linker (lld): pass '--sysroot <dir>' or set {variable}";
    }
    return $"\nnote: linking for '{triple}' with the system root '{sysroot.value()}' needs LLVM's linker (lld) beside clang";
}

## Links `objects` into the executable `output` with clang, for `target`.
##
## @param objects the object files
## @param output the executable to write
## @param libraries the libraries to link, by name
## @param library_dirs the folders to search for them
## @param target the compile target
## @param sysroot its system root (`effective_sysroot`), if any
## @returns nothing, or why the link failed
export link_objects(
    objects: Path[], output: Path, libraries: String[], library_dirs: Path[], target: link.Target, sysroot: Path?
): Result<void, String> {
    var ndk = target.os == "android" ? AndroidNdk.locate(sysroot) : Optional<AndroidNdk>.Empty;
    var driver = ndk.is_value() ? Optional<Path>.Value(ndk.value().clang) : find_link_driver();
    if (!driver.is_value()) {
        return Result<void, String>.err(_missing_link_driver());
    }
    var root = sysroot.is_value() ? sysroot : apple_sdk(target);
    var command = process.Command(driver.value().to_string());
    command.argument("-o").argument(output.to_string());
    # The NDK's clang runs the NDK's own lld, and clang's MSVC toolchain
    # finds lld-link itself.
    var lld = Optional<Path>.Empty;
    if ((!target.is_host() and target.os != "windows" and !ndk.is_value())
        or (target.is_host() and target.os == "linux")) {
        lld = find_lld(target.os, driver.value());
    }
    for (var argument in target_arguments(target, root, lld)) {
        command.argument(argument);
    }
    if (target.os == "windows") {
        # A PE image has no symbol table of its own: backtraces name
        # functions through a `.pdb` of the public symbols.
        for (var flag in ["/DEBUG", "/INCREMENTAL:NO", "/OPT:REF"]) {
            command.argument("-Xlinker").argument(flag);
        }
    }
    for (var object in objects) {
        command.argument(object.to_string());
    }
    for (var dir in library_dirs) {
        command.argument($"-L{dir}");
    }
    # GNU ld and lld resolve static archives left to right: in a group, an
    # archive (a static LLVM) may need one named before it (zlib).
    bool group = target.os == "linux";
    if (group) {
        command.argument("-Wl,--start-group");
    }
    for (var library in libraries) {
        if (!is_built_into_libc(target.os, library)) {
            command.argument($"-l{library}");
        }
    }
    for (var library in default_system_libraries(target.os)) {
        command.argument($"-l{library}");
    }
    if (group) {
        command.argument("-Wl,--end-group");
    }
    command.stdout(process.Stream.Pipe).stderr(process.Stream.Pipe);
    var ran = command.run();
    if (ran.is_err()) {
        return Result<void, String>.err($"Link failed: cannot run {driver.value()}: {ran.error().message}");
    }
    var out = ran.value();
    if (out.status.success()) {
        # Link warnings matter too: pass on anything the driver said.
        if (!out.stdout.trim().is_empty) {
            File.stdout().write_all(out.stdout);
        }
        if (!out.stderr.trim().is_empty) {
            File.stderr().write_all(out.stderr);
        }
        return Result<void, String>.ok();
    }
    var detail = out.stdout.trim();
    if (!out.stderr.trim().is_empty) {
        detail = detail.is_empty ? out.stderr.trim() : detail + "\n" + out.stderr.trim();
    }
    return Result<void, String>.err(
        $"Link failed: {driver.value()} exited with {out.status}\n{detail}{cross_link_note(target, root)}"
    );
}

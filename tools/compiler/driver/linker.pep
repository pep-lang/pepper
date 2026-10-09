## Linking: the objects and libraries into an executable, with clang as
## the link driver, as `crates/pepper-driver/src/linker.rs` does for the
## host.

import io;
import [Directory, File, Path] from io;
import os;
import process;

## The LLVM major the compiler is built against, whose clang links.
export const LLVM_MAJOR = "20";

## The environment variable that names the LLVM install.
export const LLVM_PREFIX_ENV = "LLVM_SYS_201_PREFIX";

## `name` as an executable's file name on the host: `name.exe` on Windows.
executable_name(name: String): String {
    return os.system_os() == os.OperatingSystem.Windows ? name + ".exe" : name;
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

## Finds clang, the link driver: in `$LLVM_SYS_201_PREFIX/bin`, beside the
## running compiler, on the PATH (plain, then with this LLVM's major), then
## in the folders LLVM's packages install it in.
##
## @returns its path, or Empty when there is none
export find_link_driver(): Path? {
    var exe = executable_name("clang");
    var candidates = Array<Path>();
    var prefix = os.environment(LLVM_PREFIX_ENV);
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

## System libraries every Pepper executable needs on the host's OS: those
## clang does not add itself. A floating-point `**` calls `pow`, which
## glibc keeps in libm.
export default_system_libraries(): String[] {
    var system = os.system_os();
    if (system == os.OperatingSystem.Windows) {
        return ["kernel32", "user32", "shell32"];
    }
    if (system == os.OperatingSystem.Linux) {
        # glibc before 2.34 keeps threads and `dlopen` in libraries of their
        # own; later ones keep empty stubs of them.
        return ["m", "pthread", "dl"];
    }
    return Array<String>();
}

## Links `objects` into the executable `output` with clang.
##
## @param objects the object files
## @param output the executable to write
## @param libraries the libraries to link, by name
## @param library_dirs the folders to search for them
## @returns nothing, or why the link failed
export link_objects(objects: Path[], output: Path, libraries: String[], library_dirs: Path[]): Result<void, String> {
    var driver = find_link_driver();
    if (!driver.is_value()) {
        return Result<void, String>.err(
            $"Link failed: no clang found; install LLVM {LLVM_MAJOR} or set {LLVM_PREFIX_ENV}"
        );
    }
    var command = process.Command(driver.value().to_string());
    command.argument("-o").argument(output.to_string());
    if (os.system_os() == os.OperatingSystem.Windows) {
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
    for (var library in libraries) {
        command.argument($"-l{library}");
    }
    for (var library in default_system_libraries()) {
        command.argument($"-l{library}");
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
    return Result<void, String>.err($"Link failed: {driver.value()} exited with {out.status}\n{detail}");
}

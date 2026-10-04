//! CLI options: clap-derive port of `source/Compiler/Options.cpp:20-42`.

use clap::Parser;
use std::path::PathBuf;

#[derive(Debug, Parser)]
#[command(name = "pep-build", version, about = "Pepper compiler")]
pub struct Options {
    /// The program's entry file. The files it imports are found on their
    /// own; only the first file named is compiled. With none, builds the
    /// project whose `pep.toml` is in the current directory or above it.
    pub source_files: Vec<PathBuf>,

    /// Add a directory to the import search path.
    #[arg(short = 'I', value_name = "DIR")]
    pub import_paths: Vec<PathBuf>,

    /// Force an import by name.
    #[arg(long = "import", value_name = "NAME")]
    pub forced_imports: Vec<String>,

    /// Link against a library.
    #[arg(short = 'l', value_name = "LIB")]
    pub libraries: Vec<String>,

    /// Add a directory to the linker's library search path. The folders in
    /// `$PEPPER_LIBRARY_PATH` (separated like `PATH`) are searched after
    /// these and `[Link(path = ...)]` folders.
    #[arg(short = 'L', value_name = "DIR")]
    pub library_dirs: Vec<PathBuf>,

    /// Define a build option: `-D NAME`, or `-D NAME=VALUE` with a value
    /// (a bare `NAME` is `NAME=1`, as in C). `[BuildOption("NAME")]` and
    /// `BuildOption(NAME)` in `[Target(...)]` select code by it, and
    /// `static` blocks read it with `reflect.build_option`. Repeat for more
    /// options; of two that name one option, the later wins.
    #[arg(short = 'D', value_name = "NAME[=VALUE]", value_parser = parse_build_option)]
    pub build_options: Vec<(String, String)>,

    /// Output path: the executable, with `--lib` the library, or with
    /// `--emit-static` the folder for the expanded source.
    #[arg(short = 'o', value_name = "OUT")]
    pub output: Option<PathBuf>,

    /// Build a library for C code to link instead of an executable:
    /// `static` (`libname.a`, `name.lib` on Windows) or `shared`
    /// (`libname.so`, `libname.dylib`, `name.dll`), with a C header beside
    /// it declaring the `[Export]`ed functions. No `main` is needed.
    #[arg(long = "lib", value_name = "KIND", value_parser = ["static", "shared"])]
    pub library: Option<String>,

    /// Build directory.
    #[arg(long = "build", value_name = "DIR")]
    pub build_dir: Option<PathBuf>,

    /// Optimization level: `-O0` (the default) through `-O3`; `-O` alone is
    /// `-O2`. Without it, `$PEPPER_OPT_LEVEL` when set.
    #[arg(short = 'O', value_name = "LEVEL", value_parser = clap::value_parser!(u8).range(0..=3))]
    pub opt_level: Option<u8>,

    /// Link-time optimization: `full` optimizes the whole program as one
    /// module after linking every file's code, so calls between files (into
    /// the runtime, for one) inline; `off` optimizes each file alone. The
    /// default is `full` at `-O2` and `-O3`, and `off` below.
    #[arg(long = "lto", value_name = "MODE", value_parser = ["full", "off"])]
    pub lto: Option<String>,

    /// The platform to compile for, as an LLVM target triple
    /// (`aarch64-apple-darwin`, `x86_64-pc-windows-msvc`,
    /// `x86_64-unknown-linux-gnu`). The default is the machine the compiler
    /// runs on. `[Target(...)]` selects code for it, and linking another
    /// platform's executable needs its system libraries (`--sysroot`).
    #[arg(long = "target", value_name = "TRIPLE")]
    pub target: Option<String>,

    /// The directory holding the target's system headers and libraries,
    /// passed to the link driver. Without it, `$PEPPER_SYSROOT_<TRIPLE>`
    /// (the triple upper-cased, with `_` for `-`) when set.
    #[arg(long = "sysroot", value_name = "DIR")]
    pub sysroot: Option<PathBuf>,

    /// The CPU to generate code for, with clang's names and meanings:
    /// `-march=<cpu>` (x86: `x86-64-v3`, `native`), `-mcpu=<cpu>` (AArch64:
    /// `apple-m2`, `native`), `-march=<arch>` (AArch64: `armv8.2-a+crypto`),
    /// `-mtune=<cpu>`, and `-m<feature>` / `-mno-<feature>`. The default is
    /// clang's for the target (`x86-64`; `apple-m1` on Apple arm64).
    #[arg(short = 'm', value_name = "OPTION", allow_hyphen_values = true)]
    pub machine: Vec<String>,

    /// Remove kinds of runtime check from an optimized build, as a
    /// comma-separated list: `overflow` (integer overflow; arithmetic then
    /// wraps), `divide` (division by zero and `MIN / -1`; then undefined),
    /// `shift` (a count of at least the width; then masked), `bounds`
    /// (array and string indexing) and `null` (calls and matches through a
    /// null reference), or `all`. Removing `bounds` or `null` gives up
    /// memory safety. Ignored, with a warning, at `-O0`.
    #[arg(long = "no-runtime-checks", value_name = "CHECKS", value_parser = parse_runtime_checks)]
    pub no_runtime_checks: Option<pepper_codegen::checks::RuntimeChecks>,

    /// Build the entry file's tests: keep its `[Test]` functions, define
    /// the build option `TEST`, and replace its `main` with one that lists
    /// or runs them (`--list`, `--run NAME`). Given several files of one
    /// folder, builds the tests of them all into one program, each file
    /// keeping the scope it has in any program. `pep-test` builds with it.
    #[arg(long = "test", conflicts_with = "library")]
    pub test: bool,

    /// Emit LLVM IR (optimized at the `-O` level).
    #[arg(long = "emit-llvm")]
    pub emit_llvm: bool,

    /// Write the program's source with each `static` block replaced by the
    /// code it emits, like C's `cc -E`, into the folder `-o` names (default
    /// `<name>.static`) instead of compiling it. `--emit-static=keep` also
    /// keeps each block, as `#` comments above its expansion.
    #[arg(long = "emit-static", value_name = "MODE", num_args = 0..=1, require_equals = true, default_missing_value = "expand", value_parser = ["expand", "keep"])]
    pub emit_static: Option<String>,

    /// Emit debug info: DWARF on Linux and macOS, CodeView and a `.pdb` on
    /// Windows.
    #[arg(short = 'g', long = "emit-debug")]
    pub emit_debug: bool,

    /// With `-g`, where the debugger shows the code a `static` block emits:
    /// `source` (the default), the block as written, stopping on a loop's
    /// header once per pass; or `expanded`, a copy of each file with its
    /// blocks expanded as `--emit-static` writes them, saved beside the
    /// output as `<name>.static.pep`, stepping through the expanded
    /// statements. `expanded` builds without the build cache
    #[arg(long = "debug-static", value_name = "VIEW", requires = "emit_debug", value_parser = ["source", "expanded"])]
    pub debug_static: Option<String>,

    /// Keep the frame pointer in every function, even when optimizing, so
    /// profilers and stack walkers unwind the stack cheaply (clang's
    /// `-fno-omit-frame-pointer`). `pep-profile` builds with it.
    #[arg(long = "frame-pointers")]
    pub frame_pointers: bool,

    /// Accepted for compatibility; prints nothing more yet.
    #[arg(short = 'v', long = "verbose")]
    pub verbose: bool,

    /// Skip runtime discovery.
    #[arg(long = "no-runtime")]
    pub no_runtime: bool,

    /// Dump the parsed AST instead of compiling: as source-like text
    /// (`--emit-ast`, `--emit-ast=text`) or as JSON (`--emit-ast=json`).
    #[arg(long = "emit-ast", value_name = "FORMAT", num_args = 0..=1, require_equals = true, default_missing_value = "text", value_parser = ["text", "json"])]
    pub emit_ast: Option<String>,

    /// Load and link the program instead of compiling it, and print every
    /// file's syntax tree after linking, with the linking errors, as JSON.
    #[arg(long = "emit-linked")]
    pub emit_linked: bool,

    /// Load, link and check the program instead of compiling it, and print
    /// what the checks before sema report: the errors (linking, then
    /// `[__BuiltIn]` misuse, then visibility), then the warnings, rendered.
    #[arg(long = "emit-checked")]
    pub emit_checked: bool,

    /// Load, link, check and build the program's sema model instead of
    /// compiling it, and print the model before any sema pass, as JSON.
    #[arg(long = "emit-model")]
    pub emit_model: bool,

    /// Enable a trace channel (see `TRACE_CHANNELS`). `time` prints how long
    /// each compile stage took; `passes` prints how long each sema pass
    /// took, summed over its runs; `cache` prints whether each unit's object
    /// came from the build cache; any other name is accepted and ignored.
    #[arg(short = 'T', value_name = "CHAN")]
    pub trace: Vec<String>,

    /// Enable all trace channels.
    #[arg(long = "Tall")]
    pub trace_all: bool,

    /// Compile every unit without reading or writing the build cache.
    #[arg(long = "no-cache")]
    pub no_cache: bool,

    /// Build cache directory (default: `$PEPPER_CACHE_DIR`, else
    /// `$CWD/.pep/cache`).
    #[arg(long = "cache", value_name = "DIR")]
    pub cache_dir: Option<PathBuf>,

    /// Check the build cache: generate the code of every unit that hits
    /// anyway, and fail if it differs from the cached object's, or if
    /// skipping the hit units' bodies in sema changes another unit's code
    /// (also `PEPPER_CACHE_VERIFY=1`). For testing the compiler.
    #[arg(long = "verify-cache", conflicts_with = "no_verify_cache")]
    pub verify_cache: bool,

    /// Do not check the build cache, even with `PEPPER_CACHE_VERIFY` set.
    #[arg(long = "no-verify-cache")]
    pub no_verify_cache: bool,

    /// Use the MSVC linker. Not ported: always an error.
    #[arg(long = "MSVC")]
    pub msvc: bool,

    /// The project being built (the folder of its `pep.toml`) when no
    /// source file is given: its `.pep` holds the build and the cache.
    #[arg(skip)]
    pub project_dir: Option<PathBuf>,

    /// That project's package name, which names its output by default.
    #[arg(skip)]
    pub project_name: Option<String>,
}

/// The channels `-T` turns on (`--Tall` turns on all of them). The book's
/// tools/pep-build.md documents each, and `tool_docs_tests` checks it does.
pub const TRACE_CHANNELS: [&str; 3] = ["time", "passes", "cache"];

/// The environment variable naming `triple`'s system root:
/// `PEPPER_SYSROOT_AARCH64_APPLE_DARWIN` for `aarch64-apple-darwin`.
pub fn sysroot_variable(triple: &str) -> String {
    let name: String = triple.chars().map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' }).collect();
    format!("PEPPER_SYSROOT_{}", name)
}

/// One `-D` option: its name and value.
fn parse_build_option(text: &str) -> Result<(String, String), String> {
    pepper_sema::passes::platform::parse_build_option(text)
}

/// The checks `--no-runtime-checks=<list>` leaves on.
fn parse_runtime_checks(list: &str) -> Result<pepper_codegen::checks::RuntimeChecks, String> {
    pepper_codegen::checks::RuntimeChecks::without(list)
}

/// The command line with a bare `-O` spelled `-O2`, so `-O` may come
/// before a source file without taking it as its level.
pub fn normalize_args(args: impl IntoIterator<Item = std::ffi::OsString>) -> Vec<std::ffi::OsString> {
    args.into_iter().map(|arg| if arg == "-O" { "-O2".into() } else { arg }).collect()
}

impl Options {
    /// Apply the project's `pep.toml`. With no source file, the project is
    /// the nearest `pep.toml` at or above the current directory, and its
    /// `[build]` table names the entry file and (unless `-o`) the output.
    /// With one, it is the `pep.toml` above that file, if any. Either way,
    /// `[build]`'s `link` libraries are linked; its `include` folders join
    /// the search paths when the program loads.
    pub fn apply_project(&mut self) -> Result<(), String> {
        self.apply_project_in(&std::env::current_dir().unwrap_or_default())
    }

    /// [`Options::apply_project`], as if run in the folder `cwd`.
    pub fn apply_project_in(&mut self, cwd: &std::path::Path) -> Result<(), String> {
        use pepper_files::project::{MANIFEST_FILE, Manifest, ManifestFailure, find_manifest, find_project};
        let manifest_path = match self.source_files.first() {
            Some(file) => find_project(&cwd.join(file)).map(|dir| dir.join(MANIFEST_FILE)),
            None => {
                Some(find_manifest(cwd).ok_or_else(|| {
                    format!("no source files provided, and no {} in {} or a folder above it", MANIFEST_FILE, cwd.display())
                })?)
            }
        };
        let Some(manifest_path) = manifest_path else { return Ok(()) };
        let manifest = Manifest::read(&manifest_path).map_err(|failure| match failure {
            ManifestFailure::Unreadable(message) => message,
            ManifestFailure::Invalid { path, text, errors } => pepper_sema::program::render_manifest_errors(&path, &text, &errors),
        })?;
        if self.source_files.is_empty() {
            let entry = manifest.entry();
            if !entry.is_file() {
                return Err(format!(
                    "cannot find the project's entry file {}; set 'entry' in '[build]' of {}",
                    entry.display(),
                    manifest.path.display()
                ));
            }
            self.source_files.push(entry);
            if self.output.is_none() && self.library_kind().is_none() {
                let mut output = manifest.output();
                // A Windows executable needs its extension to run.
                if self.targets_windows() && output.extension().is_none() {
                    output.set_extension("exe");
                }
                self.output = Some(output);
            }
            self.project_dir = Some(manifest.dir().to_path_buf());
            self.project_name = Some(manifest.package.name.clone());
        }
        for library in &manifest.build.link {
            if !self.libraries.contains(library) {
                self.libraries.push(library.clone());
            }
        }
        Ok(())
    }

    /// Whether the program is built for Windows (an unsupported `--target`
    /// is reported later, when the build reads it).
    fn targets_windows(&self) -> bool {
        self.effective_target().map(|target| target.os == "windows").unwrap_or(cfg!(windows))
    }

    /// Where `.pep` goes: the project's folder when building a project,
    /// else the current directory.
    fn work_dir(&self) -> PathBuf {
        self.project_dir.clone().unwrap_or_else(|| std::env::current_dir().unwrap_or_default())
    }

    /// The optimization level: `-O`, else `$PEPPER_OPT_LEVEL`, else `-O0`.
    pub fn effective_opt_level(&self) -> Result<pepper_codegen::target::OptLevel, String> {
        match self.opt_level {
            Some(n) => pepper_codegen::target::OptLevel::from_number(n).ok_or_else(|| format!("invalid optimization level '-O{}'", n)),
            None => Ok(pepper_codegen::target::OptLevel::from_env()?.unwrap_or_default()),
        }
    }

    /// How units are compiled: the `-O` level, and link-time optimization
    /// (`--lto`, on by default at `-O2` and `-O3`; an error at `-O0`).
    pub fn effective_build(&self) -> Result<crate::cache::Build, String> {
        use pepper_codegen::target::OptLevel;
        let opt_level = self.effective_opt_level()?;
        let lto = match self.lto.as_deref() {
            Some("full") if opt_level == OptLevel::O0 => return Err("'--lto=full' needs optimization: add '-O'".to_string()),
            Some("full") => true,
            Some(_) => false,
            None => matches!(opt_level, OptLevel::O2 | OptLevel::O3),
        };
        let runtime_checks = self.effective_runtime_checks()?;
        Ok(crate::cache::Build {
            opt_level,
            lto,
            debug: self.emit_debug,
            frame_pointers: self.frame_pointers,
            cpu: self.effective_cpu()?,
            runtime_checks,
            build_options: self.effective_build_options(),
        })
    }

    /// The runtime checks the code performs: every one at `-O0`, else all
    /// but those `--no-runtime-checks` removes.
    pub fn effective_runtime_checks(&self) -> Result<pepper_codegen::checks::RuntimeChecks, String> {
        use pepper_codegen::target::OptLevel;
        match self.no_runtime_checks {
            Some(checks) if self.effective_opt_level()? != OptLevel::O0 => Ok(checks),
            _ => Ok(pepper_codegen::checks::RuntimeChecks::ALL),
        }
    }

    /// The warning `--no-runtime-checks` at `-O0` gets: debug builds keep
    /// every check.
    pub fn runtime_checks_warning(&self) -> Option<String> {
        let ignored = self.no_runtime_checks.is_some_and(|c| c != pepper_codegen::checks::RuntimeChecks::ALL)
            && self.effective_opt_level().is_ok_and(|level| level == pepper_codegen::target::OptLevel::O0);
        ignored.then(|| "warning: '--no-runtime-checks' has no effect at -O0".to_string())
    }

    /// The platform to compile for (`--target`'s, else the host), with the
    /// build options `-D` defines.
    pub fn effective_target(&self) -> Result<pepper_sema::Target, String> {
        let mut target = match &self.target {
            Some(triple) => pepper_sema::Target::parse(triple)?,
            None => pepper_sema::Target::host(),
        };
        target.build_options = self.effective_build_options();
        Ok(target)
    }

    /// The build options `-D` defines; of two that name one option, the
    /// later wins.
    /// `--test` defines `TEST`, unless `-D` gave it a value.
    pub fn effective_build_options(&self) -> pepper_sema::BuildOptions {
        let mut options: pepper_sema::BuildOptions = pepper_sema::BuildOptions::new();
        if self.test {
            options.insert(pepper_sema::passes::platform::TEST_BUILD_OPTION.to_string(), "1".to_string());
        }
        options.extend(self.build_options.iter().cloned());
        options
    }

    /// The modules `--import` loads into every file, and in a test build
    /// the runtime's `testing` module.
    pub fn effective_forced_imports(&self) -> Vec<String> {
        let mut imports = self.forced_imports.clone();
        if self.test && !imports.iter().any(|name| name == crate::test_main::TESTING_MODULE) {
            imports.push(crate::test_main::TESTING_MODULE.to_string());
        }
        imports
    }

    /// The CPU `-march`, `-mcpu`, `-mtune` and `-m<feature>` choose for the
    /// target triple, else clang's default for it.
    pub fn effective_cpu(&self) -> Result<pepper_codegen::target::Cpu, String> {
        let triple = pepper_sema::with_target(self.effective_target()?, pepper_codegen::target::triple_name);
        pepper_codegen::target::Cpu::from_options(&triple, &self.machine)
    }

    /// The target's system root: `--sysroot`, else
    /// `$PEPPER_SYSROOT_<TRIPLE>` for a `--target` triple.
    pub fn effective_sysroot(&self) -> Option<PathBuf> {
        if let Some(dir) = &self.sysroot {
            return Some(dir.clone());
        }
        // The canonical triple: `wasm32-wasi` reads PEPPER_SYSROOT_WASM32_WASIP1,
        // and `arm64-apple-ios17.0` PEPPER_SYSROOT_AARCH64_APPLE_IOS.
        let triple = self.effective_target().ok()?.platform_triple()?;
        std::env::var_os(sysroot_variable(&triple)).filter(|dir| !dir.is_empty()).map(PathBuf::from)
    }

    /// Port of `Options::defaults`: build dir = $CWD/.pep/build, forced
    /// imports = internals + range.
    pub fn effective_build_dir(&self) -> PathBuf {
        self.build_dir
            .clone()
            .unwrap_or_else(|| self.work_dir().join(".pep").join("build"))
    }

    /// The build cache directory, or `None` with `--no-cache`: `--cache`,
    /// else `$PEPPER_CACHE_DIR`, else `$CWD/.pep/cache`.
    pub fn effective_cache_dir(&self) -> Option<PathBuf> {
        // A cached unit's sema is skipped, so its expansions would not be
        // written for `--debug-static=expanded`.
        if self.no_cache || self.debug_static_expanded() {
            return None;
        }
        if let Some(dir) = &self.cache_dir {
            return Some(dir.clone());
        }
        if let Some(dir) = std::env::var_os("PEPPER_CACHE_DIR").filter(|d| !d.is_empty()) {
            return Some(PathBuf::from(dir));
        }
        Some(self.work_dir().join(".pep").join("cache"))
    }

    /// Whether cache hits are checked (`--verify-cache`, or
    /// `PEPPER_CACHE_VERIFY` set to anything but empty or `0`, unless
    /// `--no-verify-cache`).
    pub fn verifying_cache(&self) -> bool {
        self.verify_cache || !self.no_verify_cache && std::env::var_os("PEPPER_CACHE_VERIFY").is_some_and(|v| !v.is_empty() && v != "0")
    }

    /// Whether trace channel `channel` (`-T channel`, or `--Tall`) is on.
    pub fn tracing(&self, channel: &str) -> bool {
        debug_assert!(TRACE_CHANNELS.contains(&channel), "trace channel '{}' is missing from TRACE_CHANNELS", channel);
        self.trace_all || self.trace.iter().any(|c| c == channel)
    }

    /// The library `--lib` builds, if any.
    pub fn library_kind(&self) -> Option<crate::library::LibraryKind> {
        self.library.as_deref().and_then(crate::library::LibraryKind::parse)
    }

    /// Output path: `-o`, else $CWD/<primary source stem>, or with `--lib`
    /// the library's file name for that stem (`libmain.a`).
    /// `--debug-static=expanded`: the debugger steps through the expanded
    /// source of `static` blocks.
    pub fn debug_static_expanded(&self) -> bool {
        self.debug_static.as_deref() == Some("expanded")
    }

    pub fn output_path(&self) -> Result<PathBuf, String> {
        if let Some(out) = &self.output {
            return Ok(out.clone());
        }
        // A project's output is named after its package.
        let stem = match &self.project_name {
            Some(name) => std::ffi::OsString::from(name),
            None => {
                let primary = self.source_files.first().ok_or_else(|| "no source files".to_string())?;
                primary.file_stem().ok_or_else(|| format!("invalid source path {:?}", primary))?.to_os_string()
            }
        };
        let name = match self.library_kind() {
            Some(kind) => std::ffi::OsString::from(kind.file_name(&stem.to_string_lossy())),
            None => stem,
        };
        Ok(self.work_dir().join(name))
    }

    /// Main module name: output filename stem.
    pub fn module_name(&self) -> Result<String, String> {
        let out = self.output_path()?;
        Ok(out
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| "main".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pepper_codegen::target::OptLevel;

    fn parse(args: &[&str]) -> Options {
        Options::parse_from(normalize_args(args.iter().map(|a| std::ffi::OsString::from(*a))))
    }

    #[test]
    fn optimization_levels() {
        // A bare -O is -O2, and does not take the source file as its level.
        let options = parse(&["pepper", "-O", "main.pep"]);
        assert_eq!(options.source_files, [PathBuf::from("main.pep")]);
        assert_eq!(options.effective_opt_level(), Ok(OptLevel::O2));
        assert_eq!(parse(&["pepper", "main.pep", "-O3"]).effective_opt_level(), Ok(OptLevel::O3));
        assert_eq!(parse(&["pepper", "main.pep", "-O0"]).effective_opt_level(), Ok(OptLevel::O0));
        assert!(Options::try_parse_from(["pepper", "main.pep", "-O4"]).is_err());
    }

    #[test]
    fn build_options() {
        let options = parse(&["pepper", "-D", "FAST", "-DLEVEL=2", "-D", "PATH=a=b", "-D", "LEVEL=3", "main.pep"]);
        let expected: pepper_sema::BuildOptions =
            [("FAST", "1"), ("LEVEL", "3"), ("PATH", "a=b")].iter().map(|(n, v)| (n.to_string(), v.to_string())).collect();
        assert_eq!(options.effective_build_options(), expected);
        assert_eq!(options.effective_target().unwrap().build_options, expected);
        assert_ne!(options.effective_build().unwrap().name(), parse(&["pepper", "main.pep"]).effective_build().unwrap().name());
        let error = Options::try_parse_from(["pepper", "-D", "2FAST", "main.pep"]).unwrap_err().to_string();
        assert!(error.contains("invalid build option name '2FAST' in '-D 2FAST'"), "{error}");
    }

    #[test]
    fn a_project_built_for_windows_is_an_exe() {
        let dir = std::env::temp_dir().join(format!("pepper_options_exe_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("pep.toml"), "[package]\nname = \"demo\"\n").unwrap();
        std::fs::write(dir.join("main.pep"), "main(): int {\n    return 0;\n}\n").unwrap();
        let mut windows = parse(&["pepper", "--target", "x86_64-pc-windows-msvc"]);
        windows.apply_project_in(&dir).unwrap();
        assert_eq!(windows.output, Some(dir.join("demo.exe")));
        let mut linux = parse(&["pepper", "--target", "x86_64-unknown-linux-gnu"]);
        linux.apply_project_in(&dir).unwrap();
        assert_eq!(linux.output, Some(dir.join("demo")));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn targets() {
        assert_eq!(parse(&["pepper", "main.pep"]).effective_target(), Ok(pepper_sema::Target::host()));
        let target = parse(&["pepper", "--target", "arm64-apple-macosx14.0", "main.pep"]).effective_target().unwrap();
        assert_eq!((target.os.as_str(), target.arch.as_str()), ("macos", "aarch64"));
        assert_eq!(target.triple.as_deref(), Some("arm64-apple-macosx14.0"));
        let error = parse(&["pepper", "--target", "riscv64-unknown-linux-gnu", "main.pep"]).effective_target().unwrap_err();
        assert!(error.starts_with("unsupported target 'riscv64-unknown-linux-gnu'; expected one of: x86_64-unknown-linux-gnu"), "{error}");
        // `-m` options are checked against the target's architecture.
        let options = parse(&["pepper", "--target", "aarch64-unknown-linux-gnu", "-march=x86-64-v3", "main.pep"]);
        assert!(options.effective_cpu().unwrap_err().contains("invalid arch name"));
        let options = parse(&["pepper", "--target", "x86_64-pc-windows-msvc", "-mcpu=generic", "main.pep"]);
        assert!(options.effective_cpu().unwrap_err().contains("for target 'x86_64-pc-windows-msvc'"));
    }

    #[test]
    fn sysroot_variables() {
        assert_eq!(sysroot_variable("aarch64-apple-darwin"), "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN");
        assert_eq!(sysroot_variable("arm64-apple-macosx14.0"), "PEPPER_SYSROOT_ARM64_APPLE_MACOSX14_0");
        let options = parse(&["pepper", "--sysroot", "/sdk", "main.pep"]);
        assert_eq!(options.effective_sysroot(), Some(PathBuf::from("/sdk")));
    }
}

/// The library search directories in `$PEPPER_LIBRARY_PATH`, separated the
/// way `PATH` is (`:`, or `;` on Windows); empty entries are skipped.
pub fn environment_library_dirs() -> Vec<PathBuf> {
    std::env::var_os("PEPPER_LIBRARY_PATH")
        .map(|value| std::env::split_paths(&value).filter(|dir| !dir.as_os_str().is_empty()).collect())
        .unwrap_or_default()
}

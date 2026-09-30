//! CLI options: clap-derive port of `source/Compiler/Options.cpp:20-42`.

use clap::Parser;
use std::path::PathBuf;

#[derive(Debug, Parser)]
#[command(name = "pepper", version, about = "Pepper compiler")]
pub struct Options {
    /// Source files to compile (≥1).
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

    /// Output executable path.
    #[arg(short = 'o', value_name = "OUT")]
    pub output: Option<PathBuf>,

    /// Build directory.
    #[arg(long = "build", value_name = "DIR")]
    pub build_dir: Option<PathBuf>,

    /// Emit LLVM IR.
    #[arg(long = "emit-llvm")]
    pub emit_llvm: bool,

    /// Emit debug info (parsed; DI port deferred).
    #[arg(short = 'g', long = "emit-debug")]
    pub emit_debug: bool,

    /// Verbose output.
    #[arg(short = 'v', long = "verbose")]
    pub verbose: bool,

    /// Skip runtime discovery.
    #[arg(long = "no-runtime")]
    pub no_runtime: bool,

    /// Dump the parsed AST instead of compiling.
    #[arg(long = "emit-ast")]
    pub emit_ast: bool,

    /// Enable a trace channel. `time` prints how long each compile stage
    /// took; `cache` prints whether each unit's object came from the build
    /// cache; the others (codegen|ast|parser|ir|debuginfo|link) are accepted
    /// and ignored.
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

    /// Use the MSVC linker (not ported; errors on non-Windows).
    #[arg(long = "MSVC")]
    pub msvc: bool,
}

impl Options {
    /// Port of `Options::defaults`: build dir = $CWD/.pep/build, forced
    /// imports = internals + range.
    pub fn effective_build_dir(&self) -> PathBuf {
        self.build_dir
            .clone()
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_default().join(".pep").join("build"))
    }

    /// The build cache directory, or `None` with `--no-cache`: `--cache`,
    /// else `$PEPPER_CACHE_DIR`, else `$CWD/.pep/cache`.
    pub fn effective_cache_dir(&self) -> Option<PathBuf> {
        if self.no_cache {
            return None;
        }
        if let Some(dir) = &self.cache_dir {
            return Some(dir.clone());
        }
        if let Some(dir) = std::env::var_os("PEPPER_CACHE_DIR").filter(|d| !d.is_empty()) {
            return Some(PathBuf::from(dir));
        }
        Some(std::env::current_dir().unwrap_or_default().join(".pep").join("cache"))
    }

    /// Whether trace channel `channel` (`-T channel`, or `--Tall`) is on.
    pub fn tracing(&self, channel: &str) -> bool {
        self.trace_all || self.trace.iter().any(|c| c == channel)
    }

    /// Output path: `-o` or $CWD/<primary source stem>.
    pub fn output_path(&self) -> Result<PathBuf, String> {
        if let Some(out) = &self.output {
            return Ok(out.clone());
        }
        let primary = self
            .source_files
            .first()
            .ok_or_else(|| "no source files".to_string())?;
        let stem = primary
            .file_stem()
            .ok_or_else(|| format!("invalid source path {:?}", primary))?;
        Ok(std::env::current_dir()
            .unwrap_or_default()
            .join(stem))
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

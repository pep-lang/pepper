//! Host target registration and the machine everything emits for.
//!
//! LLVM will not resolve a triple until its backend is registered, and only
//! the backends you ask for are linked in: `inkwell`'s default `target-all`
//! feature wants initializers for every LLVM target, including ones a given
//! LLVM build omits, which fails at link time with unresolved
//! `LLVMInitialize<Target>*`. So each crate asks for exactly the backend its
//! host needs (see the arch-gated `inkwell` entries in Cargo.toml) and this
//! registers that one.
//!
//! Registering only x86 is what made the compiler unusable on Apple silicon:
//! the CLI failed on every input with
//!
//!   error: No available targets are compatible with triple
//!   "arm64-apple-darwin25.6.0"
//!
//! while the suite stayed green -- which is worth understanding, because the
//! suite does resolve the native triple: `CodeGenerator::instantiate_struct`
//! in lib.rs asks for a machine to measure struct ABI sizes with. What hid it
//! is that inkwell's execution-engine constructors call
//! `Target::initialize_native` (inkwell/src/module.rs), registering the host
//! backend process-wide, so whichever JIT test ran first masked the wrong
//! explicit registration for everything after it. Order-dependent masking,
//! not absence of resolution; the unit test below asks directly instead.
//!
//! This lives in one place because four call sites had their own copy, and
//! three of them would have had to be found again for any new architecture.

use inkwell::targets::{CodeModel, InitializationConfig, RelocMode, Target, TargetMachine};
use inkwell::OptimizationLevel;

/// Register the host's LLVM backend.
///
/// Safe to call repeatedly: `TargetRegistry::RegisterTarget` returns early
/// once a target of that name is registered, and the MC/TargetMachine
/// registrations re-assign the same function pointers. That is a
/// check-then-set rather than a `call_once`, so it is idempotent but does not
/// serialize two threads racing the very first call.
pub fn initialize_host() {
    let config = InitializationConfig::default();

    // `initialize_x86` / inkwell's `target-x86` is LLVM's X86 backend, which
    // serves x86-64 as well as i386 -- there is no separate "x86_64" target
    // to register. 32-bit output is never selected, because the triple is
    // always the host's, and a 32-bit *host* trips the compile_error below.
    #[cfg(target_arch = "x86_64")]
    Target::initialize_x86(&config);

    #[cfg(target_arch = "aarch64")]
    Target::initialize_aarch64(&config);

    // Silences "unused variable" on an architecture with no arm above, which
    // cannot happen while the compile_error below stands, but would be the
    // first thing to break when it is relaxed.
    let _ = &config;
}

#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
compile_error!(
    "pepper supports x86_64 and aarch64 hosts: add the matching \
     Target::initialize_* call in crates/pepper-codegen/src/target.rs and the \
     inkwell target-* feature in the arch-gated dependency tables"
);

/// How much LLVM optimizes the code it is given: `-O0` through `-O3`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Hash)]
pub enum OptLevel {
    /// No optimization (the default): only the dead-code removal that
    /// `partition::finish` runs.
    #[default]
    O0,
    O1,
    O2,
    O3,
}

impl OptLevel {
    /// The level `-O<n>` names, or `None` for a number above 3.
    pub fn from_number(n: u8) -> Option<OptLevel> {
        match n {
            0 => Some(OptLevel::O0),
            1 => Some(OptLevel::O1),
            2 => Some(OptLevel::O2),
            3 => Some(OptLevel::O3),
            _ => None,
        }
    }

    /// The `n` of `-O<n>`.
    pub fn number(self) -> u8 {
        self as u8
    }

    /// The level `PEPPER_OPT_LEVEL` names (`0` to `3`), when it is set and
    /// not empty: what the compiler uses without `-O`, and what every
    /// [`crate::CodeGenerator`] starts with, so the whole test suite can run
    /// optimized.
    pub fn from_env() -> Result<Option<OptLevel>, String> {
        let Some(value) = std::env::var_os("PEPPER_OPT_LEVEL").filter(|v| !v.is_empty()) else {
            return Ok(None);
        };
        let value = value.to_string_lossy();
        value
            .parse::<u8>()
            .ok()
            .and_then(OptLevel::from_number)
            .map(Some)
            .ok_or_else(|| format!("PEPPER_OPT_LEVEL is '{}'; expected 0, 1, 2 or 3", value))
    }

    /// The code generator's level for the machine.
    pub fn machine_level(self) -> OptimizationLevel {
        match self {
            OptLevel::O0 => OptimizationLevel::None,
            OptLevel::O1 => OptimizationLevel::Less,
            OptLevel::O2 => OptimizationLevel::Default,
            OptLevel::O3 => OptimizationLevel::Aggressive,
        }
    }

    /// LLVM's standard pipeline for the level (`default<O2>`, what clang
    /// runs at `-O2`), or `None` at `-O0`.
    pub fn pipeline(self) -> Option<&'static str> {
        match self {
            OptLevel::O0 => None,
            OptLevel::O1 => Some("default<O1>"),
            OptLevel::O2 => Some("default<O2>"),
            OptLevel::O3 => Some("default<O3>"),
        }
    }
}

/// Which of LLVM's pipelines for a level to run: the ordinary one, or the
/// two halves of link-time optimization (clang's `-flto`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pipeline {
    /// `default<On>`: a unit compiled to its object.
    Default,
    /// `lto-pre-link<On>`: a unit kept as bitcode for link-time optimization.
    PreLink,
    /// `lto<On>`: the whole program, once every unit is linked into it.
    Link,
}

/// The CPU to generate code for, and the features to add to or remove
/// from it: what clang's `-march`, `-mcpu`, `-mtune` and `-m<feature>`
/// choose. The default is clang's for the host triple.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Cpu {
    /// LLVM's name for the CPU (`x86-64`, `x86-64-v3`, `apple-m1`).
    pub name: String,
    /// Features to add or remove, as LLVM spells them (`+avx2,-sse4.2`);
    /// empty for the CPU's own.
    pub features: String,
    /// The CPU to schedule for, when it differs from [`Cpu::name`]
    /// (`generic`, as clang tunes on x86 without `-march`).
    pub tune: Option<String>,
}

impl Default for Cpu {
    /// Clang's default for the host triple.
    fn default() -> Cpu {
        let triple = TargetMachine::get_default_triple();
        Cpu::default_for(&triple.as_str().to_string_lossy())
    }
}

impl Cpu {
    /// Clang's default CPU for `triple`, from its driver
    /// (`clang/lib/Driver/ToolChains/Arch/{X86,AArch64}.cpp`): `x86-64`, or
    /// `penryn` on macOS, tuned for `generic` on x86; `apple-m1` on Apple
    /// arm64, else `generic` (Armv8-A).
    pub fn default_for(triple: &str) -> Cpu {
        let apple = triple.contains("-apple-");
        if is_x86(triple) {
            let name = if apple { "penryn" } else { "x86-64" };
            Cpu { name: name.to_string(), features: String::new(), tune: Some("generic".to_string()) }
        } else {
            let name = if apple { "apple-m1" } else { "generic" };
            Cpu { name: name.to_string(), features: String::new(), tune: None }
        }
    }

    /// The CPU clang's options choose for `triple`: each of `machine` is
    /// what follows `-m`, in order (`arch=x86-64-v3`, `cpu=native`,
    /// `tune=znver4`, `avx2`, `no-avx2`). As in clang:
    ///
    /// - On x86, `-march` names the CPU (`native` is the host's) and
    ///   `-mcpu` is not accepted. Without `-march`, the code is tuned for
    ///   `generic`.
    /// - On AArch64, `-mcpu` names the CPU and `-march` the architecture
    ///   (`armv8.2-a`), each with `+<extension>` or `+no<extension>` after
    ///   it.
    /// - `-mtune` names the CPU to schedule for; `native` is the host's.
    /// - `-m<feature>` adds an LLVM feature and `-mno-<feature>` removes
    ///   it, after the ones the CPU or architecture implies.
    ///
    /// The last of each option wins.
    pub fn from_options(triple: &str, machine: &[String]) -> Result<Cpu, String> {
        let mut cpu = Cpu::default_for(triple);
        let x86 = is_x86(triple);
        let host = || TargetMachine::get_host_cpu_name().to_string();
        let (mut arch, mut mcpu, mut tune) = (None, None, None);
        let mut extra = vec![];
        for option in machine {
            if let Some(value) = option.strip_prefix("arch=") {
                arch = Some(value);
            } else if let Some(value) = option.strip_prefix("cpu=") {
                if x86 {
                    return Err(format!("unsupported option '-mcpu=' for target '{}'; use '-march' or '-mtune'", triple));
                }
                mcpu = Some(value);
            } else if let Some(value) = option.strip_prefix("tune=") {
                tune = Some(value);
            } else if let Some(feature) = option.strip_prefix("no-") {
                extra.push(format!("-{}", feature));
            } else if !option.is_empty() && !option.contains('=') {
                extra.push(format!("+{}", option));
            } else {
                return Err(format!("unknown argument '-m{}'", option));
            }
        }
        let mut features: Vec<String> = vec![];
        let empty = |value: &str, option: &str| {
            if value.is_empty() {
                Err(format!("missing value for '-m{}='", option))
            } else {
                Ok(())
            }
        };
        if x86 {
            if let Some(arch) = arch {
                empty(arch, "arch")?;
                if arch == "native" {
                    cpu.name = host();
                    features.push(TargetMachine::get_host_cpu_features().to_string());
                    cpu.tune = Some(host());
                } else {
                    cpu.name = arch.to_string();
                    cpu.tune = None;
                }
            }
        } else {
            // `-mcpu` sets the CPU and `-march` the architecture; with both,
            // clang takes the CPU from `-mcpu` and the features from both.
            if let Some(arch) = arch {
                empty(arch, "arch")?;
                if arch == "native" {
                    cpu.name = host();
                    features.push(TargetMachine::get_host_cpu_features().to_string());
                } else {
                    let (base, extensions) = split_extensions(arch);
                    let version = base
                        .strip_prefix("armv")
                        .and_then(|v| v.strip_suffix("-a"))
                        .filter(|v| !v.is_empty())
                        .ok_or_else(|| format!("invalid arch name '-march={}'", arch))?;
                    cpu.name = "generic".to_string();
                    features.push(format!("+v{}a", version));
                    features.extend(extensions);
                }
            }
            if let Some(name) = mcpu {
                empty(name, "cpu")?;
                if name == "native" {
                    cpu.name = host();
                    features.push(TargetMachine::get_host_cpu_features().to_string());
                } else {
                    let (base, extensions) = split_extensions(name);
                    cpu.name = base.to_string();
                    features.extend(extensions);
                }
            }
        }
        if let Some(name) = tune {
            empty(name, "tune")?;
            cpu.tune = Some(if name == "native" { host() } else { name.to_string() });
        }
        features.extend(extra);
        cpu.features = features.into_iter().filter(|f| !f.is_empty()).collect::<Vec<_>>().join(",");
        Ok(cpu)
    }

    /// The CPU, features and tuning as one line, for the build cache's key
    /// and its directory name (`x86-64-v3+avx512f@generic`).
    pub fn key(&self) -> String {
        let mut key = self.name.clone();
        if !self.features.is_empty() {
            key.push_str(&self.features.replace(',', ""));
        }
        if let Some(tune) = &self.tune {
            key.push('@');
            key.push_str(tune);
        }
        key
    }

    /// Put the CPU, features and tuning on every function `module` defines,
    /// as clang does (`"target-cpu"`, `"target-features"`, `"tune-cpu"`), so
    /// code keeps its CPU when link-time optimization inlines it into
    /// another unit's.
    pub fn stamp(&self, module: &inkwell::module::Module<'_>) {
        use inkwell::attributes::AttributeLoc;
        let context = module.get_context();
        let mut attributes = vec![context.create_string_attribute("target-cpu", &self.name)];
        if !self.features.is_empty() {
            attributes.push(context.create_string_attribute("target-features", &self.features));
        }
        if let Some(tune) = &self.tune {
            attributes.push(context.create_string_attribute("tune-cpu", tune));
        }
        for function in module.get_functions().filter(|f| f.count_basic_blocks() > 0) {
            for attribute in &attributes {
                function.add_attribute(AttributeLoc::Function, *attribute);
            }
        }
    }
}

fn is_x86(triple: &str) -> bool {
    triple.starts_with("x86_64") || triple.starts_with("amd64")
}

/// `name+ext+noext` as `name` and the LLVM features `+ext`, `-ext`.
fn split_extensions(value: &str) -> (&str, Vec<String>) {
    let mut parts = value.split('+');
    let base = parts.next().unwrap_or_default();
    let extensions = parts
        .filter(|e| !e.is_empty())
        .map(|e| match e.strip_prefix("no") {
            Some(feature) => format!("-{}", feature),
            None => format!("+{}", e),
        })
        .collect();
    (base, extensions)
}

/// Run `level`'s pipeline over `module` (nothing at `-O0`).
pub fn optimize(module: &inkwell::module::Module<'_>, level: OptLevel) -> Result<(), String> {
    optimize_with(module, level, Pipeline::Default, &Cpu::default())
}

/// Run `level`'s `pipeline` over `module` (nothing at `-O0`), for `cpu`.
pub fn optimize_with(module: &inkwell::module::Module<'_>, level: OptLevel, pipeline: Pipeline, cpu: &Cpu) -> Result<(), String> {
    let Some(default) = level.pipeline() else {
        return Ok(());
    };
    let pipeline = match pipeline {
        Pipeline::Default => default.to_string(),
        Pipeline::PreLink => default.replace("default<", "lto-pre-link<"),
        Pipeline::Link => default.replace("default<", "lto<"),
    };
    let pipeline = pipeline.as_str();
    let machine = machine(level, cpu)?;
    module
        .run_passes(pipeline, &machine, inkwell::passes::PassBuilderOptions::create())
        .map_err(|e| format!("cannot optimize '{}': {}", module.get_name().to_string_lossy(), e.to_string()))
}

/// The machine to emit for, unoptimized: the host, with clang's default CPU.
pub fn host_machine() -> Result<TargetMachine, String> {
    host_machine_at(OptLevel::O0)
}

/// The machine to emit for at `level`: the host, with clang's default CPU.
pub fn host_machine_at(level: OptLevel) -> Result<TargetMachine, String> {
    machine(level, &Cpu::default())
}

/// The machine to emit for at `level`: the host triple, generating code for
/// `cpu`. Without `-march` or `-mcpu` that is clang's default for the
/// triple, never the build machine's own CPU, so a program runs on any
/// machine its triple names.
pub fn machine(level: OptLevel, cpu: &Cpu) -> Result<TargetMachine, String> {
    initialize_host();
    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).map_err(|e| e.to_string())?;
    target
        .create_target_machine(
            &triple,
            &cpu.name,
            &cpu.features,
            level.machine_level(),
            // PIC so the objects link into PIE executables. `Default` emits
            // non-relocatable code, which GNU ld rejects once clang links with
            // -pie (the Linux default): "relocation R_X86_64_32 ... can not be
            // used when making a PIE object". PIC is also what macOS requires
            // and a no-op on Windows.
            RelocMode::PIC,
            CodeModel::Default,
        )
        .ok_or_else(|| {
            format!(
                "LLVM has no target machine for {}",
                triple.as_str().to_string_lossy()
            )
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The host's own triple has to resolve to a machine. This is the
    /// assertion that fails when the wrong backend is registered -- the state
    /// in which the CLI cannot compile anything -- and it does not depend on
    /// some other test having created a JIT engine first, which is what used
    /// to mask it.
    #[test]
    fn the_host_triple_resolves_to_a_target_machine() {
        // The `expect` is the assertion: `Target::from_triple` fails here
        // unless this host's backend is registered.
        let _machine = host_machine().expect("host target machine");
        let triple = TargetMachine::get_default_triple();
        let triple = triple.as_str().to_string_lossy().to_string();

        // And the machine has to describe *this* architecture: a registration
        // for the wrong one would still produce a machine on a host whose
        // triple it happens to parse.
        let arch = triple.split('-').next().unwrap_or_default();
        let expected: &[&str] = if cfg!(target_arch = "x86_64") {
            &["x86_64", "amd64"]
        } else if cfg!(target_arch = "aarch64") {
            &["aarch64", "arm64"]
        } else {
            unreachable!("add this host's triple names alongside initialize_host")
        };
        assert!(
            expected.contains(&arch),
            "host triple {triple} does not name this architecture ({expected:?})"
        );
    }
}

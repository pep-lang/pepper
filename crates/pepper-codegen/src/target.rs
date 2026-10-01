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

/// Run `level`'s pipeline over `module` (nothing at `-O0`).
pub fn optimize(module: &inkwell::module::Module<'_>, level: OptLevel) -> Result<(), String> {
    optimize_with(module, level, Pipeline::Default)
}

/// Run `level`'s `pipeline` over `module` (nothing at `-O0`).
pub fn optimize_with(module: &inkwell::module::Module<'_>, level: OptLevel, pipeline: Pipeline) -> Result<(), String> {
    let Some(default) = level.pipeline() else {
        return Ok(());
    };
    let pipeline = match pipeline {
        Pipeline::Default => default.to_string(),
        Pipeline::PreLink => default.replace("default<", "lto-pre-link<"),
        Pipeline::Link => default.replace("default<", "lto<"),
    };
    let pipeline = pipeline.as_str();
    let machine = host_machine_at(level)?;
    module
        .run_passes(pipeline, &machine, inkwell::passes::PassBuilderOptions::create())
        .map_err(|e| format!("cannot optimize '{}': {}", module.get_name().to_string_lossy(), e.to_string()))
}

/// The machine to emit for, unoptimized: the host, CPU `generic`.
pub fn host_machine() -> Result<TargetMachine, String> {
    host_machine_at(OptLevel::O0)
}

/// The machine to emit for at `level`: the host, CPU `generic`.
///
/// `generic` is a port of `LLVMCodeGenerator.cpp:245-258` and is a valid CPU
/// name for both supported architectures; naming the host CPU instead would
/// bake the build machine's microarchitecture into the output.
pub fn host_machine_at(level: OptLevel) -> Result<TargetMachine, String> {
    initialize_host();
    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).map_err(|e| e.to_string())?;
    target
        .create_target_machine(
            &triple,
            "generic",
            "",
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

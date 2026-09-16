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

/// The machine to emit for: the host, CPU `generic`.
///
/// `generic` is a port of `LLVMCodeGenerator.cpp:245-258` and is a valid CPU
/// name for both supported architectures; naming the host CPU instead would
/// bake the build machine's microarchitecture into the output.
pub fn host_machine() -> Result<TargetMachine, String> {
    initialize_host();
    let triple = TargetMachine::get_default_triple();
    let target = Target::from_triple(&triple).map_err(|e| e.to_string())?;
    target
        .create_target_machine(
            &triple,
            "generic",
            "",
            OptimizationLevel::None,
            RelocMode::Default,
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

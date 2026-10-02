//! The facts codegen states for LLVM (`facts.rs`) and the target CPU options
//! (`-march`, `-mcpu`, `-mtune`, `-m<feature>`; INTERNALS.md §4.1).

use crate::support::{compile_jit_with_runtime, sema};
use clap::Parser;
use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::values::AnyValue;
use pepper_codegen::CodeGenerator;

const PROGRAM: &str = "struct Counter {\n    var hits: int;\n    construct() { this.hits = 0; }\n}\n\
bump(c: Counter, n: int): int {\n    var i = 0;\n    while (i < n) {\n        c.hits += 1;\n        i += 1;\n    }\n    return c.hits;\n}\n\
test(): int {\n    var c = Counter();\n    return bump(c, 5) - 5;\n}\n";

/// `PROGRAM`'s module with the runtime, as codegen leaves it.
fn generated(context: &inkwell::context::Context) -> CodeGenerator<'_> {
    let module = sema(PROGRAM).unwrap();
    let mut generator = CodeGenerator::new(context, "facts");
    generator.generate(&module).unwrap();
    generator
}

fn has(function: inkwell::values::FunctionValue<'_>, at: AttributeLoc, name: &str) -> bool {
    function.get_enum_attribute(at, Attribute::get_named_enum_kind_id(name)).is_some()
}

#[test]
fn functions_do_not_unwind_and_panics_do_not_return() {
    let context = inkwell::context::Context::create();
    let generator = generated(&context);
    let module = &generator.module;
    for function in module.get_functions().filter(|f| !f.get_name().to_string_lossy().starts_with("llvm.")) {
        let name = function.get_name().to_string_lossy();
        assert!(has(function, AttributeLoc::Function, "nounwind"), "'{}' may unwind", name);
        if function.count_basic_blocks() > 0 {
            assert!(has(function, AttributeLoc::Function, "uwtable"), "'{}' has no unwind table", name);
        }
    }
    let panic = module.get_function("_pep_panic").expect("_pep_panic");
    assert!(has(panic, AttributeLoc::Function, "noreturn") && has(panic, AttributeLoc::Function, "cold"));
    let malloc = module.get_function("_pep_malloc").expect("_pep_malloc");
    assert!(has(malloc, AttributeLoc::Return, "noalias"));
    assert!(!has(module.get_function("bump").expect("bump"), AttributeLoc::Function, "noreturn"));
}

#[test]
fn object_fields_and_counts_carry_distinct_tbaa_tags() {
    let context = inkwell::context::Context::create();
    let generator = generated(&context);
    let ir = generator.module.get_function("bump").expect("bump").print_to_string().to_string();
    let module = generator.module.print_to_string().to_string();
    // `c.hits += 1` loads and stores a field; the parameter's acquire and
    // release step `c`'s count.
    assert!(ir.contains("!tbaa"), "no tagged access in:\n{}", ir);
    assert!(module.contains("!\"reference counts\"") && module.contains("!\"fields\""), "no TBAA type nodes");
    // The facts change no behavior.
    assert_eq!(compile_jit_with_runtime(PROGRAM), 0);
}

/// The options `-m...` give for this host.
fn cpu(machine: &[&str]) -> Result<pepper_codegen::target::Cpu, String> {
    let mut args = vec!["pepper", "main.pep"];
    args.extend(machine);
    pepper_driver::Options::parse_from(args).effective_cpu()
}

#[test]
fn the_cpu_is_clangs_default_unless_an_option_names_one() {
    let default = cpu(&[]).unwrap();
    assert_eq!(default, pepper_codegen::target::Cpu::default());
    if cfg!(target_arch = "x86_64") {
        assert_eq!(default.tune.as_deref(), Some("generic"));
        let v3 = cpu(&["-march=x86-64-v3", "-mno-avx2", "-mtune=znver4"]).unwrap();
        assert_eq!((v3.name.as_str(), v3.features.as_str(), v3.tune.as_deref()), ("x86-64-v3", "-avx2", Some("znver4")));
        let error = cpu(&["-mcpu=skylake"]).unwrap_err();
        assert!(error.starts_with("unsupported option '-mcpu='"), "{}", error);
    } else {
        let m2 = cpu(&["-mcpu=apple-m2+nocrypto"]).unwrap();
        assert_eq!((m2.name.as_str(), m2.features.as_str()), ("apple-m2", "-crypto"));
        let arch = cpu(&["-march=armv8.2-a+crypto"]).unwrap();
        assert_eq!((arch.name.as_str(), arch.features.as_str()), ("generic", "+v8.2a,+crypto"));
    }
    let native = cpu(&["-march=native"]).unwrap_or_else(|_| cpu(&["-mcpu=native"]).unwrap());
    assert_eq!(native.name, inkwell::targets::TargetMachine::get_host_cpu_name().to_string());
}

#[test]
fn every_function_carries_the_cpu() {
    let context = inkwell::context::Context::create();
    let generator = generated(&context);
    let chosen = if cfg!(target_arch = "x86_64") { cpu(&["-march=x86-64-v2", "-mpopcnt"]) } else { cpu(&["-mcpu=apple-m2"]) };
    let chosen = chosen.unwrap();
    chosen.stamp(&generator.module);
    let bump = generator.module.get_function("bump").expect("bump");
    let attribute = |key: &str| bump.get_string_attribute(AttributeLoc::Function, key).map(|a| a.get_string_value().to_string_lossy().into_owned());
    assert_eq!(attribute("target-cpu").as_deref(), Some(chosen.name.as_str()));
    assert_eq!(attribute("tune-cpu"), chosen.tune);
    if !chosen.features.is_empty() {
        assert_eq!(attribute("target-features").as_deref(), Some(chosen.features.as_str()));
    }
}

/// The C library's `memcpy`, `memmove` and `memset` lower to LLVM's
/// intrinsics, so a constant-size copy optimizes to loads and stores
/// rather than a call (#340).
#[test]
fn memory_externs_inline_at_o2() {
    let source = "extern void memcpy(void* destination, void* source, ulong size);\n\
extern void memmove(void* destination, void* source, ulong size);\n\
extern void memset(void* pointer, int value, ulong size);\n\
export copy_one(a: __ptr<u8>, b: __ptr<u8>) { memcpy(a, b, sizeof<long>()); }\n\
export move_one(a: __ptr<u8>, b: __ptr<u8>) { memmove(a, b, 4); }\n\
export fill_one(a: __ptr<u8>) { memset(a, 7, 2); }\n\
test(): int { return 0; }\n";
    let module = sema(source).unwrap();
    let context = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&context, "memory");
    generator.generate(&module).unwrap();
    pepper_codegen::target::optimize(&generator.module, pepper_codegen::target::OptLevel::O2).unwrap();
    for name in ["copy_one", "move_one", "fill_one"] {
        let function = generator.module.get_function(name).unwrap_or_else(|| panic!("no '{}'", name));
        let ir = function.print_to_string().to_string();
        assert!(!ir.contains("call "), "'{}' still calls out:\n{}", name, ir);
        assert!(ir.contains("store "), "'{}' stores nothing:\n{}", name, ir);
    }
}

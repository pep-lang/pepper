## The LLVM backends and triple code is generated for: the host's, or the
## target `--target` names. pepper-llvm's `TargetMachine.create` finds each
## backend's `LLVMInitialize*` functions by name, which a pep-build that
## links LLVM statically does not export: these calls link in every backend
## `--target` can name (x86, AArch64 and WebAssembly), with their assembly
## parsers, which inline assembly needs.

import [Target] from compiler.link;
import llvm;

extern void LLVMInitializeX86TargetInfo();
extern void LLVMInitializeX86Target();
extern void LLVMInitializeX86TargetMC();
extern void LLVMInitializeX86AsmPrinter();
extern void LLVMInitializeX86AsmParser();
extern void LLVMInitializeAArch64TargetInfo();
extern void LLVMInitializeAArch64Target();
extern void LLVMInitializeAArch64TargetMC();
extern void LLVMInitializeAArch64AsmPrinter();
extern void LLVMInitializeAArch64AsmParser();
extern void LLVMInitializeWebAssemblyTargetInfo();
extern void LLVMInitializeWebAssemblyTarget();
extern void LLVMInitializeWebAssemblyTargetMC();
extern void LLVMInitializeWebAssemblyAsmPrinter();
extern void LLVMInitializeWebAssemblyAsmParser();

## Registers every backend `--target` can name, with its assembly parser.
## Calling it again does nothing.
export initialize_backends() {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
    LLVMInitializeX86AsmPrinter();
    LLVMInitializeX86AsmParser();
    LLVMInitializeAArch64TargetInfo();
    LLVMInitializeAArch64Target();
    LLVMInitializeAArch64TargetMC();
    LLVMInitializeAArch64AsmPrinter();
    LLVMInitializeAArch64AsmParser();
    LLVMInitializeWebAssemblyTargetInfo();
    LLVMInitializeWebAssemblyTarget();
    LLVMInitializeWebAssemblyTargetMC();
    LLVMInitializeWebAssemblyAsmPrinter();
    LLVMInitializeWebAssemblyAsmParser();
}

## The triple code is generated for: `target`'s, else the host's own
## (LLVM's default triple).
##
## @param target the compile target
## @returns the triple
export target_triple(target: Target): String {
    return target.triple.is_empty ? llvm.default_triple() : target.triple;
}

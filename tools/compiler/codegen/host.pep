## The host's LLVM backend, registered by direct calls. pepper-llvm's
## `TargetMachine.create` finds each backend's `LLVMInitialize*` functions
## by name, which a pep-build that links LLVM statically does not export:
## these calls link the host's in and register them, the assembly parser
## included, which inline assembly needs.

import llvm;

[Target(Arch(x64))]
extern void LLVMInitializeX86AsmParser();

[Target(Arch(aarch64))]
extern void LLVMInitializeAArch64AsmParser();

[Target(Arch(x64))]
_initialize_asm_parser() {
    LLVMInitializeX86AsmParser();
}

[Target(Arch(aarch64))]
_initialize_asm_parser() {
    LLVMInitializeAArch64AsmParser();
}

## Registers the host's backend and its assembly parser. Calling it again
## does nothing.
export initialize_host_backend() {
    llvm.initialize_native_target();
    _initialize_asm_parser();
}

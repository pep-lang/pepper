//! The context-switch intrinsics behind the `async` runtime's fibers on
//! Linux and macOS (Windows uses the Fibers API instead).
//!
//! The runtime declares them as externs:
//!
//! ```text
//! extern void __switch_context(void* save, void* resume);
//! extern void* __prepare_context(void* stack_top, void* entry);
//! ```
//!
//! and the code generator defines each one it finds declared as a naked
//! function whose body is one block of assembly for the target: the callee-
//! saved registers go on the current stack, the stack pointer into `*save`,
//! and the other context's registers come off the stack `resume` points at.
//! `__prepare_context` lays out a fresh stack so that the first switch to
//! it "returns" into a trampoline that calls `entry(null)`; `entry` must
//! never return (the runtime switches away at the end of a task instead).
//! The definitions have no owner, so each unit that uses them defines them
//! and `partition::finish` makes them `linkonce_odr`.

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::values::FunctionValue;

/// The declared name of the switch intrinsic.
pub const SWITCH_CONTEXT: &str = "__switch_context";
/// The declared name of the stack-preparing intrinsic.
pub const PREPARE_CONTEXT: &str = "__prepare_context";

/// x86-64 System V: rbx, rbp, r12-r15, and the SSE and x87 control words.
/// `save` is in rdi, `resume` in rsi.
const X86_64_SWITCH: &str = "
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $$8, %rsp
    stmxcsr (%rsp)
    fnstcw 4(%rsp)
    movq %rsp, (%rdi)
    movq %rsi, %rsp
    ldmxcsr (%rsp)
    fldcw 4(%rsp)
    addq $$8, %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    retq
";

/// Lays out the frame `X86_64_SWITCH` pops below the 16-byte aligned
/// `stack_top` (rdi): control words, six registers with `entry` (rsi) in
/// r12, and the trampoline as the return address. The trampoline then
/// runs with rsp 16-byte aligned, as a call requires.
const X86_64_PREPARE: &str = "
    movq %rdi, %rax
    andq $$-16, %rax
    subq $$80, %rax
    movl $$0x1F80, (%rax)
    movw $$0x037F, 4(%rax)
    movq $$0, 8(%rax)
    movq $$0, 16(%rax)
    movq $$0, 24(%rax)
    movq %rsi, 32(%rax)
    movq $$0, 40(%rax)
    movq $$0, 48(%rax)
    leaq 1f(%rip), %rcx
    movq %rcx, 56(%rax)
    retq
1:
    xorl %edi, %edi
    callq *%r12
    ud2
";

/// AArch64 (Linux and Apple): x19-x28, the frame pointer and link register,
/// and d8-d15, in a 176-byte frame. `save` is in x0, `resume` in x1.
const AARCH64_SWITCH: &str = "
    sub sp, sp, #176
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    stp d8, d9, [sp, #96]
    stp d10, d11, [sp, #112]
    stp d12, d13, [sp, #128]
    stp d14, d15, [sp, #144]
    mov x9, sp
    str x9, [x0]
    mov sp, x1
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    ldp d8, d9, [sp, #96]
    ldp d10, d11, [sp, #112]
    ldp d12, d13, [sp, #128]
    ldp d14, d15, [sp, #144]
    add sp, sp, #176
    ret
";

/// Lays out the frame `AARCH64_SWITCH` loads below the 16-byte aligned
/// `stack_top` (x0): `entry` (x1) in x19, a zero frame pointer, and the
/// trampoline in the link register.
const AARCH64_PREPARE: &str = "
    and x9, x0, #0xfffffffffffffff0
    sub x9, x9, #176
    str x1, [x9, #0]
    str xzr, [x9, #80]
    adr x10, 1f
    str x10, [x9, #88]
    mov x0, x9
    ret
1:
    mov x0, xzr
    blr x19
    brk #0
";

impl<'ctx> crate::CodeGenerator<'ctx> {
    /// Define each context intrinsic the module declares (see the module
    /// documentation), for the architecture sema compiled for.
    pub(crate) fn define_context_intrinsics(&mut self) -> Result<(), String> {
        for name in [SWITCH_CONTEXT, PREPARE_CONTEXT] {
            let Some(function) = self.module.get_function(name) else {
                continue;
            };
            if function.count_basic_blocks() != 0 {
                continue;
            }
            let assembly = match (
                pepper_sema::passes::platform::target_os().as_str(),
                pepper_sema::passes::platform::target_arch().as_str(),
                name,
            ) {
                ("windows", _, _) => {
                    return Err(format!(
                        "'{name}' is not available on Windows; fibers there use the Fibers API"
                    ));
                }
                (_, "x86_64", SWITCH_CONTEXT) => X86_64_SWITCH,
                (_, "x86_64", _) => X86_64_PREPARE,
                (_, "aarch64", SWITCH_CONTEXT) => AARCH64_SWITCH,
                (_, "aarch64", _) => AARCH64_PREPARE,
                (_, arch, _) => return Err(format!("'{name}' is not available on {arch}")),
            };
            self.define_naked(function, assembly)?;
        }
        Ok(())
    }

    /// Give a declared function a naked body: `assembly` and nothing else.
    fn define_naked(
        &mut self,
        function: FunctionValue<'ctx>,
        assembly: &str,
    ) -> Result<(), String> {
        for attribute in ["naked", "noinline", "nounwind"] {
            let kind = Attribute::get_named_enum_kind_id(attribute);
            function.add_attribute(
                AttributeLoc::Function,
                self.context.create_enum_attribute(kind, 0),
            );
        }
        let saved = self.builder.get_insert_block();
        let entry = self.context.append_basic_block(function, "entry");
        self.builder.position_at_end(entry);
        let asm_type = self.context.void_type().fn_type(&[], false);
        let asm = self.context.create_inline_asm(
            asm_type,
            assembly.to_string(),
            String::new(),
            true,
            false,
            None,
            false,
        );
        self.builder
            .build_indirect_call(asm_type, asm, &[], "")
            .map_err(|e| e.to_string())?;
        self.builder
            .build_unreachable()
            .map_err(|e| e.to_string())?;
        if let Some(block) = saved {
            self.builder.position_at_end(block);
        }
        Ok(())
    }
}

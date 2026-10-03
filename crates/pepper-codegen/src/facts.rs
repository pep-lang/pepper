//! Facts the language guarantees, stated in the IR for LLVM's optimizer
//! (#262). [`annotate`] runs over every generated module, before it is
//! optimized:
//!
//! - **`nounwind`** on every function: Pepper has no exceptions, and a C
//!   function it calls unwinding through Pepper code is undefined, as it is
//!   for C code clang compiles. Definitions also get `uwtable`, as clang
//!   gives them, so debuggers and profilers can still walk the stack.
//!   On Apple targets they also keep the frame pointer
//!   (`"frame-pointer"="non-leaf"`), as clang does there: macOS's
//!   `backtrace` and its profilers walk the stack by frame pointers alone.
//! - **`noreturn` and `cold`** on the functions that end the program
//!   ([`NO_RETURN`]), so LLVM moves failure paths out of hot code.
//! - **`noalias`** on the result of the allocators ([`ALLOCATORS`]), so a
//!   fresh object's fields stay in registers across stores to others.
//! - **TBAA** (`!tbaa`) on loads and stores of object memory: the reference
//!   counts in an object's head and its fields never alias, so a count step
//!   does not make LLVM reload fields, and a field store does not make it
//!   reload counts. See [`tbaa`].
//!
//! Left out on purpose: `nonnull` (a struct reference may be null),
//! `dereferenceable` (an object can be freed during a call that received
//! it, as with `std::shared_ptr`), `noalias` parameters (two parameters may
//! refer to one object), and `nsw`/`nuw` (checked arithmetic goes through
//! `llvm.*.with.overflow`, see [`crate::checks`], and arithmetic built with
//! `--no-runtime-checks=overflow` wraps). LLVM infers `memory(...)`, `willreturn` and `nocapture`
//! itself, across the whole program with link-time optimization.

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::module::Module;
use inkwell::values::{AsValueRef, BasicValue, FunctionValue, InstructionOpcode, InstructionValue};

/// Functions that never return: the runtime's panic and exit paths and the
/// C functions under them.
pub const NO_RETURN: &[&str] = &["_pep_panic", "_pep_exit", "abort", "_Exit"];

/// Functions that return memory nothing else points to.
pub const ALLOCATORS: &[&str] = &["_pep_malloc", "_pep_realloc"];

/// State the facts in `module`.
pub fn annotate(module: &Module<'_>) {
    let context = module.get_context();
    let attribute = |name: &str, value: u64| context.create_enum_attribute(Attribute::get_named_enum_kind_id(name), value);
    let nounwind = attribute("nounwind", 0);
    // `uwtable(async)`, clang's default on every target Pepper supports.
    let uwtable = attribute("uwtable", 2);
    let noreturn = attribute("noreturn", 0);
    let cold = attribute("cold", 0);
    let noalias = attribute("noalias", 0);
    let frame_pointer = module
        .get_triple()
        .as_str()
        .to_str()
        .is_ok_and(|triple| triple.contains("-apple-"))
        .then(|| context.create_string_attribute("frame-pointer", "non-leaf"));
    let tags = tbaa::Tags::new(module);
    for function in module.get_functions() {
        let name = function.get_name().to_string_lossy();
        if name.starts_with("llvm.") {
            continue;
        }
        function.add_attribute(AttributeLoc::Function, nounwind);
        if NO_RETURN.contains(&name.as_ref()) {
            function.add_attribute(AttributeLoc::Function, noreturn);
            function.add_attribute(AttributeLoc::Function, cold);
        }
        if ALLOCATORS.contains(&name.as_ref()) && function.get_type().get_return_type().is_some_and(|t| t.is_pointer_type()) {
            function.add_attribute(AttributeLoc::Return, noalias);
        }
        if function.count_basic_blocks() > 0 {
            function.add_attribute(AttributeLoc::Function, uwtable);
            if let Some(frame_pointer) = frame_pointer {
                function.add_attribute(AttributeLoc::Function, frame_pointer);
            }
            tags.annotate(function);
        }
    }
}

/// Type-based alias analysis for object memory.
///
/// Every struct object starts with its head, `__refcount` and `__weakcount`
/// (fields 0 and 1, bytes 0 to 8), and its fields follow, so within any
/// object the head and the fields occupy different bytes. Each load and
/// store that addresses one or the other gets that access's tag: a field of
/// a struct object (`getelementptr %S, ptr %p, i32 0, i32 <field>`), or a
/// count in the head (codegen's `head_count` address). Two tagged accesses
/// with different tags never alias. Everything else (locals, buffers, raw
/// pointers, `memcpy`) stays untagged, and so may alias anything.
///
/// The tree is coarse on purpose: tagging fields by their own type would
/// tell LLVM more, but `__ptr` code may reach the same bytes as two types.
pub mod tbaa {
    use super::*;
    use inkwell::values::MetadataValue;

    /// The two access tags, and the kind id of `!tbaa`.
    pub struct Tags<'ctx> {
        kind: u32,
        head: MetadataValue<'ctx>,
        field: MetadataValue<'ctx>,
    }

    impl<'ctx> Tags<'ctx> {
        pub fn new(module: &Module<'ctx>) -> Tags<'ctx> {
            let context = module.get_context();
            let i64_type = context.i64_type();
            let zero = i64_type.const_zero();
            let root = context.metadata_node(&[context.metadata_string("Pepper TBAA").into()]);
            let scalar = |name: &str| context.metadata_node(&[context.metadata_string(name).into(), root.into(), zero.into()]);
            let access = |ty: MetadataValue<'ctx>| context.metadata_node(&[ty.into(), ty.into(), zero.into()]);
            Tags {
                kind: context.get_kind_id("tbaa"),
                head: access(scalar("reference counts")),
                field: access(scalar("fields")),
            }
        }

        /// Tag the loads and stores of `function` that address object memory.
        pub fn annotate(&self, function: FunctionValue<'ctx>) {
            for block in function.get_basic_blocks() {
                let mut next = block.get_first_instruction();
                while let Some(instruction) = next {
                    next = instruction.get_next_instruction();
                    let address = match instruction.get_opcode() {
                        InstructionOpcode::Load => instruction.get_operand(0),
                        InstructionOpcode::Store => instruction.get_operand(1),
                        _ => continue,
                    };
                    let Some(address) = address.and_then(|a| a.value()) else { continue };
                    let Some(gep) = address.as_instruction_value() else { continue };
                    let tag = match object_part(gep) {
                        Some(Part::Head) => self.head,
                        Some(Part::Field) => self.field,
                        None => continue,
                    };
                    let _ = instruction.set_metadata(tag, self.kind);
                }
            }
        }
    }

    pub(crate) enum Part {
        Head,
        Field,
    }

    /// Which part of an object `address` (an instruction) points into, when
    /// it is a field address of a struct object or a head count address.
    pub(crate) fn object_part(address: InstructionValue<'_>) -> Option<Part> {
        if address.get_opcode() != InstructionOpcode::GetElementPtr {
            return None;
        }
        let name = address.get_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if name.starts_with(crate::HEAD_COUNT_NAME) {
            return Some(Part::Head);
        }
        // SAFETY: `address` is a GEP instruction, which has a source type.
        let source = unsafe { inkwell::llvm_sys::core::LLVMGetGEPSourceElementType(address.as_value_ref()) };
        let source = unsafe { inkwell::types::AnyTypeEnum::new(source) };
        let inkwell::types::AnyTypeEnum::StructType(source) = source else { return None };
        if source.get_name().is_none() || address.get_num_operands() < 3 {
            return None;
        }
        let constant = |index: u32| {
            address
                .get_operand(index)
                .and_then(|o| o.value())
                .and_then(|o| match o {
                    inkwell::values::BasicValueEnum::IntValue(i) => i.get_zero_extended_constant(),
                    _ => None,
                })
        };
        if constant(1)? != 0 {
            return None;
        }
        Some(if constant(2)? < 2 { Part::Head } else { Part::Field })
    }
}

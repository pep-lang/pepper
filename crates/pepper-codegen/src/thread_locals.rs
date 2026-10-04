//! `[ThreadLocal]` module-scope variables (#625).
//!
//! A thread-local is an LLVM `thread_local` global in the initial-exec
//! model: on x86-64 Linux a read is one load at an offset from `%fs` (the
//! linker relaxes initial-exec to local-exec in an executable), on arm64
//! from `tpidr_el0`; macOS reaches it through its TLV descriptor and
//! Windows through `_tls_index` and the thread's TLS array. Each thread's
//! copy starts from the global's initializer, so sema requires a constant
//! (`check_shared_types::thread_local_constant`).
//!
//! **Release at thread exit.** A thread-local that holds references (a
//! `[Shared]` struct, a `shared` function value, a tuple of them) must drop
//! them when its thread ends. The program module defines
//! `_pep_release_thread_locals`, which stores the default into each such
//! thread-local, last declared first, and releases what it held; a
//! destructor that stores into a thread-local again is caught by the next
//! of [`RELEASE_PASSES`] passes. The runtime declares it `extern` and
//! `async`'s thread entry point calls it after the thread's body, before the
//! thread exits. It is not an operating-system destructor (a pthread key or
//! `__cxa_thread_atexit`): those outlive a JIT engine, and a test thread that
//! exits after its engine is dropped would call into freed code. So the main
//! thread's values are never released, like every other module-scope
//! variable, and a thread started by C code leaks its values.
//!
//! **JIT.** MCJIT relocates ELF TLS on x86-64 Linux, so the JIT uses real
//! thread-locals there. Elsewhere (MachO TLV, COFF TLS, AArch64 ELF) it
//! cannot, so the JIT emulates them, as LLVM's `-emulated-tls` does: the
//! global becomes the image a thread's copy starts from, and every access
//! calls the host's [`jit_thread_local`] with the image's address and size
//! and a number unique to the module (an image of a dropped engine's module
//! may share an address with a later one's), which returns the calling
//! thread's copy (made from the image on its first access). `jit_emulates_thread_locals` turns this on for any host, so
//! tests run it on Linux too.

use crate::address::Address;
use crate::CodeGenerator;
use inkwell::types::BasicTypeEnum;
use inkwell::values::{BasicValueEnum, GlobalValue};
use pepper_sema::model::VariableDef;
use pepper_sema::passes::check_shared_types::{thread_local_constant, ThreadLocalConstant};

/// The function the program defines to release the calling thread's
/// thread-locals; `runtime/async/thread.pep` declares it `extern`.
pub const RELEASE_FUNCTION: &str = "_pep_release_thread_locals";

/// The host function an emulated thread-local's accesses call (see
/// [`jit_thread_local`]).
pub const JIT_ADDRESS_FUNCTION: &str = "__pep_jit_thread_local";

/// How many times `_pep_release_thread_locals` walks the thread-locals: a
/// destructor run by one pass may store into a thread-local again, as
/// POSIX's `PTHREAD_DESTRUCTOR_ITERATIONS` allows for keys.
const RELEASE_PASSES: usize = 4;

/// Whether the JIT emulates thread-locals unless told otherwise: everywhere
/// MCJIT cannot relocate TLS.
pub const JIT_EMULATES_BY_DEFAULT: bool = !cfg!(all(target_os = "linux", target_arch = "x86_64"));

impl<'ctx> CodeGenerator<'ctx> {
    /// Make `global`, just added for `var`, a thread-local: a `thread_local`
    /// global, or under emulation the image a thread's copy starts from,
    /// with `var`'s constant initializer.
    pub(crate) fn declare_thread_local(&mut self, var: &VariableDef, global: GlobalValue<'ctx>, llvm_ty: BasicTypeEnum<'ctx>) -> Result<(), String> {
        if self.emulate_thread_locals {
            self.emulated_thread_locals.insert(var.name.clone());
        } else {
            global.set_thread_local_mode(Some(inkwell::ThreadLocalMode::InitialExecTLSModel));
        }
        let Some(default) = &var.default else { return Ok(()) };
        let constant = thread_local_constant(default).ok_or_else(|| format!("thread-local variable '{}' must start from a constant", var.name))?;
        match (constant, llvm_ty) {
            (ThreadLocalConstant::Int(v), BasicTypeEnum::IntType(it)) => global.set_initializer(&it.const_int(v as u64, true)),
            (ThreadLocalConstant::Float(v), BasicTypeEnum::FloatType(ft)) => global.set_initializer(&ft.const_float(v)),
            (ThreadLocalConstant::Int(v), BasicTypeEnum::FloatType(ft)) => global.set_initializer(&ft.const_float(v as f64)),
            // Null: the zero initializer the caller already set.
            (ThreadLocalConstant::Null, _) => {}
            _ => return Err(format!("thread-local variable '{}' cannot start from this constant", var.name)),
        }
        Ok(())
    }

    /// The address of global `id` for the code being generated: its
    /// `global_addrs` entry, or for an emulated thread-local the calling
    /// thread's copy, from a call at the builder's position.
    pub(crate) fn global_address(&mut self, id: &str) -> Result<Option<Address<'ctx>>, String> {
        let Some(addr) = self.global_addrs.get(id).cloned() else { return Ok(None) };
        if !self.emulated_thread_locals.contains(id) {
            return Ok(Some(addr));
        }
        let llvm_ty = addr.llvm_ty.ok_or_else(|| format!("thread-local '{}' has no type", id))?;
        let ptr = self.context.ptr_type(inkwell::AddressSpace::default());
        let i64_type = self.context.i64_type();
        let function = match self.module.get_function(JIT_ADDRESS_FUNCTION) {
            Some(function) => function,
            None => self.module.add_function(JIT_ADDRESS_FUNCTION, ptr.fn_type(&[ptr.into(), i64_type.into(), i64_type.into()], false), None),
        };
        let size = inkwell::types::BasicType::size_of(&llvm_ty).ok_or_else(|| format!("thread-local '{}' has no size", id))?;
        let module_id = *self.jit_module_id.get_or_insert_with(|| NEXT_MODULE_ID.fetch_add(1, std::sync::atomic::Ordering::Relaxed));
        let call = self
            .builder
            .build_call(function, &[addr.ptr.into(), size.into(), i64_type.const_int(module_id, false).into()], id)
            .map_err(|e| e.to_string())?;
        let copy = call.try_as_basic_value().basic().ok_or_else(|| "thread-local address".to_string())?.into_pointer_value();
        Ok(Some(Address { ptr: copy, ..addr }))
    }

    /// Define `_pep_release_thread_locals` in the program (a cached unit
    /// only declares it, through the runtime's `extern`), releasing every
    /// thread-local of `module` that holds references.
    pub(crate) fn emit_thread_locals_release(&mut self, module: &pepper_sema::model::Module) -> Result<(), String> {
        if self.unit.as_ref().is_some_and(|filter| filter.unit.is_some()) {
            return Ok(());
        }
        let void_fn = self.context.void_type().fn_type(&[], false);
        let function = match self.module.get_function(RELEASE_FUNCTION) {
            Some(function) => function,
            None => self.module.add_function(RELEASE_FUNCTION, void_fn, None),
        };
        if function.count_basic_blocks() != 0 {
            return Ok(());
        }
        let held: Vec<(String, String)> = module
            .globals
            .iter()
            .filter(|var| var.is_thread_local())
            .map(|var| (var.name.clone(), var.ty.to_string()))
            .filter(|(_, ty)| self.is_reference_name(ty))
            .collect();
        let entry = self.context.append_basic_block(function, "entry");
        self.builder.position_at_end(entry);
        for _ in 0..if held.is_empty() { 0 } else { RELEASE_PASSES } {
            for (name, ty) in held.iter().rev() {
                let addr = self.global_address(name)?.ok_or_else(|| format!("unknown thread-local '{}'", name))?;
                let llvm_ty = addr.llvm_ty.ok_or_else(|| format!("thread-local '{}' has no type", name))?;
                let old = addr.load(&self.builder).ok_or_else(|| format!("load failed {}", name))?;
                addr.store(&self.builder, zero_of(llvm_ty))?;
                self.release_ref(ty, old)?;
            }
        }
        // The runtime's `extern void` declared it first, returning Pepper's
        // `void` type, which is not LLVM's.
        match function.get_type().get_return_type() {
            Some(ty) => self.builder.build_return(Some(&zero_of(ty))),
            None => self.builder.build_return(None),
        }
        .map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// The zero (null, default) value of `ty`.
fn zero_of(ty: BasicTypeEnum<'_>) -> BasicValueEnum<'_> {
    match ty {
        BasicTypeEnum::IntType(t) => t.const_zero().into(),
        BasicTypeEnum::FloatType(t) => t.const_zero().into(),
        BasicTypeEnum::PointerType(t) => t.const_null().into(),
        BasicTypeEnum::ArrayType(t) => t.const_zero().into(),
        BasicTypeEnum::StructType(t) => t.const_zero().into(),
        BasicTypeEnum::VectorType(t) => t.const_zero().into(),
        BasicTypeEnum::ScalableVectorType(t) => t.const_zero().into(),
    }
}

/// The number the next module with emulated thread-locals is told apart by.
static NEXT_MODULE_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

thread_local! {
    /// The calling thread's emulated thread-locals: each module's number
    /// and image address, and the thread's copy, newest first. A plain pointer, so the slot has
    /// no destructor and is never "destroyed" while a thread's last Pepper
    /// code runs; the copies leak when the thread exits (JIT runs only).
    static COPIES: std::cell::Cell<*mut Vec<((u64, usize), *mut u8)>> = const { std::cell::Cell::new(std::ptr::null_mut()) };
}

/// The calling thread's copy of the emulated thread-local whose image, of
/// `size` bytes, is at `image` in module number `module`: made from the
/// image on the thread's first access. The JIT maps [`JIT_ADDRESS_FUNCTION`]
/// to it.
pub(crate) extern "C" fn jit_thread_local(image: *const u8, size: u64, module: u64) -> *mut u8 {
    let key = (module, image as usize);
    COPIES.with(|cell| {
        if cell.get().is_null() {
            cell.set(Box::into_raw(Box::default()));
        }
        // SAFETY: the vector belongs to this thread and is never freed.
        let copies = unsafe { &mut *cell.get() };
        if let Some(&(_, copy)) = copies.iter().find(|(found, _)| *found == key) {
            return copy;
        }
        let layout = std::alloc::Layout::from_size_align((size as usize).max(1), 16).expect("thread-local layout");
        // SAFETY: a fresh block of `size` bytes, filled from the image the
        // JIT's module holds for as long as its code can run.
        let copy = unsafe {
            let copy = std::alloc::alloc(layout);
            if copy.is_null() {
                std::alloc::handle_alloc_error(layout);
            }
            std::ptr::copy_nonoverlapping(image, copy, size as usize);
            copy
        };
        copies.insert(0, (key, copy));
        copy
    })
}

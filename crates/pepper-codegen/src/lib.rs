//! LLVM module generator: port of `source/CodeGen/LLVM/LLVMCodeGenerator.cpp`
//! and its SubGenerators (StructGen, FunctionGen, BlockGen, BranchGen,
//! LoopGen, OperatorGen) for the Rust sema model.

pub mod address;
pub mod ops;
pub mod types;
pub mod target;

use address::{Address, Frame};
use inkwell::context::Context;
use inkwell::module::Module;
use inkwell::types::BasicTypeEnum;
use inkwell::values::{AsValueRef, BasicValueEnum, FunctionValue, GlobalValue, PointerValue};
use inkwell::types::AnyType as _;
use inkwell::values::AnyValue as _;
use inkwell::OptimizationLevel;
use ops as llvm_ops;
use pepper_sema::model::{self as sema, Block, BinaryOp, Branch, Declaration, ExternDef, Expression, FunctionDef, LoopBreak, LoopBreakKind, Module as SemaModule, Statement, StructDef, UnaryOp, VariableDef, While};
use pepper_sema::model::{Diagnostic, Loc};
use pepper_sema::type_name::TypeName;
use std::collections::HashMap;

/// One codegen'd struct: LLVM struct type + size + method map (port of
/// `source/Sema/Struct.cpp` layout + `Struct.h:99-103` method keys).
pub struct StructDesc<'ctx> {
    pub name: String,
    pub llvm_type: inkwell::types::StructType<'ctx>,
    pub size: u64,
    /// real method name → mangled function name (`__dtor` → `Test.__dtor`).
    pub methods: HashMap<String, String>,
    /// real names of static methods (no `this` param).
    pub static_methods: std::collections::HashSet<String>,
    /// field name → sema type string.
    pub fields: Vec<(String, String)>,
    /// method name → return-type sema string.
    pub method_returns: HashMap<String, String>,
}

/// Result of generation.
pub struct Generated {
    pub module: Module<'static>,
}

pub struct CodeGenerator<'ctx> {
    pub context: &'ctx Context,
    pub module: Module<'ctx>,
    pub builder: inkwell::builder::Builder<'ctx>,
    pub types: types::Types<'ctx>,
    pub structs: HashMap<String, StructDesc<'ctx>>,
    /// function name → FunctionValue (methods under mangled `Struct.name` keys).
    pub functions: HashMap<String, FunctionValue<'ctx>>,
    /// free-function name → return-type sema string (for receiver typing of
    /// calls that produce struct values, e.g. `roundtrip(...) + x`).
    fn_returns: HashMap<String, String>,
    /// default-argument expressions per instantiated callable, in parameter
    /// order (keyed like `functions`); trailing missing args are padded from
    /// these at the call site.
    param_defaults: HashMap<String, Vec<Option<Expression>>>,
    /// Identical string literals share one global constant.
    global_strings: HashMap<String, PointerValue<'ctx>>,
    /// File-scope globals: name → Address (frame locals miss falls back here).
    global_addrs: HashMap<String, Address<'ctx>>,
    frame: Frame<'ctx>,
    /// Struct-reference slots alive in the current scopes, innermost last:
    /// `(name, sema type name, slot pointer)`. Each scope exit releases its
    /// occupants in reverse declaration order (shared_ptr semantics); a slot
    /// lives in exactly one scope (the innermost at declaration), so shadowed
    /// names release independently.
    scopes: Vec<Vec<(String, String, PointerValue<'ctx>)>>,
    /// Owned temporaries whose release waits for the end of the full
    /// expression: the receiver of `f().x` / `f()[i]`, whose field or element
    /// the rest of the expression still reads (C++ destroys the temporary
    /// `shared_ptr` at the end of the full expression, not after the member
    /// access). `(value, sema type name)`, released in reverse order by
    /// `flush_deferred_temps`.
    deferred_temps: Vec<(BasicValueEnum<'ctx>, String)>,
    /// Declared names of the externs (C functions) in the module.
    extern_names: std::collections::HashSet<String>,
    /// The innermost located node an error passed through on its way out,
    /// keyed by the error's text: errors are plain strings inside codegen,
    /// and `generate` attaches this location when it returns one.
    error_loc: Option<(String, Loc)>,
}
impl<'ctx> CodeGenerator<'ctx> {
    pub fn new(context: &'ctx Context, module_name: &str) -> Self {
        let module = context.create_module(module_name);
        let builder = context.create_builder();
        // The host's data layout drives alignment inference for atomic
        // instructions; without it 8-byte atomics get `align 4` and lower to
        // compiler-rt helpers MCJIT cannot resolve.
        let machine = crate::target::host_machine().expect("host target machine");
        module.set_data_layout(&machine.get_target_data().get_data_layout());
        CodeGenerator {
            context,
            module,
            builder,
            types: types::Types::new(context),
            structs: HashMap::new(),
            functions: HashMap::new(),
            fn_returns: HashMap::new(),
            param_defaults: HashMap::new(),
            global_strings: HashMap::new(),
            global_addrs: HashMap::new(),
            frame: Frame::empty(),
            scopes: Vec::new(),
            deferred_temps: Vec::new(),
            extern_names: std::collections::HashSet::new(),
            error_loc: None,
        }
    }

    /// Remember `loc` as where a failing `result`'s error arose, unless a node
    /// nested inside this one already claimed it. An error some caller
    /// swallowed leaves a stale entry, which the next different error text
    /// replaces.
    fn locate<T>(&mut self, result: &Result<T, String>, loc: Loc) {
        let Err(error) = result else { return };
        if loc.is_none() || self.error_loc.as_ref().is_some_and(|(e, _)| e == error) {
            return;
        }
        self.error_loc = Some((error.clone(), loc));
    }

    /// Instantiate + codegen in the exact C++ phase order
    /// (LLVMCodeGenerator.cpp:264-308).
    pub fn generate(&mut self, module: &mut SemaModule) -> Result<(), Diagnostic> {
        self.error_loc = None;
        self.generate_module(module).map_err(|error| {
            let loc = match self.error_loc.take() {
                Some((e, loc)) if e == error => loc,
                _ => Loc::NONE,
            };
            Diagnostic::error(error).at(loc)
        })
    }

    fn generate_module(&mut self, module: &mut SemaModule) -> Result<(), String> {
        // Instantiation pass: structs → methods → externs → functions.
        // Concrete (non-abstract) structs are pre-registered as opaque
        // pointers first: a struct's field may name a specialization that is
        // declared later in the module (`HashMap<Point, int>` before
        // `Array<Point>`), and field lookup must not fall back to the base.
        for idx in 0..module.structs.len() {
            let st = &module.structs[idx];
            if st.ty.is_generic() && st.name == st.ty.name {
                continue;
            }
            self.types.ensure_opaque(&st.name);
        }
        for idx in 0..module.structs.len() {
            self.instantiate_struct(&module.structs[idx])?;
        }
        // ABI sizes are only correct once every body is set (a field may
        // name a struct declared later, e.g. `Holder { Array<int> items; }`),
        // so measure after the whole registration pass.
        for desc in self.structs.values_mut() {
            let machine = crate::target::host_machine()?;
            desc.size = machine.get_target_data().get_abi_size(&desc.llvm_type);
        }
        for idx in 0..module.structs.len() {
            self.instantiate_methods(&module.structs[idx])?;
        }
        for idx in 0..module.structs.len() {
            self.instantiate_ctor(&module.structs[idx])?;
        }
        for idx in 0..module.externs.len() {
            self.instantiate_extern(&module.externs[idx])?;
        }
        for idx in 0..module.functions.len() {
            self.instantiate_function(&module.functions[idx])?;
        }

        // File-scope globals: LLVM globals + (if any initializer needs it) a
        // ctor-registered init function. Emitted between the instantiation and
        // codegen passes so initializers can call instantiated functions.
        self.emit_globals(module)?;

        // Codegen pass: structs → functions.
        for idx in 0..module.structs.len() {
            let st = module.structs[idx].clone();
            self.codegen_struct(&st)?;
        }
        for idx in 0..module.functions.len() {
            let function = module.functions[idx].clone();
            self.codegen_function(&function)?;
        }
        self.module
            .verify()
            .map_err(|e| format!("Module verification failed: {}", e.to_string()))
    }

    /// File-scope globals (port of the C++ reference's global handling, which
    /// kept them in a symbol table; here they are real LLVM globals).
    /// Constant initializers become `set_initializer`; non-constant ones are
    /// stored by `__pep_global_init`, registered via `llvm.global_ctors` so it
    /// runs before `main` (the JIT calls run_static_constructors; the linked
    /// binary's .init_array does it at process start).
    fn emit_globals(&mut self, module: &SemaModule) -> Result<(), String> {
        let mut non_const: Vec<(String, Expression)> = vec![];
        for var in &module.globals {
            let ty_string = var.ty.to_string();
            let is_struct_ref = self.structs.contains_key(&ty_string);
            let llvm_ty: BasicTypeEnum<'ctx> = if is_struct_ref {
                // Struct-typed globals hold POINTERS (C++ ref semantics).
                self.context.ptr_type(inkwell::AddressSpace::default()).into()
            } else {
                self.types
                    .get(&ty_string)
                    .ok_or_else(|| format!("unknown global type {}", ty_string))?
            };
            let global = self.module.add_global(llvm_ty, None, &var.name);
            // Every global is defined at link time: zero/null base initializer;
            // const arms below override it. Non-const defaults are stored by
            // the ctor-registered init fn before `main` runs.
            match llvm_ty {
                BasicTypeEnum::IntType(it) => {
                    global.set_initializer(&it.const_int(0, true));
                }
                BasicTypeEnum::FloatType(ft) => {
                    global.set_initializer(&ft.const_float(0.0));
                }
                BasicTypeEnum::PointerType(_) => {
                    global.set_initializer(
                        &self.context.ptr_type(inkwell::AddressSpace::default()).const_null(),
                    );
                }
                _ => {}
            }
            if let Some(default) = &var.default {
                match (default, llvm_ty) {
                    // Create the literal at the global's own width (inkwell's
                    // const casts are unavailable on LLVM ≥18).
                    (Expression::IntLiteral(v), BasicTypeEnum::IntType(it)) => {
                        global.set_initializer(&it.const_int(*v as u64, true));
                    }
                    (Expression::FloatLiteral(v), BasicTypeEnum::FloatType(ft)) => {
                        global.set_initializer(&ft.const_float(*v));
                    }
                    (Expression::BoolLiteral(v), BasicTypeEnum::IntType(it)) => {
                        global.set_initializer(&it.const_int(*v as u64, false));
                    }
                    (Expression::PointerLiteral, BasicTypeEnum::PointerType(_)) => {
                        global.set_initializer(
                            &self.context.ptr_type(inkwell::AddressSpace::default()).const_null(),
                        );
                    }
                    // String defaults: the string data must be a *constant*
                    // global — an internal-linkage string referenced by an
                    // external initializer fails module verification.
                    (Expression::StringLiteral { value, .. }, BasicTypeEnum::PointerType(_)) => {
                        let bytes = value.as_bytes();
                        let i8 = self.context.i8_type();
                        let data: Vec<BasicValueEnum<'ctx>> = bytes
                            .iter()
                            .map(|b| BasicValueEnum::IntValue(i8.const_int(*b as u64, false)))
                            .chain(std::iter::once(BasicValueEnum::IntValue(
                                i8.const_int(0, false),
                            )))
                            .collect();
                        // inkwell 0.10's new_const_array forwards its type arg to
                        // LLVMConstArray2, which takes the ELEMENT type on LLVM >= 18.
                        let arr = unsafe {
                            inkwell::values::ArrayValue::new_const_array(&i8, &data)
                        };
                        let data_global = self.module.add_global(arr.get_type(), None, "str");
                        data_global.set_linkage(inkwell::module::Linkage::Internal);
                        data_global.set_initializer(&arr);
                        global.set_initializer(
                            &BasicValueEnum::PointerValue(data_global.as_pointer_value()),
                        );
                    }
                    _ => non_const.push((var.name.clone(), default.clone())),
                }
            }
            self.global_addrs.insert(
                var.name.clone(),
                Address::with_llvm_ty(&var.name, &ty_string, llvm_ty, global.as_pointer_value()),
            );
        }

        // Non-constant initializers: `g = <expr>;` in a ctor-registered fn.
        if !non_const.is_empty() {
            let init_fn = self.module.add_function(
                "__pep_global_init",
                self.context.void_type().fn_type(&[], false),
                None,
            );
            let entry = self.context.append_basic_block(init_fn, "entry");
            self.builder.position_at_end(entry);
            self.deferred_temps.clear();
            for (name, expr) in &non_const {
                let value = self.codegen_expr(expr)?;
                // A struct-ref global initialized from an lvalue read acquires
                // exactly like `codegen_var_def` does: the global becomes the
                // value's owner. (No process-exit release — globals live for
                // the program's lifetime.)
                let ty_string = self.global_addrs.get(name).unwrap().ty.to_string();
                if self.structs.contains_key(&ty_string)
                    && self.is_lvalue_read(expr)
                {
                    self.acquire_ref(&ty_string, value)?;
                }
                // Match the global's width (mirrors codegen_var_def).
                let addr = self.global_addrs.get(name).unwrap();
                let value = match (&value, addr.llvm_ty) {
                    (BasicValueEnum::IntValue(v), Some(BasicTypeEnum::IntType(it)))
                        if v.get_type() != it =>
                    {
                        self.builder
                            .build_int_cast(*v, it, &format!("{}w", name))
                            .map_err(|e| e.to_string())?
                            .into()
                    }
                    (BasicValueEnum::FloatValue(v), Some(BasicTypeEnum::FloatType(ft)))
                        if v.get_type() != ft =>
                    {
                        self.builder
                            .build_float_cast(*v, ft, &format!("{}w", name))
                            .map_err(|e| e.to_string())?
                            .into()
                    }
                    _ => value,
                };
                addr.store(&self.builder, value)
                    .ok_or_else(|| format!("global store failed: {}", name))?;
                self.flush_deferred_temps()?;
            }
            self.builder.build_return(None).map_err(|e| e.to_string())?;

            // llvm.global_ctors = [1 x { i32 priority, ptr fn, ptr data }]
            // inkwell's FunctionValue has no as_pointer_value; GlobalValue is
            // a transparent newtype over the same LLVMValueRef.
            let init_fn_ptr = unsafe {
                GlobalValue::new(init_fn.as_value_ref())
                    .as_pointer_value()
            };
            let ctor_struct = self.context.const_struct(
                &[
                    BasicValueEnum::IntValue(self.context.i32_type().const_int(65535, false)),
                    BasicValueEnum::PointerValue(init_fn_ptr),
                    BasicValueEnum::PointerValue(
                        self.context.ptr_type(inkwell::AddressSpace::default()).const_null(),
                    ),
                ],
                false,
            );
            let ctor_array = unsafe {
                inkwell::values::ArrayValue::new_const_array(
                    &ctor_struct.get_type(),
                    &[ctor_struct],
                )
            };
            // `llvm.global_ctors` is a reserved name the verifier only accepts
            // with common (zero-initialized) or appending linkage; Clang uses
            // appending.
            let ctors = self.module.add_global(ctor_array.get_type(), None, "llvm.global_ctors");
            ctors.set_linkage(inkwell::module::Linkage::Appending);
            ctors.set_initializer(&ctor_array);

        }
        Ok(())
    }
    /// Compile a module, register host addresses for the declared (not
    /// defined) functions `map_global` names, then hand back the execution
    /// engine with static ctors run. Mapping must use the module's own
    /// function values — MCJIT resolves declares lazily and the engine's
    /// lookup only sees materialized functions.
    pub fn jit_engine_mapped(
        &mut self,
        module: &mut SemaModule,
        map_global: impl Fn(&str) -> Option<usize>,
    ) -> Result<inkwell::execution_engine::ExecutionEngine<'ctx>, String> {
        self.generate(module).map_err(|d| module.sources.render(&d))?;
        let ee = self
            .module
            .create_jit_execution_engine(OptimizationLevel::None)
            .map_err(|e| format!("JIT failed: {}", e.to_string()))?;
        for f in self.module.get_functions() {
            if f.count_basic_blocks() != 0 {
                continue;
            }
            let name = f.get_name().to_string_lossy();
            if let Some(addr) = map_global(name.as_ref()) {
                ee.add_global_mapping(&f, addr);
            }
        }
        // Static ctors (llvm.global_ctors, e.g. __pep_global_init) do NOT run
        // at engine creation — MCJIT only runs them on explicit request.
        ee.run_static_constructors();
        Ok(ee)
    }

    /// Compile a module and hand back the execution engine (static ctors run).
    pub fn jit_engine(
        &mut self,
        module: &mut SemaModule,
    ) -> Result<inkwell::execution_engine::ExecutionEngine<'ctx>, String> {
        self.jit_engine_mapped(module, |_| None)
    }

    /// Call a zero-argument `int` entry point in an already-created engine.
    pub fn jit_call_i32(
        ee: &inkwell::execution_engine::ExecutionEngine<'ctx>,
        entry: &str,
    ) -> Result<i32, String> {
        unsafe {
            let f = ee
                .get_function::<unsafe extern "C" fn() -> i32>(entry)
                .map_err(|e| format!("entry {}: {:?}", entry, e))?;
            Ok(f.call())
        }
    }

    /// Compile + JIT a value-test module: returns the entry's return value.
    pub fn jit_execute(&mut self, module: &mut SemaModule, entry: &str) -> Result<i32, String> {
        let ee = self.jit_engine(module)?;
        Self::jit_call_i32(&ee, entry)
    }

    // ── Struct instantiation (port of StructGen.cpp:57-106) ─────────────────

    fn instantiate_struct(&mut self, st: &StructDef) -> Result<(), String> {
        let result = self.instantiate_struct_unlocated(st);
        self.locate(&result, st.loc);
        result
    }

    fn instantiate_struct_unlocated(&mut self, st: &StructDef) -> Result<(), String> {
        // Generic struct bases are abstract: skip `Name<...>` instances and
        // generic bases (ty 'Array<T>'); specializations were cloned with
        // concrete names by sema.
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }

        let mut field_types: Vec<BasicTypeEnum<'ctx>> = vec![];
        for field in &st.field_members {
            let ty = self
                .types
                .get(&field.ty.to_string())
                .ok_or_else(|| format!("unknown type name '{}' for field '{}'", field.ty, field.name))?;
            field_types.push(ty);
        }

        self.types.register_struct(st, &field_types);
        let llvm_type = self.types.struct_type(&st.name).expect("registered");

        // ABI size is measured after all bodies are set (see `generate`),
        // because a field may name a struct declared later in the module.
        let desc = StructDesc {
            name: st.name.clone(),
            llvm_type,
            size: 0,
            methods: HashMap::new(),
            static_methods: std::collections::HashSet::new(),
            fields: st
                .field_members
                .iter()
                .map(|f| (f.name.clone(), f.ty.to_string()))
                .collect(),
            method_returns: HashMap::new(),
        };
        self.structs.insert(st.name.clone(), desc);

        // Update the ctor's `size` literal now that the size is known
        // (port of StructGen.cpp:85-95). Ctor bodies are cloned into the
        // function list at codegen time, so patch a snapshot module is
        // unnecessary — the generator reads `st` clones from the caller.
        Ok(())
    }

    // ── Method instantiation (port of StructGen.cpp:108-148) ────────────────

    fn instantiate_methods(&mut self, st: &StructDef) -> Result<(), String> {
        let result = self.instantiate_methods_unlocated(st);
        self.locate(&result, st.loc);
        result
    }

    fn instantiate_methods_unlocated(&mut self, st: &StructDef) -> Result<(), String> {
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }
        let struct_name = st.name.clone();
        let mut methods: HashMap<String, String> = HashMap::new();
        let mut method_returns: HashMap<String, String> = HashMap::new();
        let mut static_names: std::collections::HashSet<String> = std::collections::HashSet::new();
        for method in &st.method_members {
            // Mangle `<Struct>.<name>`, inject `this` first for non-static.
            let mut param_types: Vec<BasicTypeEnum<'ctx>> = vec![];
            if !method.is_static {
                // `this` is a pointer (C++ ref semantics).
                let this_ty = self
                    .types
                    .get(&struct_name)
                    .ok_or_else(|| format!("unknown this type {}", struct_name))?;
                let this_ptr_ty = match this_ty {
                    BasicTypeEnum::StructType(sct) => BasicTypeEnum::PointerType(
                        sct.ptr_type(inkwell::AddressSpace::default()),
                    ),
                    other => other,
                };
                param_types.push(this_ptr_ty);
            }
            for param in &method.parameters {
                let ty = self
                    .types
                    .get(&param.ty.to_string())
                    .ok_or_else(|| format!("unknown param type {}", param.ty))?;
                // Struct-typed params are pointers (C++ ref semantics).
                let ty = match ty {
                    BasicTypeEnum::StructType(sct) => BasicTypeEnum::PointerType(
                        sct.ptr_type(inkwell::AddressSpace::default()),
                    ),
                    other => other,
                };
                param_types.push(ty);
            }
            let mangled = format!("{}.{}", struct_name, method.name);
            // Void-returning fns get a true void fn type (types.get('void')
            // maps to i32 for value positions).
            let fn_type = if is_void(&method.ty) {
                self.context.void_type().fn_type(
                    &param_types
                        .iter()
                        .map(|p| inkwell::types::BasicMetadataTypeEnum::from(*p))
                        .collect::<Vec<_>>(),
                    false,
                )
            } else {
                let return_type = self
                    .types
                    .get(&method.ty.to_string())
                    .ok_or_else(|| format!("unknown return type {} for method {}.{}", method.ty, struct_name, method.name))?;
                llvm_fn_type(return_type, &param_types, false)
            };
            let fn_value = self.module.add_function(&mangled, fn_type, None);
            self.functions.insert(mangled.clone(), fn_value);
            self.param_defaults.insert(
                mangled.clone(),
                method.parameters.iter().map(|p| p.default.clone()).collect(),
            );
            if method.is_static {
                static_names.insert(method.name.clone());
            }
            methods.insert(method.name.clone(), mangled);
            method_returns.insert(method.name.clone(), method.ty.to_string());
        }
        if let Some(desc) = self.structs.get_mut(&st.name) {
            desc.methods = methods;
            desc.static_methods = static_names;
            desc.method_returns = method_returns;
        }
        Ok(())
    }

    // ── Extern + function instantiation (port of FunctionGen.cpp:63-95) ─────

    fn instantiate_extern(&mut self, ext: &ExternDef) -> Result<(), String> {
        let result = self.instantiate_extern_unlocated(ext);
        self.locate(&result, ext.loc);
        result
    }

    fn instantiate_extern_unlocated(&mut self, ext: &ExternDef) -> Result<(), String> {
        self.extern_names.insert(ext.name.clone());
        let mut param_types: Vec<BasicTypeEnum<'ctx>> = vec![];
        for param in &ext.parameters {
            let ty = self
                .types
                .get(&param.ty.to_string())
                .ok_or_else(|| format!("unknown param type {}", param.ty))?;
            param_types.push(ty);
        }
        let return_type = self
            .types
            .get(&ext.ty.to_string())
            .ok_or_else(|| format!("unknown return type {}", ext.ty))?;
        let fn_type = llvm_fn_type(return_type, &param_types, ext.is_variadic);
        // `[LinkName("sym")]` binds the declared name to a different C symbol.
        let symbol = ext.link_name()?;
        let fn_value = match self.module.get_function(symbol) {
            Some(f) => f,
            None => {
                let f = self.module.add_function(symbol, fn_type, None);
                // C ABI: integer arguments/returns narrower than int carry
                // signext/zeroext (as clang emits), so the callee may rely on
                // the upper bits of the register (required on e.g. Apple
                // arm64, and assumed by clang-built x86-64 code).
                use inkwell::attributes::{Attribute, AttributeLoc};
                let ext_attr = |ty_name: &str, llvm_ty: &BasicTypeEnum<'ctx>| -> Option<Attribute> {
                    let BasicTypeEnum::IntType(it) = llvm_ty else { return None };
                    if it.get_bit_width() >= 32 {
                        return None;
                    }
                    let kind = if it.get_bit_width() == 1 || llvm_ops::is_unsigned_int_type(ty_name) {
                        "zeroext"
                    } else {
                        "signext"
                    };
                    Some(self.context.create_enum_attribute(Attribute::get_named_enum_kind_id(kind), 0))
                };
                for (i, (param, llvm_ty)) in ext.parameters.iter().zip(&param_types).enumerate() {
                    if let Some(a) = ext_attr(&param.ty.to_string(), llvm_ty) {
                        f.add_attribute(AttributeLoc::Param(i as u32), a);
                    }
                }
                if let Some(a) = ext_attr(&ext.ty.to_string(), &return_type) {
                    f.add_attribute(AttributeLoc::Return, a);
                }
                f
            }
        };
        self.functions.insert(ext.name.clone(), fn_value);
        self.fn_returns.insert(ext.name.clone(), ext.ty.to_string());
        Ok(())
    }

    fn instantiate_function(&mut self, function: &FunctionDef) -> Result<(), String> {
        let result = self.instantiate_function_unlocated(function);
        self.locate(&result, function.loc);
        result
    }

    fn instantiate_function_unlocated(&mut self, function: &FunctionDef) -> Result<(), String> {
        // Generic function bases are abstract: skip them; specializations
        // were cloned with concrete names by sema. Mirrors `instantiate_struct`.
        if function.is_generic_func {
            return Ok(());
        }
        if self.functions.contains_key(&function.name) {
            return Ok(());
        }
        let mut param_types: Vec<BasicTypeEnum<'ctx>> = vec![];
        // Every declared parameter is a real LLVM parameter; missing trailing
        // arguments are padded from the defaults at the call site.
        for param in &function.parameters {
            let ty = self
                .types
                .get(&param.ty.to_string())
                .ok_or_else(|| format!("unknown param type {}", param.ty))?;
            // Struct-typed params are pointers (C++ ref semantics).
            let ty = match ty {
                BasicTypeEnum::StructType(sct) => BasicTypeEnum::PointerType(
                    sct.ptr_type(inkwell::AddressSpace::default()),
                ),
                other => other,
            };
            param_types.push(ty);
        }
        // Void-returning fns get a true void fn type (types.get('void')
        // maps to i32 for value positions).
        let fn_type = if is_void(&function.ty) {
            self.context.void_type().fn_type(
                &param_types
                    .iter()
                    .map(|p| inkwell::types::BasicMetadataTypeEnum::from(*p))
                    .collect::<Vec<_>>(),
                false,
            )
        } else {
            let return_type = self
                .types
                .get(&function.ty.to_string())
                .ok_or_else(|| format!("unknown return type {} for fn {}", function.ty, function.name))?;
            llvm_fn_type(return_type, &param_types, false)
        };
        let fn_value = self.module.add_function(&function.name, fn_type, None);
        self.functions.insert(function.name.clone(), fn_value);
        self.fn_returns.insert(function.name.clone(), function.ty.to_string());
        self.param_defaults.insert(
            function.name.clone(),
            function.parameters.iter().map(|p| p.default.clone()).collect(),
        );
        Ok(())
    }

    /// The ctor with its `size` literal patched to the computed struct size
    /// (port of StructGen's `locals()->function(structDesc->constructor())`).
    /// Both the instantiation pass and codegen must use this, so the declared
    /// function and the emitted body agree on the allocation size.
    fn patched_ctor(&self, st: &StructDef) -> FunctionDef {
        let mut ctor = st.constructor.clone();
        let struct_size = self.structs.get(&st.name).map(|d| d.size).unwrap_or(0) as i64;
        if let Some(body) = &mut ctor.body {
            for stmt in &mut body.items {
                if let Statement::Declaration(Declaration::Variable(var)) = stmt {
                    if var.name == "size" {
                        var.default = Some(Expression::IntLiteral(struct_size));
                        break;
                    }
                }
            }
        }
        ctor
    }

    /// Ctor instantiation: declare the function so call sites can bind it
    fn instantiate_ctor(&mut self, st: &StructDef) -> Result<(), String> {
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }
        self.instantiate_function(&self.patched_ctor(st))
    }

    // ── Struct codegen (ctor + methods) ─────────────────────────────────────
    fn codegen_struct(&mut self, st: &StructDef) -> Result<(), String> {
        let result = self.codegen_struct_unlocated(st);
        self.locate(&result, st.loc);
        result
    }

    fn codegen_struct_unlocated(&mut self, st: &StructDef) -> Result<(), String> {
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }
        // The ctor lives in module.structs[i].constructor, not
        // module.functions — it was instantiated in the instantiation pass.
        self.codegen_function(&self.patched_ctor(st))?;
        for method in &st.method_members {
            // Methods are registered under the mangled name; rename the
            // snapshot for the functions-map lookup.
            let mangled = format!("{}.{}", st.name, method.name);
            let mut m = method.clone();
            m.name = mangled;
            self.codegen_function(&m)?;
        }
        Ok(())
    }

    // ── Function codegen (port of FunctionGen.cpp:22-61 + Function.cpp:61-76)

    fn codegen_function(&mut self, function: &FunctionDef) -> Result<(), String> {
        let result = self.codegen_function_unlocated(function);
        self.locate(&result, function.loc);
        result
    }

    fn codegen_function_unlocated(&mut self, function: &FunctionDef) -> Result<(), String> {
        let fn_value = match self.functions.get(&function.name) {
            Some(f) => *f,
            None => return Ok(()), // extern-only or generic
        };
        let entry = self.context.append_basic_block(fn_value, "entry");
        self.builder.position_at_end(entry);

        // entry + return block + retval alloca (Function.cpp:61-76).
        // The retval alloca lives in the ENTRY block so it dominates every
        // store; the return block loads it.
        // The LLVM return type (struct returns are pointers).
        let ret_ty = self.types.get(&function.ty.to_string());
        let llvm_ret_ty = ret_ty.map(|ty| match ty {
            BasicTypeEnum::StructType(sct) => {
                BasicTypeEnum::PointerType(sct.ptr_type(inkwell::AddressSpace::default()))
            }
            other => other,
        });
        let retval = if is_void(&function.ty) {
            None
        } else {
            let ty = llvm_ret_ty.ok_or_else(|| format!("unknown return type {}", function.ty))?;
            let alloca = self
                .builder
                .build_alloca(ty, "retval")
                .map_err(|e| e.to_string())?;
            // Zero-init so functions without an explicit return return 0.
            let zero: BasicValueEnum<'ctx> = match ty {
                BasicTypeEnum::IntType(it) => BasicValueEnum::IntValue(it.const_zero()),
                BasicTypeEnum::FloatType(ft) => BasicValueEnum::FloatValue(ft.const_zero()),
                BasicTypeEnum::PointerType(pt) => BasicValueEnum::PointerValue(pt.const_null()),
                other => return Err(format!("unsupported retval type {:?}", other)),
            };
            self.builder
                .build_store(alloca, zero)
                .map_err(|e| e.to_string())?;
            Some(alloca)
        };
        let return_block = self.context.append_basic_block(fn_value, "return");
        self.builder.position_at_end(return_block);
        if is_void(&function.ty) {
            self.builder.build_return(None).map_err(|e| e.to_string())?;
        } else {
            let ty = llvm_ret_ty.expect("return type");
            let retval = retval.expect("retval");
            let loaded = self
                .builder
                .build_load(ty, retval, "retval")
                .map_err(|e| e.to_string())?;
            self.builder
                .build_return(Some(&loaded))
                .map_err(|e| e.to_string())?;
        }

        // Body: position at entry, alloca params, emit statements.
        self.builder.position_at_end(entry);
        self.frame.function = Some(fn_value);
        self.frame.return_block = Some(return_block);
        self.frame.retval = retval;
        self.frame.retval_type = Some(function.ty.to_string());
        self.frame.locals.clear();
        self.frame.exited = false;
        self.frame.loop_base_depth = None;
        // Fresh scope stack for this function: the body is one scope.
        self.scopes.clear();
        self.scopes.push(Vec::new());
        self.deferred_temps.clear();

        // Params must be alloca'd at the top of the entry block BEFORE the
        // body statements so they dominate all uses (LLVM dominance).
        // Methods (mangled `Struct.name`) have an injected `this` param 0
        // that the model doesn't declare; add it to the frame.
        let mut declared_params: Vec<(String, String)> = function
            .parameters
            .iter()
            .map(|p| (p.name.clone(), p.ty.to_string()))
            .collect();
        // Static methods are instantiated WITHOUT a this param.
        let is_static_method = function
            .name
            .split('.')
            .next()
            .and_then(|sn| self.structs.get(sn))
            .map(|desc| {
                let method_name = function.name.split('.').nth(1).unwrap_or("");
                desc.static_methods.contains(method_name)
            })
            .unwrap_or(false);
        if function.name.contains('.') && !is_static_method {
            let struct_name = function.name.split('.').next().unwrap_or("").to_string();
            // `this` is a plain struct reference (like any local of the
            // struct type), not a pointer-typed slot: its sema name carries
            // no `*`, so lvalue-read detection and return-site acquires see
            // it exactly as they see `var x = Name(...)`.
            declared_params.insert(0, ("this".to_string(), struct_name));
        }
        let param_allocas: Vec<(String, inkwell::values::PointerValue<'ctx>, inkwell::values::BasicValueEnum<'ctx>, String, BasicTypeEnum<'ctx>)> =
            declared_params
                .iter()
                .enumerate()
                .map(|(param_idx, (name, ty_string))| {
                    let arg = fn_value.get_nth_param(param_idx as u32).unwrap_or_else(|| {
                        panic!("param {} idx {} fn {}", name, param_idx, fn_value.get_name().to_string_lossy());
                    });
                    // The alloca type must match the LLVM fn's actual param
                    // type (struct params were lowered to pointers).
                    let ty = arg.get_type();
                    let alloca = self
                        .builder
                        .build_alloca(ty, name)
                        .map_err(|e| e.to_string())?;
                    Ok((name.clone(), alloca, arg, ty_string.clone(), ty))
                })
                .collect::<Result<Vec<_>, String>>()?;
        for (name, alloca, arg, ty_name, ty) in &param_allocas {
            self.builder
                .build_store(*alloca, *arg)
                .map_err(|e| e.to_string())?;
            self.frame
                .push_local(name, Address::with_llvm_ty(name, ty_name, *ty, *alloca));
            // Pass-by-value struct parameter: a copy arrives (acquire), and
            // the function's scope owns it until exit. `this` is never copied.
            if name != "this" && self.structs.contains_key(ty_name) {
                self.acquire_ref(ty_name, *arg)?;
                self.track_scope_local(name, ty_name, *alloca);
            }
        }

        let body = function.body.clone().unwrap_or_else(|| Block {
            name: String::new(),
            items: vec![],
            attributes: vec![],
        });
        self.codegen_block(&body)?;

        // Function end: release every tracked slot (fall-through path only —
        // a `return` on the same path already released them; LLVM paths are
        // disjoint, so emitting both is safe). Nothing may be emitted when
        // the insert block is terminated.
        if let Some(current) = self.builder.get_insert_block() {
            if current.get_terminator().is_none() {
                // Take the stack out temporarily (no outstanding borrow),
                // release every scope innermost-first, then restore it.
                let scopes = std::mem::take(&mut self.scopes);
                for scope in scopes.iter().rev() {
                    self.release_scope(scope)?;
                }
                self.scopes = scopes;
            }
        }
        // Terminate every block left unterminated: the fall-through tail
        // (when not already terminated), and any merge/continuation block
        // whose predecessors all returned (e.g. an `ifcont` after a branch
        // whose paths both return). Branching to the return block keeps the
        // module verifiable; such blocks are unreachable in practice.
        if let Some(return_block) = self.frame.return_block {
            for bb in self.frame.function.expect("function").get_basic_blocks() {
                if bb.get_terminator().is_none() {
                    self.builder.position_at_end(bb);
                    self.builder
                        .build_unconditional_branch(return_block)
                        .map_err(|e| e.to_string())?;
                }
            }
        }

        Ok(())
    }

    // ── Block codegen (port of BlockGen.cpp:12-54) ──────────────────────────

    fn codegen_block(&mut self, block: &Block) -> Result<(), String> {
        for stmt in &block.items {
            self.codegen_statement(stmt)?;
        }
        Ok(())
    }

    /// A nested `{ ... }` statement gets its own basic block so a `return`
    /// inside it terminates only the block's path (mirroring
    /// `codegen_branch`). Two exit shapes:
    /// - no return in the region: the region's current block is unterminated,
    ///   so a continuation block is inserted after it and the entry branches
    ///   to it — control flow resumes with the next outer statement.
    /// - a return happened: the insert point sits in the function's return
    ///   block; every region block left unterminated (the entry, branch
    ///   merges) is patched to fall through to the return block, and
    ///   subsequent statements — dead code — are emitted into a fresh dead
    ///   block so they never land after a terminator.
    fn codegen_nested_block(&mut self, inner: &Block) -> Result<(), String> {
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let return_block = self.frame.return_block.expect("return block");
        let region_start = fn_value.get_basic_blocks().len();
        let entry = self.context.append_basic_block(fn_value, "block");
        self.builder.build_unconditional_branch(entry).map_err(|e| e.to_string())?;
        self.builder.position_at_end(entry);
        // The `{ ... }` is its own scope: locals declared inside are released
        // at the fall-through exit (a `return` inside already drained all).
        self.frame.exited = false;
        self.scopes.push(Vec::new());
        self.codegen_block(inner)?;

        let current = self.builder.get_insert_block().expect("insert block");
        if !self.frame.exited {
            // No return/break/continue in the region: release this scope's
            // slots, then branch through to a continuation.
            let scope = self.scopes.pop().unwrap_or_default();
            self.release_scope(&scope)?;
            let cont = self.context.insert_basic_block_after(current, "blockcont");
            self.builder.build_unconditional_branch(cont).map_err(|e| e.to_string())?;
            self.builder.position_at_end(cont);
        } else {
            // Every path through the region exited (a `return` — break and
            // continue land in loop blocks, never here): this scope's slots
            // are all released; pop it for stack balance and patch every
            // unterminated block created by the region to fall through, then
            // keep subsequent (dead) statements landing in a fresh dead
            // block so they never land after a terminator.
            self.scopes.pop();
            let blocks = fn_value.get_basic_blocks();
            for bb in &blocks[region_start..] {
                if bb.get_terminator().is_none() {
                    self.builder.position_at_end(*bb);
                    self.builder
                        .build_unconditional_branch(return_block)
                        .map_err(|e| e.to_string())?;
                }
            }
            let dead = self.context.append_basic_block(fn_value, "blockdead");
            self.builder.position_at_end(dead);
        }
        Ok(())
    }
    fn codegen_statement(&mut self, stmt: &Statement) -> Result<(), String> {
        // Dead code after a `return`/`break`/`continue` in this region: the
        // insert point sits past a terminator (or in a dead block), so skip
        // emitting it — landing instructions after a terminator is invalid IR.
        if self.frame.exited {
            return Ok(());
        }
        match stmt {
            Statement::Expression(expr) => {
                let temp_ty = self.owned_temp_type(expr);
                let value = self.codegen_expr(expr)?;
                // A discarded owned rvalue is a temporary: shared_ptr destroys
                // it at the end of the full expression. Lvalue reads carry no
                // ref (nothing to release). `__index_set` results are owned
                // temporaries too — its return site acquires a fresh ref for
                // the returned value, so the temp is released here.
                if let Some(ty) = temp_ty {
                    self.release_temp(&ty, value)?;
                }
                self.flush_deferred_temps()?;
            }
            Statement::Block(inner) => self.codegen_nested_block(inner)?,
            Statement::Declaration(Declaration::Variable(var)) => {
                self.codegen_var_def(var)?;
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => self.codegen_branch(branch)?,
            Statement::While(wh) => self.codegen_while(wh)?,
            Statement::LoopBreak(lb) => self.codegen_loop_break(lb)?,
            Statement::Return(ret) => {
                let return_block = self
                    .frame
                    .return_block
                    .ok_or_else(|| "return outside function".to_string())?;
                let mut value: Option<BasicValueEnum<'ctx>> = None;
                let mut value_name: Option<String> = None;
                if let Some(expr) = &ret.expr {
                    let v = self.codegen_expr(expr)?;
                    value_name = Some(self.numeric_source_name(expr, &v));
                    // shared_ptr-by-value: returning a struct reference is a
                    // copy of an lvalue (local, param, field, index slot, or
                    // `this`), so acquire the new ref BEFORE releasing this
                    // function's slots — for `this` that is
                    // `shared_from_this` (`this` is untracked, so no exit
                    // release cancels it). Function and method results are
                    // owned rvalues: the callee's return site already
                    // acquired, so they move here.
                    if self.is_lvalue_read(expr) {
                        let ty = self.value_sema_type(expr).unwrap_or_default();
                        if !ty.is_empty() {
                            self.acquire_ref(&ty, v)?;
                        }
                    }
                    value = Some(v);
                }
                // The returned value is owned (acquired above) before the
                // full expression's temporaries go.
                self.flush_deferred_temps()?;
                // Early exit: release every tracked slot in every scope.
                self.release_all_scopes()?;
                if let (Some(value), Some(retval)) = (value, self.frame.retval) {
                    // Coerce the value (e.g. an i1 compare result) to the
                    // declared return type before the store.
                    let retval_ty = self
                        .frame
                        .retval_type
                        .clone()
                        .unwrap_or_default();
                    // The source's sema name carries its signedness: a `u16`
                    // returned as `long` zero-extends.
                    let coerced = llvm_ops::coerce(
                        self.context,
                        &self.builder,
                        value,
                        &value_name.unwrap_or_else(|| value_type_name(&value)),
                        &retval_ty,
                    );
                    self.builder
                        .build_store(retval, coerced)
                        .map_err(|e| e.to_string())?;
                }
                self.builder
                    .build_unconditional_branch(return_block)
                    .map_err(|e| e.to_string())?;
                // The return terminated this region: subsequent statements
                // are dead, and the region's fall-through exit (if any) is
                // unreachable — its slots were released above.
                self.frame.exited = true;
            }
        }
        Ok(())
    }

    fn codegen_var_def(&mut self, var: &VariableDef) -> Result<(), String> {
        let result = self.codegen_var_def_unlocated(var);
        self.locate(&result, var.loc);
        result
    }

    fn codegen_var_def_unlocated(&mut self, var: &VariableDef) -> Result<(), String> {
        // A `for` loop's hidden iterator: substitute the concrete source
        // (`source.iterate()` or `source` itself), so the refcount rules below
        // see an ordinary method call or read. Sema types it best-effort;
        // fall back to the substituted expression's type.
        if let Some(Expression::ForIterator(source)) = &var.default {
            let mut lowered = var.clone();
            let iterator = self.for_loop_iterator(source)?;
            if lowered.ty.to_string() == pepper_sema::type_name::AUTO {
                if let Some(ty) = self.value_sema_type(&iterator) {
                    lowered.ty = TypeName::new(&ty);
                }
            }
            lowered.default = Some(iterator);
            return self.codegen_var_def(&lowered);
        }
        // Struct-typed vars hold POINTERS (C++ ref semantics): `this`
        // (malloc'd) and locals initialized from a ctor call.
        let is_struct_ref = self.structs.contains_key(&var.ty.to_string());
        let ty = if is_struct_ref {
            self.context.ptr_type(inkwell::AddressSpace::default()).into()
        } else {
            self.types
                .get(&var.ty.to_string())
                .ok_or_else(|| {
                    let error = format!("unknown type name '{}'", var.ty);
                    // Point at the written type rather than the name.
                    self.error_loc = var.type_loc.known().map(|loc| (error.clone(), loc));
                    error
                })?
        };
        let alloca = self
            .builder
            .build_alloca(ty, &var.name)
            .map_err(|e| e.to_string())?;
        if let Some(default) = &var.default {
            let value = self.codegen_expr(default)?;
            // Copying an existing struct reference into a fresh slot acquires
            // (shared_ptr::operator=). Ctor and function/method results are
            // excluded: their result already carries its creation ref — the
            // callee's `return this` / return site acquired it, exactly as
            // `make_shared` hands out a refcount-1 shared_ptr.
            if is_struct_ref && self.is_lvalue_read(default) {
                self.acquire_ref(&var.ty.to_string(), value)?;
            }
            // Integer literals codegen as i32; adjust into the alloca's width
            // so the full word is defined (widen e.g. the ctor's `u64 size`,
            // truncate e.g. `u8 b = 200` — a mismatched-width store is invalid
            // IR and loads back garbage). A numeric target converts with C
            // semantics from the source's sema type: unsigned sources
            // zero-extend (`long l = u16 65535` stays 65535) and int<->float
            // converts rather than storing the raw bits.
            let target_name = var.ty.to_string();
            let numeric_value = matches!(value, BasicValueEnum::IntValue(_) | BasicValueEnum::FloatValue(_));
            let value = if numeric_value
                && llvm_ops::is_numeric_type(&target_name)
                && value.get_type() != ty
            {
                let src_name = self.numeric_source_name(default, &value);
                llvm_ops::coerce(self.context, &self.builder, value, &src_name, &target_name)
            } else {
                value
            };
            let value = match (&value, ty) {
                (BasicValueEnum::IntValue(v), BasicTypeEnum::IntType(it))
                    if v.get_type().get_bit_width() < it.get_bit_width() =>
                {
                    // 1-bit values (bools from comparisons / `!`) are unsigned
                    // 0/1: zero-extend, else `true` sign-extends to -1.
                    let zext = v.get_type().get_bit_width() == 1;
                    if zext {
                        self.builder
                            .build_int_z_extend(*v, it, &format!("{}w", var.name))
                            .map_err(|e| e.to_string())?
                            .into()
                    } else {
                        self.builder
                            .build_int_s_extend(
                                *v,
                                it,
                                &format!("{}w", var.name),
                            )
                            .map_err(|e| e.to_string())?
                            .into()
                    }
                }
                (BasicValueEnum::IntValue(v), BasicTypeEnum::IntType(it))
                    if v.get_type().get_bit_width() > it.get_bit_width() =>
                {
                    // A 1-bit target is a bool: truncation keeps only the low
                    // bit (`2` -> false); the value must be compared != 0.
                    if it.get_bit_width() == 1 {
                        BasicValueEnum::IntValue(llvm_ops::as_bool(
                            &self.context,
                            &self.builder,
                            BasicValueEnum::IntValue(*v),
                        ))
                    } else {
                        self.builder
                            .build_int_truncate(*v, it, &format!("{}t", var.name))
                            .map_err(|e| e.to_string())?
                            .into()
                    }
                }
                (BasicValueEnum::FloatValue(v), BasicTypeEnum::FloatType(ft))
                    if v.get_type() != ft =>
                {
                    // C 6.3.1.4: a float-typed var stores the value at its
                    // own width (`float f = i * 1.5` is an f64 binary result
                    // truncated to f32, not stored wide).
                    if v.get_type().get_bit_width() < ft.get_bit_width() {
                        self.builder
                            .build_float_ext(*v, ft, &format!("{}f", var.name))
                            .map_err(|e| e.to_string())?
                            .into()
                    } else {
                        self.builder
                            .build_float_trunc(*v, ft, &format!("{}f", var.name))
                            .map_err(|e| e.to_string())?
                            .into()
                    }
                }
                _ => value,
            };
            self.builder
                .build_store(alloca, value)
                .map_err(|e| e.to_string())?;
            self.flush_deferred_temps()?;
        } else {
            // No default: zero-initialize so loads are defined (the ctor's
            // `size` var is patched at codegen time on a clone snapshot).
            let zero: BasicValueEnum<'ctx> = match ty {
                BasicTypeEnum::IntType(it) => BasicValueEnum::IntValue(it.const_zero()),
                BasicTypeEnum::FloatType(ft) => BasicValueEnum::FloatValue(ft.const_zero()),
                BasicTypeEnum::PointerType(_) => BasicValueEnum::PointerValue(
                    self.context.ptr_type(inkwell::AddressSpace::default()).const_null(),
                ),
                BasicTypeEnum::StructType(sct) => BasicValueEnum::StructValue(sct.const_zero()),
                BasicTypeEnum::ArrayType(at) => BasicValueEnum::ArrayValue(at.const_zero()),
                BasicTypeEnum::VectorType(_) | BasicTypeEnum::ScalableVectorType(_) => {
                    return Err("unsupported zero init".to_string())
                }
            };
            self.builder
                .build_store(alloca, zero)
                .map_err(|e| e.to_string())?;
        }
        self.frame
            .push_local(&var.name, Address::with_llvm_ty(&var.name, &var.ty.to_string(), ty, alloca));
        // The scope owns the slot until exit (null occupants release to nothing).
        // The ctor's `this` is excluded: the ctor's `return this` acquires at
        // the return site, so the result leaves with rc == 1 — releasing `this`
        // here would destroy a live object.
        if is_struct_ref && var.name != "this" {
            self.track_scope_local(&var.name, &var.ty.to_string(), alloca);
        }
        Ok(())
    }

    /// The iterator a `for` loop drives over `source`: `source.iterate()` when
    /// its type declares `iterate()` (Iterable<T>), else `source` itself when
    /// it declares `next()` and `current()` (Iterator<T>).
    fn for_loop_iterator(&self, source: &Expression) -> Result<Expression, String> {
        let ty = self.struct_name_of(source).unwrap_or_else(|| "<unknown>".to_string());
        let methods = self.structs.get(&ty).map(|d| &d.methods);
        let declares = |m: &str| methods.is_some_and(|ms| ms.contains_key(m));
        if declares("iterate") {
            Ok(Expression::MethodCall { this: Box::new(source.clone()), method: "iterate".to_string(), args: vec![], loc: source.loc() })
        } else if declares("next") && declares("current") {
            Ok(source.clone())
        } else {
            Err(format!(
                "type '{}' is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())",
                ty
            ))
        }
    }

    // ── Branch + ternary + while (BranchGen.cpp, LoopGen.cpp) ───────────────

    fn codegen_branch(&mut self, branch: &Branch) -> Result<(), String> {
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let then_block = self.context.append_basic_block(fn_value, "then");
        let else_block = branch
            .else_block
            .as_ref()
            .map(|_| self.context.append_basic_block(fn_value, "else"));
        let merge_block = self.context.append_basic_block(fn_value, "ifcont");

        let cond_temp = self.owned_temp_type(&branch.condition);
        let cond = self.codegen_expr(&branch.condition)?;
        if let Some(ty) = cond_temp {
            self.release_temp(&ty, cond)?;
        }
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.flush_deferred_temps()?;
        self.builder
            .build_conditional_branch(cond_bool, then_block, else_block.unwrap_or(merge_block))
            .map_err(|e| e.to_string())?;

        // The then-arm is its own scope: its locals are released at the arm's
        // fall-through tail, where they dominate (function-end release would
        // load them from a block that does not dominate the tail).
        self.scopes.push(Vec::new());
        self.frame.exited = false;
        self.builder.position_at_end(then_block);
        self.codegen_block(&branch.if_block)?;
        let then_end = self.builder.get_insert_block().expect("insert block");
        // Pop the arm scope for stack balance. A `return` inside already
        // released every slot (scopes are non-consuming); on fall-through,
        // release this arm's own slots at its tail, where they dominate.
        let scope = self.scopes.pop().unwrap_or_default();
        if then_end.get_terminator().is_none() {
            self.release_scope(&scope)?;
            self.builder
                .build_unconditional_branch(merge_block)
                .map_err(|e| e.to_string())?;
        }

        if let Some(else_b) = else_block {
            // Same scope rule for the else-arm.
            self.scopes.push(Vec::new());
            self.frame.exited = false;
            self.builder.position_at_end(else_b);
            self.codegen_block(branch.else_block.as_ref().expect("else block"))?;
            let else_end = self.builder.get_insert_block().expect("insert block");
            let scope = self.scopes.pop().unwrap_or_default();
            if else_end.get_terminator().is_none() {
                self.release_scope(&scope)?;
                self.builder
                    .build_unconditional_branch(merge_block)
                    .map_err(|e| e.to_string())?;
            }
        }

        self.builder.position_at_end(merge_block);
        // The if statement completes here: control after it is live again.
        self.frame.exited = false;
        Ok(())
    }

    fn codegen_while(&mut self, wh: &While) -> Result<(), String> {
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let cond_block = self.context.append_basic_block(fn_value, "whilecond");
        let body_block = self.context.append_basic_block(fn_value, "while");
        let merge_block = self.context.append_basic_block(fn_value, "whilecont");

        // Initial condition check.
        let cond_temp = self.owned_temp_type(&wh.condition);
        let cond = self.codegen_expr(&wh.condition)?;
        if let Some(ty) = cond_temp {
            self.release_temp(&ty, cond)?;
        }
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.flush_deferred_temps()?;
        self.builder
            .build_conditional_branch(cond_bool, body_block, merge_block)
            .map_err(|e| e.to_string())?;

        // break/continue targets for the body: `continue` re-checks the
        // condition, `break` exits to the merge. With these the body's insert
        // block may end in any of three terminators (fall-through, break,
        // continue), so the back-edge re-check needs an explicit `cond_block`.
        let saved = self.frame.loop_break;
        let saved_base = self.frame.loop_base_depth;
        self.frame.loop_break = Some((cond_block, merge_block));

        // Body. The body is its own scope, re-created on every iteration:
        // locals declared inside are released where each iteration leaves
        // it — at the end of the body on fall-through, and at a `continue` or
        // `break` (which release only the locals declared before them). Its
        // index on the scope stack is the break/continue release boundary
        // (`loop_base_depth`).
        self.builder.position_at_end(body_block);
        let body_scope = Vec::new();
        self.scopes.push(body_scope);
        let base_depth = self.scopes.len() - 1;
        self.frame.loop_base_depth = Some(base_depth);
        self.frame.exited = false;
        self.codegen_block(&wh.block)?;
        // A `return` inside already drained all scopes; pop the (now empty)
        // body scope so the stack stays balanced.
        let body_scope = self.scopes.pop().unwrap_or_default();

        // Fall-through path: release this iteration's body locals, then
        // branch to the condition re-check. A `return`, `break` or
        // `continue` inside the body already terminated it (having released
        // what it leaves); skip in that case. Releasing here rather than in
        // `cond_block` matters: a `continue` that precedes a declaration
        // reaches `cond_block` without passing the local's alloca, so a load
        // of it there would not be dominated by its definition.
        let body_end = self.builder.get_insert_block().expect("insert block");
        if body_end.get_terminator().is_none() {
            if !body_scope.is_empty() {
                self.release_scope(&body_scope)?;
            }
            self.builder.build_unconditional_branch(cond_block).map_err(|e| e.to_string())?;
        }

        self.frame.loop_break = saved;
        self.frame.loop_base_depth = saved_base;

        // Back-edge: every path into `cond_block` has released its body
        // locals already; re-check the condition.
        self.builder.position_at_end(cond_block);
        let cond_temp = self.owned_temp_type(&wh.condition);
        let cond = self.codegen_expr(&wh.condition)?;
        if let Some(ty) = cond_temp {
            self.release_temp(&ty, cond)?;
        }
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.flush_deferred_temps()?;
        self.builder
            .build_conditional_branch(cond_bool, body_block, merge_block)
            .map_err(|e| e.to_string())?;
        self.builder.position_at_end(merge_block);
        // The loop completes here: control after it is live again.
        self.frame.exited = false;
        Ok(())
    }

    fn codegen_loop_break(&mut self, lb: &LoopBreak) -> Result<(), String> {
        let (cont, brk) = self
            .frame
            .loop_break
            .ok_or_else(|| "break/continue outside a loop".to_string())?;
        // shared_ptr-by-value: leaving the iteration destroys exactly the
        // scopes the jump leaves behind. Both `break` and `continue` release
        // everything from the innermost scope down to and including the body
        // scope — only the locals declared so far, since the scopes hold
        // exactly those at this point. (Outer scopes release at their own
        // tails after the loop, on every path.)
        let base = self
            .frame
            .loop_base_depth
            .ok_or_else(|| "break/continue outside a loop".to_string())?;
        let depth = self.scopes.len();
        let scopes = std::mem::take(&mut self.scopes);
        for scope in scopes[base.min(depth - 1)..depth].iter().rev() {
            self.release_scope(scope)?;
        }
        self.scopes = scopes;
        let target = match lb.kind {
            LoopBreakKind::Continue => cont,
            LoopBreakKind::Break => brk,
        };
        // After the branch the insert point is past a terminator: mark this
        // region exited so any remaining statements in it are skipped, and
        // its fall-through exit (if any) unreachable — the scopes above were
        // released here.
        self.frame.exited = true;
        self.builder.build_unconditional_branch(target).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Type name of an already-generated numeric value for conversion
    /// decisions: the declared sema type (which carries signedness — LLVM
    /// flattens `u16` and `i16` to i16) when it agrees with the value's
    /// kind, else the name implied by the LLVM value.
    fn numeric_source_name(&self, expr: &Expression, value: &BasicValueEnum<'ctx>) -> String {
        let fallback = value_type_name(value);
        match self.value_sema_type(expr) {
            Some(name)
                if llvm_ops::is_numeric_type(&name)
                    && llvm_ops::is_float_type(&name) == matches!(value, BasicValueEnum::FloatValue(_)) =>
            {
                name
            }
            _ => fallback,
        }
    }

    /// Sema type string of an expression's value, as declared (pointer
    fn value_sema_type(&self, expr: &Expression) -> Option<String> {
        match expr {
            // Literals carry C's type directly (6.4.4): a bool literal is
            // `bool`, an int-range integer literal is `int` (else `long`),
            // a float literal is `double`. Naming them by their LLVM width
            // (`value_type_name`) would classify an unsigned literal as
            // signed and pick sdiv/SLT where C requires udiv/ULT.
            Expression::BoolLiteral(_) => Some("bool".to_string()),
            Expression::IntLiteral(v) => {
                if (i32::MIN as i64) <= *v && *v <= (i32::MAX as i64) {
                    Some("int".to_string())
                } else {
                    Some("long".to_string())
                }
            }
            Expression::FloatLiteral(_) => Some("double".to_string()),
            // A bare struct name that no local or global shadows is a type
            // literal: the receiver of a static call `File.open(p)`. Naming
            // its type lets the call dispatch as `File.open` (no instance).
            Expression::SymbolRef { id, .. } => self
                .frame
                .find_local(id)
                .or_else(|| self.global_addrs.get(id))
                .map(|a| a.ty.to_string())
                .or_else(|| self.structs.contains_key(id).then(|| id.clone())),
            Expression::ThisRef => self
                .frame
                .find_local("this")
                .map(|a| a.ty.to_string()),
            Expression::FunctionCall { function, .. } => {
                // Free functions first (their declared return type), then
                // ctor-style calls `Name<...>(...)` resolve to Name<...>.
                self.fn_returns.get(function).cloned().or_else(|| {
                    let base = function.split('<').next().unwrap_or("").to_string();
                    if !base.is_empty() && self.structs.contains_key(&base) {
                        Some(pepper_sema::passes::gather_generics::parse_type_string(function).to_string())
                    } else {
                        None
                    }
                })
            }
            Expression::MemberRef { lhs, name, .. } => {
                let struct_name = self.struct_name_of(lhs)?;
                self.structs
                    .get(&struct_name)?
                    .fields
                    .iter()
                    .find(|(f, _)| f == name)
                    .map(|(_, ty)| ty.clone())
            }
            Expression::MethodCall { this, method, .. } => {
                let struct_name = self.struct_name_of(this)?;
                self.structs
                    .get(&struct_name)?
                    .method_returns
                    .get(method)
                    .cloned()
            }
            Expression::Unary { op, operand, .. } => match *op {
                // `!x` produces an i1; the arithmetic unaries keep the
                // operand's type (codegen_unary).
                UnaryOp::LogicalNot => Some("bool".to_string()),
                // `-x`/`~x` produce a signed two's-complement value at the
                // operand's width: a narrower-than-int unsigned operand
                // promotes to signed int (same rule as `result_type`), or
                // `-(u8 1)` zero-extends to 255 instead of -1.
                UnaryOp::Neg | UnaryOp::BitNot => self
                    .value_sema_type(operand)
                    .map(|t| llvm_ops::result_type(&t, &t)),
                _ => self.value_sema_type(operand),
            },
            Expression::Binary { op, lhs, rhs, .. } => {
                // The produced value is the *promoted* type from
                // `codegen_binary` (`binary_result_type`): numeric operands
                // are promoted to canonical i32/i64/f32/f64 (a `u8 - int`
                // binary produces a signed i32; u32/u64 keep their
                // unsignedness), non-numeric operands keep the lhs type.
                // Reporting the declared lhs type would misclassify negative
                // results as unsigned in casts.
                if is_comparison(*op) {
                    // A comparison produces an i1, not the promoted operand
                    // type: naming the operand type makes `coerce` a no-op
                    // and apply_op sign-extends `true` into -1.
                    return Some("bool".to_string());
                }
                match (self.value_sema_type(lhs), self.value_sema_type(rhs)) {
                    (Some(l), Some(r)) => Some(binary_result_type(op, &l, &r)),
                    // An unresolved rhs promotes to `int` in the same way
                    // codegen_binary coerces it: a non-numeric lhs keeps its
                    // type verbatim (pointer arithmetic retains its element
                    // type), a numeric lhs gets the canonical promotion. A
                    // float-valued rhs makes the binary produce f32/f64, so
                    // it must fall through to the `value_type_name` fallback.
                    (Some(l), None) if !is_float_valued(rhs) => {
                        Some(binary_result_type(op, &l, "int"))
                    }
                    _ => None,
                }
            }
            Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } => {
                // Indexed element: the receiver's pointee (`Array<Array<int>>`
                // → `Array<int>`), so method calls on a nested-Array element
                // mangle against the element's struct.
                self.index_receiver_pointee(lhs)
            }
            // `x as T` has the cast target's type.
            Expression::Cast { ty, .. } => Some(ty.to_string()),
            // Both ternary arms have the same declared type (enforced by
            // sema): report it so consumers (var defs, refcount helpers)
            // see the arm's type, not nothing.
            Expression::Ternary { true_expr, .. } => self.value_sema_type(true_expr),
            // Atomic intrinsics: the load yields T, the store is void, the
            // cmpxchg reports success as bool.
            Expression::AtomicLoad(ty, _) => Some(ty.to_string()),
            Expression::AtomicStore(..) => Some("void".to_string()),
            Expression::AtomicCmpXchg(..) => Some("bool".to_string()),
            Expression::AtomicFetch(_, ty, _, _) => Some(ty.to_string()),
            _ => None,
        }
    }

    /// Best-effort struct name of an expression's value, for field/method
    /// access when the receiver is not a bare frame local (e.g. a parameter).
    /// The declared name resolves exactly first — only concrete
    /// specializations are registered (`Array<Array<int>>`), never the base;
    /// unregistered names fall back to their base for abstract receivers.
    fn struct_name_of(&self, expr: &Expression) -> Option<String> {
        let ty = self.value_sema_type(expr)?.trim_end_matches('*').to_string();
        if self.structs.contains_key(&ty) {
            return Some(ty);
        }
        ty.split('<').next().filter(|n| !n.is_empty()).map(|s| s.to_string())
    }

    /// True when an expression reads an existing struct reference (an lvalue
    /// read of a tracked slot) rather than producing one: the loaded value
    /// carries no ref of its own, so copying it into another reference slot
    /// must `__acquire` the new occupant — exactly as `shared_ptr::operator=`
    /// does. Ctor-style calls (`Name<...>(...)`) and free-function/method
    /// results are excluded: their result already carries its creation ref.
    /// A lowered indexer (`x[i]` → `x.__index_get(i)`) is an lvalue read only
    /// when it takes the plain GEP + load path (receiver not pointer-typed,
    /// receiver struct declares no indexer of its own — mirroring the
    /// dispatch condition in `codegen_expr`, result type a registered
    /// struct); container-declared indexers dispatch to a method that owns
    /// its result. `this` is an lvalue read too: returning it acquires at
    /// the return site, exactly as `shared_from_this` hands out a new ref.
    fn is_lvalue_read(&self, expr: &Expression) -> bool {
        match expr {
            Expression::SymbolRef { .. }
            | Expression::ThisRef
            | Expression::MemberRef { .. }
            | Expression::Index { .. }
            | Expression::ArrayIndex { .. } => self.is_struct_ref_name(&self.value_sema_type(expr)),
            Expression::MethodCall { this, method, .. } if method == "__index_get" => {
                let receiver_is_ptr = self
                    .value_sema_type(this)
                    .is_some_and(|ty| ty.ends_with('*'));
                if receiver_is_ptr {
                    return false;
                }
                let struct_name = self.struct_name_of(this).unwrap_or_default();
                let has_indexer = self
                    .structs
                    .get(&struct_name)
                    .map(|d| d.methods.contains_key(method))
                    .unwrap_or(false);
                !has_indexer && self.is_struct_ref_name(&self.value_sema_type(expr))
            }
            _ => false,
        }
    }

    /// True when an expression's value is a freshly created owned reference
    /// (shared_ptr rvalue): a function/method result whose declared type is a
    /// registered struct. Ctor calls included — their `return this` acquires
    /// at the return site, so the result carries its creation ref exactly as
    /// `make_shared` hands out a refcount-1 shared_ptr. A discarded owned
    /// rvalue is released at the end of its full expression, exactly as C++
    /// destroys a temporary shared_ptr.
    fn is_owned_rvalue(&self, expr: &Expression) -> bool {
        match expr {
            Expression::MethodCall { .. } | Expression::FunctionCall { .. } => {
                self.is_struct_ref_name(&self.value_sema_type(expr))
            }
            // A ternary of two owned rvalues is one owned rvalue: the arm's
            // creation ref flows into the phi, so the consumer releases it
            // once. Mixed lvalue/rvalue arms are not (C++ yields a copy of
            // the lvalue there — no single temporary to destroy).
            Expression::Ternary { true_expr, false_expr, .. } => {
                self.is_owned_rvalue(true_expr) && self.is_owned_rvalue(false_expr)
            }
            // An atomic load yields a freshly acquired reference (struct T):
            // an owned rvalue, released by the consuming context.
            Expression::AtomicLoad(ty, _) => self.is_struct_ref_name(&Some(ty.to_string())),
            // An atomic fetch returns the old slot occupant (struct T): the
            // return site acquires it, so the result is an owned rvalue.
            Expression::AtomicFetch(_, ty, _, _) => self.is_struct_ref_name(&Some(ty.to_string())),
            _ => false,
        }
    }

    /// True when a sema type name names a registered struct.
    fn is_struct_ref_name(&self, ty: &Option<String>) -> bool {
        match ty {
            Some(t) => self.structs.contains_key(t),
            None => false,
        }
    }

    /// `T.__acquire(v)` for a struct-reference value (null-guarded inside).
    fn acquire_ref(&mut self, ty_name: &str, val: BasicValueEnum<'ctx>) -> Result<(), String> {
        self.call_function(&format!("{}.{}", ty_name, "__acquire"), vec![val])?;
        Ok(())
    }

    /// Sema type name when `expr` produces an owned rvalue temporary that a
    /// consuming context must release once it is done with the value (a
    /// shared_ptr destroyed at the end of its use). Lvalue reads carry no ref
    /// of their own, so they are never temporaries.
    fn owned_temp_type(&self, expr: &Expression) -> Option<String> {
        if self.is_owned_rvalue(expr) && !self.is_lvalue_read(expr) {
            self.value_sema_type(expr)
        } else {
            None
        }
    }

    /// Release an owned rvalue temporary (`T.__release`), a no-op for empty
    /// type names.
    fn release_temp(&mut self, ty: &str, val: BasicValueEnum<'ctx>) -> Result<(), String> {
        if !ty.is_empty() {
            self.call_function(&format!("{}.{}", ty, "__release"), vec![val])?;
        }
        Ok(())
    }

    /// Track a struct-reference slot for scope-exit release. A slot lives in
    /// exactly one scope (the innermost at declaration), so shadowed names
    /// release independently when their own scopes exit.
    fn track_scope_local(&mut self, name: &str, ty_name: &str, addr: PointerValue<'ctx>) {
        // No live scope (dead code after an early return): nothing to release.
        let Some(scope) = self.scopes.last_mut() else {
            return;
        };
        scope.push((name.to_string(), ty_name.to_string(), addr));
    }

    /// Release every tracked slot in `scope` (reverse declaration order).
    fn release_scope(
        &mut self,
        scope: &[(String, String, PointerValue<'ctx>)],
    ) -> Result<(), String> {
        for (_name, ty_name, addr) in scope.iter().rev() {
            let val = self.builder.build_load(
                self.context.ptr_type(inkwell::AddressSpace::default()),
                *addr,
                "scope_release",
            )
            .map_err(|e| e.to_string())?;
            self.call_function(&format!("{}.{}", ty_name, "__release"), vec![val])?;
        }
        Ok(())
    }

    /// End of a full expression: release the temporaries whose release was
    /// deferred while it was evaluated, most recent first.
    fn flush_deferred_temps(&mut self) -> Result<(), String> {
        let temps = std::mem::take(&mut self.deferred_temps);
        for (value, ty) in temps.into_iter().rev() {
            self.release_temp(&ty, value)?;
        }
        Ok(())
    }

    /// Evaluate `expr` in a conditionally executed region (a ternary arm):
    /// temporaries deferred inside it are released before the region ends,
    /// since the end of the enclosing full expression is in a block the
    /// region does not dominate.
    fn codegen_expr_in_arm(&mut self, expr: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        let outer = std::mem::take(&mut self.deferred_temps);
        let result = self.codegen_expr(expr);
        let flushed = self.flush_deferred_temps();
        self.deferred_temps = outer;
        let value = result?;
        flushed?;
        Ok(value)
    }

    /// Release every tracked slot in every enclosing scope (innermost last,
    /// each in reverse declaration order) — the early-return path, which
    /// skips the normal scope-exit releases. Scopes are NOT consumed: every
    /// exit point emits its own releases, and LLVM paths are disjoint, so a
    /// slot released here is never released again on the same runtime path.
    fn release_all_scopes(&mut self) -> Result<(), String> {
        // Take the stack out temporarily (no outstanding borrow), release
        // every scope innermost-first, then restore it — scopes are
        // non-consuming.
        let scopes = std::mem::take(&mut self.scopes);
        for scope in scopes.iter().rev() {
            self.release_scope(scope)?;
        }
        self.scopes = scopes;
        Ok(())
    }

    /// LLVM element type behind a pointer/Array receiver (`char*` → i8,
    /// `int[]`/`int*` → i32); i32 when the receiver's type is unknown.
    /// The exact name resolves first — specializations register under their
    /// full names (`Array<int>`), and a nested index on a struct-reference
    /// slot (`outer.Data[0][0]`) must stride by pointer, not by the base
    /// struct's first field. Unregistered names fall back to their base —
    /// only base struct types are registered for abstract receivers.
    fn index_element_type(&self, receiver: &Expression) -> BasicTypeEnum<'ctx> {
        // `outer.Data[0][0]` → resolve the element type from the base
        // receiver's pointee; a nested Index receiver cannot be resolved as
        // a whole by value_sema_type.
        let mut r = receiver;
        while let Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } = r {
            r = lhs;
        }
        let base = self
            .value_sema_type(r)
            .and_then(|ty| ty.strip_suffix('*').map(|s| s.to_string()))
            .or_else(|| self.value_sema_type(receiver).map(|t| t.to_string()));
        let pointee = base.as_deref().and_then(|b| {
            // `void` (opaque) is registered as i32 in the type map, but an
            // opaque pointer indexes at byte granularity — skip it so the
            // lookup falls through to `pointee_llvm_type`.
            if b == "void" {
                return None;
            }
            self.types.get(b).or_else(|| {
                b.split('<')
                    .next()
                    .filter(|n| !n.is_empty())
                    .and_then(|n| self.types.get(n))
            })
        });
        pointee.or_else(|| base.as_deref().map(|b| self.pointee_llvm_type(b)))
            .unwrap_or_else(|| self.context.i32_type().into())
    }

    /// LLVM element type for an indexed receiver's pointee name. `void`
    /// (opaque pointers) indexes at byte granularity; other unresolvable names
    /// fall back to i32, matching the historical behavior of the index arms.
    fn pointee_llvm_type(&self, name: &str) -> BasicTypeEnum<'ctx> {
        if name == "void" {
            return self.context.i8_type().into();
        }
        self.types.get(name).unwrap_or_else(|| self.context.i32_type().into())
    }

    /// Value type of an indexed element: struct elements are stored as
    /// references, so they load and store as pointers while the GEP stride
    /// stays the element type.
    fn index_value_type(&self, receiver: &Expression) -> BasicTypeEnum<'ctx> {
        let elem = self.index_element_type(receiver);
        if matches!(elem, BasicTypeEnum::StructType(_)) {
            return self.context.ptr_type(inkwell::AddressSpace::default()).into();
        }
        elem
    }
    /// Sema type string of an indexed receiver's pointee (`Array<Array<int>>`
    /// → `Array<int>`); the element type for method mangling on a nested-Array
    /// index. Specialized names resolve through their base for struct lookup;
    /// `None` when the receiver's type is unknown.
    fn index_receiver_pointee(&self, receiver: &Expression) -> Option<String> {
        let pointee = self
            .value_sema_type(receiver)
            .and_then(|ty| ty.strip_suffix('*').map(|s| s.to_string()))?;
        if self.types.get(&pointee).is_some() {
            return Some(pointee);
        }
        pointee.split('<').next().filter(|n| !n.is_empty()).map(|s| s.to_string())
    }
    /// For a nested index on a struct-reference slot (`outer.Data[0][i]`),
    /// `slot_ptr` addresses the loaded inner reference; the indexed buffer
    /// lives in its `Data` field. Returns that buffer pointer and the
    /// buffer's element name (the pointee of the `__ptr<T>` Data field, or
    /// the field type itself for non-pointer fields); `None` for plain
    /// (non-nested) receivers, which GEP the raw buffer directly.
    fn nested_index_buffer(
        &self,
        lhs: &Expression,
        slot_ptr: PointerValue<'ctx>,
    ) -> Result<Option<(PointerValue<'ctx>, String)>, String> {
        if !matches!(lhs, Expression::Index { .. } | Expression::ArrayIndex { .. }) {
            return Ok(None);
        }
        let elem = self.index_element_type(lhs);
        // Copy the descriptor data out before returning; no `self` borrow
        // crosses codegen below.
        let (llvm_ty, data_idx, data_name) = match elem {
            BasicTypeEnum::StructType(st) => {
                let desc = self.structs.get(
                    &st
                        .get_name()
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_default(),
                )
                .ok_or_else(|| "nested index on unregistered struct".to_string())?;
                let (idx, name) = desc
                    .fields
                    .iter()
                    .enumerate()
                    .find(|(_, (n, _))| n == "Data")
                    .map(|(i, (_, t))| {
                        // The Data field is a raw pointer buffer (`T*` after
                        // the `__ptr<T>` rewrite): its element is the pointee
                        // (`int`, `Array<int>`, …), which drives the GEP
                        // stride and load/store value type. Non-pointer
                        // fields use their own type name.
                        let elem_name = t.strip_suffix('*').map(str::to_string).unwrap_or_else(|| t.clone());
                        (i, elem_name)
                    })
                    .ok_or_else(|| "nested index: no Data field".to_string())?;
                (desc.llvm_type, idx, name)
            }
            _ => return Err("nested index on non-struct element".to_string()),
        };
        // `slot_ptr` addresses the inner reference; its `Data` field is the
        // raw buffer pointer. GEP the field, then load it to get the buffer.
        let data_addr = self
            .builder
            .build_struct_gep(llvm_ty, slot_ptr, data_idx as u32, "dataf")
            .map_err(|e| e.to_string())?;
        let buffer = self
            .builder
            .build_load(self.context.ptr_type(inkwell::AddressSpace::default()), data_addr, "innerbuf")
            .map_err(|e| e.to_string())?
            .into_pointer_value();
        Ok(Some((buffer, data_name)))
    }
    /// LLVM type of a buffer field's element name for the GEP stride.
    /// Element names are pointees (`int`, `Array<int>`), so they resolve to
    /// their own LLVM type; unresolvable names fall back to i32, matching
    /// the historical behavior of the index arms.
    fn buffer_element_type(&self, name: &str) -> BasicTypeEnum<'ctx> {
        self.pointee_llvm_type(name)
    }
    /// GEP stride for an indexed element. Struct elements are stored as
    /// pointers, so every struct slot is exactly pointer-sized: correctly
    /// aligned for the 8-byte pointer loads/stores and independent of the
    /// struct's own ABI size (which need not be a pointer multiple). Matches
    /// the SizeOf branch below, which sizes the allocation.
    fn slot_stride(&self, elem: BasicTypeEnum<'ctx>) -> BasicTypeEnum<'ctx> {
        if matches!(elem, BasicTypeEnum::StructType(_)) {
            return self.context.ptr_type(inkwell::AddressSpace::default()).into();
        }
        elem
    }
    /// Store a struct-reference value into an Array element slot, applying the
    /// unified shared_ptr `operator=` rule (`store_refcount_ops`). Arrays are
    /// just a collection of individual references, so every store into one
    /// transfers ownership at the store site. Both methods null-guard
    /// themselves, so calling them on zero-initialized slots is safe.
    fn index_refcount_ops(
        &mut self,
        elem_name: &str,
        value_ty: BasicTypeEnum<'ctx>,
        gep: PointerValue<'ctx>,
        new_val: BasicValueEnum<'ctx>,
        source: &Expression,
    ) -> Result<(), String> {
        // The element needs refcount ops only when the buffer's own element
        // type is a struct (before the pointer stride): `__ptr<T>` and scalar
        // buffers hold raw values, so they need none. `elem_name` and
        // `value_ty` are the same values the caller used for the GEP, so this
        // stays in lockstep with it for nested stores (`outer.Data[0][i]`).
        let elem = self.buffer_element_type(elem_name);
        if !matches!(elem, BasicTypeEnum::StructType(_)) {
            return Ok(());
        }
        self.store_refcount_ops(elem_name, gep, value_ty, new_val, source)
    }
    /// Store a struct-reference value into a struct-typed field, applying the
    /// unified shared_ptr `operator=` rule (`store_refcount_ops`). A field is
    /// one reference slot; struct values are references, so the slot holds a
    /// pointer. Both methods null-guard themselves, so storing over a
    /// zero-initialized field is safe.
    fn field_refcount_ops(
        &mut self,
        lhs: &Expression,
        gep: PointerValue<'ctx>,
        new_val: BasicValueEnum<'ctx>,
        source: &Expression,
    ) -> Result<(), String> {
        let field_ty_name = match lhs {
            Expression::MemberRef { lhs, name, .. } => {
                // `codegen_lvalue` already resolved this MemberRef; a miss
                // here means the store target is not a struct field.
                let struct_name = self.struct_name_of(lhs).unwrap_or_default();
                let Some(desc) = self.structs.get(&struct_name) else {
                    return Ok(());
                };
                let Some((_, field_ty_name)) = desc.fields.iter().find(|(n, _)| n == name) else {
                    return Ok(());
                };
                field_ty_name.clone()
            }
            // `this = ...` is not a valid store target.
            _ => return Ok(()),
        };
        let field_ty = self.types.get(&field_ty_name);
        let value_ty = match field_ty {
            Some(BasicTypeEnum::StructType(_)) => {
                BasicTypeEnum::PointerType(self.context.ptr_type(inkwell::AddressSpace::default()))
            }
            _ => return Ok(()),
        };
        self.store_refcount_ops(&field_ty_name, gep, value_ty, new_val, source)
    }

    /// Store a struct-reference value into an existing reference slot: the
    /// same shared_ptr `operator=` rule, one code path for every source kind.
    /// Same pointer as the current occupant (self-assignment in any form) →
    /// no-op; otherwise acquire the new occupant before releasing the old
    /// one, so a genuine store cannot destroy its own value mid-statement.
    /// Both methods null-guard themselves, so zero-initialized slots are
    /// safe. `value_ty` is the slot's LLVM pointee type (pointer for struct
    /// references); `source` is kept for the caller's diagnostics.
    #[allow(unused_variables)]
    fn store_refcount_ops(
        &mut self,
        ty_name: &str,
        gep: PointerValue<'ctx>,
        value_ty: BasicTypeEnum<'ctx>,
        new_val: BasicValueEnum<'ctx>,
        source: &Expression,
    ) -> Result<(), String> {
        let old = self.builder.build_load(value_ty, gep, "oldref").map_err(|e| e.to_string())?;
        let i64 = self.context.i64_type();
        let old_i = self
            .builder
            .build_ptr_to_int(old.into_pointer_value(), i64, "oldi")
            .map_err(|e| e.to_string())?;
        let new_i = self
            .builder
            .build_ptr_to_int(new_val.into_pointer_value(), i64, "newi")
            .map_err(|e| e.to_string())?;
        let same = self
            .builder
            .build_int_compare(inkwell::IntPredicate::EQ, old_i, new_i, "same")
            .map_err(|e| e.to_string())?;
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let ops_block = self.context.append_basic_block(fn_value, "rcops");
        let cont_block = self.context.append_basic_block(fn_value, "cont");
        self.builder
            .build_conditional_branch(same, cont_block, ops_block)
            .map_err(|e| e.to_string())?;
        self.builder.position_at_end(ops_block);
        self.call_function(&format!("{}.{}", ty_name, "__acquire"), vec![new_val])?;
        self.call_function(&format!("{}.{}", ty_name, "__release"), vec![old])?;
        self.builder
            .build_unconditional_branch(cont_block)
            .map_err(|e| e.to_string())?;
        self.builder.position_at_end(cont_block);
        Ok(())
    }
    fn codegen_expr(&mut self, expr: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        let result = self.codegen_expr_unlocated(expr);
        self.locate(&result, expr.loc());
        result
    }

    fn codegen_expr_unlocated(&mut self, expr: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        match expr {
            Expression::BoolLiteral(v) => Ok(BasicValueEnum::IntValue(
                self.context.bool_type().const_int(*v as u64, false),
            )),
            Expression::IntLiteral(v) => {
                // C 6.4.4.1: an integer literal is `int` when it fits in the
                // signed-int range, else `long`. Emitting i32 for int-range
                // literals keeps mixed-type ops on the int path (`ulong * 1`
                // must promote to u64, not force both sides to i64); values
                // outside emit i64 so `long b = 2^40` does not wrap to zero.
                if (i32::MIN as i64) <= *v && *v <= (i32::MAX as i64) {
                    Ok(BasicValueEnum::IntValue(
                        self.context.i32_type().const_int(*v as u64, true),
                    ))
                } else {
                    Ok(BasicValueEnum::IntValue(
                        self.context.i64_type().const_int(*v as u64, true),
                    ))
                }
            }
            Expression::FloatLiteral(v) => Ok(BasicValueEnum::FloatValue(
                self.context.f64_type().const_float(*v),
            )),
            Expression::StringLiteral { value, .. } => {
                if let Some(ptr) = self.global_strings.get(value).copied() {
                    return Ok(BasicValueEnum::PointerValue(ptr));
                }
                let ptr = self
                    .builder
                    .build_global_string_ptr(value, "str")
                    .map_err(|e| e.to_string())?
                    .as_pointer_value();
                self.global_strings.insert(value.clone(), ptr);
                Ok(BasicValueEnum::PointerValue(ptr))
            }
            Expression::PointerLiteral => Ok(BasicValueEnum::PointerValue(
                self.context.ptr_type(inkwell::AddressSpace::default())
                    .const_null(),
            )),
            Expression::SymbolRef { id, .. } => {
                let addr = self
                    .frame
                    .find_local(id)
                    .or_else(|| self.global_addrs.get(id))
                    .ok_or_else(|| format!("use of undeclared identifier '{}'", id))?;
                addr.load(&self.builder)
                    .ok_or_else(|| format!("load failed {}", id))
            }
            Expression::ThisRef => {
                let addr = self
                    .frame
                    .find_local("this")
                    .ok_or_else(|| "no this".to_string())?;
                addr.load(&self.builder)
                    .ok_or_else(|| "load this failed".to_string())
            }
            Expression::MemberRef { lhs, name, .. } => {
                // Load lhs (this pointer), then StructGEP (Struct.cpp:60-70).
                // The struct name comes from the lhs's static type, not the
                // LLVM value (opaque pointers lose the type).
                let struct_name = self.struct_name_of(lhs).unwrap_or_default();
                // An owned-rvalue receiver (`f().x`) is a temporary: its
                // creation ref is released at the end of the full expression,
                // which may still read the field (`f().s == "x"`).
                let lhs_temp = self.owned_temp_type(lhs);
                let this_ptr = self.codegen_expr(lhs)?;
                let base_ptr = match this_ptr {
                    BasicValueEnum::StructValue(_) => self.codegen_lvalue(lhs)?.ptr,
                    _ => this_ptr.into_pointer_value(),
                };
                let desc = self
                    .structs
                    .get(&struct_name)
                    .ok_or_else(|| format!("not a struct: {}", struct_name))?;
                let idx = desc
                    .fields
                    .iter()
                    .position(|(n, _)| n == name)
                    .ok_or_else(|| format!("no member named '{}' in '{}'", name, struct_name))?;
                let field_ty = self
                    .types
                    .get(&desc.fields[idx].1)
                    .ok_or_else(|| format!("unknown field type {}", desc.fields[idx].1))?;
                let gep = unsafe {
                    self.builder
                        .build_struct_gep(desc.llvm_type, base_ptr, idx as u32, name)
                        .map_err(|e| e.to_string())?
                };
                // Struct-typed fields store a reference (the heap object's
                // pointer), exactly like struct locals and params — load the
                // stored pointer, not the slot address.
                let value = match field_ty {
                    BasicTypeEnum::StructType(_) => self
                        .builder
                        .build_load(self.context.ptr_type(inkwell::AddressSpace::default()), gep, name)
                        .map_err(|e| e.to_string())?,
                    _ => self
                        .builder
                        .build_load(field_ty, gep, name)
                        .map_err(|e| e.to_string())?,
                };
                if let Some(ty) = lhs_temp {
                    self.deferred_temps.push((this_ptr, ty));
                }
                Ok(value)
            }
            Expression::Binary { op, lhs, rhs, .. } => self.codegen_binary(op, lhs, rhs),
            Expression::Unary { op, operand, .. } => self.codegen_unary(*op, operand),
            Expression::Cast { expr, ty, .. } => self.codegen_cast(expr, ty),
            Expression::Ternary {
                condition,
                true_expr,
                false_expr,
            } => self.codegen_ternary(condition, true_expr, false_expr),
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                // POD Array indexing.
                let index = self.codegen_expr(rhs)?;
                // An owned-rvalue receiver (`f()[i]`) is a temporary: its
                // creation ref is released at the end of the full expression.
                let lhs_temp = self.owned_temp_type(lhs);
                let slot_ptr = self.codegen_expr(lhs)?.into_pointer_value();
                // A nested index (`outer.Data[0][i]`) GEPs the inner
                // struct's own `Data` buffer (the slot holds its reference);
                // a plain index GEPs the raw buffer directly. The element and
                // value types come from the indexed buffer's field type in
                // both cases.
                let (ptr, elem_name) = match self.nested_index_buffer(lhs, slot_ptr)? {
                    Some((buffer, name)) => (buffer, name),
                    None => (slot_ptr, self.index_receiver_pointee(lhs).unwrap_or_else(|| "i32".to_string())),
                };
                let element_ty = self.slot_stride(self.buffer_element_type(&elem_name));
                // Struct elements are stored as references, so `slot_stride`
                // already mapped them to the pointer value type.
                let value_ty = element_ty;
                let gep = unsafe {
                    self.builder
                        .build_gep(element_ty, ptr, &[index.into_int_value()], "idx")
                        .map_err(|e| e.to_string())?
                };
                let value = self
                    .builder
                    .build_load(value_ty, gep, "loadidx")
                    .map_err(|e| e.to_string())?;
                if let Some(ty) = lhs_temp {
                    self.deferred_temps.push((slot_ptr.into(), ty));
                }
                Ok(value)
            }
            Expression::SizeOf(ty) => {
                let name = ty.to_string();
                if self.structs.contains_key(&name) {
                    // Struct elements are stored as pointers, so a struct's
                    // slot (and its `sizeof`) is exactly pointer-sized,
                    // independent of the struct's own ABI size (matches
                    // `slot_stride`).
                    Ok(BasicValueEnum::IntValue(
                        self.context.i64_type().const_int(std::mem::size_of::<usize>() as u64, false),
                    ))
                } else if let Some(ty) = self.types.get(&name) {
                    // Scalar/pointer ABI size: `AnyType::size_of` is an
                    // unfolded ptrtoint under opaque pointers (None for
                    // scalars); the TargetData measure is authoritative, as
                    // in `instantiate_struct`.
                    let any = ty.as_any_type_enum();
                    let machine = crate::target::host_machine()?;
                    let size = machine.get_target_data().get_abi_size(&any);
                    Ok(BasicValueEnum::IntValue(
                        self.context.i64_type().const_int(size, false),
                    ))
                } else {
                    Err(format!("unknown type in sizeof: {}", name))
                }
            }
            Expression::IsPod(_) => {
                // __is_pod<T>: false for structs (the only corpus use).
                Ok(self.context.bool_type().const_int(0, false).into())
            }
            Expression::Default(ty) => {
                // __default<T>: the type's zero value — 0 for numerics, a null
                // pointer for pointers and struct types (including `String`).
                let name = ty.to_string();
                if let Some(ty) = self.types.get(&name) {
                    let any = match ty {
                        BasicTypeEnum::IntType(it) => it.const_zero().into(),
                        BasicTypeEnum::FloatType(ft) => ft.const_zero().into(),
                        BasicTypeEnum::PointerType(pt) => pt.const_null().into(),
                        BasicTypeEnum::StructType(_) => {
                            self.context.ptr_type(inkwell::AddressSpace::default()).const_null().into()
                        }
                        _ => self.context.i32_type().const_zero().into(),
                    };
                    Ok(any)
                } else {
                    Ok(self.context.i32_type().const_zero().into())
                }
            }
            Expression::RefCount(ty, arg) => {
                // __refcount<T>(t): 0 for POD T; the u32 head field of a
                // struct object (index 0, inserted by sema's apply_synthesized).
                let struct_ty = match self.types.get(&ty.to_string()) {
                    Some(BasicTypeEnum::StructType(sct)) => sct,
                    _ => return Ok(self.context.i32_type().const_int(0, false).into()),
                };
                // An owned-rvalue argument is a temporary: its creation ref
                // is released once the head field is read.
                let arg_temp = self.owned_temp_type(arg);
                let val = self.codegen_expr(arg)?;
                let ptr = match val {
                    BasicValueEnum::PointerValue(p) => p,
                    other => return Err(format!("__refcount expects a pointer, got {:?}", other)),
                };
                let zero = self.context.i32_type().const_int(0, false);
                let ptr_int = self.builder.build_ptr_to_int(ptr, self.context.i64_type(), "rcptr").map_err(|e| e.to_string())?;
                let is_null = self.builder.build_int_compare(inkwell::IntPredicate::EQ, ptr_int, self.context.i64_type().const_int(0, false), "refcount_null").map_err(|e| e.to_string())?;
                // The head-field load must not run on a null pointer: branch
                // first and phi the result (a select over an already-executed
                // load would dereference null).
                let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
                let entry = self.builder.get_insert_block().expect("no insert block");
                let then_block = self.context.append_basic_block(fn_value, "refcount_nonnull");
                let merge_block = self.context.append_basic_block(fn_value, "refcount_merge");
                self.builder.build_conditional_branch(is_null, merge_block, then_block).map_err(|e| e.to_string())?;
                self.builder.position_at_end(then_block);
                let idx0 = self.context.i32_type().const_int(0, false);
                let field = unsafe {
                    self.builder
                        .build_gep(struct_ty, ptr, &[idx0.into()], "refcount")
                        .map_err(|e| e.to_string())?
                };
                let loaded = self.builder.build_load(self.context.i32_type(), field, "refcount_val").map_err(|e| e.to_string())?;
                if let Some(ty) = arg_temp {
                    self.release_temp(&ty, val)?;
                }
                self.builder.build_unconditional_branch(merge_block).map_err(|e| e.to_string())?;
                self.builder.position_at_end(merge_block);
                let phi = self.builder.build_phi(self.context.i32_type(), "__refcount").map_err(|e| e.to_string())?;
                phi.add_incoming(&[(&loaded, then_block), (&BasicValueEnum::IntValue(zero), entry)]);
                Ok(phi.as_basic_value().into_int_value().into())
            }
            Expression::Address(ty, arg) => {
                // __address<T>(v): identity hash — the object's pointer
                // address for struct T (null → seed), the value's own bytes
                // folded FNV-1a for POD T.
                let i64 = self.context.i64_type();
                let seed = i64.const_int(0xcbf29ce484222325, false);
                match self.types.get(&ty.to_string()) {
                    Some(BasicTypeEnum::StructType(_)) => {
                        // An owned-rvalue argument is a temporary: its
                        // creation ref is released once the address is read.
                        let arg_temp = self.owned_temp_type(arg);
                        let val = self.codegen_expr(arg)?;
                        let ptr = match val {
                            BasicValueEnum::PointerValue(p) => p,
                            other => return Err(format!("__address expects a pointer, got {:?}", other)),
                        };
                        let ptr_int = self.builder.build_ptr_to_int(ptr, i64, "addrptr").map_err(|e| e.to_string())?;
                        let is_null = self.builder.build_int_compare(inkwell::IntPredicate::EQ, ptr_int, i64.const_zero(), "addrnul").map_err(|e| e.to_string())?;
                        // Null-guard: branch and phi the result (mirrors `__refcount`).
                        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
                        let entry = self.builder.get_insert_block().expect("no insert block");
                        let then_block = self.context.append_basic_block(fn_value, "addr_nonnull");
                        let merge_block = self.context.append_basic_block(fn_value, "addr_merge");
                        self.builder.build_conditional_branch(is_null, merge_block, then_block).map_err(|e| e.to_string())?;
                        self.builder.position_at_end(then_block);
                        // Fold the address bits through FNV-1a: every
                        // `_pep_malloc` result is pointer-aligned, so a raw
                        // `h & mask` would land all struct keys in bucket 0.
                        let folded = self.fnv_fold_8(seed, &ptr_int)?;
                        if let Some(ty) = arg_temp {
                            self.release_temp(&ty, val)?;
                        }
                        self.builder.build_unconditional_branch(merge_block).map_err(|e| e.to_string())?;
                        self.builder.position_at_end(merge_block);
                        let phi = self.builder.build_phi(i64, "__address").map_err(|e| e.to_string())?;
                        phi.add_incoming(&[(&folded, then_block), (&seed, entry)]);
                        Ok(phi.as_basic_value().into_int_value().into())
                    }
                    Some(_) => {
                        // POD: fold the value's own bytes.
                        let val = self.codegen_expr(arg)?;
                        let v64 = self.hash_value_to_i64(&val)?;
                        Ok(self.fnv_fold_8(seed, &v64)?.into())
                    }
                    None => Err(format!("__address: unknown type {}", ty)),
                }
            }
            Expression::AtomicLoad(ty, arg) => {
                // __atomic_load<T>(p): acquire-ordered load of the slot's
                // T-sized value. Struct T stores a reference pointer; the
                // loaded pointer is an owned ref (shared_ptr copy), so
                // acquire it once. POD/float/pointer T: no ref work.
                let ty_name = ty.to_string();
                // Struct T occupies the slot as a reference pointer; track
                // that before remapping `stored` to the pointer type.
                let is_struct = matches!(self.types.get(&ty_name), Some(BasicTypeEnum::StructType(_)));
                let stored = match self.types.get(&ty_name) {
                    Some(BasicTypeEnum::StructType(_)) => {
                        BasicTypeEnum::PointerType(self.context.ptr_type(inkwell::AddressSpace::default()))
                    }
                    Some(t) => t,
                    None => return Err(format!("__atomic_load: unknown type {}", ty_name)),
                };
                let ptr = match self.codegen_expr(arg)? {
                    BasicValueEnum::PointerValue(p) => p,
                    other => return Err(format!("__atomic_load expects a pointer, got {:?}", other)),
                };
                let loaded = self.builder.build_load(stored, ptr, "atomic_load").map_err(|e| e.to_string())?;
                // inkwell 0.10 exposes no typed-atomic-load builder: set the
                // ordering through the C API directly.
                unsafe {
                    inkwell::llvm_sys::core::LLVMSetOrdering(loaded.as_value_ref(), inkwell::AtomicOrdering::Acquire.into());
                }
                if is_struct {
                    self.acquire_ref(&ty_name, loaded)?;
                }
                Ok(loaded)
            }
            Expression::AtomicStore(ty, arg_ptr, arg_val) => {
                // __atomic_store<T>(p, v): release-ordered store ≡ shared_ptr
                // `operator=`: acquire(v), release(old). Struct T must swap
                // the slot atomically (a plain load of old would race a
                // concurrent store and leak or double-free it), so it uses an
                // atomic xchg on the pointer's i64 bits; POD/float/pointer T
                // has no ref work, so a plain release store suffices.
                let ty_name = ty.to_string();
                // Struct T swaps the slot's reference pointer atomically;
                // track that before remapping `stored` to the pointer type.
                let is_struct = matches!(self.types.get(&ty_name), Some(BasicTypeEnum::StructType(_)));
                let stored = match self.types.get(&ty_name) {
                    Some(BasicTypeEnum::StructType(_)) => {
                        BasicTypeEnum::PointerType(self.context.ptr_type(inkwell::AddressSpace::default()))
                    }
                    Some(t) => t,
                    None => return Err(format!("__atomic_store: unknown type {}", ty_name)),
                };
                let ptr = match self.codegen_expr(arg_ptr)? {
                    BasicValueEnum::PointerValue(p) => p,
                    other => return Err(format!("__atomic_store expects a pointer, got {:?}", other)),
                };
                // Owned-rvalue argument: its creation ref is released once the
                // slot has taken over ownership (the store acquires it below).
                let val_temp = self.owned_temp_type(arg_val);
                let val = self.codegen_expr(arg_val)?;
                if is_struct {
                    self.acquire_ref(&ty_name, val)?;
                    let i64 = self.context.i64_type();
                    // Opaque pointers: no bitcast — go through integer bits.
                    let new_bits = self.builder.build_ptr_to_int(val.into_pointer_value(), i64, "atomic_new").map_err(|e| e.to_string())?;
                    let old_bits = self.builder.build_atomicrmw(inkwell::AtomicRMWBinOp::Xchg, ptr, new_bits, inkwell::AtomicOrdering::Release).map_err(|e| e.to_string())?;
                    let old = self.builder.build_int_to_ptr(old_bits, self.context.ptr_type(inkwell::AddressSpace::default()), "atomic_old").map_err(|e| e.to_string())?;
                    self.release_temp(&ty_name, old.into())?;
                } else {
                    let store = self.builder.build_store(ptr, val).map_err(|e| e.to_string())?;
                    store.set_atomic_ordering(inkwell::AtomicOrdering::Release).map_err(|e| e.to_string())?;
                }
                if let Some(t) = val_temp {
                    self.release_temp(&t, val)?;
                }
                // Void: the value is unused by every consuming context.
                Ok(self.context.i32_type().const_zero().into())
            }
            Expression::AtomicCmpXchg(ty, arg_ptr, arg_expected, arg_desired) => {
                // __atomic_cmpxchg<T>(p, expected, desired): acquire/release
                // compare-and-exchange; returns success as i1. On success the
                // slot now owns `desired` (acquire it) and drops `old`
                // (release it); on failure nothing is released — both args
                // remain owned by their callers.
                let ty_name = ty.to_string();
                // Struct T compares the slot's reference pointer; track that
                // before remapping `stored` to the pointer type.
                let is_struct = matches!(self.types.get(&ty_name), Some(BasicTypeEnum::StructType(_)));
                let stored = match self.types.get(&ty_name) {
                    Some(BasicTypeEnum::StructType(_)) => {
                        BasicTypeEnum::PointerType(self.context.ptr_type(inkwell::AddressSpace::default()))
                    }
                    Some(t) => t,
                    None => return Err(format!("__atomic_cmpxchg: unknown type {}", ty_name)),
                };
                let ptr = match self.codegen_expr(arg_ptr)? {
                    BasicValueEnum::PointerValue(p) => p,
                    other => return Err(format!("__atomic_cmpxchg expects a pointer, got {:?}", other)),
                };
                let mut expected = self.codegen_expr(arg_expected)?;
                let mut desired = self.codegen_expr(arg_desired)?;
                // cmpxchg only accepts integers and pointers: bitcast floats.
                match stored {
                    BasicTypeEnum::FloatType(ft) => {
                        let int_ty = match ft.get_bit_width() {
                            32 => self.context.i32_type(),
                            64 => self.context.i64_type(),
                            w => return Err(format!("__atomic_cmpxchg: unsupported float width {}", w)),
                        };
                        expected = self.builder.build_bit_cast(expected, int_ty, "cas_e").map_err(|e| e.to_string())?;
                        desired = self.builder.build_bit_cast(desired, int_ty, "cas_d").map_err(|e| e.to_string())?;
                    }
                    _ => {}
                }
                let res = self
                    .builder
                    .build_cmpxchg(ptr, expected, desired, inkwell::AtomicOrdering::AcquireRelease, inkwell::AtomicOrdering::Monotonic)
                    .map_err(|e| e.to_string())?;
                // `get_field_at_index` is broken for instruction results in
                // inkwell 0.10 — extract via instructions instead.
                let success = self.builder.build_extract_value(res, 1, "cas_ok").map_err(|e| e.to_string())?.into_int_value();
                if is_struct {
                    // Success only: the slot now owns `desired` and drops
                    // `old`; failure leaves every ref where it was.
                    let old = self.builder.build_extract_value(res, 0, "cas_old").map_err(|e| e.to_string())?;
                    let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
                    let then_block = self.context.append_basic_block(fn_value, "cas_ok");
                    let merge_block = self.context.append_basic_block(fn_value, "cas_merge");
                    self.builder.build_conditional_branch(success, then_block, merge_block).map_err(|e| e.to_string())?;
                    self.builder.position_at_end(then_block);
                    self.acquire_ref(&ty_name, desired)?;
                    self.release_temp(&ty_name, old)?;
                    self.builder.build_unconditional_branch(merge_block).map_err(|e| e.to_string())?;
                    self.builder.position_at_end(merge_block);
                }
                Ok(success.into())
            }
            Expression::AtomicFetch(op, ty, arg_ptr, arg_val) => {
                // __atomic_fetch_{add,sub,and,or,xor}<T>(p, v): acquire/release
                // atomic read-modify-write on the T-sized value at pointer p;
                // returns the previous slot occupant. Integer T only (the
                // runtime restricts fetch_* to numeric types), so no ref work:
                // the old value is a plain integer, not an owned reference.
                let ty_name = ty.to_string();
                let stored = match self.types.get(&ty_name) {
                    Some(BasicTypeEnum::IntType(it)) => it,
                    _ => {
                        // Non-integer T: the fetch operations are undefined
                        // (as in C++'s std::atomic<T>::fetch_add for a
                        // non-arithmetic T). Emit an abort — unreachable at
                        // runtime; the constant return keeps the IR valid.
                        let dummy = match self.types.get(&ty_name) {
                            Some(BasicTypeEnum::StructType(_)) => {
                                BasicValueEnum::PointerValue(
                                    self.context.ptr_type(inkwell::AddressSpace::default()).const_null(),
                                )
                            }
                            Some(BasicTypeEnum::FloatType(ft)) => {
                                BasicValueEnum::FloatValue(ft.const_zero())
                            }
                            _ => BasicValueEnum::IntValue(self.context.i64_type().const_zero()),
                        };
                        self.call_function("abort", vec![])?;
                        return Ok(dummy);
                    }
                };
                let ptr = match self.codegen_expr(arg_ptr)? {
                    BasicValueEnum::PointerValue(p) => p,
                    other => return Err(format!("__atomic_fetch expects a pointer, got {:?}", other)),
                };
                // Owned-rvalue argument: released once the RMW has consumed it.
                let val_temp = self.owned_temp_type(arg_val);
                let val = match self.codegen_expr(arg_val)? {
                    BasicValueEnum::IntValue(v) => v,
                    other => return Err(format!("__atomic_fetch expects an integer, got {:?}", other)),
                };
                // Match the slot's width (i32 int vs i64 long operands).
                let val = if val.get_type() != stored {
                    self.builder
                        .build_int_cast(val, stored, "fetchv")
                        .map_err(|e| e.to_string())?
                } else {
                    val
                };
                let rmw_op = match op {
                    pepper_sema::model::AtomicFetchOp::Add => inkwell::AtomicRMWBinOp::Add,
                    pepper_sema::model::AtomicFetchOp::Sub => inkwell::AtomicRMWBinOp::Sub,
                    pepper_sema::model::AtomicFetchOp::And => inkwell::AtomicRMWBinOp::And,
                    pepper_sema::model::AtomicFetchOp::Or => inkwell::AtomicRMWBinOp::Or,
                    pepper_sema::model::AtomicFetchOp::Xor => inkwell::AtomicRMWBinOp::Xor,
                };
                let old = self
                    .builder
                    .build_atomicrmw(rmw_op, ptr, val, inkwell::AtomicOrdering::AcquireRelease)
                    .map_err(|e| e.to_string())?;
                if let Some(t) = val_temp {
                    self.release_temp(&t, BasicValueEnum::IntValue(val))?;
                }
                Ok(old.into())
            }
            Expression::FunctionCall {
                function: name,
                args, ..
            } => self.codegen_call(name, args),
            // Only a var default in well-formed models (codegen_var_def).
            Expression::ForIterator(source) => {
                let iterator = self.for_loop_iterator(source)?;
                self.codegen_expr(&iterator)
            }
            Expression::MethodCall { this, method, args, .. } => {
                // Receiver is a buffer slot (`Data[i]`): GEP the element out
                // of the raw buffer. Indexer methods are the exception — they
                // address the pointee's own data (`s[0]` on `String s`), so
                // they dispatch to the pointee when it declares them.
                if matches!(this.as_ref(), Expression::Index { .. } | Expression::ArrayIndex { .. }) {
                    let lhs = match this.as_ref() {
                        Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } => {
                            lhs.as_ref()
                        }
                        _ => unreachable!(),
                    };
                    let pointee = self.index_element_type(lhs);
                    let pointee_struct = match pointee {
                        BasicTypeEnum::StructType(st) => st
                            .get_name()
                            .map(|s| s.to_string_lossy().into_owned())
                            .unwrap_or_default(),
                        _ => String::new(),
                    };
                    let pointee_declares = self
                        .structs
                        .get(&pointee_struct)
                        .map(|d| d.methods.contains_key(method))
                        .unwrap_or(false);
                    if method.starts_with("__index_") || !pointee_declares {
                        return self.codegen_index_method(this, method, args);
                    }
                    // Load the slot value with the correct element type —
                    // the Index arm GEPs + loads using the receiver's pointee.
                    let elem_val = self.codegen_expr(this)?;
                    let is_static = self
                        .structs
                        .get(&pointee_struct)
                        .map(|d| d.static_methods.contains(method.as_str()))
                        .unwrap_or(false);
                    let mangled = format!("{}.{}", pointee_struct, method);
                    let mut arg_vals = if is_static { vec![] } else { vec![elem_val] };
                    let mut arg_names: Vec<String> = if is_static { vec![] } else { vec![String::new()] };
                    // Owned-rvalue arguments are temporaries (shared_ptr): their
                    // creation ref is released after the call, at the end of the
                    // full expression. Lvalue reads are not — the callee's param
                    // entry owns them.
                    let mut owned_arg_temps: Vec<(BasicValueEnum<'ctx>, String)> = Vec::new();
                    for arg in args {
                        let v = self.codegen_expr(arg)?;
                        if let Some(ty) = self.owned_temp_type(arg) {
                            owned_arg_temps.push((v, ty));
                        }
                        arg_names.push(self.numeric_source_name(arg, &v));
                        arg_vals.push(v);
                    }
                    for extra in self.missing_args(&mangled, args.len())? {
                        let v = self.codegen_expr(&extra)?;
                        arg_names.push(self.numeric_source_name(&extra, &v));
                        arg_vals.push(v);
                    }
                    let result = self.call_function_typed(&mangled, arg_vals, &arg_names)?;
                    for (temp, ty) in owned_arg_temps {
                        self.release_temp(&ty, temp)?;
                    }
                    return Ok(result);
                }
                // Mangle: `<StructOf(this)>.<method>`. The struct name comes
                // from the receiver's static type; non-struct receivers fall
                // back to the method name as-is (Array index methods resolve
                let struct_name = self.struct_name_of(this.as_ref()).unwrap_or_default();
                if method.starts_with("__index_") {
                    // POD Array index set/get: direct GEP + load/store — but
                    // only when the receiver's struct declares the indexer
                    // and the receiver is not itself a pointer. A pointer
                    // receiver (raw buffer field like `Data` on
                    // `Array<Array<int>>`) must GEP the slot; dispatching
                    // would call the pointee's indexer on the element's own
                    // data.
                    let receiver_is_ptr = self
                        .value_sema_type(this)
                        .is_some_and(|ty| ty.ends_with('*'));
                    let has_indexer = !receiver_is_ptr
                        && self
                            .structs
                            .get(&struct_name)
                            .map(|d| d.methods.contains_key(method))
                            .unwrap_or(false);
                    if !has_indexer {
                        return self.codegen_index_method(this, method, args);
                    }
                }
                // The receiver is the instance pointer: loading the lhs gives
                // exactly what the `this` parameter expects. When the receiver
                // itself is an owned rvalue (`f().g()`), it is a temporary
                // whose creation ref we release after the call. A static call
                // on a type literal (`Result<int>.ok(5)`) lowers its receiver
                // to a ctor-style call that must NOT run — no instance exists.
                let mangled = format!("{}.{}", struct_name, method);
                let is_static = self
                    .structs
                    .get(&struct_name)
                    .map(|d| d.static_methods.contains(method.as_str()))
                    .unwrap_or(false);
                let this_temp = if is_static { None } else { self.owned_temp_type(this.as_ref()) };
                let mut arg_vals: Vec<BasicValueEnum<'ctx>> = vec![];
                let mut arg_names: Vec<String> = vec![];
                let mut this_val_opt: Option<BasicValueEnum<'ctx>> = None;
                if !is_static {
                    let this_val = self.codegen_expr(this)?;
                    this_val_opt = Some(this_val);
                    arg_vals.push(this_val);
                    arg_names.push(String::new());
                }
                // Owned-rvalue arguments are temporaries (shared_ptr): their
                // creation ref is released after the call, at the end of the
                // full expression. Lvalue reads are not — the callee's param
                // entry owns them.
                let mut owned_arg_temps: Vec<(BasicValueEnum<'ctx>, String)> = Vec::new();
                for arg in args {
                    let v = self.codegen_expr(arg)?;
                    if let Some(ty) = self.owned_temp_type(arg) {
                        owned_arg_temps.push((v, ty));
                    }
                    arg_names.push(self.numeric_source_name(arg, &v));
                    arg_vals.push(v);
                }
                for extra in self.missing_args(&mangled, args.len())? {
                    let v = self.codegen_expr(&extra)?;
                    arg_names.push(self.numeric_source_name(&extra, &v));
                    arg_vals.push(v);
                }
                let result = self.call_function_typed(&mangled, arg_vals, &arg_names)?;
                if let (Some(ty), Some(this_val)) = (this_temp, this_val_opt) {
                    self.release_temp(&ty, this_val)?;
                }
                for (temp, ty) in owned_arg_temps {
                    self.release_temp(&ty, temp)?;
                }
                Ok(result)
            }
        }
    }
    /// FNV-1a fold of one i64's eight bytes (memory order) into `h`.
    fn fnv_fold_8(&mut self, mut h: inkwell::values::IntValue<'ctx>, v: &inkwell::values::IntValue<'ctx>) -> Result<inkwell::values::IntValue<'ctx>, String> {
        let i64 = self.context.i64_type();
        let prime = i64.const_int(0x100000001b3, false);
        for shift in [0u64, 8, 16, 24, 32, 40, 48, 56] {
            let byte = self.builder.build_right_shift(*v, i64.const_int(shift, false), false, "hfsh").map_err(|e| e.to_string())?;
            let masked = self.builder.build_and(byte, i64.const_int(0xff, false), "hfb").map_err(|e| e.to_string())?;
            h = self.builder.build_xor(h, masked, "hfx").map_err(|e| e.to_string())?;
            h = self.builder.build_int_mul(h, prime, "hfm").map_err(|e| e.to_string())?;
        }
        Ok(h)
    }

    /// A loaded field's value as i64: ints zext/trunc, floats bitcast,
    /// pointers ptrtoint (identity).
    fn hash_value_to_i64(&mut self, val: &BasicValueEnum<'ctx>) -> Result<inkwell::values::IntValue<'ctx>, String> {
        let i64 = self.context.i64_type();
        match val {
            BasicValueEnum::IntValue(iv) => {
                if iv.get_type().get_bit_width() == 64 {
                    Ok(*iv)
                } else if iv.get_type().get_bit_width() > 64 {
                    Ok(self.builder.build_int_truncate(*iv, i64, "hft").map_err(|e| e.to_string())?)
                } else {
                    Ok(self.builder.build_int_z_extend(*iv, i64, "hfz").map_err(|e| e.to_string())?)
                }
            }
            BasicValueEnum::FloatValue(fv) => {
                let bits = if fv.get_type().get_bit_width() == 64 {
                    self.builder.build_bit_cast(*fv, i64, "hfbits").map_err(|e| e.to_string())?
                } else {
                    let ext = self.builder.build_float_ext(*fv, self.context.f64_type(), "hfext").map_err(|e| e.to_string())?;
                    self.builder.build_bit_cast(ext, i64, "hfbits").map_err(|e| e.to_string())?
                };
                Ok(bits.into_int_value())
            }
            BasicValueEnum::PointerValue(pv) => Ok(self.builder.build_ptr_to_int(*pv, i64, "hfptri").map_err(|e| e.to_string())?),
            other => Err(format!("__address: cannot fold {:?}", other)),
        }
    }
    /// POD Array index get/set: `arr[i]` → load via GEP, `arr[i] = v` →
    /// store via GEP.
    fn codegen_index_method(
        &mut self,
        this: &Expression,
        method: &str,
        args: &[Expression],
    ) -> Result<BasicValueEnum<'ctx>, String> {
        let element_ty = self.slot_stride(self.index_element_type(this));
        let value_ty = self.index_value_type(this);
        let base = self.codegen_expr(this)?;
        let ptr = match base {
            BasicValueEnum::PointerValue(p) => p,
            BasicValueEnum::StructValue(_) => {
                return Err("index method on struct value".to_string())
            }
            _ => return Err("index method on non-pointer".to_string()),
        };
        let index_expr = args.first().ok_or_else(|| "index needs an index".to_string())?;
        let index = self.codegen_expr(index_expr)?;
        let gep = unsafe {
            self.builder
                .build_gep(element_ty, ptr, &[index.into_int_value()], "idxm")
                .map_err(|e| e.to_string())?
        };
        if method == "__index_get" {
            self.builder
                .build_load(value_ty, gep, "loadidx")
                .map_err(|e| e.to_string())
        } else {
            // __index_set: the value is args[1]. An owned-rvalue value is a
            // temporary — the slot store acquires its own ref for the new
            // occupant, so the temp's creation ref is released after the
            // store.
            let value_expr = args.get(1).ok_or_else(|| "index set needs a value".to_string())?;
            let value_temp = self.owned_temp_type(value_expr);
            let mut value = self.codegen_expr(value_expr)?;
            if let (BasicTypeEnum::IntType(target), BasicValueEnum::IntValue(iv)) =
                (value_ty, &value)
            {
                if iv.get_type().get_bit_width() > target.get_bit_width() {
                    value = match self.builder.build_int_truncate(*iv, target, "narrow") {
                        Ok(t) => BasicValueEnum::IntValue(t),
                        Err(_) => value,
                    };
                }
            }
            self.index_refcount_ops(&self.index_receiver_pointee(this).unwrap_or_else(|| "i32".to_string()), value_ty, gep, value, value_expr)?;
            if let Some(ty) = value_temp {
                self.release_temp(&ty, value)?;
            }
            self.builder
                .build_store(gep, value)
                .map_err(|e| e.to_string())?;
            Ok(value)
        }
    }

    fn codegen_call(&mut self, name: &str, args: &[Expression]) -> Result<BasicValueEnum<'ctx>, String> {
        // Builtins first: print → _pep_print/_pep_print_int.
        if name == "print" {
            return self.codegen_print(args);
        }
        // assert(condition, msg): the message is a raw `char*`. A String
        // literal (already rewritten by convert_string_literals into a
        // `String(raw, size, len)` ctor call) lowers to its global pointer —
        // no temporary allocation on hot paths like index bounds checks.
        // Any other expression is lowered to `msg.c_str()`.
        if name == "assert" && args.len() == 2 {
            let cond = self.codegen_expr(&args[0])?;
            // An owned-rvalue message (e.g. a `String` rvalue) is a temporary:
            // it must live until `assert` returns, then its creation ref is
            // released. A raw literal lowers to a global pointer — not an
            // owned value — so it carries no temp.
            let (msg_value, already_ptr, msg_temp) = match &args[1] {
                Expression::FunctionCall { function, args: inner, .. }
                    if function == "String"
                        && matches!(
                            inner.first(),
                            Some(Expression::StringLiteral { is_raw: true, .. })
                        ) =>
                {
                    (self.codegen_expr(inner.first().unwrap())?, true, None)
                }
                other => {
                    let v = self.codegen_expr(other)?;
                    // The message must be a `char*`: an argument already typed
                    // as a pointer (`char*`, `__ptr<T>`) is passed through,
                    // everything else (notably `String`) lowers via `c_str`.
                    let ptr = self
                        .value_sema_type(other)
                        .is_some_and(|ty| ty.ends_with('*') || ty.starts_with("__ptr<"));
                    (v, ptr, self.owned_temp_type(other))
                }
            };
            let msg = if already_ptr {
                msg_value
            } else {
                self.call_function("String.c_str", vec![msg_value])?
            };
            let result = self.call_function("assert", vec![cond, msg])?;
            if let Some(ty) = msg_temp {
                self.release_temp(&ty, msg_value)?;
            }
            return Ok(result);
        }
        // release<T>(v): no-op for POD values (nothing to free), dispatches
        // to T.__release for struct references.
        if name == "release" || name.starts_with("release<") {
            let value = args.first().map(|a| self.codegen_expr(a)).transpose()?;
            if let (Some(v), Some(parsed)) =
                (value, name.strip_prefix("release<").and_then(|s| s.strip_suffix('>')))
            {
                let parsed = pepper_sema::passes::gather_generics::parse_type_string(parsed);
                let is_struct = matches!(self.types.get(&parsed.to_string()), Some(BasicTypeEnum::StructType(_)));
                if is_struct {
                    return self.call_function(&format!("{}.__release", parsed), vec![v]);
                }
            }
            return Ok(value.unwrap_or_else(|| self.context.i32_type().const_zero().into()));
        }
        // Intrinsics: __is_pod<T> → false for structs (true for POD);
        // __default<T> → the type's zero value.
        if name == "__is_pod" {
            return Ok(self.context.bool_type().const_int(0, false).into());
        }
        if name == "__default" || name.starts_with("__default<") {
            let parsed = pepper_sema::passes::gather_generics::parse_type_string(name);
            let inner = match parsed.sub_types.into_iter().next() {
                Some(inner) => inner,
                None => TypeName::new(&parsed.name),
            };
            if let Some(ty) = self.types.get(&inner.to_string()) {
                let any = match ty {
                    BasicTypeEnum::IntType(it) => it.const_zero().into(),
                    BasicTypeEnum::FloatType(ft) => ft.const_zero().into(),
                    BasicTypeEnum::PointerType(pt) => pt.const_null().into(),
                    BasicTypeEnum::StructType(_) => {
                        self.context.ptr_type(inkwell::AddressSpace::default()).const_null().into()
                    }
                    _ => self.context.i32_type().const_zero().into(),
                };
                return Ok(any);
            }
            return Ok(self.context.i32_type().const_zero().into());
        }
        // Constructor call `Name<...>(ctor_args)`: specializations are
        // registered under their full name (`Array<int>`); fall back to the
        // base name for non-generic ctors.
        let target = if self.functions.contains_key(name) {
            name.to_string()
        } else {
            name.split('<').next().unwrap_or(name).trim().to_string()
        };
        // Owned-rvalue arguments are temporaries (shared_ptr): their creation
        // ref is released after the call, at the end of the full expression.
        // Lvalue reads are not — the callee's param entry owns them.
        let mut owned_arg_temps: Vec<(BasicValueEnum<'ctx>, String)> = Vec::new();
        let mut arg_vals = vec![];
        let mut arg_names: Vec<String> = vec![];
        let is_extern = self.extern_names.contains(&target);
        for arg in args {
            // A string literal passed to a C function is its NUL-terminated
            // global (`puts("hi")`, `getenv("HOME")`), exactly as for
            // `assert`'s message; convert_string_literals made it a
            // `String(raw, size, len)` ctor call, whose String object C
            // would read as garbage.
            if is_extern {
                if let Expression::FunctionCall { function, args: inner, .. } = arg {
                    if let (true, Some(raw @ Expression::StringLiteral { is_raw: true, .. })) =
                        (function == "String", inner.first())
                    {
                        let v = self.codegen_expr(raw)?;
                        arg_names.push(String::new());
                        arg_vals.push(v);
                        continue;
                    }
                }
            }
            let v = self.codegen_expr(arg)?;
            if let Some(ty) = self.owned_temp_type(arg) {
                owned_arg_temps.push((v, ty));
            }
            arg_names.push(self.numeric_source_name(arg, &v));
            arg_vals.push(v);
        }
        for extra in self.missing_args(&target, args.len())? {
            let v = self.codegen_expr(&extra)?;
            arg_names.push(self.numeric_source_name(&extra, &v));
            arg_vals.push(v);
        }
        let result = self.call_function_typed(&target, arg_vals, &arg_names)?;
        for (temp, ty) in owned_arg_temps {
            self.release_temp(&ty, temp)?;
        }
        Ok(result)
    }

    fn codegen_print(&mut self, args: &[Expression]) -> Result<BasicValueEnum<'ctx>, String> {
        for arg in args {
            // An owned-rvalue argument is a temporary: released once the
            // print call has consumed it.
            let value_temp = self.owned_temp_type(arg);
            let value = self.codegen_expr(arg)?;
            match value {
                BasicValueEnum::PointerValue(_) => {
                    self.call_function("_pep_print", vec![value])?;
                }
                BasicValueEnum::IntValue(v) => {
                    // Unsigned (and bool) sources widen zero-extended, or a
                    // u16 65535 prints as -1.
                    let unsigned = v.get_type().get_bit_width() == 1
                        || self
                            .value_sema_type(arg)
                            .is_some_and(|s| llvm_ops::is_unsigned_int_type(&s));
                    let wide = if v.get_type().get_bit_width() < 64 && unsigned {
                        self.builder
                            .build_int_z_extend(v, self.context.i64_type(), "printw")
                            .map_err(|e| e.to_string())?
                    } else if v.get_type().get_bit_width() < 64 {
                        self.builder
                            .build_int_s_extend(v, self.context.i64_type(), "printw")
                            .map_err(|e| e.to_string())?
                    } else {
                        v
                    };
                    self.call_function("_pep_print_int", vec![BasicValueEnum::IntValue(wide)])?;
                }
                BasicValueEnum::FloatValue(v) => {
                    let double = self
                        .builder
                        .build_float_cast(v, self.context.f64_type(), "printf64")
                        .map_err(|e| e.to_string())?;
                    self.call_function("_pep_print_float", vec![BasicValueEnum::FloatValue(double)])?;
                }
                _ => return Err("unsupported print arg".to_string()),
            }
            if let Some(ty) = value_temp {
                self.release_temp(&ty, value)?;
            }
        }
        Ok(self.context.i32_type().const_zero().into())
    }

    /// Default-argument expressions for the parameters a call did not supply.
    fn missing_args(&self, target: &str, provided: usize) -> Result<Vec<Expression>, String> {
        let Some(defaults) = self.param_defaults.get(target) else {
            // Unknown names are not an error here: call_function declares
            // support-library externs (_pep_malloc, …) on demand.
            return Ok(vec![]);
        };
        // Parameters from the last one without a default on are optional.
        let required = defaults.iter().rposition(Option::is_none).map_or(0, |i| i + 1);
        let expected = |bound: &str, n: usize| {
            if required == defaults.len() { n.to_string() } else { format!("{} {}", bound, n) }
        };
        if provided > defaults.len() {
            return Err(format!(
                "too many arguments to '{}': expected {}, have {}",
                target,
                expected("at most", defaults.len()),
                provided
            ));
        }
        if provided < required {
            return Err(format!(
                "too few arguments to '{}': expected {}, have {}",
                target,
                expected("at least", required),
                provided
            ));
        }
        Ok(defaults[provided..].iter().map(|d| d.clone().expect("trailing parameters have defaults")).collect())
    }

    fn call_function(
        &mut self,
        name: &str,
        args: Vec<BasicValueEnum<'ctx>>,
    ) -> Result<BasicValueEnum<'ctx>, String> {
        self.call_function_typed(name, args, &[])
    }

    /// `call_function` with the sema type names of (a prefix of) the
    /// arguments, so integer arguments widen by their own signedness (a
    /// `u16` passed to a `long` parameter zero-extends).
    fn call_function_typed(
        &mut self,
        name: &str,
        args: Vec<BasicValueEnum<'ctx>>,
        arg_names: &[String],
    ) -> Result<BasicValueEnum<'ctx>, String> {
        let fn_value = match self.functions.get(name) {
            Some(f) => *f,
            None => {
                return Err(match name.split_once('.') {
                    Some((owner, member)) => format!("no member named '{}' in '{}'", member, owner),
                    None => format!("call to undeclared function '{}'", name),
                })
            }
        };
        // Coerce args to the declared param types (e.g. i32 refcount → i64
        // for trace_int).
        let mut coerced: Vec<BasicValueEnum<'ctx>> = vec![];
        for (idx, arg) in args.iter().enumerate() {
            let param_ty: Option<BasicTypeEnum<'ctx>> = fn_value
                .get_type()
                .get_param_types()
                .get(idx)
                .and_then(|m| match m {
                    inkwell::types::BasicMetadataTypeEnum::IntType(it) => {
                        Some(BasicTypeEnum::IntType(*it))
                    }
                    inkwell::types::BasicMetadataTypeEnum::FloatType(ft) => {
                        Some(BasicTypeEnum::FloatType(*ft))
                    }
                    inkwell::types::BasicMetadataTypeEnum::PointerType(pt) => {
                        Some(BasicTypeEnum::PointerType(*pt))
                    }
                    _ => None,
                });
            let coerced_val: BasicValueEnum<'ctx> = match (param_ty, arg) {
                (
                    Some(BasicTypeEnum::IntType(it)),
                    BasicValueEnum::IntValue(v),
                ) => {
                    let unsigned = v.get_type().get_bit_width() == 1
                        || arg_names.get(idx).is_some_and(|n| llvm_ops::is_unsigned_int_type(n));
                    if it.get_bit_width() > v.get_type().get_bit_width() && unsigned {
                        BasicValueEnum::IntValue(
                            self.builder
                                .build_int_z_extend(*v, it, "argw")
                                .unwrap_or(*v),
                        )
                    } else if it.get_bit_width() > v.get_type().get_bit_width() {
                        BasicValueEnum::IntValue(
                            self.builder
                                .build_int_s_extend(*v, it, "argw")
                                .unwrap_or(*v),
                        )
                    } else if it.get_bit_width() < v.get_type().get_bit_width() {
                        BasicValueEnum::IntValue(
                            self.builder
                                .build_int_truncate(*v, it, "argt")
                                .unwrap_or(*v),
                        )
                    } else {
                        *arg
                    }
                }
                (Some(BasicTypeEnum::IntType(_)), BasicValueEnum::PointerValue(_)) => *arg,
                // int -> float parameter converts the value (C 6.3.1.4)
                // instead of passing the integer bits.
                (Some(BasicTypeEnum::FloatType(ft)), BasicValueEnum::IntValue(v)) => {
                    let unsigned = v.get_type().get_bit_width() == 1
                        || arg_names.get(idx).is_some_and(|n| llvm_ops::is_unsigned_int_type(n));
                    let converted = if unsigned {
                        self.builder.build_unsigned_int_to_float(*v, ft, "argf")
                    } else {
                        self.builder.build_signed_int_to_float(*v, ft, "argf")
                    };
                    converted.map(BasicValueEnum::FloatValue).unwrap_or(*arg)
                }
                (Some(BasicTypeEnum::FloatType(ft)), BasicValueEnum::FloatValue(v)) if v.get_type() != ft => {
                    let converted = if v.get_type().get_bit_width() < ft.get_bit_width() {
                        self.builder.build_float_ext(*v, ft, "argf")
                    } else {
                        self.builder.build_float_trunc(*v, ft, "argf")
                    };
                    converted.map(BasicValueEnum::FloatValue).unwrap_or(*arg)
                }
                // An argument in a variadic extern's `...` has no declared
                // type: C's default argument promotions apply (6.5.2.2p7),
                // so integers narrower than int widen to int by their own
                // signedness and float widens to double.
                (None, BasicValueEnum::IntValue(v))
                    if fn_value.get_type().is_var_arg() && v.get_type().get_bit_width() < 32 =>
                {
                    let i32t = self.context.i32_type();
                    let unsigned = v.get_type().get_bit_width() == 1
                        || arg_names.get(idx).is_some_and(|n| llvm_ops::is_unsigned_int_type(n));
                    let widened = if unsigned {
                        self.builder.build_int_z_extend(*v, i32t, "vararg")
                    } else {
                        self.builder.build_int_s_extend(*v, i32t, "vararg")
                    };
                    widened.map(BasicValueEnum::IntValue).unwrap_or(*arg)
                }
                (None, BasicValueEnum::FloatValue(v))
                    if fn_value.get_type().is_var_arg() && v.get_type().get_bit_width() < 64 =>
                {
                    self.builder
                        .build_float_ext(*v, self.context.f64_type(), "vararg")
                        .map(BasicValueEnum::FloatValue)
                        .unwrap_or(*arg)
                }
                _ => *arg,
            };
            coerced.push(coerced_val);
        }
        let meta_args: Vec<inkwell::values::BasicMetadataValueEnum<'ctx>> =
            coerced.iter().map(|a| (*a).into()).collect();
        let call = self
            .builder
            .build_call(fn_value, &meta_args, "call")
            .map_err(|e| e.to_string())?;
        Ok(call
            .try_as_basic_value()
            .basic()
            .unwrap_or_else(|| self.context.i32_type().const_zero().into()))
    }

    fn codegen_binary(
        &mut self,
        op: &BinaryOp,
        lhs: &Expression,
        rhs: &Expression,
    ) -> Result<BasicValueEnum<'ctx>, String> {
        // Assignment: store into the lhs address (OperatorGen.cpp:155-180).
        if op.is_assignment() {
            // An owned-rvalue rhs (e.g. `a[i] = f()`) is a temporary: the
            // slot store acquires its own ref for the new occupant, so the
            // temp's creation ref is released after the store.
            let rhs_temp = self.owned_temp_type(rhs);
            let rhs_val = self.codegen_expr(rhs)?;
            let lhs_addr = self.codegen_lvalue(lhs)?;
            let lhs_ty = lhs_addr.ty.clone();
            // The sema names carry signedness (`u8` vs `i8`) — LLVM value
            // names flatten both to i8, which would sext a u8 200 to -56.
            let rhs_name = self.value_sema_type(rhs).unwrap_or_else(|| value_type_name(&rhs_val));
            let coerced = llvm_ops::coerce(
                self.context,
                &self.builder,
                rhs_val,
                &rhs_name,
                &lhs_ty,
            );
            // The sema type name can be a pointer (`__ptr<char>` → i32 in
            // coerce) while the address's LLVM pointee is narrower (i8);
            // narrow to it so `Data[Size] = 0` stores one byte, not four.
            let fit = |v: BasicValueEnum<'ctx>| -> BasicValueEnum<'ctx> {
                if let (Some(BasicTypeEnum::IntType(target)), BasicValueEnum::IntValue(iv)) =
                    (&lhs_addr.llvm_ty, &v)
                {
                    if iv.get_type().get_bit_width() > target.get_bit_width() {
                        return match self.builder.build_int_truncate(*iv, *target, "narrow") {
                            Ok(t) => BasicValueEnum::IntValue(t),
                            Err(_) => v,
                        };
                    }
                }
                v
            };
            let coerced = fit(coerced);
            // Compound assign: load lhs, apply the base op, store.
            if let Some(base_op) = op.base_assign_op() {
                let lhs_val = lhs_addr
                    .load(&self.builder)
                    .ok_or_else(|| "compound lhs load".to_string())?;
                let lhs_name = self.value_sema_type(lhs).unwrap_or_else(|| value_type_name(&lhs_val));
                // C: `x op= e` is `x = x op e` — the op runs on the usual
                // conversion of (lhs type, rhs type), so feed the unconverted
                // rhs (`int += 2.5` adds at f64; `u8 += 200` wraps at int).
                let rhs_name = self.value_sema_type(rhs).unwrap_or_else(|| value_type_name(&rhs_val));
                let result_ty = binary_result_type(&base_op, &lhs_name, &rhs_name);
                let lhs_c = llvm_ops::coerce(self.context, &self.builder, lhs_val, &lhs_name, &result_ty);
                let rhs_c = llvm_ops::coerce(self.context, &self.builder, rhs_val, &rhs_name, &result_ty);
                let result = apply_op(self.context, &self.builder, base_op, lhs_c, rhs_c, &result_ty, None, None)?;
                // C: `x op= e` converts the converted operands to the usual
                // conversion type (e.g. `int += 2.5` adds at f64), then the
                // result is converted back to the lhs's type for the store.
                let lhs_sema = self.value_sema_type(lhs).unwrap_or_else(|| value_type_name(&lhs_val));
                let result = if result_ty != lhs_sema {
                    llvm_ops::coerce(self.context, &self.builder, result, &result_ty, &lhs_sema)
                } else {
                    result
                };
                let fitted = fit(result);
                if matches!(lhs, Expression::Index { .. } | Expression::ArrayIndex { .. }) {
                    // Compound store into a struct-reference slot transfers
                    // ownership like any other index store.
                    self.index_refcount_ops(lhs_addr.ty.as_ref(), lhs_addr.llvm_ty.unwrap(), lhs_addr.ptr, fitted, rhs)?;
                }
                if let Expression::MemberRef { .. } = lhs {
                    // Compound store into a struct-typed field transfers
                    // ownership like any other reference-slot store.
                    self.field_refcount_ops(lhs, lhs_addr.ptr, fitted, rhs)?;
                }
                if let Some(ty) = rhs_temp {
                    self.release_temp(&ty, rhs_val)?;
                }
                lhs_addr
                    .store(&self.builder, fitted)
                    .ok_or_else(|| "compound store".to_string())?;
                return Ok(fitted);
            }
            if matches!(lhs, Expression::Index { .. } | Expression::ArrayIndex { .. }) {
                // The element type is resolved from the buffer's pointee
                // (`Data`), not the index expression itself.
                self.index_refcount_ops(lhs_addr.ty.as_ref(), lhs_addr.llvm_ty.unwrap(), lhs_addr.ptr, coerced, rhs)?;
            }
            if let Expression::MemberRef { .. } = lhs {
                // A struct-typed field is one reference slot: storing over it
                // releases the old occupant and acquires the new value.
                self.field_refcount_ops(lhs, lhs_addr.ptr, coerced, rhs)?;
            }
            if let Expression::SymbolRef { .. } = lhs {
                // A plain struct-reference local/global is one reference slot:
                // the same shared_ptr `operator=` rule as index and field
                // stores — same pointer (self-assignment in any form) is a
                // no-op, otherwise acquire new then release old.
                let ty_name = lhs_addr.ty.to_string();
                if self.structs.contains_key(&ty_name) {
                    self.store_refcount_ops(&ty_name, lhs_addr.ptr, lhs_addr.llvm_ty.unwrap(), coerced, rhs)?;
                }
            }
            if let Some(ty) = rhs_temp {
                self.release_temp(&ty, rhs_val)?;
            }
            lhs_addr
                .store(&self.builder, coerced)
                .ok_or_else(|| "assign store".to_string())?;
            return Ok(coerced);
        }
        let lhs_temp = self.owned_temp_type(lhs);
        let rhs_temp = self.owned_temp_type(rhs);
        let lhs_val = self.codegen_expr(lhs)?;
        let rhs_val = self.codegen_expr(rhs)?;
        let lhs_name = self.value_sema_type(lhs).unwrap_or_else(|| value_type_name(&lhs_val));
        let rhs_name = self.value_sema_type(rhs).unwrap_or_else(|| value_type_name(&rhs_val));
        let result_ty = binary_result_type(op, &lhs_name, &rhs_name);
        let lhs_c = llvm_ops::coerce(self.context, &self.builder, lhs_val, &lhs_name, &result_ty);
        let rhs_c = llvm_ops::coerce(self.context, &self.builder, rhs_val, &rhs_name, &result_ty);
        // Pointer arithmetic needs the pointer's element type (`char*` strides
        // i8); `value_type_name` flattens pointers to `void*`, so use the
        // sema type of the lhs expression for that.
        let ptr_elem = self
            .value_sema_type(lhs)
            .and_then(|ty| ty.strip_suffix('*').map(|s| s.to_string()))
            .filter(|base| base != "void")
            .and_then(|base| self.types.get(&base));
        // Sema pointee name for the i8 fallback on opaque (`void*`) pointers.
        let ptr_elem_name = self
            .value_sema_type(lhs)
            .and_then(|ty| ty.strip_suffix('*').map(str::to_string));
        let result = apply_op(self.context, &self.builder, *op, lhs_c, rhs_c, &result_ty, ptr_elem, ptr_elem_name.as_deref())?;
        // Owned-rvalue operands are temporaries: released once the op has
        // consumed them.
        if let Some(ty) = lhs_temp {
            self.release_temp(&ty, lhs_val)?;
        }
        if let Some(ty) = rhs_temp {
            self.release_temp(&ty, rhs_val)?;
        }
        Ok(result)
    }

    /// Resolve an lvalue expression to an Address (assignment target).
    fn codegen_lvalue(&mut self, expr: &Expression) -> Result<Address<'ctx>, String> {
        let result = self.codegen_lvalue_unlocated(expr);
        self.locate(&result, expr.loc());
        result
    }

    fn codegen_lvalue_unlocated(&mut self, expr: &Expression) -> Result<Address<'ctx>, String> {
        match expr {
            Expression::SymbolRef { id, .. } => self
                .frame
                .find_local(id)
                .or_else(|| self.global_addrs.get(id))
                .cloned()
                .ok_or_else(|| format!("unknown lvalue {}", id)),
            Expression::ThisRef => self
                .frame
                .find_local("this")
                .cloned()
                .ok_or_else(|| "no this".to_string()),
            Expression::MemberRef { lhs, name, .. } => {
                let struct_name = self.struct_name_of(lhs).unwrap_or_default();
                // An owned-rvalue receiver (`f().x = v`) is a temporary: its
                // creation ref is released at the end of the full expression,
                // after the store through the field address.
                let lhs_temp = self.owned_temp_type(lhs);
                let this_ptr = self.codegen_expr(lhs)?;
                let base_ptr = match this_ptr {
                    BasicValueEnum::StructValue(_) => self.codegen_lvalue(lhs)?.ptr,
                    _ => this_ptr.into_pointer_value(),
                };
                let desc = self
                    .structs
                    .get(&struct_name)
                    .ok_or_else(|| format!("not a struct: {}", struct_name))?;
                let idx = desc
                    .fields
                    .iter()
                    .position(|(n, _)| n == name)
                    .ok_or_else(|| format!("no member named '{}' in '{}'", name, struct_name))?;
                let ty_name = desc.fields[idx].1.clone();
                let field_ty = self
                    .types
                    .get(&ty_name)
                    .ok_or_else(|| format!("unknown field type {}", ty_name))?;
                let gep = unsafe {
                    self.builder
                        .build_struct_gep(desc.llvm_type, base_ptr, idx as u32, name)
                        .map_err(|e| e.to_string())?
                };
                if let Some(ty) = lhs_temp {
                    self.deferred_temps.push((this_ptr, ty));
                }
                Ok(Address::with_llvm_ty(name, &ty_name, field_ty, gep))
            }
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                // POD Array element store: `arr[i] = v` → GEP + store.
                let index = self.codegen_expr(rhs)?;
                // An owned-rvalue receiver (`f()[i] = v`) is a temporary: its
                // creation ref is released at the end of the full expression.
                let lhs_temp = self.owned_temp_type(lhs);
                let slot_ptr = self.codegen_expr(lhs)?.into_pointer_value();
                // A nested index (`outer.Data[0][i] = v`) stores into the
                // inner struct's own `Data` buffer, not its reference slot.
                let (ptr, elem_name) = match self.nested_index_buffer(lhs, slot_ptr)? {
                    Some((buffer, name)) => (buffer, name),
                    None => (slot_ptr, self.index_receiver_pointee(lhs).unwrap_or_else(|| "i32".to_string())),
                };
                let element_ty = self.slot_stride(self.buffer_element_type(&elem_name));
                // Carry the element's value type so stores truncate to it
                // (`Data[Size] = 0` on `char*` must store one byte, not four);
                // struct elements load/store as pointers.
                let value_ty = element_ty;
                let gep = unsafe {
                    self.builder
                        .build_gep(element_ty, ptr, &[index.into_int_value()], "idxl")
                        .map_err(|e| e.to_string())?
                };
                if let Some(ty) = lhs_temp {
                    self.deferred_temps.push((slot_ptr.into(), ty));
                }
                Ok(Address::with_llvm_ty("idxl", &elem_name, value_ty, gep))
            }
            _ => Err("unsupported lvalue".to_string()),
        }
    }

    fn codegen_unary(&mut self, op: UnaryOp, operand: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        use UnaryOp::*;
        match op {
            Neg => {
                let operand_temp = self.owned_temp_type(operand);
                let value = self.codegen_expr(operand)?;
                // C integer promotions apply to the unary operand first:
                // `-x` on a narrower-than-int x negates at int width (a u8 1
                // becomes -1, not 255). 64-bit operands already meet the
                // minimum and are untouched.
                let value = match (value, self.value_sema_type(operand)) {
                    (BasicValueEnum::IntValue(v), Some(n))
                        if v.get_type().get_bit_width() < 32 =>
                    {
                        llvm_ops::coerce(self.context, &self.builder, value, &n, "i32")
                    }
                    _ => value,
                };
                let result = match value {
                    BasicValueEnum::IntValue(v) => Ok(BasicValueEnum::IntValue(
                        self.builder.build_int_neg(v, "neg").map_err(|e| e.to_string())?,
                    )),
                    BasicValueEnum::FloatValue(v) => Ok(BasicValueEnum::FloatValue(
                        self.builder
                            .build_float_neg(v, "fneg")
                            .map_err(|e| e.to_string())?,
                    )),
                    _ => Err("unsupported neg operand".to_string()),
                }?;
                if let Some(ty) = operand_temp {
                    self.release_temp(&ty, value)?;
                }
                Ok(result)
            }
            Pos => self.codegen_expr(operand),
            LogicalNot => {
                let operand_temp = self.owned_temp_type(operand);
                let value = self.codegen_expr(operand)?;
                let b = llvm_ops::as_bool(self.context, &self.builder, value);
                if let Some(ty) = operand_temp {
                    self.release_temp(&ty, value)?;
                }
                Ok(BasicValueEnum::IntValue(
                    self.builder.build_not(b, "lnot").map_err(|e| e.to_string())?,
                ))
            }
            BitNot => {
                let operand_temp = self.owned_temp_type(operand);
                let value = self.codegen_expr(operand)?;
                // C integer promotions apply to the unary operand first
                // (`~x` on a narrower-than-int x complements at int width).
                let value = match (value, self.value_sema_type(operand)) {
                    (BasicValueEnum::IntValue(v), Some(n))
                        if v.get_type().get_bit_width() < 32 =>
                    {
                        llvm_ops::coerce(self.context, &self.builder, value, &n, "i32")
                    }
                    _ => value,
                };
                let result = match value {
                    BasicValueEnum::IntValue(v) => Ok(BasicValueEnum::IntValue(
                        self.builder.build_not(v, "bnot").map_err(|e| e.to_string())?,
                    )),
                    _ => Err("unsupported bitnot operand".to_string()),
                }?;
                if let Some(ty) = operand_temp {
                    self.release_temp(&ty, value)?;
                }
                Ok(result)
            }
            PreInc | PostInc | PreDec | PostDec => {
                // ++x / x++ / --x / x--: modify in place, return old/new.
                let addr = self.codegen_lvalue(operand)?;
                let old = addr
                    .load(&self.builder)
                    .ok_or_else(|| "inc load".to_string())?;
                let inc = matches!(op, PreInc | PostInc);
                let new_val = match old {
                    BasicValueEnum::IntValue(v) => {
                        let one = v.get_type().const_int(1, false);
                        let v2 = if inc {
                            self.builder
                                .build_int_add(v, one, "inc")
                                .map_err(|e| e.to_string())?
                        } else {
                            self.builder
                                .build_int_sub(v, one, "dec")
                                .map_err(|e| e.to_string())?
                        };
                        BasicValueEnum::IntValue(v2)
                    }
                    BasicValueEnum::FloatValue(v) => {
                        let one = v.get_type().const_float(1.0);
                        let v2 = if inc {
                            self.builder
                                .build_float_add(v, one, "finc")
                                .map_err(|e| e.to_string())?
                        } else {
                            self.builder
                                .build_float_sub(v, one, "fdec")
                                .map_err(|e| e.to_string())?
                        };
                        BasicValueEnum::FloatValue(v2)
                    }
                    _ => return Err("unsupported inc operand".to_string()),
                };
                addr.store(&self.builder, new_val)
                    .ok_or_else(|| "inc store".to_string())?;
                match op {
                    PreInc | PreDec => Ok(new_val),
                    _ => Ok(old),
                }
            }
        }
    }

    /// `expr as T` — static cast (spec docs/pepper.md: "equivalent of
    /// static_cast; compile error if the cast cannot succeed"). Numeric and
    /// bool targets only; struct casts are rejected. A pointer may cast to an
    /// integer (address-as-integer for C ABI interop) or to another pointer
    /// type.
    fn codegen_cast(&mut self, expr: &Expression, ty: &TypeName) -> Result<BasicValueEnum<'ctx>, String> {
        // Source signedness decides zext vs sext on widening (same rule as
        // ops::coerce); resolve it before codegen_expr mutates the frame.
        let source_name = self.value_sema_type(expr);
        // An owned-rvalue source is a temporary: released once the cast has
        // consumed it.
        let src_temp = self.owned_temp_type(expr);
        let val = self.codegen_expr(expr)?;
        let name = ty.to_string();
        let target = self.types.get(&name).ok_or_else(|| format!("unknown cast target type {}", name))?;
        // A no-op cast (identical LLVM types) is not a copy: the source keeps
        // its ref, so an owned-rvalue source stays a live temporary.
        let identity = match (val, target) {
            (BasicValueEnum::IntValue(from), BasicTypeEnum::IntType(to)) => from.get_type() == to,
            (BasicValueEnum::FloatValue(from), BasicTypeEnum::FloatType(to)) => from.get_type() == to,
            (BasicValueEnum::PointerValue(_), BasicTypeEnum::PointerType(_)) => true,
            _ => false,
        };
        let result = match (val, target) {
            (BasicValueEnum::IntValue(from), BasicTypeEnum::IntType(to)) => {
                if from.get_type() == to {
                    val
                } else {
                    let v = if from.get_type().get_bit_width() < to.get_bit_width() {
                        // 1-bit bool values and unsigned sources widen zero-extended
                        // (`true` = 1, not -1; u8 200 stays positive); signed types
                        // sign-extend.
                        let unsigned = source_name.as_deref().is_some_and(|s| {
                            llvm_ops::is_unsigned_int_type(s)
                                || s == "bool"
                            // `void*` indexes load one byte (unsigned char in C);
                            // a sign-extension would turn 0xC8 into all-F.
                                || s == "void"
                        });
                        if from.get_type().get_bit_width() == 1 || unsigned {
                            self.builder.build_int_z_extend(from, to, "cast").map_err(|e| e.to_string())?
                        } else {
                            self.builder.build_int_s_extend(from, to, "cast").map_err(|e| e.to_string())?
                        }
                    } else if to.get_bit_width() == 1 {
                        // A 1-bit target is a bool: compare != 0 (`2 as bool` is
                        // true); truncation would keep only the low bit.
                        llvm_ops::as_bool(&self.context, &self.builder, val)
                    } else {
                        // Truncate: static_cast keeps the low bits (negative -> u8 wraps).
                        self.builder.build_int_truncate(from, to, "cast").map_err(|e| e.to_string())?
                    };
                    BasicValueEnum::IntValue(v)
                }
            }
            (BasicValueEnum::FloatValue(from), BasicTypeEnum::FloatType(to)) => {
                if from.get_type() == to {
                    val
                } else {
                    let v = if from.get_type().get_bit_width() < to.get_bit_width() {
                        self.builder.build_float_ext(from, to, "cast").map_err(|e| e.to_string())?
                    } else {
                        self.builder.build_float_trunc(from, to, "cast").map_err(|e| e.to_string())?
                    };
                    BasicValueEnum::FloatValue(v)
                }
            }
            (BasicValueEnum::IntValue(from), BasicTypeEnum::FloatType(to)) => {
                // Same signedness rule as the int->int widening arm: unsigned
                // and 1-bit sources convert via sitofp's unsigned sibling, or
                // `u8 200 as float` reinterprets as -56.0.
                let unsigned = from.get_type().get_bit_width() == 1
                    || source_name.as_deref().is_some_and(|s| {
                        llvm_ops::is_unsigned_int_type(s) || s == "bool"
                    });
                let v = if unsigned {
                    self.builder.build_unsigned_int_to_float(from, to, "cast").map_err(|e| e.to_string())?
                } else {
                    self.builder.build_signed_int_to_float(from, to, "cast").map_err(|e| e.to_string())?
                };
                BasicValueEnum::FloatValue(v)
            }
            (BasicValueEnum::FloatValue(from), BasicTypeEnum::IntType(to)) => {
                if to.get_bit_width() == 1 {
                    // fptosi to i1 is poison outside -1..0; a bool target
                    // compares != 0 (as_bool handles the float compare).
                    BasicValueEnum::IntValue(llvm_ops::as_bool(&self.context, &self.builder, val))
                } else {
                    // fptosi is poison above the *signed* range of the target;
                    // unsigned targets (u8..ulong) need fptoui, mirroring the
                    // signedness rule on the int->float arm.
                    let unsigned = llvm_ops::is_unsigned_int_type(&name);
                    let v = if unsigned {
                        self.builder.build_float_to_unsigned_int(from, to, "cast").map_err(|e| e.to_string())?
                    } else {
                        self.builder.build_float_to_signed_int(from, to, "cast").map_err(|e| e.to_string())?
                    };
                    BasicValueEnum::IntValue(v)
                }
            }
            // Pointer to pointer (`p as __ptr<char>`): LLVM pointers are
            // opaque, so only the sema pointee (index stride) changes.
            (BasicValueEnum::PointerValue(_), BasicTypeEnum::PointerType(_)) => val,
            (BasicValueEnum::PointerValue(from), BasicTypeEnum::IntType(to)) => {
                // Address-as-integer for C ABI interop (e.g. hex-dumping a pointer).
                BasicValueEnum::IntValue(
                    self.builder.build_ptr_to_int(from, to, "ptrtoint").map_err(|e| e.to_string())?,
                )
            }
            _ => return Err(format!("cannot cast to {}", name)),
        };
        if !identity {
            if let Some(ty) = src_temp {
                self.release_temp(&ty, val)?;
            }
        }
        Ok(result)
    }

    fn codegen_ternary(
        &mut self,
        condition: &Expression,
        true_expr: &Expression,
        false_expr: &Expression,
    ) -> Result<BasicValueEnum<'ctx>, String> {
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let true_block = self.context.append_basic_block(fn_value, "true");
        let false_block = self.context.append_basic_block(fn_value, "false");
        let merge_block = self.context.append_basic_block(fn_value, "ternarycont");

        let cond_temp = self.owned_temp_type(condition);
        let cond = self.codegen_expr(condition)?;
        if let Some(ty) = cond_temp {
            self.release_temp(&ty, cond)?;
        }
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.builder
            .build_conditional_branch(cond_bool, true_block, false_block)
            .map_err(|e| e.to_string())?;

        self.builder.position_at_end(true_block);
        let true_val = self.codegen_expr_in_arm(true_expr)?;
        // The arm's creation ref survives into the phi: a ternary of owned
        // rvalues is itself an owned rvalue (the consumer releases it once),
        // exactly as C++'s conditional operator yields one temporary.
        self.builder
            .build_unconditional_branch(merge_block)
            .map_err(|e| e.to_string())?;
        let true_end = self.builder.get_insert_block().expect("insert block");

        self.builder.position_at_end(false_block);
        let false_val = self.codegen_expr_in_arm(false_expr)?;
        self.builder
            .build_unconditional_branch(merge_block)
            .map_err(|e| e.to_string())?;
        let false_end = self.builder.get_insert_block().expect("insert block");

        self.builder.position_at_end(merge_block);
        // Mixed-width arms (e.g. `cond ? sizeof<T>() : 8` — i64 vs an i32
        // literal) must promote to a common type before the phi, mirroring
        // binary-op promotion; equal LLVM types need no work.
        let (true_val, false_val) = if true_val.get_type() == false_val.get_type() {
            (true_val, false_val)
        } else {
            let true_name = self.value_sema_type(true_expr).unwrap_or_else(|| value_type_name(&true_val));
            let false_name = self.value_sema_type(false_expr).unwrap_or_else(|| value_type_name(&false_val));
            let common = llvm_ops::result_type(&true_name, &false_name);
            (
                llvm_ops::coerce(self.context, &self.builder, true_val, &value_type_name(&true_val), &common),
                llvm_ops::coerce(self.context, &self.builder, false_val, &value_type_name(&false_val), &common),
            )
        };
        let phi = self
            .builder
            .build_phi(true_val.get_type(), "ternary")
            .map_err(|e| e.to_string())?;
        phi.add_incoming(&[(&true_val, true_end), (&false_val, false_end)]);
        Ok(phi.as_basic_value())
    }
}

/// Is the sema return type void?
fn is_void(ty: &TypeName) -> bool {
    ty.to_string() == "void"
}

/// Build an LLVM FunctionType from a return + params.
fn llvm_fn_type<'ctx>(
    return_type: BasicTypeEnum<'ctx>,
    params: &[BasicTypeEnum<'ctx>],
    varargs: bool,
) -> inkwell::types::FunctionType<'ctx> {
    let param_meta: Vec<inkwell::types::BasicMetadataTypeEnum<'ctx>> =
        params.iter().map(|p| (*p).into()).collect();
    match return_type {
        BasicTypeEnum::ArrayType(at) => at.fn_type(&param_meta, varargs),
        BasicTypeEnum::FloatType(ft) => ft.fn_type(&param_meta, varargs),
        BasicTypeEnum::IntType(it) => it.fn_type(&param_meta, varargs),
        BasicTypeEnum::PointerType(pt) => pt.fn_type(&param_meta, varargs),
        // Struct-typed returns are pointers (C++ ref semantics: functions
        // return `this` as a pointer).
        BasicTypeEnum::StructType(sct) => sct
            .ptr_type(inkwell::AddressSpace::default())
            .fn_type(&param_meta, varargs),
        BasicTypeEnum::VectorType(vt) => vt.fn_type(&param_meta, varargs),
        BasicTypeEnum::ScalableVectorType(vt) => vt.fn_type(&param_meta, varargs),
    }
}

/// Best-effort type name of a value for coerce decisions.
fn value_type_name<'ctx>(value: &BasicValueEnum<'ctx>) -> String {
    match value {
        BasicValueEnum::IntValue(v) => match v.get_type().get_bit_width() {
            1 => "bool".to_string(),
            8 => "i8".to_string(),
            16 => "i16".to_string(),
            32 => "i32".to_string(),
            64 => "i64".to_string(),
            w => format!("i{}", w),
        },
        BasicValueEnum::FloatValue(v) => {
            if v.get_type().get_bit_width() == 32 {
                "f32".to_string()
            } else {
                "f64".to_string()
            }
        }
        BasicValueEnum::PointerValue(_) => "void*".to_string(),
        _ => "unknown".to_string(),
    }
}

/// Apply a binary op to two coerced values (OperatorGen.cpp:182-205).
fn apply_op<'ctx>(
    context: &'ctx Context,
    builder: &inkwell::builder::Builder<'ctx>,
    op: BinaryOp,
    lhs: BasicValueEnum<'ctx>,
    rhs: BasicValueEnum<'ctx>,
    ty_name: &str,
    ptr_elem: Option<BasicTypeEnum<'ctx>>,
    ptr_elem_name: Option<&str>,
) -> Result<BasicValueEnum<'ctx>, String> {
    match (lhs, rhs) {
        (BasicValueEnum::IntValue(l), BasicValueEnum::IntValue(r)) => {
            // Mixed widths: coerce both to the wider one before the op.
            // Defensive — both call sites pre-coerce operands to a common
            // width, so this only fires if that coercion failed. Width alone
            // can't recover signedness, but 1-bit values (bools) are unsigned
            // 0/1 and must zero-extend (`true` sign-extends to -1).
            let ext = |src: inkwell::values::IntValue<'ctx>,
                       dst: inkwell::types::IntType<'ctx>|
                    -> inkwell::values::IntValue<'ctx> {
                if src.get_type().get_bit_width() == 1 {
                    builder.build_int_z_extend(src, dst, "argw").unwrap_or(src)
                } else {
                    builder.build_int_s_extend(src, dst, "argw").unwrap_or(src)
                }
            };
            let (l2, r2) = if l.get_type().get_bit_width() == r.get_type().get_bit_width() {
                (l, r)
            } else if l.get_type().get_bit_width() > r.get_type().get_bit_width() {
                (l, ext(r, l.get_type()))
            } else {
                (ext(l, r.get_type()), r)
            };
            Ok(BasicValueEnum::IntValue(
                llvm_ops::int_binary(context, builder, op, l2, r2, ty_name)
                    .ok_or_else(|| {
                        format!("unsupported op {:?}", op)
                    })?,
            ))
        }
        (BasicValueEnum::FloatValue(l), BasicValueEnum::FloatValue(r)) => {
            if is_comparison(op) {
                Ok(BasicValueEnum::IntValue(
                    llvm_ops::float_compare(builder, op, l, r)
                        .ok_or_else(|| format!("unsupported op {:?}", op))?,
                ))
            } else {
                Ok(BasicValueEnum::FloatValue(
                    llvm_ops::float_binary(builder, op, l, r)
                        .ok_or_else(|| format!("unsupported op {:?}", op))?,
                ))
            }
        }
        (BasicValueEnum::PointerValue(l), BasicValueEnum::PointerValue(r)) => {
            Ok(BasicValueEnum::IntValue(
                llvm_ops::pointer_binary(context, builder, op, l, r)
                    .ok_or_else(|| {
                        format!("unsupported op {:?}", op)
                    })?,
            ))
        }
        // Pointer arithmetic: ptr + int / ptr - int (e.g. `Data + idx`).
        // Other ops (`ptr == int`) fall through to the mixed comparison.
        (BasicValueEnum::PointerValue(p), BasicValueEnum::IntValue(i))
            if matches!(op, BinaryOp::Add | BinaryOp::Sub) =>
        {
            match op {
                BinaryOp::Add | BinaryOp::Sub => {
                    let idx = if op == BinaryOp::Add {
                        i
                    } else {
                        builder.build_int_neg(i, "negidx").unwrap_or(i)
                    };
                    // Stride by the pointer's element type (`char*` → i8,
                    // `int*` → i32); opaque (`void*`) pointers stride by byte.
                    // The declared result type is authoritative when the lhs
                    // type did not resolve (a malloc'd buffer is `void*` with
                    // no element), so a `void* + n` advances n bytes.
                    let element_ty = match (ptr_elem, ptr_elem_name, ty_name) {
                        (Some(BasicTypeEnum::IntType(it)), _, _) => it,
                        (_, Some("void"), _) => context.i8_type(),
                        // A declared pointer result whose element type did not
                        // resolve (`void*` from a malloc'd buffer): stride by byte.
                        (_, _, r) if r.ends_with('*') => context.i8_type(),
                        _ => context.i32_type(),
                    };
                    let advanced = unsafe {
                        builder
                            .build_in_bounds_gep(element_ty, p, &[idx], "ptrarith")
                            .map_err(|e| e.to_string())?
                    };
                    Ok(BasicValueEnum::PointerValue(advanced))
                }
                _ => {
            Err(format!("unsupported op {:?} on pointer", op))
        }
            }
        }
        // Mixed int/pointer comparison: ptrtoint the pointer side.
        (l_kind, r_kind) if is_comparison(op) => {
            let ptr_val = match (l_kind, r_kind) {
                (BasicValueEnum::IntValue(_), BasicValueEnum::PointerValue(p)) => p,
                (BasicValueEnum::PointerValue(p), BasicValueEnum::IntValue(_)) => p,
                _ => return Err(format!("unsupported operand kinds for {:?}", op)),
            };
            let as_int = builder
                .build_ptr_to_int(ptr_val, context.i64_type(), "p2i")
                .map_err(|e| e.to_string())?;
            // `ty_name` names the integer operand (binary_result_type):
            // widen it to address width by its own signedness.
            let widen = |i: inkwell::values::IntValue<'ctx>| -> Result<inkwell::values::IntValue<'ctx>, String> {
                if i.get_type().get_bit_width() >= 64 {
                    Ok(i)
                } else if i.get_type().get_bit_width() == 1 || llvm_ops::is_unsigned_int_type(ty_name) {
                    builder.build_int_z_extend(i, context.i64_type(), "argw").map_err(|e| e.to_string())
                } else {
                    builder.build_int_s_extend(i, context.i64_type(), "argw").map_err(|e| e.to_string())
                }
            };
            let (li, ri) = match (l_kind, r_kind) {
                (BasicValueEnum::IntValue(i), _) => (widen(i)?, as_int),
                (_, BasicValueEnum::IntValue(i)) => (as_int, widen(i)?),
                _ => return Err(format!("unsupported operand kinds for {:?}", op)),
            };
            let pred = match op {
                BinaryOp::Equal | BinaryOp::Identical => inkwell::IntPredicate::EQ,
                BinaryOp::NotEqual => inkwell::IntPredicate::NE,
                _ => return Err(format!("unsupported op {:?}", op)),
            };
            Ok(BasicValueEnum::IntValue(
                builder
                    .build_int_compare(pred, li, ri, "mixedcmp")
                    .map_err(|e| e.to_string())?,
            ))
        }
        _ => Err(format!("unsupported operand kinds for {:?}", op)),
    }
}

fn is_comparison(op: BinaryOp) -> bool {
    use BinaryOp::*;
    matches!(
        op,
        Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual | Identical
    )
}

/// True when the expression codegens to a float value. `value_sema_type`
/// cannot resolve every form (literals, nested unresolvable binaries), so
/// callers deciding signedness from an unresolved operand must check this
/// first — reporting an int-promoted type for a float-producing binary makes
/// `coerce` hit `into_int_value()` on a FloatValue.
fn is_float_valued(expr: &Expression) -> bool {
    match expr {
        Expression::FloatLiteral(_) => true,
        Expression::Unary { operand, .. } => is_float_valued(operand),
        Expression::Binary { lhs, rhs, .. } => {
            is_float_valued(lhs) || is_float_valued(rhs)
        }
        Expression::Cast { ty, .. } => llvm_ops::is_float_type(ty.to_string().as_str()),
        Expression::Ternary { true_expr, false_expr, .. } => {
            is_float_valued(true_expr) || is_float_valued(false_expr)
        }
        _ => false,
    }
}

/// The type `codegen_binary` produces for a binary op — the single source of
/// truth shared by `value_sema_type` and both codegen sites. Shifts are
/// excluded from the usual arithmetic conversions (C semantics): each operand
/// is promoted independently and the result takes the type of the promoted
/// *left* operand, so an unsigned shift amount must not turn a signed `>>`
/// into a logical shift.
fn binary_result_type(op: &BinaryOp, lhs_name: &str, rhs_name: &str) -> String {
    if matches!(op, BinaryOp::LShift | BinaryOp::RShift) {
        llvm_ops::result_type(lhs_name, lhs_name)
    } else if matches!(op, BinaryOp::Add | BinaryOp::Sub)
        && (lhs_name.ends_with('*') || rhs_name.ends_with('*'))
    {
        // Pointer arithmetic produces a pointer: name the pointer operand so
        // `coerce` does not ptrtoint the result into an integer.
        if lhs_name.ends_with('*') {
            lhs_name.to_string()
        } else {
            rhs_name.to_string()
        }
    } else if is_comparison(*op) && lhs_name.ends_with('*') != rhs_name.ends_with('*') {
        // Pointer against integer: name the integer operand, so `coerce`
        // leaves it at its own width and signedness (naming the pointer
        // would narrow a `long` to i32) and `apply_op` compares addresses.
        if lhs_name.ends_with('*') {
            rhs_name.to_string()
        } else {
            lhs_name.to_string()
        }
    } else {
        llvm_ops::result_type(lhs_name, rhs_name)
    }
}

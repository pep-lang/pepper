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
use inkwell::values::{BasicValueEnum, FunctionValue, PointerValue};
use inkwell::types::AnyType as _;
use inkwell::OptimizationLevel;
use ops as llvm_ops;
use pepper_sema::model::{self as sema, Block, BinaryOp, Branch, Declaration, ExternDef, Expression, FunctionDef, Module as SemaModule, Statement, StructDef, UnaryOp, VariableDef, While};
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
    frame: Frame<'ctx>,
}
impl<'ctx> CodeGenerator<'ctx> {
    pub fn new(context: &'ctx Context, module_name: &str) -> Self {
        let module = context.create_module(module_name);
        let builder = context.create_builder();
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
            frame: Frame::empty(),
        }
    }

    /// Instantiate + codegen in the exact C++ phase order
    /// (LLVMCodeGenerator.cpp:264-308).
    pub fn generate(&mut self, module: &mut SemaModule) -> Result<(), String> {
        // Instantiation pass: structs → methods → externs → functions.
        // Concrete (non-abstract) structs are pre-registered as opaque
        // pointers first: a struct's field may name a specialization that is
        // declared later in the module (`hash_map<Point, int>` before
        // `array<Point>`), and field lookup must not fall back to the base.
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
        // name a struct declared later, e.g. `Holder { array<int> items; }`),
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

    /// Compile + JIT a value-test module: returns the entry's return value.
    pub fn jit_execute(&mut self, module: &mut SemaModule, entry: &str) -> Result<i32, String> {
        self.generate(module)?;
        let ee = self
            .module
            .create_jit_execution_engine(OptimizationLevel::None)
            .map_err(|e| format!("JIT failed: {}", e.to_string()))?;

        // Bind the runtime support functions. The JIT cannot discover them on
        // its own: they live in a static rlib linked into this executable, so
        // they are absent from the process export table that MCJIT's symbol
        // search consults, and calls would land on unresolved addresses.
        for (name, addr) in pepper_support::support_symbols() {
            if let Some(declared) = self.module.get_function(name) {
                ee.add_global_mapping(&declared, addr);
            }
        }

        unsafe {
            let f = ee
                .get_function::<unsafe extern "C" fn() -> i32>(entry)
                .map_err(|e| format!("entry {}: {:?}", entry, e))?;
            Ok(f.call())
        }
    }

    // ── Struct instantiation (port of StructGen.cpp:57-106) ─────────────────

    fn instantiate_struct(&mut self, st: &StructDef) -> Result<(), String> {
        // Generic struct bases are abstract: skip `Name<...>` instances and
        // generic bases (ty 'array<T>'); specializations were cloned with
        // concrete names by sema.
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }

        let mut field_types: Vec<BasicTypeEnum<'ctx>> = vec![];
        for field in &st.field_members {
            let ty = self
                .types
                .get(&field.ty.to_string())
                .ok_or_else(|| format!("Field {} has unknown type {}", field.name, field.ty))?;
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
        let fn_type = llvm_fn_type(return_type, &param_types, false);
        let fn_value = match self.module.get_function(&ext.name) {
            Some(f) => f,
            None => self.module.add_function(&ext.name, fn_type, None),
        };
        self.functions.insert(ext.name.clone(), fn_value);
        self.fn_returns.insert(ext.name.clone(), ext.ty.to_string());
        Ok(())
    }

    fn instantiate_function(&mut self, function: &FunctionDef) -> Result<(), String> {
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
            declared_params.insert(0, ("this".to_string(), format!("{}*", struct_name)));
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
        }

        let body = function.body.clone().unwrap_or_else(|| Block {
            name: String::new(),
            items: vec![],
            attributes: vec![],
        });
        self.codegen_block(&body)?;

        // Terminate any orphaned trailing block (e.g. an `ifcont` after a
        // branch whose paths both return) with a branch to the return block.
        if let Some(current) = self.builder.get_insert_block() {
            if current.get_terminator().is_none() {
                if let Some(return_block) = self.frame.return_block {
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
        let entry = self.context.append_basic_block(fn_value, "block");
        self.builder.build_unconditional_branch(entry).map_err(|e| e.to_string())?;
        self.builder.position_at_end(entry);
        self.codegen_block(inner)?;

        let current = self.builder.get_insert_block().expect("insert block");
        if current.get_terminator().is_none() {
            // No return in the region: branch through to a continuation.
            let cont = self.context.insert_basic_block_after(current, "blockcont");
            self.builder.build_unconditional_branch(cont).map_err(|e| e.to_string())?;
            self.builder.position_at_end(cont);
        } else {
            // A return in the region: patch every unterminated block created
            // by it to fall through, then land subsequent (dead) statements
            // in a fresh unreachable block.
            let blocks = fn_value.get_basic_blocks();
            let start = blocks.iter().position(|b| *b == entry).expect("entry block");
            for bb in &blocks[start..] {
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
        match stmt {
            Statement::Expression(expr) => {
                self.codegen_expr(expr)?;
            }
            Statement::Block(inner) => self.codegen_nested_block(inner)?,
            Statement::Declaration(Declaration::Variable(var)) => {
                self.codegen_var_def(var)?;
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => self.codegen_branch(branch)?,
            Statement::While(wh) => self.codegen_while(wh)?,
            Statement::Return(ret) => {
                let return_block = self
                    .frame
                    .return_block
                    .ok_or_else(|| "return outside function".to_string())?;
                if let Some(expr) = &ret.expr {
                    let value = self.codegen_expr(expr)?;
                    if let Some(retval) = self.frame.retval {
                        // Coerce the value (e.g. an i1 compare result) to the
                        // declared return type before the store.
                        let retval_ty = self
                            .frame
                            .retval_type
                            .clone()
                            .unwrap_or_default();
                        let coerced = llvm_ops::coerce(
                            self.context,
                            &self.builder,
                            value,
                            &value_type_name(&value),
                            &retval_ty,
                        );
                        self.builder
                            .build_store(retval, coerced)
                            .map_err(|e| e.to_string())?;
                    }
                }
                self.builder
                    .build_unconditional_branch(return_block)
                    .map_err(|e| e.to_string())?;
            }
        }
        Ok(())
    }

    fn codegen_var_def(&mut self, var: &VariableDef) -> Result<(), String> {
        // Struct-typed vars hold POINTERS (C++ ref semantics): `this`
        // (malloc'd) and locals initialized from a ctor call.
        let is_struct_ref = self.structs.contains_key(&var.ty.to_string());
        let ty = if is_struct_ref {
            self.context.ptr_type(inkwell::AddressSpace::default()).into()
        } else {
            self.types
                .get(&var.ty.to_string())
                .ok_or_else(|| format!("unknown type {}", var.ty))?
        };
        let alloca = self
            .builder
            .build_alloca(ty, &var.name)
            .map_err(|e| e.to_string())?;
        if let Some(default) = &var.default {
            let value = self.codegen_expr(default)?;
            // Integer literals codegen as i32; widen into a wider int alloca
            // so the full word is defined (e.g. the ctor's `u64 size`).
            let value = match (&value, ty) {
                (BasicValueEnum::IntValue(v), BasicTypeEnum::IntType(it))
                    if v.get_type().get_bit_width() < it.get_bit_width() =>
                {
                    self.builder
                        .build_int_s_extend(
                            *v,
                            it,
                            &format!("{}w", var.name),
                        )
                        .map_err(|e| e.to_string())?
                        .into()
                }
                _ => value,
            };
            self.builder
                .build_store(alloca, value)
                .map_err(|e| e.to_string())?;
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
        Ok(())
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

        let cond = self.codegen_expr(&branch.condition)?;
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.builder
            .build_conditional_branch(cond_bool, then_block, else_block.unwrap_or(merge_block))
            .map_err(|e| e.to_string())?;

        self.builder.position_at_end(then_block);
        self.codegen_block(&branch.if_block)?;
        // Branch to the merge block if the then block doesn't already
        // terminate (a `return` inside the branch ends the path).
        let then_end = self.builder.get_insert_block().expect("insert block");
        if then_end.get_terminator().is_none() {
            self.builder
                .build_unconditional_branch(merge_block)
                .map_err(|e| e.to_string())?;
        }

        if let Some(else_b) = else_block {
            self.builder.position_at_end(else_b);
            self.codegen_block(branch.else_block.as_ref().expect("else block"))?;
            let else_end = self.builder.get_insert_block().expect("insert block");
            if else_end.get_terminator().is_none() {
                self.builder
                    .build_unconditional_branch(merge_block)
                    .map_err(|e| e.to_string())?;
            }
        }

        self.builder.position_at_end(merge_block);
        Ok(())
    }

    fn codegen_while(&mut self, wh: &While) -> Result<(), String> {
        let fn_value = self.frame.function.ok_or_else(|| "no function".to_string())?;
        let body_block = self.context.append_basic_block(fn_value, "while");
        let merge_block = self.context.append_basic_block(fn_value, "whilecont");

        // Initial condition check.
        let cond = self.codegen_expr(&wh.condition)?;
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.builder
            .build_conditional_branch(cond_bool, body_block, merge_block)
            .map_err(|e| e.to_string())?;

        // Body.
        self.builder.position_at_end(body_block);
        self.codegen_block(&wh.block)?;

        // Re-evaluate condition after the body (port of LoopGen.cpp:29-32).
        let after_body = self.builder.get_insert_block().expect("insert block");
        self.builder.position_at_end(after_body);
        let cond = self.codegen_expr(&wh.condition)?;
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.builder
            .build_conditional_branch(cond_bool, body_block, merge_block)
            .map_err(|e| e.to_string())?;

        self.builder.position_at_end(merge_block);
        Ok(())
    }

    /// Sema type string of an expression's value, as declared (pointer
    /// suffix intact); `None` when it cannot be determined.
    fn value_sema_type(&self, expr: &Expression) -> Option<String> {
        match expr {
            Expression::SymbolRef { id, .. } => self
                .frame
                .find_local(id)
                .map(|a| a.ty.to_string()),
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
            Expression::MemberRef { lhs, name } => {
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
            Expression::Binary { lhs, .. } => {
                // Arithmetic keeps the left operand's type (`char* + int`
                // stays `char*`, `int + int` stays `int`).
                self.value_sema_type(lhs)
            }
            Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } => {
                // Indexed element: the receiver's pointee (`array<array<int>>`
                // → `array<int>`), so method calls on a nested-array element
                // mangle against the element's struct.
                self.index_receiver_pointee(lhs)
            }
            _ => None,
        }
    }

    /// Best-effort struct name of an expression's value, for field/method
    /// access when the receiver is not a bare frame local (e.g. a parameter).
    /// The declared name resolves exactly first — only concrete
    /// specializations are registered (`array<array<int>>`), never the base;
    /// unregistered names fall back to their base for abstract receivers.
    fn struct_name_of(&self, expr: &Expression) -> Option<String> {
        let ty = self.value_sema_type(expr)?.trim_end_matches('*').to_string();
        if self.structs.contains_key(&ty) {
            return Some(ty);
        }
        ty.split('<').next().filter(|n| !n.is_empty()).map(|s| s.to_string())
    }

    /// LLVM element type behind a pointer/array receiver (`char*` → i8,
    /// `int[]`/`int*` → i32); i32 when the receiver's type is unknown.
    /// The exact name resolves first — specializations register under their
    /// full names (`array<int>`), and a nested index on a struct-reference
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
        let pointee = base.and_then(|b| {
            self.types.get(&b).or_else(|| {
                b.split('<')
                    .next()
                    .filter(|n| !n.is_empty())
                    .and_then(|n| self.types.get(n))
            })
        });
        pointee.unwrap_or_else(|| self.context.i32_type().into())
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
    /// Sema type string of an indexed receiver's pointee (`array<array<int>>`
    /// → `array<int>`); the element type for method mangling on a nested-array
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
                        // (`int`, `array<int>`, …), which drives the GEP
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
    /// Element names are pointees (`int`, `array<int>`), so they resolve to
    /// their own LLVM type; unresolvable names fall back to i32, matching
    /// the historical behavior of the index arms.
    fn buffer_element_type(&self, name: &str) -> BasicTypeEnum<'ctx> {
        self.types.get(name).unwrap_or_else(|| self.context.i32_type().into())
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
    /// Release the old occupant and acquire the new value of a struct-reference
    /// index slot. Arrays are just a collection of individual references, so
    /// every store into one transfers ownership at the store site, regardless
    /// of caller. Both methods null-guard themselves, so calling them on
    /// zero-initialized slots is safe.
    fn index_refcount_ops(
        &mut self,
        elem_name: &str,
        value_ty: BasicTypeEnum<'ctx>,
        gep: PointerValue<'ctx>,
        new_val: BasicValueEnum<'ctx>,
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
        let old = self.builder.build_load(value_ty, gep, "oldref").map_err(|e| e.to_string())?;
        self.call_function(&format!("{}.{}", elem_name, "__acquire"), vec![new_val])?;
        self.call_function(&format!("{}.{}", elem_name, "__release"), vec![old])?;
        Ok(())
    }
    /// Release the old occupant of a struct-typed field. A field is one
    /// reference slot: the stored value already carries its creation ref, so
    /// a store transfers exactly that one ref — no acquire here (acquiring
    /// would leave every ctor-initialized field at refcount 2 and nothing
    /// would ever reach zero). Mirrors the load-old side of
    /// `index_refcount_ops`. Struct values are references, so the slot holds a
    /// pointer; `__release` null-guards itself, so storing over a
    /// zero-initialized field is safe.
    fn field_refcount_ops(
        &mut self,
        lhs: &Expression,
        gep: PointerValue<'ctx>,
    ) -> Result<(), String> {
        let field_ty_name = match lhs {
            Expression::MemberRef { lhs, name } => {
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
        let old = self.builder.build_load(value_ty, gep, "oldref").map_err(|e| e.to_string())?;
        // Release the old occupant with the FIELD type's __release (not the
        // enclosing struct's): the slot holds a field-typed reference.
        self.call_function(&format!("{}.{}", field_ty_name, "__release"), vec![old])?;
        Ok(())
    }
    fn codegen_expr(&mut self, expr: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        match expr {
            Expression::BoolLiteral(v) => Ok(BasicValueEnum::IntValue(
                self.context.bool_type().const_int(*v as u64, false),
            )),
            Expression::IntLiteral(v) => Ok(BasicValueEnum::IntValue(
                self.context.i32_type().const_int(*v as u64, true),
            )),
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
                    .ok_or_else(|| format!("unknown symbol {}", id))?;
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
            Expression::MemberRef { lhs, name } => {
                // Load lhs (this pointer), then StructGEP (Struct.cpp:60-70).
                // The struct name comes from the lhs's static type, not the
                // LLVM value (opaque pointers lose the type).
                let struct_name = self.struct_name_of(lhs).unwrap_or_default();
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
                    .ok_or_else(|| format!("no field {}.{}", struct_name, name))?;
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
                match field_ty {
                    BasicTypeEnum::StructType(_) => self
                        .builder
                        .build_load(self.context.ptr_type(inkwell::AddressSpace::default()), gep, name)
                        .map_err(|e| e.to_string()),
                    _ => self
                        .builder
                        .build_load(field_ty, gep, name)
                        .map_err(|e| e.to_string()),
                }
            }
            Expression::Binary { op, lhs, rhs } => self.codegen_binary(op, lhs, rhs),
            Expression::Unary { op, operand } => self.codegen_unary(*op, operand),
            Expression::Ternary {
                condition,
                true_expr,
                false_expr,
            } => self.codegen_ternary(condition, true_expr, false_expr),
            Expression::Index { lhs, rhs } | Expression::ArrayIndex { lhs, rhs, .. } => {
                // POD array indexing.
                let index = self.codegen_expr(rhs)?;
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
                self.builder
                    .build_load(value_ty, gep, "loadidx")
                    .map_err(|e| e.to_string())
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
                // pointer for pointers and struct types (including `string`).
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
            Expression::FunctionCall {
                function: name,
                args,
            } => self.codegen_call(name, args),
            Expression::MethodCall { this, method, args } => {
                // Receiver is a buffer slot (`Data[i]`): GEP the element out
                // of the raw buffer. Indexer methods are the exception — they
                // address the pointee's own data (`s[0]` on `string s`), so
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
                    for arg in args {
                        arg_vals.push(self.codegen_expr(arg)?);
                    }
                    for extra in self.missing_args(&mangled, args.len())? {
                        arg_vals.push(self.codegen_expr(&extra)?);
                    }
                    return self.call_function(&mangled, arg_vals);
                }
                // Mangle: `<StructOf(this)>.<method>`. The struct name comes
                // from the receiver's static type; non-struct receivers fall
                // back to the method name as-is (array index methods resolve
                let struct_name = self.struct_name_of(this.as_ref()).unwrap_or_default();
                if method.starts_with("__index_") {
                    // POD array index set/get: direct GEP + load/store — but
                    // only when the receiver's struct declares the indexer
                    // and the receiver is not itself a pointer. A pointer
                    // receiver (raw buffer field like `Data` on
                    // `array<array<int>>`) must GEP the slot; dispatching
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
                // exactly what the `this` parameter expects.
                let this_val = self.codegen_expr(this)?;
                let mangled = format!("{}.{}", struct_name, method);
                let is_static = self
                    .structs
                    .get(&struct_name)
                    .map(|d| d.static_methods.contains(method.as_str()))
                    .unwrap_or(false);
                let mut arg_vals = if is_static { vec![] } else { vec![this_val] };
                for arg in args {
                    arg_vals.push(self.codegen_expr(arg)?);
                }
                for extra in self.missing_args(&mangled, args.len())? {
                    arg_vals.push(self.codegen_expr(&extra)?);
                }
                self.call_function(&mangled, arg_vals)
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
    /// POD array index get/set: `arr[i]` → load via GEP, `arr[i] = v` →
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
            // __index_set: the value is args[1].
            let value_expr = args.get(1).ok_or_else(|| "index set needs a value".to_string())?;
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
            self.index_refcount_ops(&self.index_receiver_pointee(this).unwrap_or_else(|| "i32".to_string()), value_ty, gep, value)?;
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
        // assert(condition, msg): the message is a raw `char*`. A string
        // literal (already rewritten by convert_string_literals into a
        // `string(raw, size, len)` ctor call) lowers to its global pointer —
        // no temporary allocation on hot paths like index bounds checks.
        // Any other expression is lowered to `msg.c_str()`.
        if name == "assert" && args.len() == 2 {
            let cond = self.codegen_expr(&args[0])?;
            let msg = match &args[1] {
                Expression::FunctionCall { function, args: inner }
                    if function == "string"
                        && matches!(
                            inner.first(),
                            Some(Expression::StringLiteral { is_raw: true, .. })
                        ) =>
                {
                    self.codegen_expr(inner.first().unwrap())?
                }
                other => {
                    let v = self.codegen_expr(other)?;
                    // The message must be a `char*`: an argument already typed
                    // as a pointer (`char*`, `__ptr<T>`) is passed through,
                    // everything else (notably `string`) lowers via `c_str`.
                    match self.value_sema_type(other) {
                        Some(ty) if ty.ends_with('*') || ty.starts_with("__ptr<") => v,
                        _ => self.call_function("string.c_str", vec![v])?,
                    }
                }
            };
            return self.call_function("assert", vec![cond, msg]);
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
        // registered under their full name (`array<int>`); fall back to the
        // base name for non-generic ctors.
        let target = if self.functions.contains_key(name) {
            name.to_string()
        } else {
            name.split('<').next().unwrap_or(name).trim().to_string()
        };
        let mut arg_vals = vec![];
        for arg in args {
            arg_vals.push(self.codegen_expr(arg)?);
        }
        for extra in self.missing_args(&target, args.len())? {
            arg_vals.push(self.codegen_expr(&extra)?);
        }
        self.call_function(&target, arg_vals)
    }

    fn codegen_print(&mut self, args: &[Expression]) -> Result<BasicValueEnum<'ctx>, String> {
        for arg in args {
            let value = self.codegen_expr(arg)?;
            match value {
                BasicValueEnum::PointerValue(_) => {
                    self.call_function("_pep_print", vec![value])?;
                }
                BasicValueEnum::IntValue(v) => {
                    let wide = if v.get_type().get_bit_width() < 64 {
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
        if provided >= defaults.len() {
            return Ok(vec![]);
        }
        defaults[provided..]
            .iter()
            .enumerate()
            .map(|(offset, default)| {
                default.clone().ok_or_else(|| {
                    format!("{}: missing argument {}", target, provided + offset)
                })
            })
            .collect()
    }

    fn call_function(
        &mut self,
        name: &str,
        args: Vec<BasicValueEnum<'ctx>>,
    ) -> Result<BasicValueEnum<'ctx>, String> {
        let fn_value = match self.functions.get(name) {
            Some(f) => *f,
            None => {
                // Declare an extern against the support library.
                let i32t = self.context.i32_type();
                let ptr_ty = self
                    .context
                    .i8_type()
                    .ptr_type(inkwell::AddressSpace::default());
                let (ret, params): (BasicTypeEnum<'ctx>, Vec<BasicTypeEnum<'ctx>>) = match name {
                    "_pep_print" => (i32t.into(), vec![ptr_ty.into()]),
                    "_pep_print_int" => (i32t.into(), vec![self.context.i64_type().into()]),
                    "_pep_print_float" => (i32t.into(), vec![self.context.f64_type().into()]),
                    "_pep_free" => (i32t.into(), vec![ptr_ty.into()]),
                    "_pep_hash_bytes" => {
                        (self.context.i64_type().into(), vec![ptr_ty.into(), self.context.i64_type().into()])
                    }
                    "_pep_malloc" | "_pep_realloc" => {
                        (ptr_ty.into(), vec![self.context.i64_type().into()])
                    }
                    "_pep_live_allocs" => (self.context.i64_type().into(), vec![]),
                    "trace_int" => (
                        i32t.into(),
                        vec![self.context.i64_type().into(), ptr_ty.into()],
                    ),
                    "trace_ptr" | "trace_region" => {
                        // trace_region(ptr, size, name); trace_ptr(ptr, name).
                        if *name == *"trace_region" {
                            (
                                i32t.into(),
                                vec![ptr_ty.into(), self.context.i64_type().into(), ptr_ty.into()],
                            )
                        } else {
                            (i32t.into(), vec![ptr_ty.into(), ptr_ty.into()])
                        }
                    }
                    &_ => {
                        return Err(format!("unknown function {}", name));
                    }
                };
                let fn_type = llvm_fn_type(ret, &params, false);
                let declared = self.module.add_function(name, fn_type, None);
                self.functions.insert(name.to_string(), declared);
                declared
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
                    if it.get_bit_width() > v.get_type().get_bit_width() {
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
            let rhs_val = self.codegen_expr(rhs)?;
            let lhs_addr = self.codegen_lvalue(lhs)?;
            let lhs_ty = lhs_addr.ty.clone();
            let coerced = llvm_ops::coerce(
                self.context,
                &self.builder,
                rhs_val,
                &value_type_name(&rhs_val),
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
                let lhs_name = value_type_name(&lhs_val);
                let rhs_name = value_type_name(&coerced);
                let result_ty = llvm_ops::result_type(&lhs_name, &rhs_name);
                let lhs_c = llvm_ops::coerce(self.context, &self.builder, lhs_val, &lhs_name, &result_ty);
                let rhs_c = llvm_ops::coerce(self.context, &self.builder, coerced, &rhs_name, &result_ty);
                let result = apply_op(self.context, &self.builder, base_op, lhs_c, rhs_c, &result_ty, None)?;
                let fitted = fit(result);
                if matches!(lhs, Expression::Index { .. } | Expression::ArrayIndex { .. }) {
                    // Compound store into a struct-reference slot transfers
                    // ownership like any other index store.
                    self.index_refcount_ops(lhs_addr.ty.as_ref(), lhs_addr.llvm_ty.unwrap(), lhs_addr.ptr, fitted)?;
                }
                if let Expression::MemberRef { .. } = lhs {
                    // Compound store into a struct-typed field transfers
                    // ownership like any other reference-slot store.
                    self.field_refcount_ops(lhs, lhs_addr.ptr)?;
                }
                lhs_addr
                    .store(&self.builder, fitted)
                    .ok_or_else(|| "compound store".to_string())?;
                return Ok(fitted);
            }
            if matches!(lhs, Expression::Index { .. } | Expression::ArrayIndex { .. }) {
                // The element type is resolved from the buffer's pointee
                // (`Data`), not the index expression itself.
                self.index_refcount_ops(lhs_addr.ty.as_ref(), lhs_addr.llvm_ty.unwrap(), lhs_addr.ptr, coerced)?;
            }
            if let Expression::MemberRef { .. } = lhs {
                // A struct-typed field is one reference slot: storing over it
                // releases the old occupant and acquires the new value.
                    self.field_refcount_ops(lhs, lhs_addr.ptr)?;
            }
            lhs_addr
                .store(&self.builder, coerced)
                .ok_or_else(|| "assign store".to_string())?;
            return Ok(coerced);
        }

        let lhs_val = self.codegen_expr(lhs)?;
        let rhs_val = self.codegen_expr(rhs)?;
        let lhs_name = value_type_name(&lhs_val);
        let rhs_name = value_type_name(&rhs_val);
        let result_ty = llvm_ops::result_type(&lhs_name, &rhs_name);
        let lhs_c = llvm_ops::coerce(self.context, &self.builder, lhs_val, &lhs_name, &result_ty);
        let rhs_c = llvm_ops::coerce(self.context, &self.builder, rhs_val, &rhs_name, &result_ty);
        // Pointer arithmetic needs the pointer's element type (`char*` strides
        // i8); `value_type_name` flattens pointers to `void*`, so use the
        // sema type of the lhs expression for that.
        let ptr_elem = self
            .value_sema_type(lhs)
            .and_then(|ty| ty.strip_suffix('*').map(|s| s.to_string()))
            .and_then(|base| self.types.get(&base));
        apply_op(self.context, &self.builder, *op, lhs_c, rhs_c, &result_ty, ptr_elem)
    }

    /// Resolve an lvalue expression to an Address (assignment target).
    fn codegen_lvalue(&mut self, expr: &Expression) -> Result<Address<'ctx>, String> {
        match expr {
            Expression::SymbolRef { id, .. } => self
                .frame
                .find_local(id)
                .cloned()
                .ok_or_else(|| format!("unknown lvalue {}", id)),
            Expression::ThisRef => self
                .frame
                .find_local("this")
                .cloned()
                .ok_or_else(|| "no this".to_string()),
            Expression::MemberRef { lhs, name } => {
                let struct_name = self.struct_name_of(lhs).unwrap_or_default();
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
                    .ok_or_else(|| format!("no field {}.{}", struct_name, name))?;
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
                Ok(Address::with_llvm_ty(name, &ty_name, field_ty, gep))
            }
            Expression::Index { lhs, rhs } | Expression::ArrayIndex { lhs, rhs, .. } => {
                // POD array element store: `arr[i] = v` → GEP + store.
                let index = self.codegen_expr(rhs)?;
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
                Ok(Address::with_llvm_ty("idxl", &elem_name, value_ty, gep))
            }
            _ => Err("unsupported lvalue".to_string()),
        }
    }

    fn codegen_unary(&mut self, op: UnaryOp, operand: &Expression) -> Result<BasicValueEnum<'ctx>, String> {
        use UnaryOp::*;
        match op {
            Neg => {
                let value = self.codegen_expr(operand)?;
                match value {
                    BasicValueEnum::IntValue(v) => Ok(BasicValueEnum::IntValue(
                        self.builder.build_int_neg(v, "neg").map_err(|e| e.to_string())?,
                    )),
                    BasicValueEnum::FloatValue(v) => Ok(BasicValueEnum::FloatValue(
                        self.builder
                            .build_float_neg(v, "fneg")
                            .map_err(|e| e.to_string())?,
                    )),
                    _ => Err("unsupported neg operand".to_string()),
                }
            }
            Pos => self.codegen_expr(operand),
            LogicalNot => {
                let value = self.codegen_expr(operand)?;
                let b = llvm_ops::as_bool(self.context, &self.builder, value);
                Ok(BasicValueEnum::IntValue(
                    self.builder.build_not(b, "lnot").map_err(|e| e.to_string())?,
                ))
            }
            BitNot => {
                let value = self.codegen_expr(operand)?;
                match value {
                    BasicValueEnum::IntValue(v) => Ok(BasicValueEnum::IntValue(
                        self.builder.build_not(v, "bnot").map_err(|e| e.to_string())?,
                    )),
                    _ => Err("unsupported bitnot operand".to_string()),
                }
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

        let cond = self.codegen_expr(condition)?;
        let cond_bool = llvm_ops::as_bool(self.context, &self.builder, cond);
        self.builder
            .build_conditional_branch(cond_bool, true_block, false_block)
            .map_err(|e| e.to_string())?;

        self.builder.position_at_end(true_block);
        let true_val = self.codegen_expr(true_expr)?;
        self.builder
            .build_unconditional_branch(merge_block)
            .map_err(|e| e.to_string())?;
        let true_end = self.builder.get_insert_block().expect("insert block");

        self.builder.position_at_end(false_block);
        let false_val = self.codegen_expr(false_expr)?;
        self.builder
            .build_unconditional_branch(merge_block)
            .map_err(|e| e.to_string())?;
        let false_end = self.builder.get_insert_block().expect("insert block");

        self.builder.position_at_end(merge_block);
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
) -> Result<BasicValueEnum<'ctx>, String> {
    match (lhs, rhs) {
        (BasicValueEnum::IntValue(l), BasicValueEnum::IntValue(r)) => {
            // Mixed widths: coerce both to the wider one before the op.
            let (l2, r2) = if l.get_type().get_bit_width() == r.get_type().get_bit_width() {
                (l, r)
            } else if l.get_type().get_bit_width() > r.get_type().get_bit_width() {
                let r2 = builder
                    .build_int_s_extend(r, l.get_type(), "argw")
                    .unwrap_or(r);
                (l, r2)
            } else {
                let l2 = builder
                    .build_int_s_extend(l, r.get_type(), "argw")
                    .unwrap_or(l);
                (l2, r)
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
        (BasicValueEnum::PointerValue(p), BasicValueEnum::IntValue(i)) => {
            match op {
                BinaryOp::Add | BinaryOp::Sub => {
                    let idx = if op == BinaryOp::Add {
                        i
                    } else {
                        builder.build_int_neg(i, "negidx").unwrap_or(i)
                    };
                    // Stride by the pointer's element type (`char*` → i8,
                    // `int*` → i32); opaque pointers carry no element info.
                    let element_ty = match ptr_elem {
                        Some(BasicTypeEnum::IntType(it)) => it,
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
            let (li, ri) = match (l_kind, r_kind) {
                (BasicValueEnum::IntValue(i), _) => {
                    let li = if i.get_type().get_bit_width() < 64 {
                        builder
                            .build_int_s_extend(i, context.i64_type(), "argw")
                            .map_err(|e| e.to_string())?
                    } else {
                        i
                    };
                    (li, as_int)
                }
                (_, BasicValueEnum::IntValue(i)) => {
                    let ri = if i.get_type().get_bit_width() < 64 {
                        builder
                            .build_int_s_extend(i, context.i64_type(), "argw")
                            .map_err(|e| e.to_string())?
                    } else {
                        i
                    };
                    (as_int, ri)
                }
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

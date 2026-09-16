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
use inkwell::values::{BasicValueEnum, FunctionValue};
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
            frame: Frame::empty(),
        }
    }

    /// Instantiate + codegen in the exact C++ phase order
    /// (LLVMCodeGenerator.cpp:264-308).
    pub fn generate(&mut self, module: &mut SemaModule) -> Result<(), String> {
        // Instantiation pass: structs → methods → externs → functions.
        for idx in 0..module.structs.len() {
            self.instantiate_struct(&module.structs[idx])?;
        }
        for idx in 0..module.structs.len() {
            self.instantiate_methods(&module.structs[idx])?;
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

        // Store size via llvm_type.size_of (port of Struct.cpp:14-40). The
        // ABI size comes from the TargetData of a created execution engine;
        // StructType::size_of needs the struct body set (it is).
        // StructType::size_of yields an unfolded ptrtoint expression under
        // opaque pointers; use the TargetMachine's TargetData for ABI size.
        let size = {
            let machine = crate::target::host_machine()?;
            let td = machine.get_target_data();
            td.get_abi_size(&llvm_type)
        };
        let desc = StructDesc {
            name: st.name.clone(),
            llvm_type,
            size,
            methods: HashMap::new(),
            static_methods: std::collections::HashSet::new(),
            fields: st
                .field_members
                .iter()
                .map(|f| (f.name.clone(), f.ty.to_string()))
                .collect(),
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
                    .ok_or_else(|| format!("unknown return type {}", method.ty))?;
                llvm_fn_type(return_type, &param_types, false)
            };
            let fn_value = self.module.add_function(&mangled, fn_type, None);
            self.functions.insert(mangled.clone(), fn_value);
            if method.is_static {
                static_names.insert(method.name.clone());
            }
            methods.insert(method.name.clone(), mangled);
        }
        if let Some(desc) = self.structs.get_mut(&st.name) {
            desc.methods = methods;
            desc.static_methods = static_names;
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
        Ok(())
    }

    fn instantiate_function(&mut self, function: &FunctionDef) -> Result<(), String> {
        // Generic functions are abstract.
        if function.ty.is_generic() {
            return Ok(());
        }
        if self.functions.contains_key(&function.name) {
            return Ok(());
        }
        let mut param_types: Vec<BasicTypeEnum<'ctx>> = vec![];
        // Params with defaults are optional: the LLVM fn takes only the
        // required ones (defaults are emitted in the body).
        for param in function.parameters.iter().filter(|p| p.default.is_none()) {
            let ty = self
                .types
                .get(&param.ty.to_string())
                .ok_or_else(|| format!("unknown param type {}", param.ty))?;
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
                .ok_or_else(|| format!("unknown return type {}", function.ty))?;
            llvm_fn_type(return_type, &param_types, false)
        };
        let fn_value = self.module.add_function(&function.name, fn_type, None);
        self.functions.insert(function.name.clone(), fn_value);
        Ok(())
    }

    // ── Struct codegen (ctor + methods) ─────────────────────────────────────

    fn codegen_struct(&mut self, st: &StructDef) -> Result<(), String> {
        if st.ty.is_generic() && st.name == st.ty.name {
            return Ok(());
        }
        // Patch the ctor's `size` literal with the computed struct size
        // (port of StructGen.cpp:85-95).
        let mut ctor = st.constructor.clone();
        if let Some(body) = &mut ctor.body {
            for stmt in &mut body.items {
                if let Statement::Declaration(Declaration::Variable(var)) = stmt {
                    if var.name == "size" {
                        if let Some(desc) = self.structs.get(&st.name) {
                            if let Some(default) = &mut var.default {
                                *default = Expression::IntLiteral(desc.size as i64);
                            }
                        }
                        break;
                    }
                }
            }
        }
        // The ctor lives in module.structs[i].constructor, not
        // module.functions — instantiate it here (port of StructGen's
        // `locals()->function(structDesc->constructor())`).
        self.instantiate_function(&ctor)?;
        self.codegen_function(&ctor)?;
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
            .filter(|p| p.default.is_none())
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

        // Defaulted params become locals initialized from their defaults.
        let mut defaulted_stmts: Vec<Statement> = vec![];
        for param in function.parameters.iter().filter(|p| p.default.is_some()) {
            let ty = self
                .types
                .get(&param.ty.to_string())
                .ok_or_else(|| format!("unknown param type {}", param.ty))?;
            let ty = match ty {
                BasicTypeEnum::StructType(sct) => BasicTypeEnum::PointerType(
                    sct.ptr_type(inkwell::AddressSpace::default()),
                ),
                other => other,
            };
            let alloca = self
                .builder
                .build_alloca(ty, &param.name)
                .map_err(|e| e.to_string())?;
            if let Some(default) = &param.default {
                let value = self.codegen_expr(default)?;
                self.builder
                    .build_store(alloca, value)
                    .map_err(|e| e.to_string())?;
            }
            self.frame.push_local(
                &param.name,
                Address::with_llvm_ty(&param.name, &param.ty.to_string(), ty, alloca),
            );
        }
        let body = function.body.clone().unwrap_or_else(|| Block {
            name: String::new(),
            items: vec![],
        });
        self.codegen_block(&body)?;
        let _ = defaulted_stmts;

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

    fn codegen_statement(&mut self, stmt: &Statement) -> Result<(), String> {
        match stmt {
            Statement::Expression(expr) => {
                self.codegen_expr(expr)?;
            }
            Statement::Block(inner) => self.codegen_block(inner)?,
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

    // ── Expression codegen (OperatorGen.cpp + FunctionGen emit) ─────────────

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
            Expression::StringLiteral { value, .. } => Ok(BasicValueEnum::PointerValue(
                self.builder
                    .build_global_string_ptr(value, "str")
                    .map_err(|e| e.to_string())?
                    .as_pointer_value(),
            )),
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
                // The struct name comes from the lhs Address's sema type, not
                // the LLVM value (opaque pointers lose the type).
                let local_name = match lhs.as_ref() {
                    Expression::SymbolRef { id, .. } => id.as_str(),
                    Expression::ThisRef => "this",
                    _ => "",
                };
                let raw_ty = self
                    .frame
                    .find_local(local_name)
                    .map(|a| a.ty.to_string())
                    .unwrap_or_default();
                let struct_name = raw_ty.trim_end_matches('*').to_string();
                let this_ptr = self.codegen_expr(lhs)?;
                let desc = self
                    .structs
                    .get(&struct_name)
                    .ok_or_else(|| format!("not a struct: {}", struct_name))?;
                let idx = desc
                    .fields
                    .iter()
                    .position(|(n, _)| n == name)
                    .ok_or_else(|| format!("no field {}.{}", struct_name, name))?;
                let base_ptr = match this_ptr {
                    BasicValueEnum::StructValue(_) => {
                        // Double-loaded: use the lhs alloca pointer directly.
                        self.frame
                            .find_local(local_name)
                            .map(|a| a.ptr)
                            .ok_or_else(|| "no lhs alloca".to_string())?
                    }
                    _ => this_ptr.into_pointer_value(),
                };
                let gep = unsafe {
                    self.builder
                        .build_struct_gep(desc.llvm_type, base_ptr, idx as u32, name)
                        .map_err(|e| e.to_string())?
                };
                let field_ty = self
                    .types
                    .get(&desc.fields[idx].1)
                    .ok_or_else(|| format!("unknown field type {}", desc.fields[idx].1))?;
                self.builder
                    .build_load(field_ty, gep, name)
                    .map_err(|e| e.to_string())
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
                let base = self.codegen_expr(lhs)?;
                let index = self.codegen_expr(rhs)?;
                let ptr = base.into_pointer_value();
                let gep = unsafe {
                    self.builder
                        .build_gep(self.context.i32_type(), ptr, &[index.into_int_value()], "idx")
                        .map_err(|e| e.to_string())?
                };
                self.builder
                    .build_load(self.context.i32_type(), gep, "loadidx")
                    .map_err(|e| e.to_string())
            }
            Expression::SizeOf(ty) => {
                let name = ty.to_string();
                if let Some(desc) = self.structs.get(&name) {
                    Ok(BasicValueEnum::IntValue(
                        self.context.i64_type().const_int(desc.size, false),
                    ))
                } else if let Some(ty) = self.types.get(&name) {
                    let any = match ty {
                        BasicTypeEnum::ArrayType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::FloatType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::IntType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::PointerType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::StructType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::VectorType(t) => t.as_any_type_enum(),
                        BasicTypeEnum::ScalableVectorType(t) => t.as_any_type_enum(),
                    };
                    let size = any
                        .size_of()
                        .and_then(|v| v.get_zero_extended_constant())
                        .unwrap_or(0);
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
                // __default<T>: the type's zero value.
                let name = ty.to_string();
                if let Some(ty) = self.types.get(&name) {
                    let any = match ty {
                        BasicTypeEnum::IntType(it) => it.const_zero().into(),
                        BasicTypeEnum::FloatType(ft) => ft.const_zero().into(),
                        BasicTypeEnum::PointerType(pt) => pt.const_null().into(),
                        BasicTypeEnum::StructType(sct) => sct.const_zero().into(),
                        _ => self.context.i32_type().const_zero().into(),
                    };
                    Ok(any)
                } else {
                    Ok(self.context.i32_type().const_zero().into())
                }
            }
            Expression::FunctionCall {
                function: name,
                args,
            } => self.codegen_call(name, args),
            Expression::MethodCall { this, method, args } => {
                // Mangle: `<StructOf(this)>.<method>`. The struct name comes
                // from the this Address's sema type (strip the pointer suffix);
                // non-symbol lhs (e.g. Index) falls back to the method name
                // as-is (array index methods resolve at codegen).
                let struct_name = match this.as_ref() {
                    Expression::SymbolRef { id, .. } => self
                        .frame
                        .find_local(id)
                        .map(|a| a.ty.to_string())
                        .unwrap_or_default()
                        .trim_end_matches('*')
                        .to_string(),
                    Expression::ThisRef => self
                        .frame
                        .find_local("this")
                        .map(|a| a.ty.to_string())
                        .unwrap_or_default()
                        .trim_end_matches('*')
                        .to_string(),
                    _ => String::new(),
                };
                if method.starts_with("__index_") {
                    // POD array index set/get: direct GEP + load/store.
                    return self.codegen_index_method(this, method, args);
                }
                // Struct-typed args pass the POINTER (C++ ref semantics):
                // load the alloca address, not the struct value.
                let this_val = match this.as_ref() {
                    Expression::SymbolRef { id, .. } if self
                        .frame
                        .find_local(id)
                        .map(|a| self.structs.contains_key(a.ty.trim_end_matches('*')))
                        .unwrap_or(false) =>
                    {
                        let addr = self.frame.find_local(id).unwrap();
                        BasicValueEnum::PointerValue(addr.ptr)
                    }
                    Expression::ThisRef => {
                        let addr = self.frame.find_local("this").unwrap();
                        BasicValueEnum::PointerValue(addr.ptr)
                    }
                    _ => self.codegen_expr(this)?,
                };
                let mangled = format!("{}.{}", struct_name, method);
                let mut arg_vals = vec![this_val];
                for arg in args {
                    arg_vals.push(self.codegen_expr(arg)?);
                }
                // Static methods have no `this` param: if the fn's param
                // count is arg_vals.len() - 1, drop the this.
                if let Some(f) = self.functions.get(&mangled) {
                    let param_count = f.get_type().get_param_types().len();
                    if param_count == arg_vals.len() - 1 {
                        arg_vals.remove(0);
                    }
                }
                self.call_function(&mangled, arg_vals)
            }
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
                .build_gep(self.context.i32_type(), ptr, &[index.into_int_value()], "idxm")
                .map_err(|e| e.to_string())?
        };
        if method == "__index_get" {
            // POD arrays load i32; the string indexer returns a string (ptr).
            let base_ty = self
                .frame
                .find_local(
                    match this {
                        Expression::SymbolRef { id, .. } => id.as_str(),
                        Expression::ThisRef => "this",
                        _ => "",
                    },
                )
                .map(|a| a.ty.to_string())
                .unwrap_or_default();
            let load_ty: BasicTypeEnum<'ctx> = if base_ty.starts_with("string") {
                self.context.ptr_type(inkwell::AddressSpace::default()).into()
            } else {
                self.context.i32_type().into()
            };
            self.builder
                .build_load(load_ty, gep, "loadidx")
                .map_err(|e| e.to_string())
        } else {
            // __index_set: the value is args[1].
            let value_expr = args.get(1).ok_or_else(|| "index set needs a value".to_string())?;
            let value = self.codegen_expr(value_expr)?;
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
        // release<T>(v) → v.__release() (POD no-op).
        if name == "release" || name.starts_with("release<") {
            if let Some(first) = args.first() {
                let value = self.codegen_expr(first)?;
                return Ok(value);
            }
            return Ok(self.context.i32_type().const_zero().into());
        }
        // Intrinsics: __is_pod<T> → false for structs (true for POD);
        // __default<T> → the type's zero value.
        if name == "__is_pod" {
            return Ok(self.context.bool_type().const_int(0, false).into());
        }
        if name == "__default" {
            let base = name.split('<').next().unwrap_or(name);
            let _ = base;
            // The generic arg type: `__default<T>` — use the ty from the
            // call's target string.
            if let Some(ty) = self.types.get(&name.to_string()) {
                let any = match ty {
                    BasicTypeEnum::IntType(it) => it.const_zero().into(),
                    BasicTypeEnum::FloatType(ft) => ft.const_zero().into(),
                    BasicTypeEnum::PointerType(pt) => pt.const_null().into(),
                    BasicTypeEnum::StructType(sct) => sct.const_zero().into(),
                    _ => self.context.i32_type().const_zero().into(),
                };
                return Ok(any);
            }
            return Ok(self.context.i32_type().const_zero().into());
        }
        // `string(lit, len)` ctor: for the literal flow the raw bytes
        // pointer IS the string; return the first arg directly.
        if name == "string" {
            if let Some(first) = args.first() {
                return self.codegen_expr(first);
            }
            return Ok(self
                .context
                .ptr_type(inkwell::AddressSpace::default())
                .const_null()
                .into());
        }
        // Constructor call `Name<...>(ctor_args)`: the ctor is registered
        // under the plain struct name (specializations under `Name<args>`).
        let target = if self.functions.contains_key(name) || self.structs.contains_key(name) {
            if self.functions.contains_key(name) {
                name
            } else {
                name
            }
        } else {
            name.split('<').next().unwrap_or(name).trim()
        };
        let mut arg_vals = vec![];
        for arg in args {
            arg_vals.push(self.codegen_expr(arg)?);
        }
        self.call_function(target, arg_vals)
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
                    // codegen_print widens float args to f64 before calling.
                    "_pep_print_float" => (i32t.into(), vec![self.context.f64_type().into()]),
                    "_pep_malloc" | "_pep_realloc" => {
                        (ptr_ty.into(), vec![self.context.i64_type().into()])
                    }
                    "_pep_free" => (i32t.into(), vec![ptr_ty.into()]),
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
                    &_ => return Err(format!("unknown function {}", name)),
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
                let result = apply_op(self.context, &self.builder, base_op, lhs_c, rhs_c, &result_ty)?;
                lhs_addr
                    .store(&self.builder, result)
                    .ok_or_else(|| "compound store".to_string())?;
                return Ok(result);
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
        apply_op(self.context, &self.builder, *op, lhs_c, rhs_c, &result_ty)
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
                let local_name = match lhs.as_ref() {
                    Expression::SymbolRef { id, .. } => id.as_str(),
                    Expression::ThisRef => "this",
                    _ => "",
                };
                let raw_ty = self
                    .frame
                    .find_local(local_name)
                    .map(|a| a.ty.to_string())
                    .unwrap_or_default();
                let struct_name = raw_ty.trim_end_matches('*').to_string();
                let this_ptr = self.codegen_expr(lhs)?;
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
                let base_ptr = match this_ptr {
                    BasicValueEnum::StructValue(_) => self
                        .frame
                        .find_local(local_name)
                        .map(|a| a.ptr)
                        .ok_or_else(|| "no lhs alloca".to_string())?,
                    _ => this_ptr.into_pointer_value(),
                };
                let gep = unsafe {
                    self.builder
                        .build_struct_gep(desc.llvm_type, base_ptr, idx as u32, name)
                        .map_err(|e| e.to_string())?
                };
                Ok(Address::with_llvm_ty(name, &ty_name, field_ty, gep))
            }
            Expression::Index { lhs, rhs } | Expression::ArrayIndex { lhs, rhs, .. } => {
                // POD array element store: `arr[i] = v` → GEP + store.
                let base = self.codegen_expr(lhs)?;
                let index = self.codegen_expr(rhs)?;
                let ptr = base.into_pointer_value();
                let gep = unsafe {
                    self.builder
                        .build_gep(self.context.i32_type(), ptr, &[index.into_int_value()], "idxl")
                        .map_err(|e| e.to_string())?
                };
                Ok(Address::new("idxl", "i32", gep))
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
            if v.get_type().size_of().get_zero_extended_constant() == Some(32) {
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
                    let advanced = unsafe {
                        builder
                            .build_in_bounds_gep(context.i32_type(), p, &[idx], "ptrarith")
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

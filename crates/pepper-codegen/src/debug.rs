//! Debug info (`-g`): line tables, subprograms, scopes and variables, as
//! DWARF 4 on Linux and macOS and CodeView on Windows (see INTERNALS.md
//! §4.4).
//!
//! A [`DebugInfo`] belongs to one LLVM module, which is one compile unit.
//! Each Pepper block is a `DILexicalBlock` ([`DebugInfo::push_block`]), and
//! each local and parameter is declared in the block it is visible in
//! ([`DebugInfo::declare`]), with the types `debug_types` builds.
//! Codegen gives each function it compiles from source a `DISubprogram`
//! ([`DebugInfo::begin_function`]) and stamps every instruction with the
//! location of the expression or statement being compiled
//! ([`DebugInfo::location`]), so compiler-inserted code (acquires, releases,
//! drops) is attributed to the source that caused it. [`DebugInfo::finish`]
//! then gives every other defined function (thunks, constructors' helpers,
//! global initializers) an artificial subprogram, and moves to line 0 any
//! instruction stamped while codegen was emitting another function, so the
//! module verifies. LLVM's inliner adds the `inlinedAt` chains itself.

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::context::Context;
use inkwell::debug_info::{
    AsDIScope, DICompileUnit, DIFile, DIFlags, DIFlagsConstants, DILocation, DIScope, DISubprogram, DISubroutineType,
    DWARFEmissionKind, DWARFSourceLanguage, DebugInfoBuilder,
};
use inkwell::module::{FlagBehavior, Module};
use inkwell::basic_block::BasicBlock;
use inkwell::debug_info::DIType;
use inkwell::llvm_sys::prelude::LLVMMetadataRef;
use inkwell::values::{AsValueRef, FunctionValue, GlobalValue, PointerValue};
use pepper_parser::diagnostic::{FileId, Loc, SourceMap, Sources};
use std::collections::HashMap;

/// The debug info of one module.
pub struct DebugInfo<'ctx> {
    builder: DebugInfoBuilder<'ctx>,
    unit: DICompileUnit<'ctx>,
    /// The directory file names are relative to (the compiler's working
    /// directory).
    directory: String,
    /// Each source's name and the byte offset of each line, by file.
    lines: HashMap<FileId, (String, Vec<u32>)>,
    files: HashMap<FileId, DIFile<'ctx>>,
    /// The type every subprogram has: types come in phase 2.
    signature: DISubroutineType<'ctx>,
    optimized: bool,
    /// The scopes of the function being compiled: its subprogram, then
    /// each enclosing block.
    scopes: Vec<DIScope<'ctx>>,
    /// Each lexical block's subprogram.
    block_owners: HashMap<LLVMMetadataRef, LLVMMetadataRef>,
    /// Types by Pepper type name (see `debug_types`).
    pub(crate) types: HashMap<String, DIType<'ctx>>,
    /// The tuples and structs whose types are being built: a reference
    /// back to one is a declaration (see `debug_types`).
    pub(crate) building: std::collections::HashSet<String>,
    /// The plain enums, by name: `(location, representation, cases)`.
    pub(crate) enums: HashMap<String, (Loc, String, Vec<(String, i64)>)>,
}

impl<'ctx> DebugInfo<'ctx> {
    /// Debug info for `module`, whose compile unit is named `unit_name` (a
    /// source file of the unit, or the module's name). `sources` are the
    /// program's files; `optimized` marks code built with `-O1` or above.
    pub fn new(module: &Module<'ctx>, sources: &SourceMap, unit_name: &str, optimized: bool) -> Self {
        let directory = std::env::current_dir().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default();
        // gdb trusts the line table (to skip a function's prologue, for one)
        // only from a producer it knows to be LLVM, so the producer says so,
        // as rustc's does.
        let producer = format!("clang LLVM (pepper {})", env!("CARGO_PKG_VERSION"));
        let (builder, unit) = module.create_debug_info_builder(
            true,
            DWARFSourceLanguage::C,
            unit_name,
            &directory,
            &producer,
            optimized,
            "",
            0,
            "",
            DWARFEmissionKind::Full,
            0,
            false,
            false,
            "",
            "",
        );
        let signature = builder.create_subroutine_type(unit.get_file(), None, &[], DIFlags::ZERO);
        let mut lines = HashMap::new();
        let mut id = 0;
        while let Some((name, text)) = sources.get(FileId(id)) {
            let mut starts = vec![0];
            starts.extend(text.bytes().enumerate().filter(|&(_, b)| b == b'\n').map(|(i, _)| i as u32 + 1));
            // A canonical Windows path's `\\?\` prefix confuses debuggers.
            let name = name.strip_prefix(r"\\?\").unwrap_or(name);
            lines.insert(FileId(id), (name.to_string(), starts));
            id += 1;
        }
        let context = module.get_context();
        let int = context.i32_type();
        module.add_basic_value_flag(
            "Debug Info Version",
            FlagBehavior::Warning,
            int.const_int(inkwell::debug_info::debug_metadata_version() as u64, false),
        );
        // The object format follows the triple, which a simulated host
        // (`with_simulated_host`) leaves as this machine's.
        if crate::target::triple_name().contains("-windows") {
            module.add_basic_value_flag("CodeView", FlagBehavior::Warning, int.const_int(1, false));
        } else {
            // DWARF 4, as Rust emits: LLVM's DWARF 5 adds a `.debug_names`
            // index per object (the C API cannot turn it off), and GNU ld
            // concatenates those into one gdb rejects.
            module.add_basic_value_flag("Dwarf Version", FlagBehavior::Warning, int.const_int(4, false));
        }
        DebugInfo { builder, unit, directory, lines, files: HashMap::new(), signature,
            optimized,
            scopes: vec![],
            block_owners: HashMap::new(),
            types: HashMap::new(),
            building: Default::default(),
            enums: HashMap::new(),
        }
    }

    /// The 1-based line and column of `loc`, or `None` for no location.
    pub fn line_column(&self, loc: Loc) -> Option<(u32, u32)> {
        let (_, starts) = self.lines.get(&loc.known()?.file)?;
        let offset = loc.span.start as u32;
        let line = starts.partition_point(|&start| start <= offset);
        Some((line as u32, offset - starts[line - 1] + 1))
    }

    /// The builder, for `debug_types`.
    pub(crate) fn builder(&self) -> &DebugInfoBuilder<'ctx> {
        &self.builder
    }

    /// The file `loc` is in, or the unit's.
    pub(crate) fn file_of(&mut self, loc: Loc) -> DIFile<'ctx> {
        match loc.known() {
            Some(loc) => self.file(loc.file),
            None => self.unit.get_file(),
        }
    }

    /// The compile unit, as a scope for types.
    pub(crate) fn unit_scope(&self) -> DIScope<'ctx> {
        self.unit.as_debug_info_scope()
    }

    fn file(&mut self, file: FileId) -> DIFile<'ctx> {
        if let Some(&f) = self.files.get(&file) {
            return f;
        }
        let f = match self.lines.get(&file) {
            Some((name, _)) => self.builder.create_file(name, &self.directory),
            None => self.unit.get_file(),
        };
        self.files.insert(file, f);
        f
    }

    /// Start compiling `function`, declared at `loc` as `name` (its display
    /// name, such as `Array<int>.append`), and `synthesized` by the compiler
    /// rather than written: give it a subprogram, which becomes the scope of
    /// every [`Self::location`] until [`Self::end_function`].
    pub fn begin_function(&mut self, function: FunctionValue<'ctx>, name: &str, loc: Loc, synthesized: bool) {
        let line = self.line_column(loc).map_or(0, |(line, _)| line);
        let file = self.file_of(loc);
        let flags = if synthesized { DIFlags::ARTIFICIAL } else { DIFlags::PROTOTYPED };
        let subprogram = self.subprogram(function, name, file, line, flags);
        self.scopes = vec![subprogram.as_debug_info_scope()];
    }

    /// Done compiling the current function.
    pub fn end_function(&mut self) {
        self.scopes.clear();
    }

    /// Enter a block of the current function that starts at `loc` (its
    /// first statement's location; the enclosing scope's when unknown).
    pub fn push_block(&mut self, loc: Loc) {
        let (Some(&parent), Some(subprogram)) = (self.scopes.last(), self.scopes.first()) else { return };
        let subprogram = subprogram.as_mut_ptr();
        let (line, column) = self.line_column(loc).unwrap_or((0, 0));
        let file = self.file_of(loc);
        let block = self.builder.create_lexical_block(parent, file, line, column).as_debug_info_scope();
        self.block_owners.insert(block.as_mut_ptr(), subprogram);
        self.scopes.push(block);
    }

    /// Leave the block [`Self::push_block`] entered.
    pub fn pop_block(&mut self) {
        if self.scopes.len() > 1 {
            self.scopes.pop();
        }
    }

    /// Declare the variable `name` of type `ty`, declared at `loc` and
    /// stored at `storage`, in the current scope, at the end of `block`:
    /// parameter number `argument` (from 1) when it is one.
    pub fn declare(
        &mut self,
        context: &'ctx Context,
        storage: PointerValue<'ctx>,
        name: &str,
        ty: DIType<'ctx>,
        loc: Loc,
        argument: Option<u32>,
        block: BasicBlock<'ctx>,
    ) {
        let Some(&scope) = self.scopes.last() else { return };
        let file = self.file_of(loc);
        // A parameter without a location (`this`) is declared on its
        // function's line.
        let line = self.line_column(loc).map_or(0, |(line, _)| line);
        let variable = match argument {
            Some(number) => {
                let flags = if name == "this" { DIFlags::ARTIFICIAL | DIFlags::OBJECT_POINTER } else { DIFlags::ZERO };
                self.builder.create_parameter_variable(scope, name, number, file, line, ty, true, flags)
            }
            None => self.builder.create_auto_variable(scope, name, file, line, ty, true, DIFlags::ZERO, 0),
        };
        let at = self.builder.create_debug_location(context, line, 0, scope, None);
        // LLVM 19 declares with a debug record, which inkwell's wrapper
        // mistakes for an instruction.
        #[cfg(feature = "llvm18-1")]
        self.builder.insert_declare_at_end(storage, Some(variable), None, at, block);
        #[cfg(not(feature = "llvm18-1"))]
        unsafe {
            let expression = self.builder.create_expression(vec![]);
            inkwell::llvm_sys::debuginfo::LLVMDIBuilderInsertDeclareRecordAtEnd(
                self.builder.as_mut_ptr(),
                storage.as_value_ref(),
                variable.as_mut_ptr(),
                expression.as_mut_ptr(),
                at.as_mut_ptr(),
                block.as_mut_ptr(),
            );
        }
    }

    fn subprogram(&self, function: FunctionValue<'ctx>, name: &str, file: DIFile<'ctx>, line: u32, flags: DIFlags) -> DISubprogram<'ctx> {
        // No linkage name, as clang gives a C function: a debugger shows a
        // subprogram by its linkage name when it has one, and the linker
        // spelling (`_Ptotal`, see `partition::symbol_name`) is not what the
        // user wrote. The subprogram is tied to its code by address.
        let subprogram = self.builder.create_function(
            self.unit.as_debug_info_scope(),
            name,
            None,
            file,
            line,
            self.signature,
            false,
            true,
            line,
            flags,
            self.optimized,
        );
        function.set_subprogram(subprogram);
        subprogram
    }

    /// Describe the module-scope variable `global`, named `name` and
    /// declared at `loc`, whose value has type `ty`.
    pub fn declare_global(&mut self, context: &'ctx Context, global: GlobalValue<'ctx>, name: &str, ty: DIType<'ctx>, loc: Loc) {
        let file = self.file_of(loc);
        let line = self.line_column(loc).map_or(0, |(line, _)| line);
        let expression =
            self.builder.create_global_variable_expression(self.unit.as_debug_info_scope(), name, name, file, line, ty, false, None, None, 0);
        global.set_metadata(expression.as_metadata_value(context), context.get_kind_id("dbg"));
    }

    /// The location of `loc` in the current function, or `None` outside a
    /// function or for no location.
    pub fn location(&self, context: &'ctx Context, loc: Loc) -> Option<DILocation<'ctx>> {
        let scope = *self.scopes.last()?;
        let (line, column) = self.line_column(loc)?;
        Some(self.builder.create_debug_location(context, line, column, scope, None))
    }

    /// Carry gdb's pretty-printers for the runtime's types
    /// (`runtime/debuggers/gdb_printers.py`) in a `.debug_gdb_scripts`
    /// section, as an inline script gdb loads with the program (ELF only:
    /// the section means nothing to Mach-O or COFF debuggers). The
    /// program's module carries it, kept by `llvm.used`.
    pub fn embed_gdb_printers(&self, module: &Module<'ctx>) {
        let triple = crate::target::triple_name();
        if triple.contains("-windows") || triple.contains("-apple-") {
            return;
        }
        const PRINTERS: &str = include_str!("../../../runtime/debuggers/gdb_printers.py");
        // Kind 4: an inline Python script, its name on the first line.
        let mut bytes = b"\x04pepper/gdb_printers.py\n".to_vec();
        bytes.extend_from_slice(PRINTERS.as_bytes());
        bytes.push(0);
        let context = module.get_context();
        let text = context.const_string(&bytes, false);
        let section = module.add_global(text.get_type(), None, "__pep_debug_gdb_scripts");
        section.set_initializer(&text);
        section.set_constant(true);
        section.set_section(Some(".debug_gdb_scripts"));
        section.set_alignment(1);
        section.set_linkage(inkwell::module::Linkage::Private);
        let pointer = context.ptr_type(inkwell::AddressSpace::default());
        let used = module.add_global(pointer.array_type(1), None, "llvm.used");
        used.set_linkage(inkwell::module::Linkage::Appending);
        used.set_section(Some("llvm.metadata"));
        used.set_initializer(&pointer.const_array(&[section.as_pointer_value()]));
    }

    /// Finish the module's debug info (see the module comment), and give
    /// every defined function an unwind table, so a debugger can walk its
    /// frame.
    pub fn finish(&self, module: &Module<'ctx>) {
        use inkwell::llvm_sys::debuginfo::{LLVMDILocationGetScope, LLVMInstructionGetDebugLoc, LLVMInstructionSetDebugLoc};
        let context = module.get_context();
        let uwtable = context.create_enum_attribute(Attribute::get_named_enum_kind_id("uwtable"), 2);
        for function in module.get_functions() {
            if function.count_basic_blocks() == 0 {
                continue;
            }
            function.add_attribute(AttributeLoc::Function, uwtable);
            let subprogram = match function.get_subprogram() {
                Some(subprogram) => subprogram,
                None => {
                    let name = function.get_name().to_string_lossy().into_owned();
                    self.subprogram(function, &name, self.unit.get_file(), 0, DIFlags::ARTIFICIAL)
                }
            };
            let scope = subprogram.as_debug_info_scope();
            let line_zero = self.builder.create_debug_location(context, 0, 0, scope, None);
            for block in function.get_basic_blocks() {
                let mut instruction = block.get_first_instruction();
                while let Some(i) = instruction {
                    // Stamped in this function's scope, or else unstamped,
                    // as clang leaves a prologue: a location from another
                    // function (codegen emits a thunk in the middle of a
                    // caller) does not verify. LLVM requires a location on
                    // every call, so a call gets line 0, which a debugger
                    // skips: the prologue ends at the first statement.
                    let stamped = unsafe { LLVMInstructionGetDebugLoc(i.as_value_ref()) };
                    let own = !stamped.is_null() && {
                        let stamped_scope = unsafe { LLVMDILocationGetScope(stamped) };
                        let owner = self.block_owners.get(&stamped_scope).copied().unwrap_or(stamped_scope);
                        owner == scope.as_mut_ptr()
                    };
                    if !own {
                        let call = i.get_opcode() == inkwell::values::InstructionOpcode::Call;
                        let location = if call { line_zero.as_mut_ptr() } else { std::ptr::null_mut() };
                        unsafe { LLVMInstructionSetDebugLoc(i.as_value_ref(), location) };
                    }
                    instruction = i.get_next_instruction();
                }
            }
        }
        self.builder.finalize();
    }
}

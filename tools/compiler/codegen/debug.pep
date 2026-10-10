## Debug info (`-g`): line tables, subprograms, scopes and variables, as
## DWARF 4 on Linux and macOS and CodeView on Windows:
## `crates/pepper-codegen/src/debug.rs` in Pepper (see INTERNALS.md §4.4).
##
## A `DebugInfo` belongs to the program's module, which is one compile
## unit, copied into each part `partition.pep` splits it into. Each Pepper
## block is a `DILexicalBlock` (`push_block`), and each local and parameter
## is declared in the block it is visible in (`declare`), with the types
## `debug_types.pep` builds. Codegen gives each function it compiles from
## source a `DISubprogram` (`begin_function`) and stamps every instruction
## with the location of the statement being compiled (`location`), so
## compiler-inserted code (acquires, releases, drops) is attributed to the
## source that caused it. `finish` then gives every other defined function
## (thunks, adapters, global initializers) an artificial subprogram, and
## moves to line 0 any instruction stamped while codegen was emitting
## another function, so the module verifies. LLVM's inliner adds the
## `inlinedAt` chains itself.

import compiler.ast;
import [SourceText] from compiler.diagnostic;
import llvm;
import llvm.llvm_c;
import process;
import [Loc] from compiler.sema;

# The parts of `llvm-c/DebugInfo.h` and `llvm-c/Core.h` the `llvm` package
# does not declare.
extern void* malloc(ulong size);
extern void free(void* pointer);
extern void* LLVMDIBuilderCreateEnumerator(void* builder, char* name, ulong length, long value, int is_unsigned);
extern void* LLVMDIBuilderCreateEnumerationType(
    void* builder,
    void* scope,
    char* name,
    ulong length,
    void* file,
    uint line,
    ulong size_in_bits,
    uint align_in_bits,
    void** elements,
    uint count,
    void* class_type
);
extern void* LLVMDIBuilderCreateArrayType(
    void* builder, ulong size_in_bits, uint align_in_bits, void* element_type, void** subscripts, uint count
);
extern void* LLVMDIBuilderGetOrCreateSubrange(void* builder, long lower_bound, long count);
extern void* LLVMDIBuilderCreateGlobalVariableExpression(
    void* builder,
    void* scope,
    char* name,
    ulong name_length,
    char* linkage,
    ulong linkage_length,
    void* file,
    uint line,
    void* variable_type,
    int local_to_unit,
    void* expression,
    void* declaration,
    uint align_in_bits
);
extern void LLVMGlobalSetMetadata(void* global, uint kind, void* metadata);
extern void LLVMGlobalEraseMetadata(void* global, uint kind);
extern void* LLVMGetSubprogram(void* function);
extern void* LLVMInstructionGetDebugLoc(void* instruction);
extern void* LLVMDILocationGetScope(void* location);
extern ulong LLVMDITypeGetSizeInBits(void* debug_type);

## `LLVMDIFlags`.
const FLAG_FORWARD_DECLARATION: int = 4;
const FLAG_ARTIFICIAL: int = 64;
const FLAG_PROTOTYPED: int = 256;
const FLAG_OBJECT_POINTER: int = 1024;

## The `dbg` metadata kind, fixed in every context.
const DBG_KIND: uint = 0;

## LLVM's opcode for a call (`LLVMCall`).
const OPCODE_CALL: int = 45;

## `items` as a C array of handles, which the caller frees.
_refs(items: llvm.Metadata[]): __ptr<__ptr<void>> {
    __ptr<__ptr<void>> refs = malloc((items.count + 1) * sizeof<__ptr<void>>());
    for (var index in 0..items.count) {
        refs[index] = items[index].ref;
    }
    return refs;
}

## A metadata handle as a number, to key maps by.
_key(metadata: llvm.Metadata): ulong {
    return unsafe_cast<ulong>(metadata.ref);
}

## A `static` block pass's places in the expanded source
## (`--debug-static=expanded`): its header, and each statement it emits, by
## the location of its source.
struct _StaticPlaces {
    var header: (Loc, Loc)? = Optional<(Loc, Loc)>.Empty;
    var lines: Array<(Loc, Loc)> = Array<(Loc, Loc)>();

    construct() {}
}

## The debug info of one module.
export struct DebugInfo {
    var builder: llvm.DebugBuilder;
    var context: llvm.Context;
    var unit: llvm.Metadata;
    ## The unit's file, the file of what has no location.
    var unit_file: llvm.Metadata;
    ## The directory file names are relative to (the compiler's working
    ## directory).
    var directory: String;
    ## Each source's name and the byte offset of each line, by file index.
    var lines: Array<(String, ulong[])> = Array<(String, ulong[])>();
    var files: HashMap<uint, llvm.Metadata> = HashMap<uint, llvm.Metadata>();
    ## The type every subprogram has.
    var signature: llvm.Metadata;
    var optimized: bool;
    ## The scopes of the function being compiled: its subprogram, then
    ## each enclosing block.
    var scopes: llvm.Metadata[] = Array<llvm.Metadata>();
    ## The file each of `scopes` is in.
    var scope_files: uint[] = Array<uint>();
    ## Each lexical block's subprogram, by handle.
    var block_owners: HashMap<ulong, ulong> = HashMap<ulong, ulong>();
    ## A block of a scope in another file than the scope's, by scope handle
    ## and file: where a location in that file goes (`scope_for`).
    var file_blocks: HashMap<String, llvm.Metadata> = HashMap<String, llvm.Metadata>();
    ## Types by Pepper type name (see `debug_types.pep`).
    var types: HashMap<String, llvm.Metadata> = HashMap<String, llvm.Metadata>();
    ## The tuples and structs whose types are being built: a reference
    ## back to one is a declaration (see `debug_types.pep`).
    var building: HashSet<String> = HashSet<String>();
    ## The plain enums, by name: `(location, representation, cases)`.
    var enums: HashMap<String, (Loc, String, Array<(String, long)>)> = HashMap<String, (Loc, String, Array<(String, long)>)>();
    ## `--debug-static=expanded`: where each emitted statement and pass
    ## header is in the expanded source, by its id.
    var static_locations: HashMap<uint, Loc> = HashMap<uint, Loc>();
    ## The passes of `static` blocks being compiled, innermost last (see
    ## `push_static`).
    var _static_passes: Array<_StaticPlaces> = Array<_StaticPlaces>();

    ## Debug info for `ir`, whose compile unit is named `unit_name`.
    ## `sources` are the program's files; `optimized` marks code built with
    ## `-O1` or above.
    construct(ir: llvm.Module, sources: SourceText[], unit_name: String, optimized: bool) {
        var cwd = process.working_directory();
        directory = cwd.is_ok() ? cwd.value().to_string() : "";
        this.optimized = optimized;
        context = ir.context;
        builder = llvm.DebugBuilder(ir);
        unit_file = builder.file(unit_name, directory);
        # gdb trusts the line table (to skip a function's prologue, for one)
        # only from a producer it knows to be LLVM, so the producer says so,
        # as rustc's does.
        unit = builder.compile_unit(unit_file, "clang LLVM (pepper)", llvm.DwarfLanguage.C, optimized);
        signature = builder.subroutine_type(unit_file, llvm.Metadata(), Array<llvm.Metadata>());
        for (var source in sources) {
            var starts = Array<ulong>();
            starts.append(0);
            var bytes = source.text.bytes();
            for (var index in 0..bytes.count) {
                if (bytes[index] == 10) {
                    starts.append(index + 1);
                }
            }
            # A canonical Windows path's `\\?\` prefix confuses debuggers.
            var name = source.name.starts_with("\\\\?\\") ?
                source.name.substr_bytes(4, source.name.size - 4) :
                source.name;
            lines.append((name, starts));
        }
        # The object format follows the triple.
        if (ir.target_triple().contains("-windows")) {
            builder.use_codeview();
        } else {
            # DWARF 4, as Rust emits: LLVM's DWARF 5 adds a `.debug_names`
            # index per object (the C API cannot turn it off), and GNU ld
            # concatenates those into one gdb rejects.
            builder.set_dwarf_version(4);
        }
    }

    ## The 1-based line and column of `loc`, or none for no location.
    line_column(loc: Loc): (uint, uint)? {
        if (loc.is_none() or loc.file as ulong >= lines.count) {
            return Optional<(uint, uint)>.Empty;
        }
        var (_, starts) = lines[loc.file as ulong];
        var offset = loc.span.start;
        # The number of line starts at or before the offset.
        ulong low = 0;
        ulong high = starts.count;
        while (low < high) {
            var middle = (low + high) / 2;
            if (starts[middle] <= offset) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return Optional<(uint, uint)>.Value((low as uint, (offset - starts[low - 1] + 1) as uint));
    }

    ## The line of `loc`, or 0 for no location.
    line_of(loc: Loc): uint {
        var found = line_column(loc);
        return found.is_value() ? found.value().0 : 0;
    }

    ## The name a closure's body takes in debug info: `closure at
    ## main.pep:12`, for the closure written at `loc`.
    closure_name(loc: Loc): String? {
        var found = line_column(loc);
        if (!found.is_value()) {
            return Optional<String>.Empty;
        }
        var (name, _) = lines[loc.file as ulong];
        var slash = name.rfind("/");
        var backslash = name.rfind("\\");
        var cut = slash > backslash ? slash : backslash;
        var file = cut < 0 ? name : name.substr_bytes(cut as ulong + 1, name.size - cut as ulong - 1);
        return Optional<String>.Value($"closure at {file}:{found.value().0}");
    }

    ## The file `loc` is in, or the unit's.
    file_of(loc: Loc): llvm.Metadata {
        if (loc.is_none()) {
            return unit_file;
        }
        return file(loc.file);
    }

    file(index: uint): llvm.Metadata {
        var found = files.try_get(index);
        if (found.is_value()) {
            return found.value();
        }
        var made = unit_file;
        if ((index as ulong) < lines.count) {
            var (name, _) = lines[index as ulong];
            made = builder.file(name, directory);
        }
        files[index] = made;
        return made;
    }

    ## Starts compiling `function`, declared at `loc` as `name` (its display
    ## name, such as `Array<int>.append`), and `synthesized` by the compiler
    ## rather than written: gives it a subprogram, which becomes the scope of
    ## every `location` until `end_function`.
    begin_function(function: llvm.Value, name: String, loc: Loc, synthesized: bool) {
        var flags = synthesized ? FLAG_ARTIFICIAL : FLAG_PROTOTYPED;
        var subprogram = _subprogram(function, name, file_of(loc), line_of(loc), flags);
        scopes = [subprogram];
        scope_files = [loc.file];
    }

    ## Done compiling the current function.
    end_function() {
        scopes = Array<llvm.Metadata>();
        scope_files = Array<uint>();
    }

    ## Enters a block of the current function that starts at `loc` (its
    ## first statement's location; the enclosing scope's when unknown).
    push_block(loc: Loc) {
        if (scopes.is_empty) {
            return;
        }
        var at = place(loc);
        var parent = scopes[scopes.count - 1];
        var found = line_column(at);
        var (line, column) = found.is_value() ? found.value() : (0 as uint, 0 as uint);
        var block = builder.lexical_block(parent, file_of(at), line, column);
        block_owners[_key(block)] = _key(scopes[0]);
        scopes.append(block);
        scope_files.append(at.is_none() ? scope_files[scope_files.count - 1] : at.file);
    }

    ## Leaves the block `push_block` entered.
    pop_block() {
        if (scopes.count > 1) {
            scopes.pop();
            scope_files.pop();
        }
    }

    ## Enters a pass of a `static` block: with `--debug-static=expanded`,
    ## the locations of its header and of the statements it emits are moved
    ## to the expanded source (`place`) until `pop_static`. Returns whether
    ## it was entered.
    push_static(loc: Loc, header: uint?, statements: Array<(Loc, uint)>): bool {
        if (static_locations.is_empty) {
            return false;
        }
        var places = _StaticPlaces();
        if (header.is_value()) {
            var target = static_locations.try_get(header.value());
            if (target.is_value()) {
                places.header = Optional<(Loc, Loc)>.Value((loc, target.value()));
            }
        }
        for (var (source, id) in statements) {
            var target = static_locations.try_get(id);
            if (target.is_value()) {
                places.lines.append((source, target.value()));
            }
        }
        _static_passes.append(places);
        return true;
    }

    ## Leaves the pass `push_static` entered.
    pop_static() {
        _static_passes.pop();
    }

    ## Where the debugger shows `loc`: in the expanded source, when it is
    ## the header of a pass being compiled or inside a statement one
    ## emitted (see `push_static`); else `loc`.
    place(loc: Loc): Loc {
        var index = _static_passes.count;
        while (index > 0) {
            index -= 1;
            var pass = _static_passes[index];
            if (pass.header.is_value()) {
                var (header, target) = pass.header.value();
                if (header == loc) {
                    return target;
                }
            }
            for (var (statement, target) in pass.lines) {
                if (statement.file == loc.file
                    and statement.span.start <= loc.span.start
                    and loc.span.start < statement.span.end) {
                    return _relocate(loc, statement, target);
                }
            }
        }
        return loc;
    }

    # `loc`, inside the statement written at `statement`, in its expanded
    # copy at `target`, which keeps the statement's lines: the same line and
    # column relative to the statement's start (the column is approximate
    # where placeholders changed the text's length).
    _relocate(loc: Loc, statement: Loc, target: Loc): Loc {
        var at = line_column(loc);
        var first = line_column(statement);
        var to = line_column(target);
        if (!at.is_value() or !first.is_value() or !to.is_value() or target.file as ulong >= lines.count) {
            return target;
        }
        var (line, column) = at.value();
        var (first_line, first_column) = first.value();
        var (target_line, target_column) = to.value();
        var (_, starts) = lines[target.file as ulong];
        var moved = target_line + (line > first_line ? line - first_line : 0);
        if (moved as ulong > starts.count) {
            return target;
        }
        var start = starts[moved as ulong - 1];
        var end = (moved as ulong) < starts.count ? starts[moved as ulong] - 1 : 0xffffffffffffffff;
        var shifted = (target_column as long) + (column as long) - (first_column as long);
        var offset = start + (shifted < 1 ? 1 : shifted as ulong) - 1;
        if (offset > end) {
            offset = end;
        }
        return Loc.at(target.file, ast.Span(offset, offset));
    }

    # The current scope, or for a location in another file, a block of it
    # in that file: a location takes its file from its scope. Null outside
    # a function.
    _scope_for(loc: Loc): llvm.Metadata {
        if (scopes.is_empty) {
            return llvm.Metadata();
        }
        var scope = scopes[scopes.count - 1];
        if (loc.is_none() or scope_files[scope_files.count - 1] == loc.file) {
            return scope;
        }
        var key = $"{_key(scope)} {loc.file}";
        var found = file_blocks.try_get(key);
        if (found.is_value()) {
            return found.value();
        }
        var block = builder.lexical_block(scope, file(loc.file), 0, 0);
        block_owners[_key(block)] = _key(scopes[0]);
        file_blocks[key] = block;
        return block;
    }

    ## Declares the variable `name` of type `ty`, declared at `loc` and
    ## stored at `storage`, in the current scope, at the end of `block`:
    ## parameter number `argument` (from 1) when it is one, else 0.
    declare(storage: llvm.Value, name: String, ty: llvm.Metadata, loc: Loc, argument: uint, block: llvm.BasicBlock) {
        var at = place(loc);
        var scope = _scope_for(at);
        if (scope.is_null()) {
            return;
        }
        var in_file = file_of(at);
        # A parameter without a location (`this`) is declared on its
        # function's line.
        var line = line_of(at);
        llvm.Metadata variable;
        if (argument > 0) {
            var flags = name == "this" ? FLAG_ARTIFICIAL | FLAG_OBJECT_POINTER : 0;
            variable = llvm.Metadata(
                llvm_c.LLVMDIBuilderCreateParameterVariable(
                    builder.ref, scope.ref, name.c_str(), name.size, argument, in_file.ref, line, ty.ref, 1, flags
                )
            );
        } else {
            variable = builder.local_variable(scope, name, in_file, line, ty);
        }
        builder.declare(storage, variable, builder.location(line, 0, scope), block);
    }

    # A subprogram for `function`. No linkage name, as clang gives a C
    # function: a debugger shows a subprogram by its linkage name when it
    # has one, and the linker spelling (`link.symbol_name`) is not what the
    # user wrote. The subprogram is tied to its code by address.
    _subprogram(function: llvm.Value, name: String, in_file: llvm.Metadata, line: uint, flags: int): llvm.Metadata {
        var subprogram = llvm.Metadata(
            llvm_c.LLVMDIBuilderCreateFunction(
                builder.ref,
                unit.ref,
                name.c_str(),
                name.size,
                "",
                0,
                in_file.ref,
                line,
                signature.ref,
                0,
                1,
                line,
                flags,
                optimized ? 1 : 0
            )
        );
        function.set_subprogram(subprogram);
        return subprogram;
    }

    ## Describes the module-scope variable `global`, named `name` and
    ## declared at `loc`, whose value has type `ty`.
    declare_global(global: llvm.Value, name: String, ty: llvm.Metadata, loc: Loc) {
        var expression = LLVMDIBuilderCreateGlobalVariableExpression(
            builder.ref,
            unit.ref,
            name.c_str(),
            name.size,
            name.c_str(),
            name.size,
            file_of(loc).ref,
            line_of(loc),
            ty.ref,
            0,
            llvm_c.LLVMDIBuilderCreateExpression(builder.ref, __null, 0),
            __null,
            0
        );
        LLVMGlobalSetMetadata(global.ref, DBG_KIND, expression);
    }

    ## The location of `loc` in the current function: null outside a
    ## function or for no location.
    location(loc: Loc): llvm.Metadata {
        var at = place(loc);
        var found = line_column(at);
        if (!found.is_value()) {
            return llvm.Metadata();
        }
        var scope = _scope_for(at);
        if (scope.is_null()) {
            return llvm.Metadata();
        }
        var (line, column) = found.value();
        return builder.location(line, column, scope);
    }

    ## Carries gdb's pretty-printers for the runtime's types (`printers`,
    ## the text of `runtime/debuggers/gdb_printers.py`) in a
    ## `.debug_gdb_scripts` section, as an inline script gdb loads with the
    ## program (ELF only: the section means nothing to Mach-O or COFF
    ## debuggers). `llvm.used` keeps it, so it lands in the program's entry
    ## part.
    embed_gdb_printers(ir: llvm.Module, printers: String) {
        var triple = ir.target_triple();
        if (printers.is_empty
            or triple.contains("-windows")
            or triple.contains("-apple-")
            or triple.starts_with("wasm")) {
            return;
        }
        # Kind 4: an inline Python script, its name on the first line.
        var text = context.const_string("\u{4}pepper/gdb_printers.py\n" + printers, true);
        var section = ir.add_global(text.value_type(), "__pep_debug_gdb_scripts");
        section.set_initializer(text);
        section.set_global_constant(true);
        section.set_section(".debug_gdb_scripts");
        section.set_alignment(1);
        section.set_linkage(llvm.Linkage.Private);
        # Its address means nothing, so partitioning leaves it private.
        section.set_unnamed_address(2);
        var pointer = context.pointer_type();
        var used = ir.add_global(pointer.array_type(1), "llvm.used");
        used.set_linkage(llvm.Linkage.Appending);
        used.set_section("llvm.metadata");
        used.set_initializer(pointer.const_array([section]));
    }

    ## Finishes the module's debug info (see the module comment), and gives
    ## every defined function an unwind table, so a debugger can walk its
    ## frame.
    finish(ir: llvm.Module) {
        var uwtable = context.attribute("uwtable", 2);
        for (var function in ir.functions()) {
            if (function.block_count() == 0) {
                continue;
            }
            function.add_function_attribute(uwtable);
            var subprogram = llvm.Metadata(LLVMGetSubprogram(function.ref));
            if (subprogram.is_null()) {
                subprogram = _subprogram(function, function.name(), unit_file, 0, FLAG_ARTIFICIAL);
            }
            var owner = _key(subprogram);
            var line_zero = builder.location(0, 0, subprogram);
            for (var block in function.blocks()) {
                var instruction = block.first_instruction();
                while (!instruction.is_null()) {
                    # Stamped in this function's scope, or else unstamped, as
                    # clang leaves a prologue: a location from another
                    # function (codegen emits a thunk in the middle of a
                    # caller) does not verify. LLVM requires a location on
                    # every call, so a call gets line 0, which a debugger
                    # skips: the prologue ends at the first statement.
                    var stamped = LLVMInstructionGetDebugLoc(instruction.ref);
                    bool own = false;
                    if (stamped != __null) {
                        var scope = unsafe_cast<ulong>(LLVMDILocationGetScope(stamped));
                        var block_owner = block_owners.try_get(scope);
                        own = (block_owner.is_value() ? block_owner.value() : scope) == owner;
                    }
                    if (!own) {
                        instruction.set_location(instruction.opcode() == OPCODE_CALL ? line_zero : llvm.Metadata());
                    }
                    instruction = instruction.next_instruction();
                }
            }
        }
        builder.finalize();
    }

    ## An enumerator of an enumeration type.
    enumerator(name: String, value: long, is_unsigned: bool): llvm.Metadata {
        return llvm.Metadata(
            LLVMDIBuilderCreateEnumerator(builder.ref, name.c_str(), name.size, value, is_unsigned ? 1 : 0)
        );
    }

    ## An enumeration type of `cases` over `underlying`.
    enumeration(
        name: String, loc: Loc, size_in_bits: ulong, cases: llvm.Metadata[], underlying: llvm.Metadata
    ): llvm.Metadata {
        var refs = _refs(cases);
        var made = LLVMDIBuilderCreateEnumerationType(
            builder.ref,
            unit.ref,
            name.c_str(),
            name.size,
            file_of(loc).ref,
            line_of(loc),
            size_in_bits,
            0,
            refs,
            cases.count as uint,
            underlying.ref
        );
        free(refs);
        return llvm.Metadata(made);
    }

    ## An array of `count` elements of `element`.
    array(size_in_bits: ulong, align_in_bits: uint, element: llvm.Metadata, count: long): llvm.Metadata {
        var range = llvm.Metadata(LLVMDIBuilderGetOrCreateSubrange(builder.ref, 0, count));
        var refs = _refs([range]);
        var made = LLVMDIBuilderCreateArrayType(builder.ref, size_in_bits, align_in_bits, element.ref, refs, 1);
        free(refs);
        return llvm.Metadata(made);
    }

    ## A structure type named `name` (unique as `identifier`), declared at
    ## `loc`; with `declaration`, a forward declaration of one.
    structure(
        name: String,
        loc: Loc,
        size_in_bits: ulong,
        members: llvm.Metadata[],
        identifier: String,
        declaration: bool = false
    ): llvm.Metadata {
        var refs = _refs(members);
        var made = llvm_c.LLVMDIBuilderCreateStructType(
            builder.ref,
            unit.ref,
            name.c_str(),
            name.size,
            file_of(loc).ref,
            line_of(loc),
            size_in_bits,
            0,
            declaration ? FLAG_FORWARD_DECLARATION : 0,
            __null,
            refs,
            members.count as uint,
            0,
            __null,
            identifier.c_str(),
            identifier.size
        );
        free(refs);
        return llvm.Metadata(made);
    }

    ## The size of the type `ty`, in bits.
    size_in_bits(ty: llvm.Metadata): ulong {
        return LLVMDITypeGetSizeInBits(ty.ref);
    }

    ## A member of a structure, declared at `loc`.
    member(name: String, loc: Loc, size_in_bits: ulong, offset_in_bits: ulong, ty: llvm.Metadata): llvm.Metadata {
        return builder.member_type(unit, name, file_of(loc), line_of(loc), size_in_bits, 0, offset_in_bits, ty);
    }
}

## Removes the debug info of `global`, a definition another part owns,
## which this part only declares.
##
## @param global the global variable
export forget_global_debug_info(global: llvm.Value) {
    LLVMGlobalEraseMetadata(global.ref, DBG_KIND);
}

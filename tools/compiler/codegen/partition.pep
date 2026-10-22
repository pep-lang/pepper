## Splitting the program's LLVM module into parts that are optimized and
## compiled to objects in parallel, then linked.
##
## The whole program is generated as one module, as before. `prepare` then
## gives every definition the linkage of a multi-object program, and
## assigns each file's symbols to one part, the part of its translation
## unit (`link.translation_units`), so each unit's object can be kept in the
## build cache:
##
## - a symbol with an owner (`Generator.owners`, the file declaring it) is
##   defined only in its file's part, and is external with hidden
##   visibility, since code in another part may call it;
## - every other definition (instantiations such as `Array<int>.append`,
##   and code without a source location) becomes `linkonce_odr`, in a
##   comdat of its own name except on Apple targets, defined in each part
##   that uses it, so each part can inline it and the linker
##   keeps one copy, the way C++ emits templates; a private constant whose
##   address means nothing (`unnamed_addr`, such as a string's bytes) stays
##   private, copied into each part that uses it;
## - the program's own entry points (`main`, `__pep_global_init`, the C
##   exports, the thread-locals' release, and LLVM's `llvm.*` globals such
##   as `llvm.global_ctors`) are in a part of their own, which depends on
##   the whole program and is never cached. Each export's entry point,
##   named `EXPORT_PREFIX` and its C symbol until then, takes its C symbol.
##   So does an extern a Pepper function shares its C symbol's name with,
##   named `EXTERN_PREFIX` and its C symbol until then.
##
## Every symbol a definition names gets its linker spelling
## (`link.symbol_name`), so names with `@`, `<` or spaces survive every linker.
## `keep_part` then turns a copy of the prepared module into one part:
## every other part's definitions become declarations, and `globaldce`
## removes what the part does not use.

import [File] from io;
import compiler.link;
import llvm;
import "checks";
import [forget_global_debug_info] from "debug";
import "globals";

extern void LLVMSetComdat(void* global, void* comdat);
extern void* LLVMGetComdat(void* global);
extern void LLVMSetComdatSelectionKind(void* comdat, int kind);
extern char* LLVMGetSection(void* global);

## A program's symbols assigned to parts.
export struct Partition {
    ## The part of each symbol defined in exactly one part, by its linker
    ## spelling.
    var part_of: HashMap<String, uint>;
    ## How much code each part defines (blocks and definitions); 0 for a
    ## part that defines nothing.
    var sizes: ulong[];
    ## The Pepper name of each definition `prepare` gave another linker
    ## spelling, by that spelling.
    var names: HashMap<String, String> = HashMap<String, String>();

    construct(part_of: HashMap<String, uint>, sizes: ulong[] = Array<ulong>()) {
        this.part_of = part_of;
        this.sizes = sizes;
    }
}

## Whether `name` is one of the program's own entry points, defined once,
## in part 0, under its own name.
_is_entry(name: String): bool {
    return name == "main"
        or name == "__pep_global_init"
        or name == RELEASE_FUNCTION
        or name.starts_with(EXPORT_PREFIX)
        or name.starts_with("llvm.");
}

## Returns how much code each file owns, to split the program into parts
## of about the same size: its functions' blocks, plus one for each
## definition.
##
## @param ir the whole program's module, before `prepare`
## @param owners each owned symbol's file, by name (`Generator.owners`)
## @param files how many files the program has
## @returns each file's size
export file_sizes(ir: llvm.Module, owners: HashMap<String, uint>, files: ulong): ulong[] {
    var sizes = Array<ulong>();
    for (var _ in 0..files) {
        sizes.append(0);
    }
    var values = Array<llvm.Value>();
    values.append_all(ir.functions());
    values.append_all(ir.globals());
    for (var value in values) {
        if (value.is_declaration() or _is_entry(value.name())) {
            continue;
        }
        var owner = owners.try_get(value.name());
        if (owner.is_value() and (owner.value() as ulong) < files) {
            sizes[owner.value() as ulong] += _size(value);
        }
    }
    return sizes;
}

## Gives every definition in `ir` its linkage and spelling for a program
## of several objects, and assigns each owned symbol to the part of its
## file (see the module documentation).
##
## @param ir the whole program's module
## @param owners each owned symbol's file, by name (`Generator.owners`)
## @param part_of_file each file's part
## @param entry_part the part of the program's own entry points, and of
##   symbols whose owner is not a file of `part_of_file`
## @param parts how many parts there are, more than any part named
## @param spread how many parts each file's symbols spread over, by file:
##   a file's symbol goes to part `part_of_file[file] + h % spread[file]`,
##   `h` its name's hash, so an edit to one function changes one part
##   (none for one each)
## @param locations_part the part of the location strings defined apart
##   from the code (`Build.separate_locations`), which a line shift
##   changes alone
## @returns the partition
export prepare(
    ir: llvm.Module,
    owners: HashMap<String, uint>,
    part_of_file: uint[],
    entry_part: uint,
    parts: uint,
    spread: uint[] = Array<uint>(),
    locations_part: uint? = Optional<uint>.Empty
): Partition {
    var sizes = Array<ulong>();
    for (var _ in 0..parts) {
        sizes.append(0);
    }
    # COFF needs a comdat for the linker to keep one copy of a
    # `linkonce_odr` definition; Mach-O has no comdats.
    bool comdats = !ir.target_triple().contains("apple");
    var functions = ir.functions();
    var part_of = HashMap<String, uint>();
    var names = HashMap<String, String>();
    # The C entry points of `[Export]`ed functions, named by their C symbols
    # once every Pepper symbol has its spelling (a Pepper `add` is `_Padd`).
    var exports = Array<llvm.Value>();
    var values = Array<llvm.Value>();
    values.append_all(functions);
    for (var global in ir.globals()) {
        values.append(global);
    }
    for (var value in values) {
        var name = value.name();
        if (value.is_declaration()) {
            # `restore_extern_names` names it below.
            if (name.starts_with(EXTERN_PREFIX)) {
                continue;
            }
            # A function whose body sema skipped (its unit's object comes
            # from the build cache) is declared only, under the spelling
            # that object defines.
            if (owners.contains(name)) {
                value.set_linkage(llvm.Linkage.External);
                _respell(value, name);
            }
            continue;
        }
        if (locations_part.is_value() and name.starts_with(LOCATION_PREFIX)) {
            # Weak, not link-once: their part uses none of them, and keeps
            # them all.
            value.set_linkage(llvm.Linkage.WeakOdr);
            value.set_visibility(llvm.Visibility.Hidden);
            if (comdats) {
                value.set_comdat(name);
            }
            part_of[name] = locations_part.value();
            sizes[locations_part.value()] += _size(value);
            continue;
        }
        if (_is_entry(name)) {
            if (name.starts_with(EXPORT_PREFIX)) {
                exports.append(value);
            } else {
                part_of[name] = entry_part;
            }
            sizes[entry_part] += _size(value);
            continue;
        }
        var owner = owners.try_get(name);
        if (owner.is_value()) {
            value.set_linkage(llvm.Linkage.External);
            value.set_visibility(llvm.Visibility.Hidden);
            var spelled = _respell(value, name);
            if (spelled != name) {
                names[spelled] = name;
            }
            var file = owner.value() as ulong;
            var part = file < part_of_file.count ? part_of_file[file] : entry_part;
            if (file < spread.count and spread[file] > 1) {
                part += (_fnv1a(spelled) % spread[file] as ulong) as uint;
            }
            part_of[spelled] = part;
            sizes[part] += _size(value);
            continue;
        }
        var linkage = value.linkage();
        if ((linkage == llvm.Linkage.Private or linkage == llvm.Linkage.Internal)
            and !value.is_function()
            and value.unnamed_address() != 0) {
            continue;
        }
        value.set_linkage(llvm.Linkage.LinkOnceOdr);
        value.set_visibility(llvm.Visibility.Hidden);
        var spelled = _respell(value, name);
        if (spelled != name) {
            names[spelled] = name;
        }
        if (comdats) {
            value.set_comdat(spelled);
        }
    }
    for (var entry in exports) {
        var name = entry.name();
        var symbol = name.substr_bytes(EXPORT_PREFIX.size, name.size - EXPORT_PREFIX.size);
        entry.set_name(symbol);
        part_of[entry.name()] = entry_part;
    }
    restore_extern_names(ir);
    var out = Partition(part_of, sizes);
    out.names = names;
    return out;
}

## How much code `value` is, to balance parts: a function's blocks, plus
## one for the definition, so a part that defines anything is not empty.
_size(value: llvm.Value): ulong {
    return value.is_function() ? value.block_count() as ulong + 1 : 1;
}

# Gives each extern kept apart from a Pepper function of its C symbol's
# name (`EXTERN_PREFIX`) that name back. The function, when it still holds
# the name (`generate_ir` does not respell), first takes its spelling.
restore_extern_names(ir: llvm.Module) {
    for (var declaration in ir.functions()) {
        var name = declaration.name();
        if (!declaration.is_declaration() or !name.starts_with(EXTERN_PREFIX)) {
            continue;
        }
        var symbol = name.substr_bytes(EXTERN_PREFIX.size, name.size - EXTERN_PREFIX.size);
        var function = ir.function(symbol);
        if (function.is_value()) {
            _respell(function.value(), symbol);
        }
        declaration.set_name(symbol);
    }
}

## Renames `value` to its linker spelling, returning the spelling.
_respell(value: llvm.Value, name: String): String {
    var spelled = link.symbol_name(name);
    if (spelled != name) {
        value.set_name(spelled);
    }
    return spelled;
}

## Turns `ir`, a module `prepare` prepared (or a copy of it), into part
## `part` of `partition`: the definitions other parts own become
## declarations, and what the part does not use is removed.
##
## @param ir the module
## @param partition the partition
## @param part the part to keep
## @returns Ok, or why the module's passes failed
export keep_part(ir: llvm.Module, partition: Partition, part: uint, trace: bool = false): Result<void> {
    var parts = HashSet<uint>();
    parts.insert(part);
    return keep_parts(ir, partition, parts, trace);
}

## Turns `ir`, a module `prepare` prepared (or a copy of it), into the
## parts `parts` of `partition` together, as `keep_part` does for one: a
## process compiling several parts keeps them all first, so each copy it
## makes for one of them is smaller.
##
## @param ir the module
## @param partition the partition
## @param parts the parts to keep
## @param trace whether to name each step on stderr before it runs (with
##   each function and global changed), to find where a split fails
## @returns Ok, or why the module's passes failed
export keep_parts(ir: llvm.Module, partition: Partition, parts: HashSet<uint>, trace: bool = false): Result<void> {
    _trace(trace, "split: functions");
    for (var function in ir.functions()) {
        if (function.is_declaration()) {
            continue;
        }
        var owner = partition.part_of.try_get(function.name());
        if (owner.is_value() and !parts.contains(owner.value())) {
            _trace(trace, $"split: delete body {function.name()}");
            function.delete_body();
        }
    }
    _trace(trace, "split: globals");
    for (var global in ir.globals()) {
        if (global.is_declaration()) {
            continue;
        }
        var name = global.name();
        var owner = partition.part_of.try_get(name);
        if (owner.is_value() and !parts.contains(owner.value())) {
            _trace(trace, $"split: global {name}");
            if (name.starts_with("llvm.")) {
                global.delete_global();
            } else {
                global.set_initializer(llvm.Value());
                global.set_linkage(llvm.Linkage.External);
                # A declaration in a comdat does not verify, and linking it
                # first (`--lto=full`) claims the comdat, so the defining
                # part's copy is dropped.
                LLVMSetComdat(global.ref, __null);
                # The part that defines it describes it.
                forget_global_debug_info(global);
            }
        }
    }
    _trace(trace, "split: globaldce");
    var removed = ir.run_passes("globaldce");
    if (removed.is_err()) {
        return Result<void>.err(removed.error());
    }
    _trace(trace, "split: done");
    return Result<void>.ok();
}

## LLVM's `LLVMNoDeduplicateComdatSelectionKind`.
const _NO_DEDUPLICATE: int = 3;

## Puts each definition of `ir`, a part about to be written as an object,
## that is not in a comdat in a comdat of its own that keeps every copy, so
## it gets a section of its own, as clang's `-ffunction-sections
## -fdata-sections` do: the linker (`/OPT:REF`, `--gc-sections`) then drops
## what nothing uses, such as an unread constant's bytes (pepper#155).
## Mach-O needs none: `-dead_strip` drops each unused symbol. WebAssembly
## gives each its own segment already.
##
## @param ir the part's module
export section_each_definition(ir: llvm.Module) {
    var triple = ir.target_triple();
    if (triple.contains("apple") or triple.starts_with("wasm")) {
        return;
    }
    var values = Array<llvm.Value>();
    values.append_all(ir.functions());
    values.append_all(ir.globals());
    for (var value in values) {
        if (value.is_declaration() or value.has_comdat() or value.name().starts_with("llvm.")) {
            continue;
        }
        # A global placed in a named section (`.debug_gdb_scripts`) stays
        # as it is.
        if (!value.is_function() and !String(LLVMGetSection(value.ref)).is_empty) {
            continue;
        }
        # A COFF comdat's symbol cannot be private.
        if (value.linkage() == llvm.Linkage.Private) {
            value.set_linkage(llvm.Linkage.Internal);
        }
        value.set_comdat(value.name());
        LLVMSetComdatSelectionKind(LLVMGetComdat(value.ref), _NO_DEDUPLICATE);
    }
}

_trace(trace: bool, line: String) {
    if (trace) {
        File.stderr().write_all(line + "\n");
    }
}

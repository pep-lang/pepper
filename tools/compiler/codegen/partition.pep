## Splitting the program's LLVM module into parts that are optimized and
## compiled to objects in parallel, then linked.
##
## The whole program is generated as one module, as before. `prepare` then
## gives every definition the linkage of a multi-object program, and
## assigns each file's symbols to one part, the part of its compilation
## unit (`link.units`), so each unit's object can be kept in the build
## cache:
##
## - a symbol with an owner (`Generator.owners`, the file declaring it) is
##   defined only in its file's part, and is external with hidden
##   visibility, since code in another part may call it;
## - every other definition (instantiations such as `Array<int>.append`,
##   and code without a source location) becomes `linkonce_odr`, defined in
##   each part that uses it, so each part can inline it and the linker
##   keeps one copy, the way C++ emits templates; a private constant whose
##   address means nothing (`unnamed_addr`, such as a string's bytes) stays
##   private, copied into each part that uses it;
## - the program's own entry points (`main`, `__pep_global_init`, the C
##   exports, the thread-locals' release, and LLVM's `llvm.*` globals such
##   as `llvm.global_ctors`) are in a part of their own, which depends on
##   the whole program and is never cached.
##
## Every symbol a definition names gets its linker spelling
## (`link.symbol_name`), so names with `@`, `<` or spaces survive every linker.
## `keep_part` then turns a copy of the prepared module into one part:
## every other part's definitions become declarations, and `globaldce`
## removes what the part does not use.

import compiler.link;
import llvm;
import "globals";

## A program's symbols assigned to parts.
export struct Partition {
    ## The part of each symbol defined in exactly one part, by its linker
    ## spelling.
    var part_of: HashMap<String, uint>;
    ## How much code each part defines (blocks and definitions); 0 for a
    ## part that defines nothing.
    var sizes: ulong[];

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
## @returns the partition
export prepare(
    ir: llvm.Module, owners: HashMap<String, uint>, part_of_file: uint[], entry_part: uint, parts: uint
): Partition {
    var sizes = Array<ulong>();
    for (var _ in 0..parts) {
        sizes.append(0);
    }
    var functions = ir.functions();
    var part_of = HashMap<String, uint>();
    var values = Array<llvm.Value>();
    values.append_all(functions);
    for (var global in ir.globals()) {
        values.append(global);
    }
    for (var value in values) {
        if (value.is_declaration()) {
            continue;
        }
        var name = value.name();
        if (_is_entry(name)) {
            part_of[name] = entry_part;
            sizes[entry_part] += _size(value);
            continue;
        }
        var owner = owners.try_get(name);
        if (owner.is_value()) {
            value.set_linkage(llvm.Linkage.External);
            value.set_visibility(llvm.Visibility.Hidden);
            var spelled = _respell(value, name);
            var file = owner.value() as ulong;
            var part = file < part_of_file.count ? part_of_file[file] : entry_part;
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
        _respell(value, name);
    }
    return Partition(part_of, sizes);
}

## How much code `value` is, to balance parts: a function's blocks, plus
## one for the definition, so a part that defines anything is not empty.
_size(value: llvm.Value): ulong {
    return value.is_function() ? value.block_count() as ulong + 1 : 1;
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
export keep_part(ir: llvm.Module, partition: Partition, part: uint): Result<void> {
    var parts = HashSet<uint>();
    parts.insert(part);
    return keep_parts(ir, partition, parts);
}

## Turns `ir`, a module `prepare` prepared (or a copy of it), into the
## parts `parts` of `partition` together, as `keep_part` does for one: a
## process compiling several parts keeps them all first, so each copy it
## makes for one of them is smaller.
##
## @param ir the module
## @param partition the partition
## @param parts the parts to keep
## @returns Ok, or why the module's passes failed
export keep_parts(ir: llvm.Module, partition: Partition, parts: HashSet<uint>): Result<void> {
    for (var function in ir.functions()) {
        if (function.is_declaration()) {
            continue;
        }
        var owner = partition.part_of.try_get(function.name());
        if (owner.is_value() and !parts.contains(owner.value())) {
            function.delete_body();
        }
    }
    for (var global in ir.globals()) {
        if (global.is_declaration()) {
            continue;
        }
        var name = global.name();
        var owner = partition.part_of.try_get(name);
        if (owner.is_value() and !parts.contains(owner.value())) {
            if (name.starts_with("llvm.")) {
                global.delete_global();
            } else {
                global.set_initializer(llvm.Value());
                global.set_linkage(llvm.Linkage.External);
            }
        }
    }
    var removed = ir.run_passes("globaldce");
    if (removed.is_err()) {
        return Result<void>.err(removed.error());
    }
    return Result<void>.ok();
}

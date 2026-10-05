## Splitting the program's LLVM module into parts that are optimized and
## compiled to objects in parallel, then linked.
##
## The whole program is generated as one module, as before. `prepare` then
## gives every definition the linkage of a multi-object program, and
## assigns each file's symbols to one part:
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
##   as `llvm.global_ctors`) are in part 0.
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

    construct(part_of: HashMap<String, uint>) {
        this.part_of = part_of;
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

## Gives every definition in `ir` its linkage and spelling for a program
## of `parts` objects, and assigns each owned symbol to the part of its
## file (see the module documentation). Files are spread over the parts
## by size, largest first, each to the part with the least code so far.
##
## @param ir the whole program's module
## @param owners each owned symbol's file, by name (`Generator.owners`)
## @param files how many files the program has
## @param parts how many parts to make, at least 1
## @returns the partition
export prepare(ir: llvm.Module, owners: HashMap<String, uint>, files: uint, parts: uint): Partition {
    # How much code each file owns: its functions' blocks.
    var sizes = Array<ulong>();
    for (var _ in 0..files) {
        sizes.append(0);
    }
    var functions = ir.functions();
    for (var function in functions) {
        var owner = owners.try_get(function.name());
        if (owner.is_value() and (owner.value() as ulong) < files) {
            sizes[owner.value() as ulong] += function.block_count() as ulong + 1;
        }
    }
    var order = Array<ulong>();
    for (var file in 0..sizes.count) {
        order.append(file);
    }
    order.sort((a, b) => sizes[a] != sizes[b] ? (sizes[a] > sizes[b] ? -1 : 1) : (a < b ? -1 : 1));
    var loads = Array<ulong>();
    for (var _ in 0..parts) {
        loads.append(0);
    }
    var part_of_file = Array<uint>();
    for (var _ in 0..files) {
        part_of_file.append(0);
    }
    for (var file in order) {
        ulong least = 0;
        for (var part in 1..loads.count) {
            if (loads[part] < loads[least]) {
                least = part;
            }
        }
        part_of_file[file] = least as uint;
        loads[least] += sizes[file];
    }

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
            part_of[name] = 0;
            continue;
        }
        var owner = owners.try_get(name);
        if (owner.is_value()) {
            value.set_linkage(llvm.Linkage.External);
            value.set_visibility(llvm.Visibility.Hidden);
            var spelled = _respell(value, name);
            part_of[spelled] = (owner.value() as ulong) < files ? part_of_file[owner.value() as ulong] : 0;
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
    return Partition(part_of);
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
    for (var function in ir.functions()) {
        if (function.is_declaration()) {
            continue;
        }
        var owner = partition.part_of.try_get(function.name());
        if (owner.is_value() and owner.value() != part) {
            function.delete_body();
        }
    }
    for (var global in ir.globals()) {
        if (global.is_declaration()) {
            continue;
        }
        var name = global.name();
        var owner = partition.part_of.try_get(name);
        if (owner.is_value() and owner.value() != part) {
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

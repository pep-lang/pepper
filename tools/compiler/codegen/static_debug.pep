## The debugger's view of an expanded `static` block (`-g`):
## `crates/pepper-codegen/src/static_debug.rs` in Pepper (see INTERNALS.md
## §4.4). `static_blocks.pep` starts each pass of an unrolled compile-time
## loop, and the branch a compile-time `if` kept, with a `StaticPass`. Here
## it becomes:
##
## - one `nop` at the loop's or the `if`'s header, under `-O0`, so stepping
##   stops on the header once per pass, as in a runtime loop. Without it
##   every pass's code carries the same line, and a debugger, which steps
##   until the line changes, runs all the passes in one step. (An empty
##   inline asm would leave no instruction to stop at.)
## - each compile-time variable in scope (the loop's `field`, a `var`),
##   stored in its own slot when the function starts (so it holds its value
##   from the header on) and declared in the pass's lexical block, so
##   `p field.name` prints the pass's member. A member, case, function or
##   attribute is a structure of what `reflect` reads from it; a string is
##   a `__ptr<char>` to a constant.

import llvm;
import llvm.llvm_c;
import [Loc, StaticConstant, StaticPass] from compiler.sema;
import "debug";
import "debug_types";
import [Generator] from "generator";
import "generator";

extend Generator {
    ## Generates a `StaticPass`: nothing without debug info.
    codegen_static_pass(pass: StaticPass): Result<void> {
        if (!debug.is_value()) {
            return Result<void>.ok();
        }
        if (pass.stop and opt_level == 0 and !ir.target_triple().starts_with("wasm")) {
            var asm_type = llvm.Type.function(context.void_type(), Array<llvm.Type>(), false);
            var nop = llvm.Value(llvm_c.LLVMGetInlineAsm(asm_type.ref, "nop", 3, "", 0, 1, 0, 0, 0));
            builder.call(asm_type, nop, Array<llvm.Value>());
        }
        for (var (name, value) in pass.values) {
            var made = _static_constant(value);
            if (!made.is_value()) {
                continue;
            }
            var (constant, ty) = made.value();
            var slot = _entry_constant(constant, name);
            debug.value().declare(slot, name, ty, pass.loc, 0, builder.insert_block());
        }
        return Result<void>.ok();
    }

    # A slot in the function's entry block holding `constant`, stored there
    # too: the debugger may show the variable as soon as it enters the
    # pass's scope, on the header, before any code of the pass runs.
    _entry_constant(constant: llvm.Value, name: String): llvm.Value {
        var block = builder.insert_block();
        var entry = block.parent().first_block();
        var first = entry.first_instruction();
        if (first.is_null()) {
            builder.position_at_end(entry);
        } else {
            builder.position_before(first);
        }
        var slot = builder.alloca(constant.value_type(), name);
        builder.store(constant, slot);
        builder.position_at_end(block);
        keep_location();
        return slot;
    }

    # `value` as an LLVM constant and its debug type.
    _static_constant(value: StaticConstant): (llvm.Value, llvm.Metadata)? {
        llvm.Value constant;
        llvm.Metadata? ty;
        match (value) {
            Int(n) => {
                constant = context.int64_type().const_int(n);
                ty = debug_type("long");
            }
            Float(x) => {
                constant = context.double_type().const_real(x);
                ty = debug_type("double");
            }
            Bool(b) => {
                constant = context.int8_type().const_uint(b ? 1 : 0);
                ty = debug_type("bool");
            }
            String(text) => {
                constant = builder.global_string(text, "static.string");
                ty = debug_type("__ptr<char>");
            }
            Record(record) => {
                var values = Array<llvm.Value>();
                var types = Array<llvm.Metadata>();
                var names = Array<String>();
                for (var (field, inner) in record.fields) {
                    var made = _static_constant(inner);
                    if (!made.is_value()) {
                        return Optional<(llvm.Value, llvm.Metadata)>.Empty;
                    }
                    var (field_value, field_type) = made.value();
                    values.append(field_value);
                    types.append(field_type);
                    names.append(field);
                }
                constant = context.const_struct(values);
                ty = _static_record_type(record.name, names, types, constant.value_type());
            }
        }
        if (!ty.is_value()) {
            return Optional<(llvm.Value, llvm.Metadata)>.Empty;
        }
        return Optional<(llvm.Value, llvm.Metadata)>.Value((constant, ty.value()));
    }

    # The structure type named `name` with members `names` of types `types`,
    # laid out as `llvm_type`: one per record name, which always has the
    # same members.
    _static_record_type(name: String, names: String[], types: llvm.Metadata[], llvm_type: llvm.Type): llvm.Metadata? {
        var info = debug.value();
        var key = $"static {name}";
        var known = info.types.try_get(key);
        if (known.is_value()) {
            return known;
        }
        var members = Array<llvm.Metadata>();
        for (var index in 0..names.count) {
            var offset = machine.offset_of(llvm_type, index as uint) * 8;
            members.append(
                info.member(names[index], Loc.none(), info.size_in_bits(types[index]), offset, types[index])
            );
        }
        var made = info.structure(name, Loc.none(), machine.size_of(llvm_type) * 8, members, key);
        info.types[key] = made;
        return Optional<llvm.Metadata>.Value(made);
    }
}

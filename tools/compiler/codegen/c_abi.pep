## `[Value]` structs passed to and from C by value (#384): how each C
## calling convention passes a struct (`c_struct_pass`), and the code that
## converts between a Pepper struct value and the pieces C passes, for an
## extern's adapter (`declare_c_struct_extern`) and an export's entry point
## (`emit_exports` in `globals.pep`).
##
## The conventions, as clang lowers them:
##
## - x86-64 System V (Linux, macOS): a struct of at most 16 bytes travels
##   in up to two registers, each 8-byte half in an integer register, or in
##   an SSE one when only floats fill it; a larger one, or one the
##   registers left cannot hold, is copied onto the stack (`byval`) and
##   returned through a hidden pointer (`sret`).
## - x86-64 Windows: a struct of 1, 2, 4 or 8 bytes is that size of
##   integer; any other is passed as a pointer to a copy the caller makes,
##   and returned through `sret`.
## - AArch64 (AAPCS64, Apple's too): up to four floats or four doubles
##   alone (a homogeneous floating-point aggregate) travel in FP registers;
##   any other struct of at most 16 bytes in one or two integer registers;
##   a larger one as a pointer to a caller's copy, returned through `sret`
##   (in x8).
## - wasm32: a struct of one scalar is that scalar; any other is copied
##   (`byval`) and returned through `sret`.

import llvm;
import compiler.sema;
import [c_abi_type] from "calls";
import "calls";
import "functions";
import [Generator] from "generator";
import "generator";

## How a C calling convention passes one struct argument, or returns one.
export struct CStructPass {
    ## The pieces it travels as, in registers: one argument each, or the
    ## fields of the result. Empty when it goes through memory.
    var parts: llvm.Type[] = Array<llvm.Type>();
    ## Whether it goes through memory: an argument as a pointer to a copy,
    ## a result through a hidden `sret` pointer.
    var indirect: bool = false;
    ## For an indirect argument, whether the pointer carries `byval` (the
    ## convention copies the struct onto the stack) rather than pointing
    ## at a copy the caller made.
    var byval: bool = false;

    ## Whether it travels in registers.
    ##
    ## @returns true unless it goes through memory
    is_direct(): bool {
        return !indirect;
    }
}

## The argument registers of x86-64 System V a call has left, which decide
## whether a small struct still travels in registers.
export struct CRegisters {
    ## Integer registers left (rdi, rsi, rdx, rcx, r8, r9).
    var integers: int = 6;
    ## SSE registers left (xmm0 to xmm7).
    var vectors: int = 8;

    ## Creates the registers of a call with none taken.
    construct() {}

    ## Takes the register a scalar argument of LLVM type `ty` travels in.
    ##
    ## @param ty the argument's LLVM type
    take(ty: llvm.Type) {
        var kind = ty.kind();
        if (kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double or kind == llvm.TypeKind.Vector) {
            vectors -= 1;
        } else {
            integers -= 1;
        }
    }
}

extend Generator {
    ## Returns how C passes a struct of LLVM type `ty` on this target, as an
    ## argument (taking from `registers`) or, with `result`, as a result;
    ## an error on a target whose convention this compiler does not know.
    ##
    ## @param ty the struct's LLVM type
    ## @param result whether it is a function's result
    ## @param registers the System V registers the call has left
    ## @returns the way it passes
    c_struct_pass(ty: llvm.Type, result: bool, registers: CRegisters): Result<CStructPass> {
        var triple = machine.triple();
        var size = machine.size_of(ty);
        var leaves = Array<(ulong, llvm.Type)>();
        _c_leaves(ty, 0, leaves);
        var pass = CStructPass();
        if (triple.starts_with("x86_64") and triple.contains("windows")) {
            if (size == 1 or size == 2 or size == 4 or size == 8) {
                pass.parts.append(context.int_type((size * 8) as uint));
            } else {
                pass.indirect = true;
            }
            return Result<CStructPass>.ok(pass);
        }
        if (triple.starts_with("x86_64")) {
            if (size <= 16) {
                pass.parts = _system_v_parts(leaves, size);
                if (result) {
                    return Result<CStructPass>.ok(pass);
                }
                int integers = 0;
                int vectors = 0;
                for (var part in pass.parts) {
                    var kind = part.kind();
                    if (kind == llvm.TypeKind.Integer) {
                        integers += 1;
                    } else {
                        vectors += 1;
                    }
                }
                if (integers <= registers.integers and vectors <= registers.vectors) {
                    registers.integers -= integers;
                    registers.vectors -= vectors;
                    return Result<CStructPass>.ok(pass);
                }
                pass.parts = Array<llvm.Type>();
            }
            pass.indirect = true;
            pass.byval = !result;
            return Result<CStructPass>.ok(pass);
        }
        if (triple.starts_with("aarch64") or triple.starts_with("arm64")) {
            var floats = _homogeneous_floats(leaves, size);
            if (floats.is_value()) {
                var (element, count) = floats.value();
                pass.parts.append(element.array_type(count));
            } else if (size <= 16) {
                var words = (size + 7) / 8;
                var word = context.int64_type();
                pass.parts.append(words == 1 ? word : word.array_type(words));
            } else {
                pass.indirect = true;
            }
            return Result<CStructPass>.ok(pass);
        }
        if (triple.starts_with("wasm32")) {
            if (leaves.count == 1) {
                var (_, only) = leaves[0];
                if (machine.size_of(only) == size) {
                    pass.parts.append(only);
                    return Result<CStructPass>.ok(pass);
                }
            }
            pass.indirect = true;
            pass.byval = !result;
            return Result<CStructPass>.ok(pass);
        }
        return fail<CStructPass>(
            $"cannot pass a struct by value to C on '{triple}': its calling convention is unknown"
        );
    }

    # The scalars of `ty` with their byte offsets from `base`, nested
    # structs and arrays unfolded.
    _c_leaves(ty: llvm.Type, base: ulong, out: Array<(ulong, llvm.Type)>) {
        var kind = ty.kind();
        if (kind == llvm.TypeKind.Struct) {
            uint field = 0;
            while (field < ty.field_count()) {
                _c_leaves(ty.field(field), base + machine.offset_of(ty, field), out);
                field += 1;
            }
        } else if (kind == llvm.TypeKind.Array) {
            var element = ty.element_type();
            var step = machine.size_of(element);
            ulong index = 0;
            while (index < ty.array_length()) {
                _c_leaves(element, base + index * step, out);
                index += 1;
            }
        } else {
            out.append((base, ty));
        }
    }

    # The registers System V passes a struct of `size` bytes (at most 16)
    # with scalars `leaves` in: one per 8-byte half, an SSE register (a
    # `double`, `float` or `<2 x float>`) when only floats fill it, else an
    # integer as wide as the bytes the half holds.
    _system_v_parts(leaves: Array<(ulong, llvm.Type)>, size: ulong): llvm.Type[] {
        var parts = Array<llvm.Type>();
        ulong start = 0;
        while (start < size) {
            var bytes = size - start < 8 ? size - start : 8;
            bool floats_only = true;
            var doubles = 0;
            var singles = 0;
            for (var (offset, leaf) in leaves) {
                if (offset < start or offset >= start + 8) {
                    continue;
                }
                var kind = leaf.kind();
                if (kind == llvm.TypeKind.Double) {
                    doubles += 1;
                } else if (kind == llvm.TypeKind.Float) {
                    singles += 1;
                } else {
                    floats_only = false;
                }
            }
            if (floats_only and doubles == 1 and singles == 0) {
                parts.append(context.double_type());
            } else if (floats_only and doubles == 0 and singles == 1 and bytes <= 4) {
                parts.append(context.float_type());
            } else if (floats_only and doubles == 0 and singles > 0) {
                parts.append(context.float_type().vector_type(2));
            } else {
                parts.append(context.int_type((bytes * 8) as uint));
            }
            start += 8;
        }
        return parts;
    }

    # A homogeneous floating-point aggregate of `leaves` (`size` bytes):
    # one to four floats, or one to four doubles, filling it.
    _homogeneous_floats(leaves: Array<(ulong, llvm.Type)>, size: ulong): (llvm.Type, ulong)? {
        var none = Optional<(llvm.Type, ulong)>.Empty;
        if (leaves.count == 0 or leaves.count > 4) {
            return none;
        }
        var (_, first) = leaves[0];
        var kind = first.kind();
        if (kind != llvm.TypeKind.Float and kind != llvm.TypeKind.Double) {
            return none;
        }
        for (var (_, leaf) in leaves) {
            if (leaf.kind() != kind) {
                return none;
            }
        }
        if (machine.size_of(first) * leaves.count != size) {
            return none;
        }
        return Optional<(llvm.Type, ulong)>.Value((first, leaves.count));
    }

    ## Returns the LLVM type a direct struct result comes back as: its one
    ## part, or a struct of its parts.
    ##
    ## @param pass how the result passes, directly
    ## @returns the type
    c_result_type(pass: CStructPass): llvm.Type {
        return pass.parts.count == 1 ? pass.parts[0] : context.struct_type(pass.parts);
    }

    ## Returns a stack slot that holds a struct of LLVM type `ty` and the
    ## pieces `pass` gives it, whichever is larger, aligned for both.
    ##
    ## @param ty the struct's LLVM type
    ## @param pass how it passes
    ## @returns the slot
    c_struct_slot(ty: llvm.Type, pass: CStructPass): llvm.Value {
        var size = machine.size_of(ty);
        var align = machine.alignment_of(ty);
        if (!pass.parts.is_empty) {
            var pieces = context.struct_type(pass.parts);
            var pieces_size = machine.size_of(pieces);
            size = pieces_size > size ? pieces_size : size;
            var pieces_align = machine.alignment_of(pieces);
            align = pieces_align > align ? pieces_align : align;
        }
        var slot = entry_alloca(context.int8_type().array_type(size), "c_struct");
        slot.set_alignment(align);
        return slot;
    }

    ## Returns the arguments that pass the struct `value` (of LLVM type
    ## `ty`) to C as `pass` says: its parts loaded from a copy, or a pointer
    ## to the copy.
    ##
    ## @param value the struct value
    ## @param ty its LLVM type
    ## @param pass how it passes
    ## @returns the arguments
    c_struct_arguments(value: llvm.Value, ty: llvm.Type, pass: CStructPass): llvm.Value[] {
        var slot = c_struct_slot(ty, pass);
        builder.store(value, slot);
        var arguments = Array<llvm.Value>();
        if (pass.indirect) {
            arguments.append(slot);
            return arguments;
        }
        var pieces = context.struct_type(pass.parts);
        for (var index in 0..pass.parts.count) {
            var at = builder.field_pointer(pieces, slot, index as uint, "c_part");
            arguments.append(builder.load(pass.parts[index], at, "c_part"));
        }
        return arguments;
    }

    ## Returns the struct value of LLVM type `ty` that C passed as `pass`
    ## says, in `arguments` (its parts, or a pointer to it).
    ##
    ## @param arguments the arguments C passed for it
    ## @param ty its LLVM type
    ## @param pass how it passed
    ## @returns the struct value
    c_struct_value(arguments: llvm.Value[], ty: llvm.Type, pass: CStructPass): llvm.Value {
        if (pass.indirect) {
            return builder.load(ty, arguments[0], "c_struct");
        }
        var slot = c_struct_slot(ty, pass);
        var pieces = context.struct_type(pass.parts);
        for (var index in 0..pass.parts.count) {
            var at = builder.field_pointer(pieces, slot, index as uint, "c_part");
            builder.store(arguments[index], at);
        }
        return builder.load(ty, slot, "c_struct");
    }

    ## Declares extern `ext`, which passes or returns a value struct, as C
    ## declares it (`symbol`, of the C convention's signature), and makes
    ## `functions[ext.name]` an adapter of the Pepper signature
    ## (`param_types`, `return_type`) that converts each value struct and
    ## calls it.
    ##
    ## @param ext the extern
    ## @param symbol its C symbol
    ## @param param_types its parameters' Pepper LLVM types
    ## @param return_type its result's Pepper LLVM type
    ## @returns an error when its convention is unknown or it is variadic
    declare_c_struct_extern(
        ext: sema.ExternDef, symbol: String, param_types: llvm.Type[], return_type: llvm.Type
    ): Result<void> {
        if (ext.is_variadic) {
            return fail<void>($"cannot pass a struct by value to the variadic C function '{ext.name}'");
        }
        var registers = CRegisters();
        var void_result = is_void(ext.ty);
        bool struct_result = state.is_value_struct(ext.ty.to_string());
        var result_pass = CStructPass();
        if (struct_result) {
            result_pass = c_struct_pass(return_type, true, registers)?;
            if (result_pass.indirect) {
                registers.integers -= 1;
            }
        }
        var c_params = Array<llvm.Type>();
        var passes = Array<CStructPass?>();
        if (struct_result and result_pass.indirect) {
            c_params.append(context.pointer_type());
        }
        for (var index in 0..ext.parameters.count) {
            var ty = param_types[index];
            if (state.is_value_struct(ext.parameters[index].ty.to_string())) {
                var pass = c_struct_pass(ty, false, registers)?;
                passes.append(Optional<CStructPass>.Value(pass));
                if (pass.indirect) {
                    c_params.append(context.pointer_type());
                } else {
                    c_params.append_all(pass.parts);
                }
            } else {
                var c = targets_32_bit() ? c_abi_type(context, ext.parameters[index].ty.to_string(), ty) : ty;
                registers.take(c);
                passes.append(Optional<CStructPass>.Empty);
                c_params.append(c);
            }
        }
        llvm.Type c_return;
        if (void_result or (struct_result and result_pass.indirect)) {
            c_return = context.void_type();
        } else if (struct_result) {
            c_return = c_result_type(result_pass);
        } else {
            c_return = targets_32_bit() ? c_abi_type(context, ext.ty.to_string(), return_type) : return_type;
        }
        var c_type = llvm.Type.function(c_return, c_params, false);
        var existing = ir.function(symbol);
        llvm.Value c_function;
        if (existing.is_value()) {
            c_function = existing.value();
        } else {
            c_function = ir.add_function(symbol, c_type);
            _c_struct_attributes(c_function, ext, param_types, return_type, result_pass, passes, false);
        }
        # The adapter: Pepper's signature, converting each struct.
        var adapter_type = llvm_fn_type(context, void_result ? context.void_type() : return_type, param_types, false);
        var adapter = ir.add_function($"__c_call.{ext.name}", adapter_type);
        adapter.set_linkage(llvm.Linkage.Private);
        var saved = builder.insert_block();
        builder.position_at_end(context.append_block(adapter, "entry"));
        var arguments = Array<llvm.Value>();
        llvm.Value? result_slot = Optional<llvm.Value>.Empty;
        if (struct_result and result_pass.indirect) {
            var slot = c_struct_slot(return_type, result_pass);
            result_slot = Optional<llvm.Value>.Value(slot);
            arguments.append(slot);
        }
        for (var index in 0..ext.parameters.count) {
            var argument = adapter.param(index as uint);
            var pass = passes[index];
            if (pass.is_value()) {
                arguments.append_all(c_struct_arguments(argument, param_types[index], pass.value()));
            } else {
                var c = c_params[arguments.count];
                arguments.append(c.same(param_types[index]) ? argument : builder.truncate(argument, c, "c_argument"));
            }
        }
        var call = builder.call(c_type, c_function, arguments, "");
        _c_struct_attributes(call, ext, param_types, return_type, result_pass, passes, true);
        if (void_result) {
            builder.return_void();
        } else if (result_slot.is_value()) {
            builder.return_value(builder.load(return_type, result_slot.value(), "c_result"));
        } else if (struct_result) {
            var slot = c_struct_slot(return_type, result_pass);
            builder.store(call, slot);
            builder.return_value(builder.load(return_type, slot, "c_result"));
        } else if (!c_return.same(return_type)) {
            var signed = !sema.is_unsigned_int_type(state, ext.ty.to_string());
            builder.return_value(
                signed ?
                    builder.sign_extend(call, return_type, "c_result") :
                    builder.zero_extend(call, return_type, "c_result")
            );
        } else {
            builder.return_value(call);
        }
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        functions[ext.name] = adapter;
        fn_returns[ext.name] = ext.ty.to_string();
        return Result<void>.ok();
    }

    # Marks the C function `target` (or a call of it, with `call`) as the
    # convention passes the structs of `ext`: `sret` on the hidden result
    # pointer, `byval` on a copied argument, and C's widening of small
    # integers.
    _c_struct_attributes(
        target: llvm.Value,
        ext: sema.ExternDef,
        param_types: llvm.Type[],
        return_type: llvm.Type,
        result_pass: CStructPass,
        passes: Array<CStructPass?>,
        call: bool
    ) {
        uint at = 0;
        if (state.is_value_struct(ext.ty.to_string()) and result_pass.indirect) {
            _c_attribute(target, at, context.type_attribute("sret", return_type), call);
            at += 1;
        } else if (!state.is_value_struct(ext.ty.to_string())) {
            var widened = extension_attribute(ext.ty.to_string(), return_type);
            if (widened.is_value() and !call) {
                target.add_return_attribute(widened.value());
            }
        }
        for (var index in 0..ext.parameters.count) {
            var pass = passes[index];
            if (pass.is_value()) {
                if (pass.value().indirect) {
                    if (pass.value().byval) {
                        _c_attribute(target, at, context.type_attribute("byval", param_types[index]), call);
                    }
                    at += 1;
                } else {
                    at += pass.value().parts.count as uint;
                }
            } else {
                var widened = extension_attribute(ext.parameters[index].ty.to_string(), param_types[index]);
                if (widened.is_value()) {
                    _c_attribute(target, at, widened.value(), call);
                }
                at += 1;
            }
        }
    }

    # Adds `attribute` to parameter `index` of function `target`, or of
    # the call `target` with `call`.
    _c_attribute(target: llvm.Value, index: uint, attribute: llvm.Attribute, call: bool) {
        if (call) {
            target.add_call_attribute(index + 1, attribute);
        } else {
            target.add_param_attribute(index, attribute);
        }
    }
}

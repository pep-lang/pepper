## File-scope globals and their initializers, thread-local release, the
## context-switch intrinsics, `[Export]` entry points, LLVM intrinsic
## externs, the language's facts for LLVM's optimizer, and the CPU stamp.

import compiler.ast;
import compiler.link;
import [NAMESPACE_SEPARATOR] from compiler.link;
import llvm;
import compiler.sema;
import [Expression, Module, TypeName, VariableDef] from compiler.sema;
import [Address] from "address";
import "address";
import "calls";
import "checks";
import "debug";
import "debug_types";
import "expressions";
import "functions";
import [Generator] from "generator";
import "generator";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import "types";

# Thread-locals

## The function the program defines to release the calling thread's
## thread-locals; `runtime/async/thread.pep` declares it `extern`.
export const RELEASE_FUNCTION = "_pep_release_thread_locals";

## How many times `_pep_release_thread_locals` walks the thread-locals: a
## destructor run by one pass may store into a thread-local again, as
## POSIX's `PTHREAD_DESTRUCTOR_ITERATIONS` allows for keys.
const RELEASE_PASSES: ulong = 4;

## LLVM's `LLVMInitialExecTLSModel`.
const INITIAL_EXEC_TLS_MODEL: int = 3;

# Context intrinsics

## The declared name of the switch intrinsic.
export const SWITCH_CONTEXT = "__switch_context";
## The declared name of the stack-preparing intrinsic.
export const PREPARE_CONTEXT = "__prepare_context";

## x86-64 System V: rbx, rbp, r12-r15, and the SSE and x87 control words.
## `save` is in rdi, `resume` in rsi.
const X86_64_SWITCH = "\n    pushq %rbp\n    pushq %rbx\n    pushq %r12\n    pushq %r13\n    pushq %r14\n    pushq %r15\n    subq $$8, %rsp\n    stmxcsr (%rsp)\n    fnstcw 4(%rsp)\n    movq %rsp, (%rdi)\n    movq %rsi, %rsp\n    ldmxcsr (%rsp)\n    fldcw 4(%rsp)\n    addq $$8, %rsp\n    popq %r15\n    popq %r14\n    popq %r13\n    popq %r12\n    popq %rbx\n    popq %rbp\n    retq\n";

## Lays out the frame `X86_64_SWITCH` pops below the 16-byte aligned
## `stack_top` (rdi): control words, six registers with `entry` (rsi) in
## r12, and the trampoline as the return address.
const X86_64_PREPARE = "\n    movq %rdi, %rax\n    andq $$-16, %rax\n    subq $$80, %rax\n    movl $$0x1F80, (%rax)\n    movw $$0x037F, 4(%rax)\n    movq $$0, 8(%rax)\n    movq $$0, 16(%rax)\n    movq $$0, 24(%rax)\n    movq %rsi, 32(%rax)\n    movq $$0, 40(%rax)\n    movq $$0, 48(%rax)\n    leaq 1f(%rip), %rcx\n    movq %rcx, 56(%rax)\n    retq\n1:\n    xorl %edi, %edi\n    callq *%r12\n    ud2\n";

## AArch64 (Linux and Apple): x19-x28, the frame pointer and link register,
## and d8-d15, in a 176-byte frame. `save` is in x0, `resume` in x1.
const AARCH64_SWITCH = "\n    sub sp, sp, #176\n    stp x19, x20, [sp, #0]\n    stp x21, x22, [sp, #16]\n    stp x23, x24, [sp, #32]\n    stp x25, x26, [sp, #48]\n    stp x27, x28, [sp, #64]\n    stp x29, x30, [sp, #80]\n    stp d8, d9, [sp, #96]\n    stp d10, d11, [sp, #112]\n    stp d12, d13, [sp, #128]\n    stp d14, d15, [sp, #144]\n    mov x9, sp\n    str x9, [x0]\n    mov sp, x1\n    ldp x19, x20, [sp, #0]\n    ldp x21, x22, [sp, #16]\n    ldp x23, x24, [sp, #32]\n    ldp x25, x26, [sp, #48]\n    ldp x27, x28, [sp, #64]\n    ldp x29, x30, [sp, #80]\n    ldp d8, d9, [sp, #96]\n    ldp d10, d11, [sp, #112]\n    ldp d12, d13, [sp, #128]\n    ldp d14, d15, [sp, #144]\n    add sp, sp, #176\n    ret\n";

## Lays out the frame `AARCH64_SWITCH` loads below the 16-byte aligned
## `stack_top` (x0): `entry` (x1) in x19, a zero frame pointer, and the
## trampoline in the link register.
const AARCH64_PREPARE = "\n    and x9, x0, #0xfffffffffffffff0\n    sub x9, x9, #176\n    str x1, [x9, #0]\n    str xzr, [x9, #80]\n    adr x10, 1f\n    str x10, [x9, #88]\n    mov x0, x9\n    ret\n1:\n    mov x0, xzr\n    blr x19\n    brk #0\n";

# Exports

## What a C entry point's name starts with until `partition.prepare` names
## it by its C symbol.
export const EXPORT_PREFIX = "__export.";

## The runtime functions (runtime/string.pep) that make a `String` from
## C's bytes, a C copy of a `String`, and free that copy.
const STRING_FROM_C = "_pep_string_from_c";
const STRING_TO_C = "_pep_string_to_c";
const STRING_FREE_C = "_pep_string_free_c";

## LLVM's `LLVMDLLExportStorageClass`.
const DLL_EXPORT_STORAGE_CLASS: int = 2;

# Facts

## LLVM's opcodes for the instructions TBAA tags (`LLVMOpcode`).
const OPCODE_LOAD: int = 27;
const OPCODE_STORE: int = 28;
const OPCODE_GET_ELEMENT_PTR: int = 29;

## Whether `kind` is a floating-point type.
is_float_type_kind(kind: llvm.TypeKind): bool {
    return kind == llvm.TypeKind.Float
        or kind == llvm.TypeKind.Double
        or kind == llvm.TypeKind.Half
        or kind == llvm.TypeKind.BFloat
        or kind == llvm.TypeKind.Fp128
        or kind == llvm.TypeKind.X86Fp80
        or kind == llvm.TypeKind.PpcFp128;
}

## Whether `ty` is a first-class value type: one a register can hold.
is_basic_type(ty: llvm.Type): bool {
    var kind = ty.kind();
    return kind == llvm.TypeKind.Integer
        or is_float_type_kind(kind)
        or kind == llvm.TypeKind.Pointer
        or kind == llvm.TypeKind.Struct
        or kind == llvm.TypeKind.Array
        or kind == llvm.TypeKind.Vector
        or kind == llvm.TypeKind.ScalableVector;
}

## Whether a module-scope variable is `[ThreadLocal]`.
is_thread_local(variable: VariableDef): bool {
    return ast.has_attribute(variable.attributes, sema.THREAD_LOCAL_ATTRIBUTE);
}

## Whether a C symbol names an LLVM intrinsic rather than a C function.
is_intrinsic_symbol(symbol: String): bool {
    return symbol.starts_with("llvm.");
}

extend Generator {
    # Globals

    ## File-scope globals, as real LLVM globals. Constant initializers become
    ## `set_initializer`; non-constant ones are stored by `__pep_global_init`,
    ## registered via `llvm.global_ctors` so it runs before `main`.
    emit_globals(module: Module): Result<void> {
        var non_const = Array<(String, Expression, uint)>();
        for (var variable in module.globals) {
            var ty_string = variable.ty.to_string();
            llvm.Type llvm_ty;
            if (is_reference_name(ty_string)) {
                # Struct-typed globals hold pointers; trait-typed ones hold
                # the (object, vtable) pair.
                llvm_ty = reference_value_type(ty_string);
            } else {
                var found = types.get(ty_string);
                if (!found.is_value()) {
                    return fail<void>($"unknown global type {ty_string}");
                }
                llvm_ty = found.value();
            }
            var global = ir.add_global(llvm_ty, variable.name);
            set_private_linkage(global, variable.name);
            own(variable.name, variable.loc);
            # Every global is defined at link time: a zero/null base
            # initializer, which the constant arms below override.
            var kind = llvm_ty.kind();
            if (kind == llvm.TypeKind.Integer) {
                global.set_initializer(llvm_ty.const_int(0));
            } else if (is_float_type_kind(kind)) {
                global.set_initializer(llvm_ty.const_real(0.0));
            } else if (kind == llvm.TypeKind.Pointer) {
                global.set_initializer(context.pointer_type().zero());
            } else if (kind == llvm.TypeKind.Array or kind == llvm.TypeKind.Struct or kind == llvm.TypeKind.Vector) {
                global.set_initializer(llvm_ty.zero());
            }
            if (is_thread_local(variable)) {
                declare_thread_local(variable, global, llvm_ty)?;
            } else if (variable.default.is_value()) {
                var initializer = variable.default.value();
                bool constant = false;
                match (initializer) {
                    # The literal at the global's own width.
                    IntLiteral(v) => {
                        if (kind == llvm.TypeKind.Integer) {
                            global.set_initializer(llvm_ty.const_int(v));
                            constant = true;
                        }
                    }
                    FloatLiteral(v) => {
                        if (is_float_type_kind(kind)) {
                            global.set_initializer(llvm_ty.const_real(v));
                            constant = true;
                        }
                    }
                    BoolLiteral(v) => {
                        if (kind == llvm.TypeKind.Integer) {
                            global.set_initializer(llvm_ty.const_uint(v ? 1 : 0));
                            constant = true;
                        }
                    }
                    PointerLiteral => {
                        if (kind == llvm.TypeKind.Pointer) {
                            global.set_initializer(context.pointer_type().zero());
                            constant = true;
                        }
                    }
                    # String defaults: the string data must be a constant
                    # global; an internal-linkage string referenced by an
                    # external initializer fails module verification.
                    StringLiteral(node) => {
                        if (kind == llvm.TypeKind.Pointer) {
                            var array = context.const_string(node.value, true);
                            var data_global = ir.add_global(array.value_type(), "str");
                            data_global.set_linkage(llvm.Linkage.Internal);
                            data_global.set_initializer(array);
                            global.set_initializer(data_global);
                            constant = true;
                        }
                    }
                    else => {}
                }
                if (!constant) {
                    non_const.append((variable.name, initializer, variable.loc.file));
                }
            }
            global_addrs[variable.name] = Address.typed(variable.name, ty_string, llvm_ty, global);
            # A debugger would read a thread-local's image, not the thread's
            # copy (DWARF needs a TLS location expression).
            if (debug.is_value() and !is_thread_local(variable)) {
                var debug_ty = debug_type(ty_string);
                if (debug_ty.is_value()) {
                    debug.value().declare_global(
                        global, link.demangle_name(variable.name), debug_ty.value(), variable.loc
                    );
                }
            }
        }

        emit_thread_locals_release(module)?;

        # Non-constant initializers: `g = <expr>;` in one function per file,
        # `__pep_init@<namespace>`; `__pep_global_init`, registered in
        # `llvm.global_ctors`, calls them in initialization order
        # (`module.globals` is sorted by it, so a file's globals are
        # consecutive).
        if (non_const.count == 0) {
            return Result<void>.ok();
        }
        var void_fn = llvm.Type.function(context.void_type(), Array<llvm.Type>(), false);
        var file_inits = Array<llvm.Value>();
        ulong start = 0;
        while (start < non_const.count) {
            var (_, _, file) = non_const[start];
            ulong end = start;
            while (end < non_const.count) {
                var (_, _, other) = non_const[end];
                if (other != file) {
                    break;
                }
                end += 1;
            }
            var namespace = (file as ulong) < file_namespaces.count ? file_namespaces[file as ulong] : $"file{file}";
            var init_fn = ir.add_function($"__pep_init{NAMESPACE_SEPARATOR}{namespace}", void_fn);
            owners[init_fn.name()] = file;
            var entry = context.append_block(init_fn, "entry");
            builder.position_at_end(entry);
            deferred_temps.clear();
            var group = Array<(String, Expression, uint)>();
            for (var i in start..end) {
                group.append(non_const[i]);
            }
            emit_global_stores(group)?;
            builder.return_void();
            file_inits.append(init_fn);
            start = end;
        }
        var init_fn = ir.add_function("__pep_global_init", void_fn);
        var entry = context.append_block(init_fn, "entry");
        builder.position_at_end(entry);
        for (var file_init in file_inits) {
            builder.call(file_init.global_type(), file_init, Array<llvm.Value>(), "");
        }
        builder.return_void();

        # llvm.global_ctors = [1 x { i32 priority, ptr fn, ptr data }]
        var ctor_struct = context.const_struct(
            [context.int32_type().const_uint(65535), init_fn, context.pointer_type().zero()], false
        );
        var ctor_array = ctor_struct.value_type().const_array([ctor_struct]);
        # `llvm.global_ctors` is a reserved name the verifier only accepts
        # with common or appending linkage; Clang uses appending.
        var ctors = ir.add_global(ctor_array.value_type(), "llvm.global_ctors");
        ctors.set_linkage(llvm.Linkage.Appending);
        ctors.set_initializer(ctor_array);
        return Result<void>.ok();
    }

    ## Stores each non-constant initializer `(global, expression, file)` into
    ## its global, at the builder's position.
    emit_global_stores(non_const: Array<(String, Expression, uint)>): Result<void> {
        for (var item in non_const) {
            var (name, expr, _) = item;
            var value = codegen_expr(expr)?;
            # A struct-ref global initialized from an lvalue read acquires
            # exactly like `codegen_var_def` does: the global becomes the
            # value's owner.
            var addr = global_addrs[name];
            var ty_string = addr.ty;
            if (is_reference_name(ty_string) and is_lvalue_read(expr)) {
                acquire_ref(ty_string, value)?;
            }
            # Match the global's width (mirrors codegen_var_def).
            if (addr.llvm_ty.is_value()) {
                var slot = addr.llvm_ty.value();
                var value_ty = value.value_type();
                var value_kind = value_ty.kind();
                var slot_kind = slot.kind();
                if (value_kind == llvm.TypeKind.Integer
                    and slot_kind == llvm.TypeKind.Integer
                    and !value_ty.same(slot)) {
                    # A signed integer cast.
                    if (value_ty.int_width() > slot.int_width()) {
                        value = builder.truncate(value, slot, $"{name}w");
                    } else {
                        value = builder.sign_extend(value, slot, $"{name}w");
                    }
                } else if (is_float_type_kind(value_kind) and is_float_type_kind(slot_kind) and !value_ty.same(slot)) {
                    # A float cast: `fptrunc` or `fpext`.
                    if (value_kind == llvm.TypeKind.Double and slot_kind == llvm.TypeKind.Float) {
                        value = builder.float_truncate(value, slot, $"{name}w");
                    } else {
                        value = builder.float_extend(value, slot, $"{name}w");
                    }
                }
            }
            addr.store(builder, value)?;
            flush_deferred_temps()?;
        }
        return Result<void>.ok();
    }

    # Thread-locals

    ## Makes `global`, just added for `variable`, a `thread_local` global in
    ## the initial-exec model, with `variable`'s constant initializer.
    declare_thread_local(variable: VariableDef, global: llvm.Value, llvm_ty: llvm.Type): Result<void> {
        global.set_thread_local_mode(INITIAL_EXEC_TLS_MODEL);
        if (!variable.default.is_value()) {
            return Result<void>.ok();
        }
        var constant = sema.thread_local_constant(variable.default.value(), state);
        if (!constant.is_value()) {
            return fail<void>($"thread-local variable '{variable.name}' must start from a constant");
        }
        var kind = llvm_ty.kind();
        match (constant.value()) {
            Int(v) => {
                if (kind == llvm.TypeKind.Integer) {
                    global.set_initializer(llvm_ty.const_int(v));
                    return Result<void>.ok();
                }
                if (is_float_type_kind(kind)) {
                    global.set_initializer(llvm_ty.const_real(v as double));
                    return Result<void>.ok();
                }
            }
            Float(v) => {
                if (is_float_type_kind(kind)) {
                    global.set_initializer(llvm_ty.const_real(v));
                    return Result<void>.ok();
                }
            }
            Null => {
                # Null: the zero initializer the caller already set.
                return Result<void>.ok();
            }
        }
        return fail<void>($"thread-local variable '{variable.name}' cannot start from this constant");
    }

    ## The address of global `id` for the code being generated: its
    ## `global_addrs` entry.
    global_address(id: String): Result<Address?> {
        return Result<Address?>.ok(global_addrs.try_get(id));
    }

    ## Defines `_pep_release_thread_locals` in the program, releasing every
    ## thread-local of `module` that holds references.
    emit_thread_locals_release(module: Module): Result<void> {
        var void_fn = llvm.Type.function(context.void_type(), Array<llvm.Type>(), false);
        var existing = ir.function(RELEASE_FUNCTION);
        llvm.Value function;
        if (existing.is_value()) {
            function = existing.value();
        } else {
            function = ir.add_function(RELEASE_FUNCTION, void_fn);
        }
        if (function.block_count() != 0) {
            return Result<void>.ok();
        }
        var held = Array<(String, String)>();
        for (var variable in module.globals) {
            if (!is_thread_local(variable)) {
                continue;
            }
            var ty = variable.ty.to_string();
            if (is_reference_name(ty)) {
                held.append((variable.name, ty));
            }
        }
        var entry = context.append_block(function, "entry");
        builder.position_at_end(entry);
        ulong passes = held.count == 0 ? 0 : RELEASE_PASSES;
        for (var _pass in 0..passes) {
            var index = held.count;
            while (index > 0) {
                index -= 1;
                var (name, ty) = held[index];
                var found = global_address(name)?;
                if (!found.is_value()) {
                    return fail<void>($"unknown thread-local '{name}'");
                }
                var addr = found.value();
                if (!addr.llvm_ty.is_value()) {
                    return fail<void>($"thread-local '{name}' has no type");
                }
                var llvm_ty = addr.llvm_ty.value();
                var old = addr.load(builder);
                if (!old.is_value()) {
                    return fail<void>($"load failed {name}");
                }
                addr.store(builder, zero_of(llvm_ty))?;
                release_ref(ty, old.value())?;
            }
        }
        # The runtime's `extern void` declared it first, returning Pepper's
        # `void` type, which is not LLVM's.
        var return_type = function.global_type().return_type();
        if (return_type.kind() == llvm.TypeKind.Void) {
            builder.return_void();
        } else {
            builder.return_value(zero_of(return_type));
        }
        return Result<void>.ok();
    }

    # Context intrinsics

    ## Defines each context intrinsic the module declares as a naked function
    ## of the target's assembly, for the architecture sema compiled for.
    define_context_intrinsics(): Result<void> {
        for (var name in [SWITCH_CONTEXT, PREPARE_CONTEXT]) {
            var found = ir.function(name);
            if (!found.is_value()) {
                continue;
            }
            var function = found.value();
            if (function.block_count() != 0) {
                continue;
            }
            var os = state.target.os;
            var arch = state.target.arch;
            String assembly;
            if (os == "windows") {
                return fail<void>($"'{name}' is not available on Windows; fibers there use the Fibers API");
            } else if (arch == "x86_64") {
                assembly = name == SWITCH_CONTEXT ? X86_64_SWITCH : X86_64_PREPARE;
            } else if (arch == "aarch64") {
                assembly = name == SWITCH_CONTEXT ? AARCH64_SWITCH : AARCH64_PREPARE;
            } else {
                return fail<void>($"'{name}' is not available on {arch}");
            }
            define_naked(function, assembly)?;
        }
        return Result<void>.ok();
    }

    ## Gives a declared function a naked body: `assembly` and nothing else.
    define_naked(function: llvm.Value, assembly: String): Result<void> {
        for (var attribute in ["naked", "noinline", "nounwind"]) {
            function.add_function_attribute(context.attribute(attribute, 0));
        }
        var saved = builder.insert_block();
        var entry = context.append_block(function, "entry");
        builder.position_at_end(entry);
        var asm_type = llvm.Type.function(context.void_type(), Array<llvm.Type>(), false);
        var asm = context.inline_asm(asm_type, assembly, "", true, false);
        builder.call(asm_type, asm, Array<llvm.Value>(), "");
        builder.unreachable();
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<void>.ok();
    }

    # Exports

    ## Defines the entry point of every export and handle function.
    emit_exports(module: Module): Result<void> {
        var exports = state.exports;
        var pointer = context.pointer_type();
        var size = context.int64_type();
        for (var item in exports.functions) {
            var found = functions.try_get(item.function);
            if (!found.is_value()) {
                return fail<void>($"exported function '{item.symbol}' has no code");
            }
            var target = found.value();
            # A `String` parameter is a pointer and a size in C, a `String`
            # result a pointer; everything else keeps its Pepper type.
            var target_type = target.global_type();
            var target_params = target_type.param_types();
            var c_parameters = Array<llvm.Type>();
            var widened = Array<TypeName>();
            for (var index in 0..item.parameters.count) {
                var (_, ty) = item.parameters[index];
                if (sema.is_export_string(ty)) {
                    c_parameters.append(pointer);
                    c_parameters.append(size);
                    widened.append(ty);
                    widened.append(ty);
                } else {
                    if (index >= target_params.count) {
                        return fail<void>("an exported function's parameters do not match");
                    }
                    c_parameters.append(target_params[index]);
                    widened.append(ty);
                }
            }
            llvm.Type entry_type;
            if (sema.is_export_string(item.result)) {
                entry_type = llvm.Type.function(pointer, c_parameters, false);
            } else {
                entry_type = llvm.Type.function(target_type.return_type(), c_parameters, false);
            }
            var entry = export_function(item.symbol, entry_type)?;
            widen_small_integers(entry, widened, item.result);
            var block = context.append_block(entry, "entry");
            builder.position_at_end(block);
            uint next = 0;
            var c_count = entry.param_count();
            var arguments = Array<llvm.Value>();
            var strings = Array<llvm.Value>();
            for (var parameter in item.parameters) {
                var (_, parameter_ty) = parameter;
                if (next >= c_count) {
                    return fail<void>("an exported function's parameters do not match");
                }
                var argument = entry.param(next);
                next += 1;
                if (sema.is_export_string(parameter_ty)) {
                    if (next >= c_count) {
                        return fail<void>("an exported function's parameters do not match");
                    }
                    var bytes_size = entry.param(next);
                    next += 1;
                    var string = call_function(STRING_FROM_C, [argument, bytes_size])?;
                    strings.append(string);
                    arguments.append(string);
                } else {
                    arguments.append(argument);
                }
            }
            var call = builder.call(target_type, target, arguments, "");
            # The strings made from C's bytes go away with the call.
            for (var string in strings) {
                release_ref("String", string)?;
            }
            if (target_type.return_type().kind() == llvm.TypeKind.Void) {
                builder.return_void();
            } else if (sema.is_export_string(item.result)) {
                var converted = call_function(STRING_TO_C, [call])?;
                release_ref("String", call)?;
                builder.return_value(converted);
            } else {
                builder.return_value(call);
            }
        }
        if (exports.frees_strings) {
            var free = llvm.Type.function(context.void_type(), [pointer], false);
            var entry = export_function(sema.STRING_FREE, free)?;
            var block = context.append_block(entry, "entry");
            builder.position_at_end(block);
            if (entry.param_count() == 0) {
                return fail<void>("the string free function has no parameter");
            }
            var text = entry.param(0);
            call_function(STRING_FREE_C, [text])?;
            builder.return_void();
        }
        var step = llvm.Type.function(context.void_type(), [pointer], false);
        for (var handle in exports.handles) {
            for (var pair in [(handle.retain, true), (handle.release, false)]) {
                var (symbol, retain) = pair;
                var entry = export_function(symbol, step)?;
                var block = context.append_block(entry, "entry");
                builder.position_at_end(block);
                if (entry.param_count() == 0) {
                    return fail<void>("a handle function has no parameter");
                }
                var object = entry.param(0);
                if (retain) {
                    acquire_ref(handle.structure, object)?;
                } else {
                    release_ref(handle.structure, object)?;
                }
                builder.return_void();
            }
        }
        return Result<void>.ok();
    }

    ## Declares the C entry point `symbol`: external, visible outside the
    ## library, and exported from a Windows DLL.
    export_function(symbol: String, ty: llvm.Type): Result<llvm.Value> {
        if (extern_names.contains(symbol)) {
            return fail<llvm.Value>($"cannot export '{symbol}': the program declares an extern of that name");
        }
        var name = $"{EXPORT_PREFIX}{symbol}";
        var entry = ir.add_function(name, ty);
        entry.set_linkage(llvm.Linkage.External);
        # Default visibility is LLVM's default: nothing to set.
        if (ir.target_triple().contains("windows")) {
            entry.set_dll_storage_class(DLL_EXPORT_STORAGE_CLASS);
        }
        return Result<llvm.Value>.ok(entry);
    }

    ## Marks the parameters and result C widens (integers narrower than
    ## `int`, and `bool`) `signext` or `zeroext`, as clang does.
    widen_small_integers(entry: llvm.Value, parameters: TypeName[], result: TypeName) {
        for (var index in 0..parameters.count) {
            var signed = small_integer_is_signed(parameters[index]);
            if (signed.is_value()) {
                entry.add_param_attribute(index as uint, context.attribute(signed.value() ? "signext" : "zeroext", 0));
            }
        }
        var signed = small_integer_is_signed(result);
        if (signed.is_value()) {
            entry.add_return_attribute(context.attribute(signed.value() ? "signext" : "zeroext", 0));
        }
    }

    ## Whether C widens `ty` (an integer narrower than `int`, or `bool`) by
    ## sign (`true`) or by zero (`false`); none for any other type.
    small_integer_is_signed(ty: TypeName): bool? {
        var stored = sema.stored_as(state, ty.name);
        if (stored == "char" or stored == "i8" or stored == "i16" or stored == "short") {
            return Optional<bool>.Value(true);
        }
        if (stored == "bool" or stored == "u8" or stored == "byte" or stored == "u16" or stored == "ushort") {
            return Optional<bool>.Value(false);
        }
        return Optional<bool>.Empty;
    }

    # Intrinsics

    ## Declares the LLVM intrinsic `symbol` with the extern's prototype
    ## `fn_type`; an overloaded intrinsic's overload is picked from the
    ## prototype. `name` is the extern's Pepper name, for the error.
    declare_intrinsic(name: String, symbol: String, fn_type: llvm.Type): Result<llvm.Value> {
        var id = llvm.lookup_intrinsic_id(symbol);
        if (id == 0) {
            return fail<llvm.Value>($"unknown LLVM intrinsic '{symbol}'");
        }
        var candidates = [symbol];
        if (llvm.intrinsic_is_overloaded(id)) {
            var ret = fn_type.return_type();
            var has_ret = ret.kind() != llvm.TypeKind.Void;
            var params = fn_type.param_types();
            var has_first = params.count > 0 and is_basic_type(params[0]);
            if (has_ret) {
                candidates.append(ir.overloaded_intrinsic_name(id, [ret]));
            }
            if (has_first) {
                candidates.append(ir.overloaded_intrinsic_name(id, [params[0]]));
            }
            if (has_ret and has_first) {
                candidates.append(ir.overloaded_intrinsic_name(id, [ret, params[0]]));
            }
        }
        var problem = "";
        for (var candidate in candidates) {
            var existing = ir.function(candidate);
            if (existing.is_value()) {
                if (existing.value().global_type().same(fn_type)) {
                    return Result<llvm.Value>.ok(existing.value());
                }
                continue;
            }
            var checked = check_intrinsic(candidate, fn_type);
            if (checked.is_ok()) {
                return Result<llvm.Value>.ok(ir.add_function(candidate, fn_type));
            }
            # Every overload but one has a mangled name that does not fit
            # the prototype; say what is wrong with the others.
            var message = checked.error().message;
            if (!message.contains("mangled")) {
                problem = message;
            }
        }
        var detail = problem.is_empty ? "" : $": {problem}";
        return fail<llvm.Value>($"'{name}' does not match the signature of LLVM intrinsic '{symbol}'{detail}");
    }

    ## Whether declaring `symbol` with `fn_type` is a valid intrinsic
    ## declaration: the verifier's first complaint, if not.
    check_intrinsic(symbol: String, fn_type: llvm.Type): Result<void> {
        var scratch = llvm.Module(context, "intrinsic_check");
        var f = scratch.add_function(symbol, fn_type);
        if (f.intrinsic_id() == 0) {
            return fail<void>($"'{symbol}' is not an LLVM intrinsic");
        }
        # The verifier checks an intrinsic's signature at its calls, not at
        # its declaration: call it once, with zeros (constants, as `immarg`
        # parameters require).
        var caller = scratch.add_function("caller", llvm.Type.function(context.void_type(), Array<llvm.Type>(), false));
        var scratch_builder = llvm.Builder(context);
        scratch_builder.position_at_end(context.append_block(caller, "entry"));
        var args = Array<llvm.Value>();
        for (var param in fn_type.param_types()) {
            if (!is_basic_type(param)) {
                return fail<void>($"'{symbol}' takes a parameter Pepper cannot pass");
            }
            args.append(param.zero());
        }
        scratch_builder.call(fn_type, f, args, "");
        scratch_builder.return_void();
        var verified = scratch.verify();
        if (verified.is_ok()) {
            return Result<void>.ok();
        }
        var message = verified.error().message;
        var newline = message.find("\n");
        var first = newline < 0 ? message : message.substr_bytes(0, newline as ulong);
        first = first.trim();
        while (first.ends_with("!")) {
            first = first.substr_bytes(0, first.size - 1);
        }
        return fail<void>(first.lower());
    }

    ## The error for argument `index` of a call of extern `name` when the
    ## extern is an intrinsic that requires that argument to be a constant
    ## (`immarg`) and `value` is not one.
    check_intrinsic_argument(name: String, index: ulong, value: llvm.Value): Result<void> {
        var found = functions.try_get(name);
        if (!found.is_value()) {
            return Result<void>.ok();
        }
        var function = found.value();
        if (function.intrinsic_id() == 0) {
            return Result<void>.ok();
        }
        if (!function.has_param_attribute(index as uint, "immarg")) {
            return Result<void>.ok();
        }
        var kind = value.value_type().kind();
        bool constant = true;
        if (kind == llvm.TypeKind.Integer or is_float_type_kind(kind)) {
            constant = value.is_constant();
        }
        if (constant) {
            return Result<void>.ok();
        }
        return fail<void>($"argument {index + 1} to '{name}' must be a constant");
    }
}

# Facts

## States the facts the language guarantees in `ir`, before it is
## optimized: `nounwind` on every function (and `uwtable`, and on Apple
## targets `"frame-pointer"="non-leaf"`, on definitions), `noreturn` and
## `cold` on the functions that end the program, `noalias` on the
## allocators' results, and TBAA on loads and stores of object memory.
export annotate_facts(ir: llvm.Module, context: llvm.Context) {
    var nounwind = context.attribute("nounwind", 0);
    # `uwtable(async)`, clang's default on every target Pepper supports.
    var uwtable = context.attribute("uwtable", 2);
    var noreturn = context.attribute("noreturn", 0);
    var cold = context.attribute("cold", 0);
    var noalias = context.attribute("noalias", 0);
    bool apple = ir.target_triple().contains("-apple-");
    var tags = TbaaTags(context);
    for (var function in ir.functions()) {
        var name = function.name();
        if (name.starts_with("llvm.")) {
            continue;
        }
        function.add_function_attribute(nounwind);
        # Functions that never return: the runtime's panic and exit paths
        # and the C functions under them.
        if (name == "_pep_panic" or name == "_pep_exit" or name == "abort" or name == "_Exit") {
            function.add_function_attribute(noreturn);
            function.add_function_attribute(cold);
        }
        # Functions that return memory nothing else points to.
        if ((name == "_pep_malloc" or name == "_pep_malloc_uninit" or name == "_pep_realloc")
            and function.global_type().return_type().kind() == llvm.TypeKind.Pointer) {
            function.add_return_attribute(noalias);
        }
        if (function.block_count() > 0) {
            function.add_function_attribute(uwtable);
            if (apple) {
                function.add_function_attribute(context.string_attribute("frame-pointer", "non-leaf"));
            }
            tags.annotate(function);
        }
    }
}

## Which part of an object an address points into.
enum ObjectPart {
    Head,
    Field,
}

## Type-based alias analysis for object memory: the two access tags (a
## count in an object's head, a field of a struct object), and the kind id
## of `!tbaa`. Two tagged accesses with different tags never alias;
## everything else stays untagged.
struct TbaaTags {
    var kind: uint;
    var head: llvm.Value;
    var field: llvm.Value;

    construct(context: llvm.Context) {
        var zero = context.constant_metadata(context.int64_type().zero());
        var root = context.metadata_node([context.metadata_string("Pepper TBAA")]);
        var head_type = context.metadata_node([context.metadata_string("reference counts"), root, zero]);
        var head_access = context.metadata_node([head_type, head_type, zero]);
        var field_type = context.metadata_node([context.metadata_string("fields"), root, zero]);
        var field_access = context.metadata_node([field_type, field_type, zero]);
        kind = context.metadata_kind("tbaa");
        head = context.metadata_value(head_access);
        field = context.metadata_value(field_access);
    }

    ## Tags the loads and stores of `function` that address object memory.
    annotate(function: llvm.Value) {
        for (var block in function.blocks()) {
            var instruction = block.first_instruction();
            while (!instruction.is_null()) {
                var current = instruction;
                instruction = current.next_instruction();
                var opcode = current.opcode();
                llvm.Value address;
                if (opcode == OPCODE_LOAD) {
                    address = current.operand(0);
                } else if (opcode == OPCODE_STORE) {
                    address = current.operand(1);
                } else {
                    continue;
                }
                if (address.is_null() or !address.is_instruction()) {
                    continue;
                }
                var part = object_part(address);
                if (!part.is_value()) {
                    continue;
                }
                current.set_metadata(kind, part.value() == ObjectPart.Head ? head : field);
            }
        }
    }
}

## Which part of an object `address` (an instruction) points into, when it
## is a field address of a struct object or a head count address.
object_part(address: llvm.Value): ObjectPart? {
    var none = Optional<ObjectPart>.Empty;
    if (address.opcode() != OPCODE_GET_ELEMENT_PTR) {
        return none;
    }
    if (address.name().starts_with(HEAD_COUNT_NAME)) {
        return Optional<ObjectPart>.Value(ObjectPart.Head);
    }
    var source = address.gep_source_type();
    if (source.kind() != llvm.TypeKind.Struct) {
        return none;
    }
    if (source.struct_name().is_empty or address.operand_count() < 3) {
        return none;
    }
    var first = address.operand(1);
    if (!first.is_constant_int() or first.zero_extended() != 0) {
        return none;
    }
    var second = address.operand(2);
    if (!second.is_constant_int()) {
        return none;
    }
    return Optional<ObjectPart>.Value(second.zero_extended() < 2 ? ObjectPart.Head : ObjectPart.Field);
}

# CPU

## Puts the CPU, features and tuning on every function `ir` defines, as
## clang does (`"target-cpu"`, `"target-features"`, `"tune-cpu"`), so code
## keeps its CPU when link-time optimization inlines it into another
## unit's. An empty `features` or `tune` is left off.
export stamp_cpu(ir: llvm.Module, context: llvm.Context, cpu: String, tune: String, features: String) {
    var attributes = [context.string_attribute("target-cpu", cpu)];
    if (!features.is_empty) {
        attributes.append(context.string_attribute("target-features", features));
    }
    if (!tune.is_empty) {
        attributes.append(context.string_attribute("tune-cpu", tune));
    }
    for (var function in ir.functions()) {
        if (function.block_count() == 0) {
            continue;
        }
        for (var attribute in attributes) {
            function.add_function_attribute(attribute);
        }
    }
}

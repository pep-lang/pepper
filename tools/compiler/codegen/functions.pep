## Declaring structs, methods, externs and functions, and generating
## function bodies, blocks and statements: the instantiation pass and the
## statement half of the codegen pass.

import compiler.ast;
import llvm;
import compiler.sema;
import [
    Block,
    Branch,
    Declaration,
    Expression,
    ExternDef,
    FunctionDef,
    LoopBreak,
    LoopBreakKind,
    Loc,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeName,
    VariableDef,
    While
] from compiler.sema;
import [Address, check_store_type] from "address";
import "address";
import "calls";
import [function_checks] from "checks";
import "checks";
import "debug";
import "debug_types";
import "expressions";
import [Generator, ScopeSlot, StructDesc] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "static_debug";
import "traits";
import [is_object] from "types";
import "types";

## The C symbol an extern binds: its `[Link(name = "sym")]`, else its name.
extern_symbol(ext: ExternDef): String {
    for (var attribute in ext.attributes) {
        var name = sema.attribute_name(attribute);
        if (!name.is_value() or name.value() != "Link") {
            continue;
        }
        for (var argument in sema.attribute_arguments(attribute)) {
            if (argument.name.is_value()) {
                var (key, _) = argument.name.value();
                if (key == "name") {
                    if (argument.value is Literal(literal, _)) {
                        if (literal is String(text)) {
                            return text;
                        }
                    }
                }
            }
        }
    }
    return ext.name;
}

## Whether `st` is a generic base (abstract) or a tuple, which get no code
## of their own.
is_abstract(st: StructDef): bool {
    return (st.ty.is_generic() and st.name == st.ty.name) or st.ty.is_tuple();
}

## Whether a struct's `__acquire` and `__release` are the standard ones,
## which codegen may inline.
standard_counts(st: StructDef): bool {
    bool immortal_cases = false;
    if (st.enum_cases.is_value()) {
        for (var c in st.enum_cases.value()) {
            if (c.payload.count == 0) {
                immortal_cases = true;
            }
        }
    }
    return st.release.body.is_value() and !st.ty.is_weak() and !st.ty.is_function_type() and !immortal_cases;
}

## Whether a struct's counts step atomically: `[Shared]`, or a shared
## function type's object.
atomic_counts(st: StructDef): bool {
    return ast.has_attribute(st.attributes, sema.SHARED_ATTRIBUTE) or st.ty.is_shared_function_type();
}

extend Generator {
    # Struct instantiation

    instantiate_struct(st: StructDef): Result<void> {
        var result = instantiate_struct_unlocated(st);
        locate(result, st.loc);
        return result;
    }

    instantiate_struct_unlocated(st: StructDef): Result<void> {
        if (is_abstract(st)) {
            return Result<void>.ok();
        }
        var field_types = Array<llvm.Type>();
        for (var field in st.field_members) {
            var ty = types.get(field.ty.to_string());
            if (!ty.is_value()) {
                var error = fail<void>($"unknown type name '{field.ty.display()}'");
                var at = !field.type_loc.is_none() ? field.type_loc : (!field.loc.is_none() ? field.loc : st.loc);
                locate(error, at);
                return error;
            }
            # A struct-typed field holds a reference; a tuple field is laid out
            # inline.
            field_types.append(slot_type(context, ty.value()));
        }
        types.register_struct(st.name, field_types);
        var llvm_type = types.struct_type(st.name).value();
        if (is_value_struct(st)) {
            var fields = Array<String>();
            for (var f in st.field_members) {
                fields.append(f.ty.to_string());
            }
            values[st.name] = fields;
        }
        var desc = StructDesc(st.name, llvm_type, st.loc);
        for (var f in st.field_members) {
            desc.fields.append((f.name, f.ty.to_string()));
            desc.field_locs.append(f.loc);
        }
        if (standard_counts(st)) {
            desc.inline_counts = Optional<bool>.Value(atomic_counts(st));
        }
        desc.lazy = ast.has_attribute(st.attributes, sema.LAZY_ATTRIBUTE);
        any_lazy = any_lazy or desc.lazy;
        structs[st.name] = desc;
        return Result<void>.ok();
    }

    # Method instantiation

    instantiate_methods(st: StructDef): Result<void> {
        var result = instantiate_methods_unlocated(st);
        locate(result, st.loc);
        return result;
    }

    instantiate_methods_unlocated(st: StructDef): Result<void> {
        if (is_abstract(st)) {
            return Result<void>.ok();
        }
        var struct_name = st.name;
        var methods = HashMap<String, String>();
        var method_returns = HashMap<String, String>();
        var method_params = HashMap<String, String[]>();
        var static_names = HashSet<String>();
        bool lazy = ast.has_attribute(st.attributes, sema.LAZY_ATTRIBUTE);
        for (var method in st.method_members) {
            var param_types = Array<llvm.Type>();
            if (!method.is_static) {
                # `this` is a pointer; a value struct's is the address of its
                # storage.
                var this_ty = types.get(struct_name);
                if (!this_ty.is_value()) {
                    return fail<void>($"unknown this type {struct_name}");
                }
                if (is_object(this_ty.value()) or is_value_struct(st)) {
                    param_types.append(context.pointer_type());
                } else {
                    param_types.append(this_ty.value());
                }
            }
            for (var param in method.parameters) {
                var ty = parameter_type(param)?;
                param_types.append(ty);
            }
            var mangled = $"{struct_name}.{method.name}";
            llvm.Type fn_type;
            if (is_void(method.ty)) {
                fn_type = llvm.Type.function(context.void_type(), param_types);
            } else {
                var return_type = types.get(method.ty.to_string());
                if (!return_type.is_value()) {
                    return fail<void>(
                        $"unknown return type {method.ty.to_string()} for method {struct_name}.{method.name}"
                    );
                }
                fn_type = llvm_fn_type(context, return_type.value(), param_types, false);
            }
            var fn_value = ir.add_function(mangled, fn_type);
            mark_cold(fn_value, method.attributes);
            set_private_linkage(fn_value, mangled);
            # A member the passes synthesize for a use (`__copy`, placed at the
            # struct) has no owner: a compilation unit that reads the struct's
            # may make it, and the object of the struct's file, cached without
            # it, would not define it. Like an instantiation, it is defined in
            # each part that uses it.
            bool synthesized = method.name.starts_with("__") and method.owner.is_none() and method.loc == st.loc;
            if (!synthesized) {
                own_function(
                    mangled, method.owner.is_none() ? (method.loc.is_none() ? st.loc : method.loc) : method.owner
                );
            }
            functions[mangled] = fn_value;
            var param_names = Array<String>();
            if (!method.is_static) {
                param_names.append("");
            }
            var defaults = Array<Expression?>();
            var sending = Array<bool>();
            bool any_sending = false;
            for (var p in method.parameters) {
                param_names.append(p.ty.to_string());
                defaults.append(p.default);
                var takes = sema.takes_over(p.attributes);
                sending.append(takes);
                any_sending = any_sending or takes;
            }
            fn_param_types[mangled] = param_names;
            param_defaults[mangled] = defaults;
            if (any_sending) {
                sending_params[mangled] = sending;
            }
            record_reads_params(mangled, method.parameters);
            if (method.is_static) {
                static_names.insert(method.name);
            }
            if (lazy and ast.has_attribute(method.attributes, sema.READS_ATTRIBUTE)) {
                reads_methods.insert(mangled);
            }
            methods[method.name] = mangled;
            method_returns[method.name] = method.ty.to_string();
            var params = Array<String>();
            for (var p in method.parameters) {
                params.append(p.ty.to_string());
            }
            method_params[method.name] = params;
        }
        var desc = structs.try_get(st.name);
        if (desc.is_value()) {
            desc.value().methods = methods;
            desc.value().static_methods = static_names;
            desc.value().method_returns = method_returns;
            desc.value().method_params = method_params;
        }
        return Result<void>.ok();
    }

    ## The LLVM type a parameter is passed as: a struct object by pointer.
    parameter_type(param: VariableDef): Result<llvm.Type> {
        var ty = types.get(param.ty.to_string());
        if (!ty.is_value()) {
            var error = fail<llvm.Type>($"unknown type name '{param.ty.to_string()}'");
            locate(error, param.type_loc);
            return error;
        }
        return Result<llvm.Type>.ok(slot_type(context, ty.value()));
    }

    # Extern and function instantiation

    instantiate_extern(ext: ExternDef): Result<void> {
        var result = instantiate_extern_unlocated(ext);
        locate(result, ext.loc);
        return result;
    }

    instantiate_extern_unlocated(ext: ExternDef): Result<void> {
        extern_names.insert(ext.name);
        var param_names = Array<String>();
        for (var p in ext.parameters) {
            param_names.append(p.ty.to_string());
        }
        extern_params[ext.name] = param_names;
        fn_param_types[ext.name] = param_names.copy();
        var param_types = Array<llvm.Type>();
        for (var param in ext.parameters) {
            var ty = types.get(param.ty.to_string());
            if (!ty.is_value()) {
                var error = fail<void>($"unknown type name '{param.ty.to_string()}'");
                locate(error, param.type_loc);
                return error;
            }
            param_types.append(ty.value());
        }
        var return_type = types.get(ext.ty.to_string());
        if (!return_type.is_value()) {
            return fail<void>($"unknown return type {ext.ty.to_string()}");
        }
        var fn_type = llvm_fn_type(context, return_type.value(), param_types, ext.is_variadic);
        # `[Link(name = "sym")]` binds the declared name to another C symbol.
        var symbol = extern_symbol(ext);
        # `[Link(name = "llvm.ctpop")]` declares an LLVM intrinsic, whose
        # `void` is a true `void`.
        if (symbol.starts_with("llvm.")) {
            if (is_void(ext.ty)) {
                fn_type = llvm.Type.function(context.void_type(), param_types, ext.is_variadic);
            }
            var intrinsic = declare_intrinsic(ext.name, symbol, fn_type)?;
            functions[ext.name] = intrinsic;
            fn_returns[ext.name] = ext.ty.to_string();
            return Result<void>.ok();
        }
        # On a 32-bit target the C function's own signature differs from
        # Pepper's (see `c_abi_type`): declare that one, and calls convert.
        if (targets_32_bit()) {
            var c_params = Array<llvm.Type>();
            for (var index in 0..ext.parameters.count) {
                c_params.append(c_abi_type(context, ext.parameters[index].ty.to_string(), param_types[index]));
            }
            var c_return = c_abi_type(context, ext.ty.to_string(), return_type.value());
            if (!c_return.same(return_type.value())) {
                extern_narrow_results[ext.name] = !sema.is_unsigned_int_type(state, ext.ty.to_string());
            }
            if (is_void(ext.ty)) {
                fn_type = llvm.Type.function(context.void_type(), c_params, ext.is_variadic);
            } else {
                fn_type = llvm_fn_type(context, c_return, c_params, ext.is_variadic);
            }
        }
        var existing = ir.function(symbol);
        llvm.Value fn_value;
        if (existing.is_value()) {
            fn_value = existing.value();
        } else {
            fn_value = ir.add_function(symbol, fn_type);
            # C ABI: integer arguments and results narrower than int carry
            # signext or zeroext, as clang emits.
            for (var index in 0..ext.parameters.count) {
                var attribute = extension_attribute(ext.parameters[index].ty.to_string(), param_types[index]);
                if (attribute.is_value()) {
                    fn_value.add_param_attribute(index as uint, attribute.value());
                }
            }
            var result = extension_attribute(ext.ty.to_string(), return_type.value());
            if (result.is_value()) {
                fn_value.add_return_attribute(result.value());
            }
        }
        functions[ext.name] = fn_value;
        fn_returns[ext.name] = ext.ty.to_string();
        return Result<void>.ok();
    }

    ## `signext` or `zeroext` for a C argument or result of Pepper type
    ## `ty_name` and LLVM type `llvm_ty` narrower than 32 bits.
    extension_attribute(ty_name: String, llvm_ty: llvm.Type): llvm.Attribute? {
        if (llvm_ty.kind() != llvm.TypeKind.Integer or llvm_ty.int_width() >= 32) {
            return Optional<llvm.Attribute>.Empty;
        }
        var kind = llvm_ty.int_width() == 1 or sema.is_unsigned_int_type(state, ty_name) ? "zeroext" : "signext";
        return Optional<llvm.Attribute>.Value(context.attribute(kind));
    }

    ## Gives a `[Cold]` function LLVM's `cold` and `noinline`, so it
    ## stays out of line however small or rarely called.
    mark_cold(function: llvm.Value, attributes: ast.Attribute[]) {
        if (!ast.has_attribute(attributes, sema.COLD_ATTRIBUTE)) {
            return;
        }
        for (var attribute in ["cold", "noinline"]) {
            function.add_function_attribute(context.attribute(attribute));
        }
    }

    instantiate_function(function: FunctionDef): Result<void> {
        var result = instantiate_function_unlocated(function);
        locate(result, function.loc);
        return result;
    }

    instantiate_function_unlocated(function: FunctionDef): Result<void> {
        # Generic function bases are abstract: their specializations were
        # cloned with concrete names.
        if (function.is_generic_func or functions.contains(function.name)) {
            return Result<void>.ok();
        }
        var param_types = Array<llvm.Type>();
        for (var param in function.parameters) {
            var ty = parameter_type(param)?;
            param_types.append(ty);
        }
        llvm.Type fn_type;
        if (is_void(function.ty)) {
            fn_type = llvm.Type.function(context.void_type(), param_types);
        } else {
            var return_type = types.get(function.ty.to_string());
            if (!return_type.is_value()) {
                return fail<void>($"unknown return type {function.ty.to_string()} for fn {function.name}");
            }
            fn_type = llvm_fn_type(context, return_type.value(), param_types, false);
        }
        # An extern bound to the C symbol this function is named after
        # (`[Link(name = "exit")]` beside a Pepper `exit`) moves aside, so the
        # function keeps its own name and `prepare` gives each its spelling.
        var taken = ir.function(function.name);
        if (taken.is_value() and taken.value().is_declaration()) {
            taken.value().set_name($"{EXTERN_PREFIX}{function.name}");
        }
        var fn_value = ir.add_function(function.name, fn_type);
        mark_cold(fn_value, function.attributes);
        set_private_linkage(fn_value, function.name);
        own_function(function.name, function.loc);
        functions[function.name] = fn_value;
        fn_returns[function.name] = function.ty.to_string();
        var defaults = Array<Expression?>();
        var names = Array<String>();
        var sending = Array<bool>();
        bool any_sending = false;
        for (var p in function.parameters) {
            defaults.append(p.default);
            names.append(p.ty.to_string());
            var takes = sema.takes_over(p.attributes);
            sending.append(takes);
            any_sending = any_sending or takes;
        }
        param_defaults[function.name] = defaults;
        fn_signatures[function.name] = (names, function.loc);
        fn_param_types[function.name] = names.copy();
        if (any_sending) {
            sending_params[function.name] = sending;
        }
        record_reads_params(function.name, function.parameters);
        return Result<void>.ok();
    }

    ## The constructors with their `__alloc_size` literal patched to the
    ## computed struct size, so the declaration and the body agree.
    patched_ctors(st: StructDef): FunctionDef[] {
        var out = Array<FunctionDef>();
        for (var c in st.constructors) {
            out.append(patched_ctor(st, c));
        }
        return out;
    }

    patched_ctor(st: StructDef, constructor: FunctionDef): FunctionDef {
        var ctor = constructor.copy();
        # Patched below: a body generated, or held back to be, is decoded
        # first.
        if (!declared_only(ctor, ctor.name)) {
            sema.full_body(ctor);
        }
        var desc = structs.try_get(st.name);
        long struct_size = desc.is_value() ? desc.value().size as long : 0;
        if (ctor.body.is_value()) {
            var items = ctor.body.value().items;
            for (var index in 0..items.count) {
                if (items[index] is Declaration(declaration)) {
                    if (declaration is Variable(var_def)) {
                        _patch_allocation(var_def, struct_size);
                    }
                }
            }
        }
        return ctor;
    }

    # Gives a constructor's `__alloc_size`, and the `this =
    # _pep_malloc(size)` allocation, the struct's size as a literal, so
    # `call_function_result` sees a constant size.
    _patch_allocation(var_def: VariableDef, struct_size: long) {
        if (var_def.name == "__alloc_size") {
            var_def.default = Optional<Expression>.Value(Expression.IntLiteral(struct_size));
            return;
        }
        if (var_def.name != "this" or !var_def.default.is_value()) {
            return;
        }
        if (var_def.default.value() is FunctionCall(call)) {
            if (call.function == "_pep_malloc") {
                call.args = [Expression.IntLiteral(struct_size)];
            }
        }
    }

    ## Declares the constructors, so call sites can bind them.
    instantiate_ctor(st: StructDef): Result<void> {
        if (is_abstract(st)) {
            return Result<void>.ok();
        }
        for (var ctor in patched_ctors(st)) {
            instantiate_function(ctor)?;
        }
        return Result<void>.ok();
    }

    # Struct and function codegen

    codegen_struct(st: StructDef): Result<void> {
        var result = codegen_struct_unlocated(st);
        locate(result, st.loc);
        return result;
    }

    codegen_struct_unlocated(st: StructDef): Result<void> {
        if (is_abstract(st)) {
            return Result<void>.ok();
        }
        debug_struct_loc = st.loc;
        var result = codegen_struct_members(st);
        debug_struct_loc = Loc.none();
        return result;
    }

    codegen_struct_members(st: StructDef): Result<void> {
        for (var ctor in patched_ctors(st)) {
            codegen_function(ctor)?;
        }
        for (var method in st.method_members) {
            var name = $"{st.name}.{method.name}";
            # One declared only needs no renamed copy of its body.
            if (declared_only(method, name)) {
                declare_external(name);
                continue;
            }
            # Most held back are never called: renamed only when generated.
            if (waits(name)) {
                hold(method, name);
                continue;
            }
            var m = method.copy();
            m.name = name;
            codegen_function(m)?;
        }
        return Result<void>.ok();
    }

    ## Whether `function`, named `name`, is declared only: its unit's
    ## object defines it, or the object of the compilation unit that made it.
    declared_only(function: FunctionDef, name: String): bool {
        if (!function.body.is_value() and stripped.contains(function.loc)) {
            return true;
        }
        if (declared.is_value()) {
            return declared.value().contains(name);
        }
        return is_cached(name);
    }

    ## Declares `name`, a function another object defines. It keeps an
    ## owner, the declaring file's or `DECLARED_ONLY` for an instantiation,
    ## so `prepare` gives the declaration the linker spelling the definition
    ## has (`link.symbol_name`).
    declare_external(name: String) {
        var declared = functions.try_get(name);
        if (declared.is_value()) {
            declared.value().set_linkage(llvm.Linkage.External);
        }
        if (!owners.contains(name)) {
            owners[name] = DECLARED_ONLY;
        }
    }

    codegen_function(function: FunctionDef): Result<void> {
        if (declared_only(function, function.name)) {
            declare_external(function.name);
            return Result<void>.ok();
        }
        if (waits(function.name)) {
            hold(function, function.name);
            return Result<void>.ok();
        }
        # `[Unsafe("...")]` turns checks off in this body only.
        var build_checks = runtime_checks;
        runtime_checks = build_checks.both(function_checks(function.attributes));
        var outer_reads = this_may_be_null;
        this_may_be_null = ast.has_attribute(function.attributes, sema.READS_ATTRIBUTE);
        var outer_finals = final_reads;
        final_reads = HashSet<SymbolRefExpression>();
        # A body a checked unit's record held undecoded is decoded only now,
        # when it is generated.
        sema.full_body(function);
        begin_debug_function(function);
        # The prologue (parameter slots, the parameters' acquires) is left
        # unstamped, as clang leaves it (`DebugInfo.finish` puts its calls on
        # line 0): a debugger ends the prologue at the first instruction with
        # a line, the first statement's, after the parameters are stored.
        var result = codegen_function_unlocated(function);
        if (debug.is_value()) {
            debug.value().end_function();
        }
        final_reads = outer_finals;
        this_may_be_null = outer_reads;
        runtime_checks = build_checks;
        locate(result, function.loc);
        return result;
    }

    ## Gives `function` its subprogram, when debug info is on: named as
    ## written, a closure's body for where it is written (`closure at
    ## main.pep:12`), as debuggers and profilers show it; a member with no
    ## location of its own (a synthesized one) artificial, at its struct.
    begin_debug_function(function: FunctionDef) {
        var fn_value = functions.try_get(function.name);
        if (!debug.is_value() or !fn_value.is_value()) {
            return;
        }
        var info = debug.value();
        var declared = function.loc.is_none() ? debug_struct_loc : function.loc;
        bool closure = function.parent.is_value()
            and sema.is_closure_struct(function.parent.value())
            and function.name.ends_with(sema.CALL_METHOD);
        var name = sema.display_name(function.name);
        if (closure) {
            var named = info.closure_name(declared);
            if (named.is_value()) {
                name = named.value();
            }
        }
        info.begin_function(fn_value.value(), name, declared, function.loc.is_none());
    }

    ## Holds `function` back until something calls it, to be generated as
    ## `name`.
    hold(function: FunctionDef, name: String) {
        waiting.append(waiting_functions.count);
        waiting_functions.append(function);
        waiting_names.append(name);
        waiting_values.append(functions[name]);
    }

    ## Whether the body of function `name` waits until something calls it:
    ## an unowned one (a generic's instantiation, a synthesized member) that
    ## nothing calls yet, since every part that does not call it drops it.
    waits(name: String): bool {
        if (owners.contains(name) or name == "main") {
            return false;
        }
        var declared = functions.try_get(name);
        return declared.is_value() and !declared.value().has_uses();
    }

    ## Generates the bodies `waits` held back that something now calls,
    ## until no new one is called; the rest stay declarations.
    codegen_called(): Result<void> {
        # Each round passes places in `waiting_functions`, not the
        # functions, so holding one back again costs no count step.
        var progress = true;
        while (progress) {
            progress = false;
            var held = waiting;
            waiting = Array<ulong>();
            for (var at in held) {
                if (!waiting_values[at].has_uses()) {
                    waiting.append(at);
                    continue;
                }
                var function = waiting_functions[at];
                if (function.name != waiting_names[at]) {
                    function = function.copy();
                    function.name = waiting_names[at];
                }
                codegen_function(function)?;
                progress = true;
            }
        }
        for (var at in waiting) {
            waiting_values[at].set_linkage(llvm.Linkage.External);
        }
        waiting = Array<ulong>();
        waiting_functions = Array<FunctionDef>();
        waiting_names = Array<String>();
        waiting_values = Array<llvm.Value>();
        return Result<void>.ok();
    }

    ## Whether the object of the unit owning function `name` comes from the
    ## build cache. Not `main`: the entry part, compiled every build,
    ## defines it.
    is_cached(name: String): bool {
        if (cached_files.is_empty or name == "main") {
            return false;
        }
        var file = owners.try_get(name);
        return file.is_value() and cached_files.contains(file.value());
    }

    codegen_function_unlocated(function: FunctionDef): Result<void> {
        var found = functions.try_get(function.name);
        if (!found.is_value()) {
            return Result<void>.ok();
        }
        var fn_value = found.value();
        var entry = context.append_block(fn_value, "entry");
        builder.position_at_end(entry);
        # A build without `-O` prints a backtrace on panic: `main` tells the
        # runtime so before anything can panic.
        if (function.name == "main" and opt_level == 0 and functions.contains("_pep_set_backtrace_default")) {
            call_function("_pep_set_backtrace_default", Array<llvm.Value>())?;
        }
        # A stack overflow reports itself instead of ending the program
        # silently (runtime/stack_guard.pep).
        if (function.name == "main" and functions.contains("_pep_stack_guard_start")) {
            call_function("_pep_stack_guard_start", Array<llvm.Value>())?;
        }
        # The entry block holds the return slot, so it dominates every store;
        # the return block loads it.
        var ret_ty = types.get(function.ty.to_string());
        var retval = Optional<llvm.Value>.Empty;
        llvm.Type llvm_ret_ty = context.int32_type();
        if (!is_void(function.ty)) {
            if (!ret_ty.is_value()) {
                return fail<void>($"unknown return type {function.ty.to_string()}");
            }
            llvm_ret_ty = slot_type(context, ret_ty.value());
            var slot = builder.alloca(llvm_ret_ty, "retval");
            # Zero so a function without an explicit return returns 0.
            builder.store(llvm_ret_ty.zero(), slot);
            retval = Optional<llvm.Value>.Value(slot);
        }
        var return_block = context.append_block(fn_value, "return");
        builder.position_at_end(return_block);
        if (is_void(function.ty)) {
            builder.return_void();
        } else {
            builder.return_value(builder.load(llvm_ret_ty, retval.value(), "retval"));
        }
        # The body: parameters first, so they dominate every use.
        builder.position_at_end(entry);
        frame.function = Optional<llvm.Value>.Value(fn_value);
        frame.return_block = Optional<llvm.BasicBlock>.Value(return_block);
        frame.retval = retval;
        frame.retval_type = function.ty.to_string();
        frame.locals = Array<(String, Address)>();
        frame.exited = false;
        frame.loop_base_depth = Optional<ulong>.Empty;
        copied_params = HashSet<String>();
        scopes = Array<Array<ScopeSlot>>();
        scopes.append(Array<ScopeSlot>());
        deferred_temps.clear();

        var declared_params = Array<(String, String)>();
        for (var p in function.parameters) {
            declared_params.append((p.name, p.ty.to_string()));
        }
        # A method (mangled `Struct.name`) has an injected `this` first; a
        # static method has none.
        var dot = function.name.find(".");
        bool is_static_method = false;
        if (dot >= 0) {
            var struct_name = function.name.substr_bytes(0, dot as ulong);
            var desc = structs.try_get(struct_name);
            if (desc.is_value()) {
                var rest = function.name.substr_bytes(dot as ulong + 1, function.name.size - dot as ulong - 1);
                var second_dot = rest.find(".");
                var method_name = second_dot < 0 ? rest : rest.substr_bytes(0, second_dot as ulong);
                is_static_method = desc.value().static_methods.contains(method_name);
            }
            if (!is_static_method) {
                declared_params.insert(0, ("this", struct_name));
            }
        }
        var param_slots = Array<(String, llvm.Value, llvm.Value, String, llvm.Type)>();
        for (var index in 0..declared_params.count) {
            var (name, ty_string) = declared_params[index];
            var arg = fn_value.param(index as uint);
            # The slot's type is the LLVM parameter's (struct parameters were
            # lowered to pointers).
            var ty = arg.value_type();
            var slot = builder.alloca(ty, name);
            param_slots.append((name, slot, arg, ty_string, ty));
        }
        for (var number in 0..param_slots.count) {
            var (name, slot, arg, ty_name, ty) = param_slots[number];
            builder.store(arg, slot);
            var declared = function.loc;
            for (var p in function.parameters) {
                if (p.name == name) {
                    declared = p.loc;
                }
            }
            debug_declare(slot, name, ty_name, declared, number as uint + 1);
            frame.push_local(name, Address.typed(name, ty_name, ty, slot));
            # A struct parameter's copy arrives acquired and the function's
            # scope owns it, unless it is `[Move]`d in or the caller made the
            # copy.
            var index = -1;
            for (var i in 0..function.parameters.count) {
                if (function.parameters[i].name == name) {
                    index = i as long;
                    break;
                }
            }
            bool copied = name != "this" and index >= 0 and copied_param(function.name, index as ulong);
            if (copied) {
                copied_params.insert(name);
            } else if (name != "this" and is_reference_name(ty_name)) {
                bool sending = false;
                for (var p in function.parameters) {
                    if (p.name == name and sema.takes_over(p.attributes)) {
                        sending = true;
                    }
                }
                if (!sending) {
                    acquire_ref(ty_name, arg)?;
                }
                track_scope_local(name, ty_name, slot);
            }
        }
        var body = function.body.is_value() ? function.body.value() : sema.Block();
        # The `SymbolRef` nodes of this body, which codegen reads.
        final_reads = final_reads_of(function, body);
        codegen_block(body)?;
        # The function's end: release every tracked slot on the fall-through
        # path.
        var current = builder.insert_block();
        if (!current.is_null() and current.terminator().is_null()) {
            var all = scopes;
            var index = all.count;
            while (index > 0) {
                index -= 1;
                release_scope(all[index])?;
            }
        }
        # Every block left without a terminator branches to the return block,
        # which keeps the module verifiable.
        for (var block in fn_value.blocks()) {
            if (block.terminator().is_null()) {
                builder.position_at_end(block);
                builder.branch(return_block);
            }
        }
        return Result<void>.ok();
    }

    # Blocks and statements

    codegen_block(block: Block): Result<void> {
        for (var statement in block.items) {
            codegen_statement(statement)?;
        }
        return Result<void>.ok();
    }

    ## A block nested in a function: its own lexical scope for the debugger.
    codegen_scoped_block(block: Block): Result<void> {
        bool in_pass = false;
        if (debug.is_value()) {
            var info = debug.value();
            # A pass of a `static` block: its places in the expanded source
            # apply from its scope on.
            if (block.items.count > 0) {
                if (block.items[0] is StaticPass(pass)) {
                    in_pass = info.push_static(pass.loc, pass.header, pass.lines);
                }
            }
            var first = Loc.none();
            for (var statement in block.items) {
                var at = statement_loc(statement);
                if (!at.is_none()) {
                    first = at;
                    break;
                }
            }
            info.push_block(first);
        }
        var result = codegen_block(block);
        if (debug.is_value()) {
            debug.value().pop_block();
            if (in_pass) {
                debug.value().pop_static();
            }
        }
        return result;
    }

    ## Declares a variable for the debugger (see `DebugInfo.declare`), when
    ## debug info is on and describes its type: parameter number `argument`
    ## (from 1), or 0 for a local. Compiler-made locals (`__iterator`) are
    ## left out.
    debug_declare(storage: llvm.Value, name: String, ty: String, loc: Loc, argument: uint) {
        if (!debug.is_value() or (name.starts_with("__") and argument == 0)) {
            return;
        }
        var debug_ty = debug_type(ty);
        if (debug_ty.is_value()) {
            debug.value().declare(storage, name, debug_ty.value(), loc, argument, builder.insert_block());
        }
    }

    ## A nested `{ ... }` gets its own basic block, so a `return` inside it
    ## ends only the block's path.
    codegen_nested_block(inner: Block): Result<void> {
        var fn_value = frame.function.value();
        var return_block = frame.return_block.value();
        var region_start = fn_value.block_count();
        var entry = context.append_block(fn_value, "block");
        builder.branch(entry);
        builder.position_at_end(entry);
        frame.exited = false;
        scopes.append(Array<ScopeSlot>());
        var locals = frame.locals.count;
        codegen_scoped_block(inner)?;
        frame.locals.truncate(locals);
        var current = builder.insert_block();
        if (!frame.exited) {
            var scope = scopes.pop();
            release_scope(scope)?;
            var cont = insert_block_after(current, "blockcont");
            builder.branch(cont);
            builder.position_at_end(cont);
        } else {
            scopes.pop();
            var blocks = fn_value.blocks();
            for (var index in (region_start as ulong)..blocks.count) {
                if (blocks[index].terminator().is_null()) {
                    builder.position_at_end(blocks[index]);
                    builder.branch(return_block);
                }
            }
            var dead = context.append_block(fn_value, "blockdead");
            builder.position_at_end(dead);
        }
        return Result<void>.ok();
    }

    ## A new block named `name` just after `block`.
    insert_block_after(block: llvm.BasicBlock, name: String): llvm.BasicBlock {
        var next = block.next();
        if (next.is_null()) {
            return context.append_block(block.parent(), name);
        }
        return context.insert_block(next, name);
    }

    ## Generates a statement, stamping what it emits, including the
    ## releases after it, with its location (see `enter_location`).
    codegen_statement(statement: Statement): Result<void> {
        var saved = enter_location(statement_loc(statement));
        var result = codegen_statement_unlocated(statement);
        leave_location(saved);
        return result;
    }

    codegen_statement_unlocated(statement: Statement): Result<void> {
        # Dead code after a `return`, `break` or `continue` in this region.
        if (frame.exited) {
            return Result<void>.ok();
        }
        match (statement) {
            Expression(expr) => {
                var temp_ty = owned_temp_type(expr);
                var value = codegen_expr(expr)?;
                # A discarded owned rvalue is released at the end of the full
                # expression.
                if (temp_ty.is_value()) {
                    release_temp(temp_ty.value(), value)?;
                }
                flush_deferred_temps()?;
            }
            Block(inner) => {
                codegen_nested_block(inner)?;
            }
            Declaration(declaration) => {
                if (declaration is Variable(var_def)) {
                    codegen_var_def(var_def)?;
                }
            }
            Branch(branch) => {
                codegen_branch(branch)?;
            }
            While(wh) => {
                codegen_while(wh)?;
            }
            LoopBreak(lb) => {
                codegen_loop_break(lb)?;
            }
            Static(_) => {
                return fail<void>("internal error: unexpanded 'static' block");
            }
            StaticPass(pass) => {
                codegen_static_pass(pass)?;
            }
            Return(ret) => {
                codegen_return(ret)?;
            }
        }
        return Result<void>.ok();
    }

    codegen_return(ret: sema.ReturnStatement): Result<void> {
        if (!frame.return_block.is_value()) {
            return fail<void>("return outside function");
        }
        var return_block = frame.return_block.value();
        var value = Optional<llvm.Value>.Empty;
        String value_name = "";
        if (ret.expr.is_value()) {
            var expr = ret.expr.value();
            # Returning a local moves it out, so an empty `[__Lazy]` one has
            # no other name to share it with and stays null.
            bool returns_local = false;
            if (expr is SymbolRef(node)) {
                returns_local = frame.find_local(node.id).is_value();
            }
            keep_lazy = returns_local;
            var v = codegen_expr(expr)?;
            value_name = numeric_source_name(expr, v);
            # Returning a read of a struct reference copies it: acquire before
            # this function's slots are released. Call results move.
            if (is_lvalue_read(expr)) {
                var ty = value_sema_type(expr);
                if (ty.is_value() and !ty.value().is_empty) {
                    acquire_copy(ty.value(), v, expr)?;
                }
            }
            value = Optional<llvm.Value>.Value(v);
        }
        flush_deferred_temps()?;
        # An early exit releases every tracked slot in every scope.
        release_all_scopes()?;
        if (value.is_value() and frame.retval.is_value()) {
            var retval_ty = frame.retval_type;
            # The source's sema name carries its signedness.
            var coerced = coerce(value.value(), value_name, retval_ty);
            var slot_ty = types.get(retval_ty);
            if (slot_ty.is_value()) {
                check_store_type(slot_type(context, slot_ty.value()), coerced, "return value", retval_ty)?;
            }
            builder.store(coerced, frame.retval.value());
        }
        builder.branch(return_block);
        frame.exited = true;
        return Result<void>.ok();
    }

    ## A local's stack slot, in the entry block, so a `var` declared inside a
    ## loop reuses one slot.
    entry_alloca(ty: llvm.Type, name: String): llvm.Value {
        var block = builder.insert_block();
        var entry = block.parent().first_block();
        var saved = block;
        var first = entry.first_instruction();
        if (first.is_null()) {
            builder.position_at_end(entry);
        } else {
            builder.position_before(first);
        }
        var slot = builder.alloca(ty, name);
        builder.position_at_end(saved);
        keep_location();
        return slot;
    }

    codegen_var_def(var_def: VariableDef): Result<void> {
        var saved = enter_location(var_def.loc);
        var result = codegen_var_def_unlocated(var_def);
        leave_location(saved);
        locate(result, var_def.loc);
        return result;
    }

    codegen_var_def_unlocated(var_def: VariableDef): Result<void> {
        # A `for` loop's hidden iterator: the concrete source
        # (`source.iterate()` or `source` itself).
        var for_source = Optional<Expression>.Empty;
        if (var_def.default.is_value()) {
            if (var_def.default.value() is ForIterator(found)) {
                for_source = Optional<Expression>.Value(found);
            }
        }
        if (for_source.is_value()) {
            var source = for_source.value();
            var lowered = var_def.copy();
            var iterator = for_loop_iterator(source)?;
            # A stored value iterator is driven in place, not through a copy.
            var source_type_found = struct_name_of(source);
            var source_type = source_type_found.is_value() ? source_type_found.value() : "";
            bool drives_source = true;
            if (iterator is MethodCall(call)) {
                drives_source = call.method != "iterate";
            }
            if (drives_source and values.contains(source_type) and is_value_place(source)) {
                var place = codegen_lvalue(source)?;
                var ty = reference_value_type(source_type);
                frame.push_local(var_def.name, Address.typed(var_def.name, source_type, ty, place.ptr));
                return Result<void>.ok();
            }
            if (lowered.ty.to_string() == sema.AUTO) {
                var ty = value_sema_type(iterator);
                if (ty.is_value()) {
                    lowered.ty = TypeName.named(ty.value());
                }
            }
            lowered.default = Optional<Expression>.Value(iterator);
            return codegen_var_def(lowered);
        }
        var ty_name = var_def.ty.to_string();
        bool is_struct_ref = is_reference_name(ty_name);
        llvm.Type ty;
        if (is_struct_ref) {
            ty = reference_value_type(ty_name);
        } else {
            var found = types.get(ty_name);
            if (!found.is_value()) {
                var error = $"unknown type name '{ty_name}'";
                # Point at the written type rather than the name.
                if (!var_def.type_loc.is_none()) {
                    error_loc = Optional<(String, Loc)>.Value((error, var_def.type_loc));
                } else {
                    error_loc = Optional<(String, Loc)>.Empty;
                }
                return fail<void>(error);
            }
            ty = found.value();
        }
        var slot = entry_alloca(ty, var_def.name);
        if (!var_def.hidden) {
            debug_declare(slot, var_def.name, ty_name, var_def.loc, 0);
        }
        if (var_def.default.is_value()) {
            var default = var_def.default.value();
            keep_lazy = is_final_read(default);
            var value = codegen_expr(default)?;
            # Copying a struct reference into a fresh slot acquires; call
            # results carry their own reference. A destructuring binding moves
            # its element out of the hidden tuple.
            var moved = is_struct_ref ? destructured_element(default) : Optional<(String, uint)>.Empty;
            if (moved.is_value()) {
                var (tuple, index) = moved.value();
                var held_at = frame.find_local(tuple);
                if (!held_at.is_value()) {
                    return fail<void>("unknown tuple");
                }
                var tuple_ty = held_at.value().llvm_ty;
                if (!tuple_ty.is_value() or tuple_ty.value().kind() != llvm.TypeKind.Struct) {
                    return fail<void>("destructured value is not a tuple");
                }
                var st = tuple_ty.value();
                var held = builder.load(st, held_at.value().ptr, "tuple");
                var zero = st.field(index).zero();
                var cleared = builder.insert_value(held, zero, index, "moved");
                builder.store(cleared, held_at.value().ptr);
            } else if (is_struct_ref and is_lvalue_read(default)) {
                acquire_copy(ty_name, value, default)?;
            }
            # A numeric value converts to the variable's type, with C's rules
            # from the source's sema type.
            var kind = value.value_type().kind();
            bool numeric_value = kind == llvm.TypeKind.Integer
                or kind == llvm.TypeKind.Float
                or kind == llvm.TypeKind.Double;
            if (numeric_value and sema.is_numeric_type(state, ty_name) and !value.value_type().same(ty)) {
                var source = numeric_source_name(default, value);
                value = coerce(value, source, ty_name);
            }
            value = fit_to_slot(value, ty, var_def.name)?;
            check_store_type(ty, value, var_def.name, ty_name)?;
            builder.store(value, slot);
            flush_deferred_temps()?;
        } else {
            # No default: zero, so loads are defined.
            builder.store(ty.zero(), slot);
        }
        frame.push_local(var_def.name, Address.typed(var_def.name, ty_name, ty, slot));
        # The scope owns the slot until it exits.
        if (is_struct_ref) {
            track_scope_local(var_def.name, ty_name, slot);
        }
        return Result<void>.ok();
    }

    ## `value` at the width of a slot of type `ty`, named for local `name`:
    ## a narrower integer extends (a 1-bit one with zeros), a wider one
    ## truncates (to a bool by a nonzero test), and a float converts.
    fit_to_slot(value: llvm.Value, ty: llvm.Type, name: String): Result<llvm.Value> {
        var value_ty = value.value_type();
        var kind = value_ty.kind();
        if (kind == llvm.TypeKind.Integer and ty.kind() == llvm.TypeKind.Integer) {
            var from = value_ty.int_width();
            var to = ty.int_width();
            if (from < to) {
                if (from == 1) {
                    return Result<llvm.Value>.ok(builder.zero_extend(value, ty, $"{name}w"));
                }
                return Result<llvm.Value>.ok(builder.sign_extend(value, ty, $"{name}w"));
            }
            if (from > to) {
                if (to == 1) {
                    return Result<llvm.Value>.ok(as_bool(value));
                }
                return Result<llvm.Value>.ok(builder.truncate(value, ty, $"{name}t"));
            }
            return Result<llvm.Value>.ok(value);
        }
        if ((kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double)
            and (ty.kind() == llvm.TypeKind.Float or ty.kind() == llvm.TypeKind.Double)
            and !value_ty.same(ty)) {
            if (kind == llvm.TypeKind.Float) {
                return Result<llvm.Value>.ok(builder.float_extend(value, ty, $"{name}f"));
            }
            return Result<llvm.Value>.ok(builder.float_truncate(value, ty, $"{name}f"));
        }
        return Result<llvm.Value>.ok(value);
    }

    ## The iterator a `for` loop drives over `source`: `source.iterate()`
    ## when its type declares `iterate()`, else `source` itself when it
    ## declares `next()` and `current()`.
    for_loop_iterator(source: Expression): Result<Expression> {
        var found = struct_name_of(source);
        var ty = found.is_value() ? found.value() : "<unknown>";
        if (declares_member(ty, "iterate")) {
            return Result<Expression>.ok(
                Expression.MethodCall(
                    sema.MethodCallExpression(source, "iterate", Array<Expression>(), sema.expression_loc(source))
                )
            );
        }
        if (declares_member(ty, "next") and declares_member(ty, "current")) {
            return Result<Expression>.ok(source);
        }
        return fail<Expression>(
            $"type '{ty}' is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())"
        );
    }

    ## Whether struct or trait `ty` declares method `member`.
    declares_member(ty: String, member: String): bool {
        var desc = structs.try_get(ty);
        if (desc.is_value() and desc.value().methods.contains(member)) {
            return true;
        }
        var t = traits.try_get(ty);
        if (t.is_value()) {
            for (var m in t.value().methods) {
                var (name, _, _) = m;
                if (name == member) {
                    return true;
                }
            }
        }
        return false;
    }

    # Branches and loops

    ## `[Likely]` or `[Unlikely]` above an `if` or on its else block: the
    ## branch weights clang gives `__builtin_expect`.
    weigh_branch(instruction: llvm.Value, branch: Branch) {
        var hint = branch_hint(branch.if_block.attributes);
        bool then_likely;
        if (hint.is_value()) {
            then_likely = hint.value();
        } else {
            if (!branch.else_block.is_value()) {
                return;
            }
            var else_hint = branch_hint(branch.else_block.value().attributes);
            if (!else_hint.is_value()) {
                return;
            }
            then_likely = !else_hint.value();
        }
        var i32 = context.int32_type();
        long taken = then_likely ? 2000 : 1;
        long not_taken = then_likely ? 1 : 2000;
        var weights = context.metadata_node(
            [
                context.metadata_string("branch_weights"),
                context.constant_metadata(i32.const_int(taken)),
                context.constant_metadata(i32.const_int(not_taken))
            ]
        );
        instruction.set_metadata(context.metadata_kind("prof"), context.metadata_value(weights));
    }

    codegen_branch(branch: Branch): Result<void> {
        var fn_value = frame.function.value();
        var then_block = context.append_block(fn_value, "then");
        var else_block = Optional<llvm.BasicBlock>.Empty;
        if (branch.else_block.is_value()) {
            else_block = Optional<llvm.BasicBlock>.Value(context.append_block(fn_value, "else"));
        }
        var merge_block = context.append_block(fn_value, "ifcont");
        var cond_temp = owned_temp_type(branch.condition);
        var cond = codegen_expr(branch.condition)?;
        if (cond_temp.is_value()) {
            release_temp(cond_temp.value(), cond)?;
        }
        var cond_bool = as_bool(cond);
        flush_deferred_temps()?;
        var instruction = builder.conditional_branch(
            cond_bool, then_block, else_block.is_value() ? else_block.value() : merge_block
        );
        weigh_branch(instruction, branch);
        # The then-arm is its own scope, released at its fall-through tail.
        scopes.append(Array<ScopeSlot>());
        frame.exited = false;
        builder.position_at_end(then_block);
        var locals = frame.locals.count;
        codegen_scoped_block(branch.if_block)?;
        frame.locals.truncate(locals);
        var then_end = builder.insert_block();
        var scope = scopes.pop();
        if (then_end.terminator().is_null()) {
            release_scope(scope)?;
            builder.branch(merge_block);
        }
        if (else_block.is_value()) {
            scopes.append(Array<ScopeSlot>());
            frame.exited = false;
            builder.position_at_end(else_block.value());
            codegen_scoped_block(branch.else_block.value())?;
            frame.locals.truncate(locals);
            var else_end = builder.insert_block();
            var else_scope = scopes.pop();
            if (else_end.terminator().is_null()) {
                release_scope(else_scope)?;
                builder.branch(merge_block);
            }
        }
        builder.position_at_end(merge_block);
        frame.exited = false;
        return Result<void>.ok();
    }

    ## The condition of a loop or branch as an `i1`, its temporaries
    ## released.
    loop_condition(condition: Expression): Result<llvm.Value> {
        var cond_temp = owned_temp_type(condition);
        var cond = codegen_expr(condition)?;
        if (cond_temp.is_value()) {
            release_temp(cond_temp.value(), cond)?;
        }
        var cond_bool = as_bool(cond);
        flush_deferred_temps()?;
        return Result<llvm.Value>.ok(cond_bool);
    }

    codegen_while(wh: While): Result<void> {
        var fn_value = frame.function.value();
        var cond_block = context.append_block(fn_value, "whilecond");
        var body_block = context.append_block(fn_value, "while");
        var merge_block = context.append_block(fn_value, "whilecont");
        var cond_bool = loop_condition(wh.condition)?;
        builder.conditional_branch(cond_bool, body_block, merge_block);
        # `continue` re-checks the condition; `break` exits to the merge.
        var saved = frame.loop_break;
        var saved_base = frame.loop_base_depth;
        frame.loop_break = Optional<(llvm.BasicBlock, llvm.BasicBlock)>.Value((cond_block, merge_block));
        # The body is its own scope, made again on every iteration.
        builder.position_at_end(body_block);
        scopes.append(Array<ScopeSlot>());
        frame.loop_base_depth = Optional<ulong>.Value(scopes.count - 1);
        frame.exited = false;
        var locals = frame.locals.count;
        codegen_scoped_block(wh.block)?;
        frame.locals.truncate(locals);
        var body_scope = scopes.pop();
        var body_end = builder.insert_block();
        if (body_end.terminator().is_null()) {
            if (body_scope.count > 0) {
                release_scope(body_scope)?;
            }
            builder.branch(cond_block);
        }
        frame.loop_break = saved;
        frame.loop_base_depth = saved_base;
        builder.position_at_end(cond_block);
        var again = loop_condition(wh.condition)?;
        builder.conditional_branch(again, body_block, merge_block);
        builder.position_at_end(merge_block);
        frame.exited = false;
        return Result<void>.ok();
    }

    codegen_loop_break(lb: LoopBreak): Result<void> {
        if (!frame.loop_break.is_value() or !frame.loop_base_depth.is_value()) {
            return fail<void>("break/continue outside a loop");
        }
        var (cont, brk) = frame.loop_break.value();
        # Leaving the iteration releases the scopes the jump leaves behind.
        var base = frame.loop_base_depth.value();
        var depth = scopes.count;
        var start = base < depth - 1 ? base : depth - 1;
        var all = scopes;
        var index = depth;
        while (index > start) {
            index -= 1;
            release_scope(all[index])?;
        }
        var target = lb.kind == LoopBreakKind.Continue ? cont : brk;
        frame.exited = true;
        builder.branch(target);
        return Result<void>.ok();
    }
}

## Where a statement is, for debug locations: its expression, returned
## value, condition or declared name; none for a block or a `break`.
statement_loc(statement: Statement): Loc {
    match (statement) {
        Expression(expr) => {
            return sema.expression_loc(expr);
        }
        Return(ret) => {
            return ret.loc;
        }
        Branch(branch) => {
            return sema.expression_loc(branch.condition);
        }
        While(wh) => {
            return sema.expression_loc(wh.condition);
        }
        Declaration(declaration) => {
            if (declaration is Variable(var_def)) {
                return var_def.loc;
            }
            return Loc.none();
        }
        Static(block) => {
            return block.loc;
        }
        StaticPass(pass) => {
            return pass.loc;
        }
        else => {
            return Loc.none();
        }
    }
}

## The branch hint `[Likely]` (true) or `[Unlikely]` (false) among
## `attributes`.
branch_hint(attributes: ast.Attribute[]): bool? {
    if (ast.has_attribute(attributes, "Likely")) {
        return Optional<bool>.Value(true);
    }
    if (ast.has_attribute(attributes, "Unlikely")) {
        return Optional<bool>.Value(false);
    }
    return Optional<bool>.Empty;
}

## The LLVM module for a checked model: `CodeGenerator` in
## `crates/pepper-codegen/src/lib.rs`, in Pepper. The generator declares
## every struct, method, extern and function first (the instantiation
## pass), then emits the globals and every body (the codegen pass), in the
## order the Rust generator does, so the two print the same IR.

import compiler.ast;
import [Diagnostic] from compiler.diagnostic;
import compiler.link;
import llvm;
import compiler.sema;
import [
    DefaultArgumentExpression, error_at, Expression, FunctionDef, Loc, Module, PassState, set_name, StructDef, TypeName
] from compiler.sema;
import [Address, Frame] from "address";
import "address";
import "calls";
import [RuntimeChecks] from "checks";
import "checks";
import "expressions";
import "functions";
import [annotate_facts, stamp_cpu] from "globals";
import "globals";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import [Types, is_object] from "types";
import "types";

## Field index of `__invoke` in a function object: after the
## `__refcount`/`__weakcount` head.
const FUNCTION_INVOKE_INDEX: uint = 2;

## The name of a head count's address (`head_count_ptr`), by which TBAA
## tells it from other byte addresses.
const HEAD_COUNT_NAME = "head_count";

## Vtable slots before the trait's own methods.
const VTABLE_RELEASE: ulong = 0;
const VTABLE_ACQUIRE: ulong = 1;
const VTABLE_METHODS: ulong = 2;

## The separator in a file's private names (`pepper_parser::namespace`).
const NAMESPACE_SEPARATOR = "@";

## One struct the generator laid out: its LLVM type, size and methods.
export struct StructDesc {
    var name: String;
    var llvm_type: llvm.Type;
    var size: ulong = 0;
    ## Real method name to mangled function name (`__dtor` to `Test.__dtor`).
    var methods: HashMap<String, String> = HashMap<String, String>();
    ## The real names of static methods (no `this` parameter).
    var static_methods: HashSet<String> = HashSet<String>();
    ## Field name and sema type, in order.
    var fields: Array<(String, String)> = Array<(String, String)>();
    var loc: Loc;
    var field_locs: Loc[] = Array<Loc>();
    ## Method name to return sema type.
    var method_returns: HashMap<String, String> = HashMap<String, String>();
    ## Method name to parameter sema types.
    var method_params: HashMap<String, String[]> = HashMap<String, String[]>();
    ## Whether codegen steps the reference count inline, and whether
    ## atomically: none for a struct whose `__acquire`/`__release` are not
    ## the standard ones.
    var inline_counts: bool? = Optional<bool>.Empty;

    construct(name: String, llvm_type: llvm.Type, loc: Loc) {
        this.name = name;
        this.llvm_type = llvm_type;
        this.loc = loc;
    }
}

## A trait used as a type: its dispatchable methods in vtable order, after
## the two count slots, as `(name, parameter sema types, return sema type)`.
export struct TraitDesc {
    var methods: Array<(String, String[], String)> = Array<(String, String[], String)>();

    construct() {}
}

## A struct reference alive in a scope: `(name, sema type, slot)`.
export struct ScopeSlot {
    var name: String;
    var ty: String;
    var slot: llvm.Value;

    construct(name: String, ty: String, slot: llvm.Value) {
        this.name = name;
        this.ty = ty;
        this.slot = slot;
    }
}

## An owned temporary waiting for the end of its full expression.
export struct Temporary {
    var value: llvm.Value;
    var ty: String;

    construct(value: llvm.Value, ty: String) {
        this.value = value;
        this.ty = ty;
    }
}

## The generator of one LLVM module.
export struct Generator {
    var context: llvm.Context;
    ## The LLVM module being generated.
    var ir: llvm.Module;
    var builder: llvm.Builder;
    var machine: llvm.TargetMachine;
    ## The passes' state: the enums and value structs they found.
    var state: PassState;
    var types: Types;
    var structs: HashMap<String, StructDesc> = HashMap<String, StructDesc>();
    ## Traits used as types, by type name.
    var traits: HashMap<String, TraitDesc> = HashMap<String, TraitDesc>();
    ## Weak trait values (`__weak<Shape>`), laid out like a trait value.
    var weak_traits: HashSet<String> = HashSet<String>();
    ## Tuple types by name: each element's sema type.
    var tuples: HashMap<String, String[]> = HashMap<String, String[]>();
    ## Tuple type names in registration order.
    var tuple_order: String[] = Array<String>();
    ## Value structs (`[Value]`) by name: their field types in order.
    var values: HashMap<String, String[]> = HashMap<String, String[]>();
    ## The program's own `hash<T>` overrides, by name.
    var hash_overrides: HashSet<String> = HashSet<String>();
    ## Each struct's `==` taking its own type, by struct name.
    var equality_methods: HashMap<String, String> = HashMap<String, String>();
    ## Function name (methods as `Struct.name`) to its LLVM function.
    var functions: HashMap<String, llvm.Value> = HashMap<String, llvm.Value>();
    ## Free function name to its return sema type.
    var fn_returns: HashMap<String, String> = HashMap<String, String>();
    ## Each callable's parameters' default arguments, in order.
    var param_defaults: HashMap<String, Array<Expression?>> = HashMap<String, Array<Expression?>>();
    ## Each free function's declared parameter types and location.
    var fn_signatures: HashMap<String, (String[], Loc)> = HashMap<String, (String[], Loc)>();
    ## The sema type of each LLVM parameter of every declared function (`""`
    ## for a method's `this`).
    var fn_param_types: HashMap<String, String[]> = HashMap<String, String[]>();
    ## Per function, which parameters are `[Move]`.
    var sending_params: HashMap<String, bool[]> = HashMap<String, bool[]>();
    ## Identical string literals share one global constant.
    var global_strings: HashMap<String, llvm.Value> = HashMap<String, llvm.Value>();
    ## The immortal `String` object of each shared literal, by value.
    var static_strings: HashMap<String, llvm.Value> = HashMap<String, llvm.Value>();
    ## Per function, per parameter: the caller makes the parameter's copy.
    var caller_copies: HashMap<String, bool[]> = HashMap<String, bool[]>();
    ## The parameters of the function being generated whose copy its caller
    ## made.
    var copied_params: HashSet<String> = HashSet<String>();
    ## Argument copies made for a call with a guarded step.
    var guarded_temps: llvm.Value[] = Array<llvm.Value>();
    ## File-scope globals.
    var global_addrs: HashMap<String, Address> = HashMap<String, Address>();
    var frame: Frame = Frame();
    ## Struct-reference slots alive in the current scopes, innermost last.
    var scopes: Array<Array<ScopeSlot>> = Array<Array<ScopeSlot>>();
    ## Owned temporaries released at the end of the full expression.
    var deferred_temps: Array<Temporary> = Array<Temporary>();
    ## The value each enclosing `WithSubject` examines, by its id.
    var subjects: HashMap<ulong, llvm.Value> = HashMap<ulong, llvm.Value>();
    ## The externs' declared names.
    var extern_names: HashSet<String> = HashSet<String>();
    ## Each extern's declared parameter types.
    var extern_params: HashMap<String, String[]> = HashMap<String, String[]>();
    ## Externs whose C result is narrower than Pepper's (a 32-bit `size_t`
    ## for `ulong`), by name: whether the result sign-extends back.
    var extern_narrow_results: HashMap<String, bool> = HashMap<String, bool>();
    ## The innermost located node an error passed through, by the error's
    ## text.
    var error_loc: Optional<(String, Loc)> = Optional<(String, Loc)>.Empty;
    ## Each file's namespace, by file index.
    var file_namespaces: String[] = Array<String>();
    ## How much the module is optimized: 0 to 3.
    var opt_level: uint = 0;
    ## Which runtime checks the code performs.
    var runtime_checks: RuntimeChecks = RuntimeChecks.all();
    ## Each source's name and line starts, for check locations.
    var check_files: Array<(String, ulong[])> = Array<(String, ulong[])>();
    ## The location of the call being generated (`__caller_location()`).
    var call_loc: Loc = Loc.none();
    ## Whether a call's default arguments are being generated.
    var in_default_argument: bool = false;

    construct(context: llvm.Context, name: String, machine: llvm.TargetMachine, state: PassState) {
        this.context = context;
        this.ir = llvm.Module(context, name);
        this.builder = llvm.Builder(context);
        this.machine = machine;
        this.state = state;
        this.types = Types(context, state);
        # The target's data layout drives alignment inference for atomic
        # instructions.
        ir.set_data_layout(machine.data_layout());
        ir.set_target_triple(machine.triple());
    }

    ## Remembers `loc` as where a failing `result` arose, unless a node nested
    ## inside claimed it first.
    locate(result: Result<void>, loc: Loc) {
        if (result.is_err()) {
            locate_error(result.error().message, loc);
        }
    }

    ## `locate` for a value's result.
    locate(result: Result<llvm.Value>, loc: Loc) {
        if (result.is_err()) {
            locate_error(result.error().message, loc);
        }
    }

    ## `locate` for a type's result.
    locate(result: Result<llvm.Type>, loc: Loc) {
        if (result.is_err()) {
            locate_error(result.error().message, loc);
        }
    }

    ## `locate` for an address's result.
    locate(result: Result<Address>, loc: Loc) {
        if (result.is_err()) {
            locate_error(result.error().message, loc);
        }
    }

    ## Remembers `loc` as where the error `error` arose, unless a node
    ## nested inside claimed it first.
    locate_error(error: String, loc: Loc) {
        if (loc.is_none()) {
            return;
        }
        if (error_loc.is_value()) {
            var (claimed, _) = error_loc.value();
            if (claimed == error) {
                return;
            }
        }
        error_loc = Optional<(String, Loc)>.Value((error, loc));
    }

    ## Instantiates and generates `module`, in the Rust generator's order.
    generate(module: Module): Result<void, Diagnostic> {
        error_loc = Optional<(String, Loc)>.Empty;
        var generated = generate_module(module);
        if (generated.is_err()) {
            var error = generated.error().message;
            var loc = Loc.none();
            if (error_loc.is_value()) {
                var (claimed, at) = error_loc.value();
                if (claimed == error) {
                    loc = at;
                }
            }
            error_loc = Optional<(String, Loc)>.Empty;
            return Result<void, Diagnostic>.err(error_at(error, loc));
        }
        var inlined = inline_vector_methods();
        if (inlined.is_err()) {
            return Result<void, Diagnostic>.err(Diagnostic.error(inlined.error().message));
        }
        annotate_facts(ir, context);
        return Result<void, Diagnostic>.ok();
    }

    generate_module(module: Module): Result<void> {
        index_check_files();
        caller_copies = module.caller_copies;
        hash_overrides = HashSet<String>();
        for (var f in module.functions) {
            if (f.name.starts_with("hash<") and f.generic_params.count == 0) {
                hash_overrides.insert(f.name);
            }
        }
        equality_methods = HashMap<String, String>();
        for (var st in module.structs) {
            var own = Optional<FunctionDef>.Empty;
            for (var m in st.method_members) {
                if (set_name(m.name) == "=="
                    and m.parameters.count == 1
                    and m.parameters[0].ty.to_string() == st.ty.to_string()) {
                    own = Optional<FunctionDef>.Value(m);
                    break;
                }
            }
            if (own.is_value()) {
                equality_methods[st.name] = $"{st.name}.{own.value().name}";
            }
        }
        return generate_items(module);
    }

    generate_items(module: Module): Result<void> {
        # The value structs' canonical spellings (`value_structs::install`).
        var defaulted = sema.defaulted_params(module);
        for (var st in module.structs) {
            if (!is_value_struct(st) or (st.ty.is_generic() and st.name == st.ty.name)) {
                continue;
            }
            var filled = st.ty.copy();
            sema.fill_defaults(filled, defaulted);
            var name = filled.to_string();
            if (name != st.name) {
                types.canonical[st.name] = name;
            }
        }
        # A weak trait value is no object: its sema struct only types it.
        weak_traits = HashSet<String>();
        for (var st in module.structs) {
            if (st.ty.is_weak() and st.ty.sub_types.count > 0 and sema.is_trait(state, st.ty.sub_types[0])) {
                weak_traits.insert(st.name);
            }
        }
        var structs = Array<StructDef>();
        for (var st in module.structs) {
            if (!weak_traits.contains(st.name)) {
                structs.append(st);
            }
        }
        # Concrete structs are registered as opaque types first: a field may
        # name a specialization declared later.
        for (var st in structs) {
            if ((st.ty.is_generic() and st.name == st.ty.name) or st.ty.is_tuple()) {
                continue;
            }
            if (is_value_struct(st)) {
                types.ensure_value_opaque(st.name);
            } else {
                types.ensure_opaque(st.name);
            }
        }
        # Trait types are values of their own layout; a field may hold one.
        for (var t in module.trait_types) {
            types.register_trait(t.ty.to_string());
        }
        var weak_names = Array<String>();
        for (var name in weak_traits) {
            weak_names.append(name);
        }
        weak_names.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
        for (var name in weak_names) {
            types.register_trait(name);
            traits[name] = TraitDesc();
        }
        # So are tuples: a struct field or another tuple may hold one.
        for (var st in structs) {
            if (st.ty.is_tuple()) {
                register_tuple(sema.parse_type_string(st.name))?;
            }
        }
        for (var st in structs) {
            instantiate_struct(st)?;
        }
        # ABI sizes are only right once every body is set.
        for (var entry in this.structs) {
            var (_, desc) = entry;
            desc.size = machine.size_of(desc.llvm_type);
        }
        for (var st in structs) {
            instantiate_methods(st)?;
        }
        for (var st in structs) {
            instantiate_ctor(st)?;
        }
        for (var ext in module.externs) {
            instantiate_extern(ext)?;
        }
        define_context_intrinsics()?;
        for (var function in module.functions) {
            instantiate_function(function)?;
        }
        for (var t in module.trait_types) {
            instantiate_trait(t)?;
        }
        for (var name in weak_names) {
            emit_weak_trait_thunk(name, true)?;
            emit_weak_trait_thunk(name, false)?;
        }
        # Value structs' thunks are declared before any thunk body calls them.
        var thunk_owners = Array<String>();
        var value_thunks = Array<llvm.Value>();
        for (var st in module.structs) {
            if (values.contains(st.name)) {
                for (var member in ["__acquire", "__release"]) {
                    var thunk = declare_tuple_refcount_thunk(st.name, member)?;
                    thunk_owners.append(st.name);
                    value_thunks.append(thunk);
                }
            }
        }
        for (var name in tuple_order.copy()) {
            emit_tuple_refcount_thunk(name, "__acquire")?;
            emit_tuple_refcount_thunk(name, "__release")?;
        }
        for (var index in 0..value_thunks.count) {
            define_tuple_refcount_thunk(thunk_owners[index], value_thunks[index])?;
        }
        # File-scope globals, between the instantiation and codegen passes so
        # initializers can call instantiated functions.
        emit_globals(module)?;
        # C entry points, before the codegen pass, which emits the shared
        # bodies they call.
        emit_exports(module)?;
        # Codegen pass: structs, then functions.
        for (var st in module.structs) {
            if (weak_traits.contains(st.name)) {
                continue;
            }
            codegen_struct(st)?;
        }
        for (var function in module.functions) {
            codegen_function(function)?;
        }
        var verified = ir.verify();
        if (verified.is_err()) {
            return fail<void>(verification_error(module, verified.error().message));
        }
        return Result<void>.ok();
    }

    ## The error for a module LLVM rejected with `message`: located at the
    ## first function the verifier rejects, and naming it.
    verification_error(module: Module, message: String): String {
        var newline = message.find("\n");
        var first = newline < 0 ? message : message.substr_bytes(0, newline as ulong);
        while (first.ends_with("!") or first.ends_with(".")) {
            first = first.substr_bytes(0, first.size - 1);
        }
        var declared = Array<(String, Loc)>();
        for (var st in module.structs) {
            for (var c in st.constructors) {
                declared.append((c.name, c.loc.is_none() ? st.loc : c.loc));
            }
            for (var m in st.method_members) {
                declared.append(($"{st.name}.{m.name}", m.loc.is_none() ? st.loc : m.loc));
            }
        }
        for (var f in module.functions) {
            declared.append((f.name, f.loc));
        }
        for (var entry in declared) {
            var (name, loc) = entry;
            var function = functions.try_get(name);
            if (function.is_value() and !function.value().verify_function()) {
                var error = $"LLVM rejected the code generated for '{link.demangle_name(name)}': {first}";
                locate_error(error, loc);
                return error;
            }
        }
        return $"LLVM rejected the generated code: {first}";
    }
}

## A failed result carrying `message`.
fail<T>(message: String): Result<T> {
    return Result<T>.err(Error(message));
}

## Whether `st` is `[Value]`: stored inline and copied like a tuple.
is_value_struct(st: StructDef): bool {
    return ast.has_attribute(st.attributes, sema.VALUE_ATTRIBUTE);
}

## Whether `ty` is `void`.
is_void(ty: TypeName): bool {
    return ty.to_string() == "void";
}

## A file's private declaration (its name mangled by module linking) is
## local to the object.
set_private_linkage(value: llvm.Value, name: String) {
    if (name.find(NAMESPACE_SEPARATOR) >= 0) {
        value.set_linkage(llvm.Linkage.Internal);
    }
}

## The LLVM function type from a return type and parameter types: a struct
## object returns as a pointer.
llvm_fn_type(context: llvm.Context, return_type: llvm.Type, params: llvm.Type[], variadic: bool): llvm.Type {
    if (is_object(return_type)) {
        return llvm.Type.function(context.pointer_type(), params, variadic);
    }
    return llvm.Type.function(return_type, params, variadic);
}

## The LLVM type a parameter or result of LLVM type `ty` is passed as: a
## struct object by pointer.
slot_type(context: llvm.Context, ty: llvm.Type): llvm.Type {
    return is_object(ty) ? context.pointer_type() : ty;
}

## The zero (null, default) value of `ty`.
zero_of(ty: llvm.Type): llvm.Value {
    return ty.zero();
}

## Best-effort type name of a value for coerce decisions.
value_type_name(value: llvm.Value): String {
    var ty = value.value_type();
    match (ty.kind()) {
        Integer => {
            var width = ty.int_width();
            if (width == 1) {
                return "bool";
            }
            return $"i{width}";
        }
        Float => {
            return "f32";
        }
        Double => {
            return "f64";
        }
        Pointer => {
            return "void*";
        }
        else => {
            return "unknown";
        }
    }
}

## The LLVM IR of the whole checked program, unoptimized, as
## `pep-build --emit-llvm -O0` writes it for the host.
##
## @param module the checked model
## @param state the passes' state for it
## @param namespaces each file's namespace, by file index
## @param name the module's name: the main file's stem
## @returns the IR, or the first error
export generate_ir(module: Module, state: PassState, namespaces: String[], name: String): Result<String, Diagnostic> {
    var machine = llvm.TargetMachine.create(llvm.default_triple(), "x86-64", "", llvm.OptLevel.O0);
    if (machine.is_err()) {
        return Result<String, Diagnostic>.err(Diagnostic.error(machine.error().message));
    }
    var context = llvm.Context();
    var generator = Generator(context, name, machine.value(), state);
    generator.file_namespaces = namespaces;
    var generated = generator.generate(module);
    if (generated.is_err()) {
        return Result<String, Diagnostic>.err(generated.error());
    }
    stamp_cpu(generator.ir, context, "x86-64", "generic", "");
    return Result<String, Diagnostic>.ok(generator.ir.to_string());
}

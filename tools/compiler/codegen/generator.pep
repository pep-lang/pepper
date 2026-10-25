## The LLVM module for a checked model. The generator declares every
## struct, method, extern and function first (the instantiation pass), then
## emits the globals and every body (the codegen pass), in a fixed order, so
## the same model always prints the same IR.

import compiler.ast;
import [Diagnostic] from compiler.diagnostic;
import compiler.link;
import llvm;
import compiler.sema;
import [
    DefaultArgumentExpression,
    error_at,
    Expression,
    FunctionDef,
    Loc,
    Module,
    PassState,
    set_name,
    StructDef,
    SymbolRefExpression,
    TypeName
] from compiler.sema;
import [Address, Frame] from "address";
import "address";
import "calls";
import "chains";
import [RuntimeChecks] from "checks";
import "checks";
import [DebugInfo] from "debug";
import "debug";
import "debug_types";
import "expressions";
import "functions";
import [annotate_facts, stamp_cpu] from "globals";
import "globals";
import "lazy";
import "operators";
import "ops";
import "partition";
import "refs";
import "simd";
import "static_debug";
import [initialize_backends, target_triple] from "target";
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

## The separator in a file's private names.
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
    ## Whether its counts step atomically, for a struct whose `__release`
    ## codegen may generate itself (`standard_release`, or a function
    ## type's): none for any other.
    var release_counts: bool? = Optional<bool>.Empty;
    ## Whether `__release` leaves an immortal object's count alone: a
    ## reference enum's cases that carry nothing, a plain function type's
    ## static objects.
    var immortal: bool = false;
    ## Declared `[__Lazy]`: the zero-argument constructor is null, and a
    ## place holding null gets its object when first read for anything but
    ## a `[__Reads]` call or a field read (see `materialize`).
    var lazy: bool = false;

    construct(name: String, llvm_type: llvm.Type, loc: Loc) {
        this.name = name;
        this.llvm_type = llvm_type;
        this.loc = loc;
    }
}

## How a chain field holds the objects of its struct's cycle.
export enum ChainKind {
    ## A struct reference.
    Struct,
    ## A trait value, whose object is one of the field's targets.
    Trait,
    ## An `Array`'s buffer of `_size` elements.
    Buffer,
    ## A function type's object, a closure of one of the field's targets.
    Closures,
}

## A field of a recursive struct that its last release takes the objects
## of its own cycle out of (`find_chains`).
export struct ChainField {
    var kind: ChainKind;
    ## The field's position in the struct.
    var position: uint;
    ## The sema type of the slot an object is read from: the field's, for
    ## a buffer its element type, and for `Closures` the function type.
    var ty: String;
    ## The structs of the cycle the slot can hold, by name.
    var targets: Array<String> = Array<String>();

    construct(kind: ChainKind, position: uint, ty: String) {
        this.kind = kind;
        this.position = position;
        this.ty = ty;
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

## The owner `Generator.owners` records for a function declared only that no
## file owns (an instantiation a lower compilation unit's object defines): not a
## file, so `prepare` only respells it.
export const DECLARED_ONLY: uint = 0xffffffff;

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
    ## Structs a cycle of fields runs through (`find_chains`): their last
    ## release is the chain one.
    var recursive: HashSet<String> = HashSet<String>();
    ## Recursive structs whose cycle also runs through something no chain
    ## field steers (a tuple, another container's buffer): their last
    ## release goes through the runtime's `_pep_release_last`.
    var deep_recursive: HashSet<String> = HashSet<String>();
    ## A recursive struct's chain fields: each field its last release takes
    ## objects of its own cycle out of (`chains.pep`).
    var chain_fields: HashMap<String, Array<ChainField>> = HashMap<String, Array<ChainField>>();
    ## Structs with chain fields whose destructor only releases fields (no
    ## `destruct` body sees them), so their last release moves a chain
    ## field's object out, leaving the field null.
    var chain_moves: HashSet<String> = HashSet<String>();
    ## The structs of each cycle `find_chains` found, each with the files it
    ## is declared in or names a type of: what the build cache keys a file's
    ## object on when its last releases steer into one (`Keys.steering`).
    var cycles: Array<Array<(String, ulong[])>> = Array<Array<(String, ulong[])>>();
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
    ## The `[__Reads]` methods of `[__Lazy]` structs, mangled
    ## (`Array<int>.__get_count`): they run on a null `this`.
    var reads_methods: HashSet<String> = HashSet<String>();
    ## Whether any struct is `[__Lazy]`.
    var any_lazy: bool = false;
    ## Set just before reading a place of a `[__Lazy]` type that must stay
    ## null (a `[__Reads]` receiver, a field read's object): the next
    ## `codegen_expr` takes it.
    var keep_lazy: bool = false;
    ## The function being generated is a `[__Reads]` method, so its `this`
    ## may be null and its field reads go through `lazy_base`.
    var this_may_be_null: bool = false;
    ## Set while `materialize` calls a `[__Lazy]` constructor, which then
    ## allocates instead of yielding null.
    var making_lazy: bool = false;
    ## The reads of `[__Lazy]` locals in the function being generated that
    ## nothing can follow (`final_reads_of`), by node identity: copying one
    ## moves the value out, so an empty one is passed on as null.
    var final_reads: HashSet<SymbolRefExpression> = HashSet<SymbolRefExpression>();
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
    ## `[__Reads]` parameters, by callee: an empty `[__Lazy]` argument
    ## reaches them as null instead of being allocated.
    var reads_params: HashMap<String, bool[]> = HashMap<String, bool[]>();
    ## Identical string literals share one global constant.
    var global_strings: HashMap<String, llvm.Value> = HashMap<String, llvm.Value>();
    ## The immortal `String` object of each shared literal, by value.
    var static_strings: HashMap<String, llvm.Value> = HashMap<String, llvm.Value>();
    ## Per function, per parameter: the caller makes the parameter's copy.
    var caller_copies: HashMap<String, bool[]> = HashMap<String, bool[]>();
    ## The functions whose bodies sema skipped (`Module.stripped`): their
    ## units' objects come from the build cache, so they are only declared.
    var stripped: HashSet<Loc> = HashSet<Loc>();
    ## The files whose units' objects come from the build cache: the bodies
    ## they own are only declared.
    var cached_files: HashSet<uint> = HashSet<uint>();
    ## Compiling one compilation unit's object: the functions declared only, by
    ## name, whoever owns them, which the objects of the compilation units below
    ## define (instantiations among them). Every other function with a body is
    ## defined here, and one whose file is another compilation unit's (a method
    ## a pass of this compilation unit added to a struct below, such as
    ## `_pep_copy_value`) has no owner, so it is `linkonce_odr`, as C++ emits an
    ## implicit special member in each object that uses it.
    var declared: HashSet<String>? = Optional<HashSet<String>>.Empty;
    ## The unowned bodies held back (`hold`), with the names they are
    ## generated as and their declarations, and the places in those of the
    ## ones no generated code calls yet.
    var waiting_functions: FunctionDef[] = Array<FunctionDef>();
    var waiting_names: String[] = Array<String>();
    var waiting_values: llvm.Value[] = Array<llvm.Value>();
    var waiting: ulong[] = Array<ulong>();
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
    ## The file each symbol a declaration defines belongs to, by symbol:
    ## its index in the program's files. Instantiations, and code without a
    ## source location, belong to no file (see `partition.pep`).
    var owners: HashMap<String, uint> = HashMap<String, uint>();
    ## Which runtime checks the code performs.
    var runtime_checks: RuntimeChecks = RuntimeChecks.all();
    ## Each source's name and line starts, for check locations.
    var check_files: Array<(String, ulong[])> = Array<(String, ulong[])>();
    ## The location of the call being generated (`__caller_location()`).
    var call_loc: Loc = Loc.none();
    ## Whether a call's default arguments are being generated.
    var in_default_argument: bool = false;
    ## Whether to emit debug info (`-g`; see `debug.pep`).
    var debug_info: bool = false;
    ## The module's debug info, while it is generated with `-g`.
    var debug: DebugInfo? = Optional<DebugInfo>.Empty;
    ## The location instructions are stamped with now, when debug info is
    ## on: null for none (see `enter_location`).
    var debug_location: llvm.Metadata = llvm.Metadata();
    ## Where the struct whose members are being generated is declared: a
    ## synthesized member without a location of its own is placed there for
    ## the debugger.
    var debug_struct_loc: Loc = Loc.none();
    ## `--debug-static=expanded`: where each emitted statement and pass
    ## header of a `static` block is in the expanded source, by its id.
    var static_locations: HashMap<uint, Loc> = HashMap<uint, Loc>();
    ## The text of gdb's pretty-printers for the runtime's types, which a
    ## Linux program carries with `-g` (`DebugInfo.embed_gdb_printers`).
    var gdb_printers: String = "";
    ## Whether `__caller_location()` strings are defined apart from the
    ## code that uses them (`located_string`).
    var separate_locations: bool = false;
    ## `Build.library`.
    var library: bool = false;
    ## How many such strings each function has used so far, by name.
    var location_counts: HashMap<String, ulong> = HashMap<String, ulong>();

    ## The module's name.
    var ir_name: String;

    construct(context: llvm.Context, name: String, machine: llvm.TargetMachine, state: PassState) {
        this.context = context;
        this.ir_name = name;
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

    ## A private `unnamed_addr` constant holding `text`'s bytes and a NUL,
    ## as `builder.global_string` makes, but sized by `text.size`:
    ## `global_string` takes a C string, so it cut a literal at its first
    ## NUL. `unnamed_addr` lets every part of a split module keep its own copy.
    ##
    ## @param text the bytes
    ## @param name the global's name
    ## @returns the global
    string_data(text: String, name: String): llvm.Value {
        var array = context.const_string(text, true);
        var global = ir.add_global(array.value_type(), name);
        global.set_initializer(array);
        global.set_global_constant(true);
        global.set_linkage(llvm.Linkage.Private);
        global.set_unnamed_address(2);
        global.set_alignment(1);
        return global;
    }

    ## Records `loc`'s file as the owner of function `name`, as `own` does,
    ## except, compiling one compilation unit's object, when the file is another
    ## compilation unit's (`Generator.declared`): the function is not in that
    ## compilation unit's object, so it is defined here unowned.
    own_function(name: String, loc: Loc) {
        if (declared.is_value() and cached_files.contains(loc.file)) {
            return;
        }
        own(name, loc);
    }

    ## Remembers `loc` as where a failing `result` arose, unless a node nested
    ## inside claimed it first.
    ## Records the file declaring `loc` as the owner of `name`, unless it
    ## names an instantiation (`Array<int>.append`, or a closure made in
    ## one, whose name spells the `<` as `_3c_`) or has no location.
    own(name: String, loc: Loc) {
        if (!loc.is_none() and !name.contains("<") and !name.contains("_3c_")) {
            owners[name] = loc.file;
        }
    }

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

    ## Instantiates and generates `module`.
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

    ## Stamps the instructions emitted from here on with `loc`'s location,
    ## when debug info is on and `loc` is known; returns the location to
    ## restore with `leave_location`.
    enter_location(loc: Loc): llvm.Metadata {
        var saved = debug_location;
        if (debug.is_value()) {
            var location = debug.value().location(loc);
            if (!location.is_null()) {
                builder.set_location(location);
                debug_location = location;
            }
        }
        return saved;
    }

    ## Stamps what is emitted next with the current location again, after
    ## positioning the builder before an instruction, which takes that
    ## instruction's location (none, for an entry block's slots).
    keep_location() {
        if (debug.is_value() and !debug_location.is_null()) {
            builder.set_location(debug_location);
        }
    }

    ## Restores the location `enter_location` replaced.
    leave_location(saved: llvm.Metadata) {
        if (!debug.is_value() or debug_location.ref == saved.ref) {
            return;
        }
        if (saved.is_null()) {
            builder.clear_location();
        } else {
            builder.set_location(saved);
        }
        debug_location = saved;
    }

    generate_module(module: Module): Result<void> {
        index_check_files();
        caller_copies = module.caller_copies;
        stripped = module.stripped;
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
        if (debug_info) {
            # One compile unit for the program's module, named for it: each
            # part split from it carries the unit.
            var info = DebugInfo(ir, state.sources, ir_name, opt_level > 0);
            info.static_locations = static_locations;
            for (var e in module.enums) {
                var plain = true;
                var cases = Array<(String, long)>();
                for (var c in e.cases) {
                    plain = plain and c.payload.is_empty;
                    cases.append((c.name, c.value));
                }
                if (plain) {
                    info.enums[e.name] = (e.loc, e.representation.to_string(), cases);
                }
            }
            for (var st in module.structs) {
                if (st.enum_cases.is_value()) {
                    var cases = Array<(String, long)>();
                    for (var c in st.enum_cases.value()) {
                        cases.append((c.name, c.value));
                    }
                    info.payload_enums[st.name] = cases;
                }
            }
            debug = Optional<DebugInfo>.Value(info);
        }
        return generate_items(module);
    }

    generate_items(module: Module): Result<void> {
        # The value structs' canonical spellings.
        var defaulted = sema.defaulted_params(module);
        for (var st in module.structs) {
            if (!is_value_struct(st) or (st.ty.is_generic() and st.name == st.ty.name)) {
                continue;
            }
            # `Range<int>` and the `Range<i32>` a literal makes are one type.
            var filled = sema.canonical_type(st.ty);
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
        find_chains(structs, module.traits);
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
        codegen_called()?;
        if (debug.is_value()) {
            debug.value().embed_gdb_printers(ir, gdb_printers);
            debug.value().finish(ir);
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
            return sema.VOID_PTR;
        }
        else => {
            return "unknown";
        }
    }
}

## The CPU code is generated for: LLVM's name for it, its features, and
## the CPU it is tuned for (empty for none).
export struct Cpu {
    var name: String;
    var features: String;
    var tune: String;

    construct(name: String, features: String, tune: String) {
        this.name = name;
        this.features = features;
        this.tune = tune;
    }

    ## Clang's default CPU for `triple`, from its driver: `x86-64` tuned for
    ## `generic` (`penryn` on Apple), else `generic` (`apple-m1` on Apple,
    ## `apple-a7` on an iOS device).
    ##
    ## @param triple the target triple
    ## @returns the CPU
    static default_for(triple: String): Cpu {
        var apple = triple.contains("-apple-");
        var arch = triple.split_once("-");
        var name = arch.is_value() ? arch.value().0 : triple;
        if (name == "x86_64" or name == "amd64" or name == "i386" or name == "i686") {
            return Cpu(
                apple ? "penryn" : "x86-64", triple.contains("-android") ? "+sse4.2,+popcnt,+cx16" : "", "generic"
            );
        }
        var device = apple and triple.contains("-ios") and !triple.ends_with("-simulator");
        return Cpu(device ? "apple-a7" : (apple ? "apple-m1" : "generic"), "", "");
    }

    ## The CPU clang's `-m` options choose for `triple`: each of `machine`
    ## is what follows `-m`, in order (`arch=x86-64-v3`, `cpu=native`,
    ## `tune=znver4`, `avx2`, `no-avx2`). On x86, `-march` names the CPU
    ## (`native` the host's) and `-mcpu` is an error; without `-march` the
    ## code is tuned for `generic`. On AArch64, `-mcpu` names the CPU and
    ## `-march` the architecture (`armv8.2-a`), each with `+<extension>` or
    ## `+no<extension>` after it. On WebAssembly, `-mcpu` names the CPU and
    ## `-march` is an error. `-mtune` names the CPU to schedule for,
    ## `-m<feature>` adds an LLVM feature and `-mno-<feature>` removes one,
    ## after those the CPU implies. The last of each option wins.
    ##
    ## @param triple the target triple
    ## @param machine the options, without their `-m`
    ## @returns the CPU, or the error, worded as clang words it
    static from_options(triple: String, machine: String[]): Result<Cpu, String> {
        var cpu = Cpu.default_for(triple);
        var x86 = _is_x86(triple);
        var wasm = triple.starts_with("wasm32");
        var cross = wasm or x86 != _is_x86(llvm.default_triple());
        String? arch;
        String? mcpu;
        String? tune;
        var extra = Array<String>();
        for (var option in machine) {
            if (option.ends_with("=native") and cross) {
                return Result<Cpu, String>.err(
                    $"'-m{option}' names this machine's CPU, which target '{triple}' cannot run on"
                );
            }
            if (option.starts_with("arch=")) {
                if (wasm) {
                    return Result<Cpu, String>.err($"unsupported option '-march=' for target '{triple}'; use '-mcpu'");
                }
                arch = Optional<String>.Value(_after(option, 5));
            } else if (option.starts_with("cpu=")) {
                if (x86) {
                    return Result<Cpu, String>.err(
                        $"unsupported option '-mcpu=' for target '{triple}'; use '-march' or '-mtune'"
                    );
                }
                mcpu = Optional<String>.Value(_after(option, 4));
            } else if (option.starts_with("tune=")) {
                tune = Optional<String>.Value(_after(option, 5));
            } else if (option.starts_with("no-")) {
                extra.append("-" + _after(option, 3));
            } else if (!option.is_empty and !option.contains("=")) {
                extra.append("+" + option);
            } else {
                return Result<Cpu, String>.err($"unknown argument '-m{option}'");
            }
        }
        var features = [cpu.features];
        if (x86) {
            if (arch.is_value()) {
                if (arch.value().is_empty) {
                    return Result<Cpu, String>.err("missing value for '-march='");
                }
                if (arch.value() == "native") {
                    cpu.name = llvm.host_cpu();
                    features.append(llvm.host_features());
                    cpu.tune = llvm.host_cpu();
                } else {
                    cpu.name = arch.value();
                    cpu.tune = "";
                }
            }
        } else {
            # `-mcpu` sets the CPU and `-march` the architecture; with both,
            # clang takes the CPU from `-mcpu` and the features from both.
            if (arch.is_value()) {
                var named = arch.value();
                if (named.is_empty) {
                    return Result<Cpu, String>.err("missing value for '-march='");
                }
                if (named == "native") {
                    cpu.name = llvm.host_cpu();
                    features.append(llvm.host_features());
                } else {
                    var (base, extensions) = _split_extensions(named);
                    # `armv<version>-a`, with a version.
                    if (base.size <= 6 or !base.starts_with("armv") or !base.ends_with("-a")) {
                        return Result<Cpu, String>.err($"invalid arch name '-march={named}'");
                    }
                    cpu.name = "generic";
                    features.append($"+v{base.substr_bytes(4, base.size - 6)}a");
                    features.append_all(extensions);
                }
            }
            if (mcpu.is_value()) {
                var named = mcpu.value();
                if (named.is_empty) {
                    return Result<Cpu, String>.err("missing value for '-mcpu='");
                }
                if (named == "native") {
                    cpu.name = llvm.host_cpu();
                    features.append(llvm.host_features());
                } else {
                    var (base, extensions) = _split_extensions(named);
                    cpu.name = base;
                    features.append_all(extensions);
                }
            }
        }
        if (tune.is_value()) {
            if (tune.value().is_empty) {
                return Result<Cpu, String>.err("missing value for '-mtune='");
            }
            cpu.tune = tune.value() == "native" ? llvm.host_cpu() : tune.value();
        }
        features.append_all(extra);
        var kept = Array<String>();
        for (var feature in features) {
            if (!feature.is_empty) {
                kept.append(feature);
            }
        }
        cpu.features = ",".join(kept);
        return Result<Cpu, String>.ok(cpu);
    }

    ## The CPU, features and tuning as one line, for the build cache's key
    ## (`x86-64-v3+avx512f@generic`).
    ##
    ## @returns the line
    key(): String {
        var out = name + features.replace(",", "");
        return tune.is_empty ? out : $"{out}@{tune}";
    }
}

# Whether `triple` names an x86-64 machine.
_is_x86(triple: String): bool {
    return triple.starts_with("x86_64") or triple.starts_with("amd64");
}

# `text` from byte `start` on.
_after(text: String, start: ulong): String {
    return text.substr_bytes(start, text.size - start);
}

# `name+ext+noext` as `name` and the LLVM features `+ext`, `-ext`.
_split_extensions(value: String): (String, String[]) {
    var parts = value.split("+");
    var extensions = Array<String>();
    for (var i in 1..parts.count) {
        var extension = parts[i];
        if (!extension.is_empty) {
            extensions.append(extension.starts_with("no") ? "-" + _after(extension, 2) : "+" + extension);
        }
    }
    return (parts[0], extensions);
}

## What `generate` builds the module for.
export struct Build {
    ## The machine code is generated for.
    var machine: llvm.TargetMachine;
    ## Its CPU, stamped on every function defined.
    var cpu: Cpu;
    ## How much the module is optimized: 0 to 3.
    var opt_level: uint = 0;
    ## Which runtime checks the code performs.
    var runtime_checks: RuntimeChecks = RuntimeChecks.all();
    ## Whether every function keeps its frame pointer (`--frame-pointers`).
    var frame_pointers: bool = false;
    ## Whether to emit debug info (`-g`).
    var debug_info: bool = false;
    ## With `--debug-static=expanded`, where each `static` block's emitted
    ## statements and pass headers are in the expanded sources, by id.
    var static_locations: HashMap<uint, Loc> = HashMap<uint, Loc>();
    ## The text of `runtime/debuggers/gdb_printers.py`, which a Linux
    ## program carries with `-g`; empty for none.
    var gdb_printers: String = "";
    ## Whether the location strings of checks and `__caller_location()`
    ## are defined apart from the code, under names that do not depend on
    ## the lines (`Generator.located_string`), so code a line shift moves
    ## stays the same (`codegen.prepare` gives them a part of their own).
    var separate_locations: bool = false;
    ## Whether the code is for a library (`--lib static` or `--lib shared`),
    ## which may end up in a shared object, so on Android its thread-locals
    ## use the general-dynamic TLS model (`Generator.declare_thread_local`).
    var library: bool = false;

    construct(machine: llvm.TargetMachine, cpu: Cpu) {
        this.machine = machine;
        this.cpu = cpu;
    }
}

## The whole checked program as one LLVM module, unoptimized, stamped with
## the build's CPU.
##
## @param module the checked model
## @param state the passes' state for it
## @param namespaces each file's namespace, by file index
## @param name the module's name: the main file's stem
## @param build the machine, CPU, optimization level and checks
## @param owners receives the file each owned symbol belongs to, by name
##               (see `partition.pep`)
## @param cached_files the files whose units' objects come from the build cache,
##   or another compilation unit's object: the bodies they own are only declared
## @param declared compiling one compilation unit's object: the functions only
##   declared, by name, whoever owns them, which the objects of
##   the compilation units below define (`Generator.declared`)
## @param cycles receives the structs of each cycle the last releases steer
##   through (`Generator.cycles`)
## @returns the module, or the first error
export generate(
    module: Module,
    state: PassState,
    namespaces: String[],
    name: String,
    build: Build,
    owners: HashMap<String, uint> = HashMap<String, uint>(),
    cached_files: HashSet<uint> = HashSet<uint>(),
    declared: HashSet<String>? = Optional<HashSet<String>>.Empty,
    cycles: Array<Array<(String, ulong[])>> = Array<Array<(String, ulong[])>>()
): Result<llvm.Module, Diagnostic> {
    var context = llvm.Context();
    var generator = Generator(context, name, build.machine, state);
    generator.owners = owners;
    generator.cycles = cycles;
    generator.cached_files = cached_files;
    generator.declared = declared;
    generator.file_namespaces = namespaces;
    generator.opt_level = build.opt_level;
    generator.runtime_checks = build.runtime_checks;
    generator.debug_info = build.debug_info;
    generator.static_locations = build.static_locations;
    generator.gdb_printers = build.gdb_printers;
    generator.separate_locations = build.separate_locations;
    generator.library = build.library;
    var generated = generator.generate(module);
    if (generated.is_err()) {
        return Result<llvm.Module, Diagnostic>.err(generated.error());
    }
    stamp_cpu(generator.ir, context, build.cpu.name, build.cpu.tune, build.cpu.features);
    if (build.frame_pointers) {
        # As clang's `-fno-omit-frame-pointer`.
        var all = context.string_attribute("frame-pointer", "all");
        for (var function in generator.ir.functions()) {
            if (function.block_count() > 0) {
                function.add_function_attribute(all);
            }
        }
    }
    return Result<llvm.Module, Diagnostic>.ok(generator.ir);
}

## The LLVM IR of the whole checked program, unoptimized, as
## `pep-build --emit-llvm -O0` writes it for the target (`state.target`).
##
## @param module the checked model
## @param state the passes' state for it
## @param namespaces each file's namespace, by file index
## @param name the module's name: the main file's stem
## @param chosen the CPU the `-m` options chose; clang's default for the
##   target without one
## @param debug_info whether to emit debug info (`-g`)
## @param opt_level the `-O` level the IR is optimized at, as LLVM's
##   standard pipeline does (`pep-build --emit-llvm`); 0 leaves it as
##   generated
## @param frame_pointers whether every function keeps its frame pointer
## @param runtime_checks the runtime checks the code keeps
## @param gdb_printers the text of gdb's pretty-printers, which a Linux
##   program carries with `-g`; empty for none
## @param library whether the code is for a library (`--lib`)
## @returns the IR, or the first error
export generate_ir(
    module: Module,
    state: PassState,
    namespaces: String[],
    name: String,
    chosen: Cpu? = Optional<Cpu>.Empty,
    debug_info: bool = false,
    opt_level: uint = 0,
    frame_pointers: bool = false,
    runtime_checks: RuntimeChecks = RuntimeChecks.all(),
    gdb_printers: String = "",
    library: bool = false
): Result<String, Diagnostic> {
    var triple = target_triple(state.target);
    var cpu = chosen.is_value() ? chosen.value() : Cpu.default_for(triple);
    initialize_backends();
    var level = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3][opt_level];
    var machine = llvm.TargetMachine.create(triple, cpu.name, cpu.features, level);
    if (machine.is_err()) {
        return Result<String, Diagnostic>.err(Diagnostic.error(machine.error().message));
    }
    var setup = Build(machine.value(), cpu);
    setup.debug_info = debug_info;
    setup.opt_level = opt_level;
    setup.frame_pointers = frame_pointers;
    setup.runtime_checks = runtime_checks;
    setup.gdb_printers = gdb_printers;
    setup.library = library;
    var generated = generate(module, state, namespaces, name, setup);
    if (generated.is_err()) {
        return Result<String, Diagnostic>.err(generated.error());
    }
    # The IR shows each extern under its C symbol, as the build links it.
    restore_extern_names(generated.value());
    if (opt_level > 0) {
        var optimized = generated.value().run_passes($"default<O{opt_level}>", machine.value());
        if (optimized.is_err()) {
            return Result<String, Diagnostic>.err(Diagnostic.error($"cannot optimize: {optimized.error().message}"));
        }
    }
    return Result<String, Diagnostic>.ok(generated.value().to_string());
}

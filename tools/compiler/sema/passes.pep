## The sema passes, in the order the compiler runs them: one step per pass
## run, so `pep-build --emit-model --emit-model-step N` prints the model
## after the first N steps. The first `PORTED_STEPS` run once each, then the
## specialization loop, whose steps a program runs as many rounds of as it
## needs.

import [Diagnostic, SourceText, compare_locations] from compiler.diagnostic;
import io;
import [Target] from compiler.link;
import os;
import [apply_extensions, check_parameter_names] from "apply_extensions";
import [check_unbound, record_argument_names] from "argument_names";
import [check_assignment_targets] from "assignment_targets";
import [check_bindings] from "bindings";
import [check_casts] from "casts";
import [check_bounds] from "check_bounds";
import [check_tries] from "check_tries";
import [restore_bodies, stash_bodies] from "checked";
import [check_closures, is_closure_struct, lift_closures] from "closures";
import [check_conditions] from "conditions";
import [check_confinement] from "confinement";
import [check_constraints, check_specializations] from "constraints";
import [convert_intrinsics] from "convert_intrinsics";
import [convert_member_refs] from "convert_member_refs";
import [convert_to_traits] from "convert_to_traits";
import [synthesize_copies] from "copies";
import [check_deprecated_members] from "deprecated_members";
import [lower_destructures] from "destructures";
import [lower_main_arguments] from "entry_point";
import [resolve_enum_cases] from "enums";
import [derive_equatable] from "equatable";
import [collect_exports] from "exports";
import [reference_functions] from "function_references";
import [synthesize_function_types] from "function_types";
import [check_function_types] from "function_types_check";
import [has_generic_methods, specialize_methods] from "generic_methods";
import [gather_generics] from "generics";
import [check_hash_keys] from "hash_keys";
import [resolve_injected, verify_injected] from "injected";
import [with_instantiation] from "instantiation";
import [check_interpolations] from "interpolation";
import [check_lazy] from "lazy";
import [drop_unused_methods, specialize_used_methods] from "lazy_methods";
import [check_string_bytes, resolve_literals] from "literals";
import [Loc, NO_FILE] from "loc";
import [lower_matches] from "matches";
import [Module] from "model";
import [bind_calls, check_link_attributes, check_named_attributes] from "named_arguments";
import [check_overloads] from "overload_checks";
import [has_overloads] from "overload_select";
import [name_overloads] from "overloads";
import [UnitDecls] from "pending";
import [apply_platform_filters] from "platform";
import [check_ranges] from "ranges";
import [release_field_refs] from "release_field_refs";
import [resolve_implicit_types] from "resolve_implicit_types";
import [resolve_operators] from "resolve_operators";
import [resolve_resolvables] from "resolve_resolvables";
import [shared_functions] from "shared_functions";
import [check_shared_types] from "shared_type_checks";
import [check_simd_shapes] from "simd_shapes";
import [specialize_functions] from "specialize_functions";
import [freeze_templates, specialize_structs] from "specialize_structs";
import [PassMemo, PassState] from "state";
import [check_attributes, expand, expand_module_blocks, remove_from_generic_code] from "static_blocks";
import [share_string_literals] from "static_strings";
import [strip_bodies] from "strip_bodies";
import [synthesize] from "synthesize";
import [resolve_type_aliases] from "type_aliases";
import [check_type_arguments] from "type_argument_checks";
import [begin_type_ids, end_type_ids] from "type_ids";
import [check_value_structs] from "value_structs";
import [lower_with_blocks] from "with_blocks";
import [check_withheld] from "withheld";

## How many steps come before the specialization loop.
export const PORTED_STEPS: ulong = 39;

## The name of each step before the specialization loop, as `--emit-steps`
## prints it: the call the step makes, spelled as the steps have always been
## named.
_step_name(index: ulong): String {
    var names = [
        "apply_platform_filters(module)",
        "struct_body::derive_equatable(module)",
        "struct_body::lift_closures(module)",
        "struct_body::strip_bodies(module)",
        "struct_body::resolve_type_aliases(module)",
        "struct_body::synthesize(module)",
        "static_blocks::check_attributes(module)",
        "static_blocks::expand_module_blocks(module)",
        "static_blocks::expand(module, false)",
        "crate::enums::resolve_enum_cases(module)",
        "entry_point::lower_main_arguments(module)",
        "check_bindings::check_bindings(module)",
        "named_arguments::check_attributes(module)",
        "check_link_attributes(module)",
        "named_arguments::bind_calls(module)",
        "synthesize_function_types(module)",
        "resolve_literals(module)",
        "overloads::name_overloads(module)",
        "injected::resolve_injected(module)",
        "gather_generics(module)",
        "resolve_implicit_types(module)",
        "check_tries::check_tries(module)",
        "resolve_resolvables(module, false)",
        "apply_extensions(module, false)",
        "interpolation::check_interpolations(module)",
        "constraints::check_constraints(module)",
        "check_bounds::check_bounds(module)",
        "specialize_structs(module)",
        "specialize_functions(module)",
        "ranges::check_ranges(module)",
        "generic_methods::specialize_methods(module)",
        "static_blocks::expand(module, true)",
        "synthesize_function_types(module)",
        "convert_intrinsics(module)",
        "resolve_resolvables(module, false)",
        "apply_extensions(module, true)",
        "convert_member_refs(module)",
        "resolve_implicit_types(module)",
        "resolve_operators(module)"
    ];
    return names[index];
}

## Runs the first `limit` steps of the passes over `module` (all of them,
## through the specialization loop, when `limit` is larger), stopping at the
## first that reports an error.
##
## @param module the model `merge` built, changed in place
## @param target the compile target
## @param limit how many steps to run
## @param sources the program's files' text, by file index
## @returns how many steps ran, or the errors the step that failed reported
export run_steps(
    module: Module, target: Target, limit: ulong, sources: SourceText[] = Array<SourceText>()
): Result<ulong, Diagnostic[]> {
    var state = PassState(target);
    state.sources = sources;
    return run_steps_with(module, state, limit);
}

## Runs every step of the passes over `module`, for code generation.
##
## @param module the model `merge` built, changed in place
## @param target the compile target
## @param sources the program's files' text, by file index
## @returns the passes' state, which code generation reads, or the errors
##   the step that failed reported
export run_passes(module: Module, target: Target, sources: SourceText[]): Result<PassState, Diagnostic[]> {
    var state = PassState(target);
    state.sources = sources;
    state.lazy_methods = true;
    var ran = run_steps_with(module, state, 0xffffffffffffffff);
    if (ran.is_err()) {
        return Result<PassState, Diagnostic[]>.Err(ran.error());
    }
    return Result<PassState, Diagnostic[]>.Ok(state);
}

## `run_steps` with the passes' state given. A step that fails stops the
## run, which returns every error it reported, as `_reportable` keeps them.
##
## @param module the model, changed in place
## @param state the passes' state
## @param limit how many steps to run
## @returns how many steps ran, or the errors the step that failed reported
export run_steps_with(module: Module, state: PassState, limit: ulong): Result<ulong, Diagnostic[]> {
    # The passes ask the same deep types the same questions: the table
    # answers each once per distinct type (#210).
    var outer = begin_type_ids();
    var ran = _run_steps(module, state, limit);
    end_type_ids(outer);
    return ran;
}

_run_steps(module: Module, state: PassState, limit: ulong): Result<ulong, Diagnostic[]> {
    var steps = _Steps(limit, state);
    while (steps.ran < limit and steps.ran < PORTED_STEPS) {
        var errors = _step(steps.ran, module, state);
        steps.record_step(_step_name(steps.ran), steps.ran >= 6);
        if (!errors.is_empty) {
            steps.errors = errors;
            break;
        }
        steps.lap();
        steps.ran += 1;
    }
    if (steps.errors.is_empty and steps.ran == PORTED_STEPS and steps.ran < limit) {
        _specialization_loop(module, state, steps);
        if (steps.errors.is_empty and steps.ran < limit) {
            _after_specializing(module, state, steps);
        }
    }
    steps.report();
    # The checked declarations' tables and members hold signatures
    # (`GenericSignature`) that hold the state: let them go with the run, or
    # the cycle keeps the state, and every checked declaration it reaches,
    # alive after it (a compilation unit worker kept every unit's, #167).
    state.checked_implicit = Optional<PassMemo>.Empty;
    state.trait_memo.members = HashMap<String, PassMemo>();
    state.unit_memos = HashMap<String, PassMemo>();
    if (!steps.errors.is_empty) {
        return Result<ulong, Diagnostic[]>.Err(_reportable(module, steps.errors));
    }
    return Result<ulong, Diagnostic[]>.Ok(steps.ran);
}

# The errors a failed step reported, as the user is shown them: those with
# a place (all when none has one), each place and message once, and of
# those in one declaration only the first reported, as a later one there is
# usually its fallout (even one earlier in the source), in source order. An
# error in a specialization notes the uses that asked for it. Runs only after
# an error: a build without one pays nothing for it.
_reportable(module: Module, errors: Diagnostic[]): Diagnostic[] {
    var placed = Array<Diagnostic>();
    for (var error in errors) {
        if (error.location is Value(at)) {
            if (at.file != NO_FILE as ulong) {
                placed.append(error);
            }
        }
    }
    if (placed.is_empty) {
        placed.append_all(errors);
    }
    var starts = _declaration_starts(module);
    var seen = HashSet<String>();
    var declarations = HashSet<ulong>();
    var out = Array<Diagnostic>();
    for (var error in placed) {
        var place = "";
        if (error.location is Value(at)) {
            place = $"{at.file}:{at.span.start}:{at.span.end}";
            var after = starts.upper_bound(_position(at.file, at.span.start));
            if (after > 0 and starts[after - 1] >> _FILE_SHIFT == at.file and !declarations.insert(starts[after - 1])) {
                continue;
            }
        }
        if (seen.insert($"{place} {error.message}")) {
            out.append(with_instantiation(module, error));
        }
    }
    out.sort((a, b) => compare_locations(a, b));
    return out;
}

# A place as one number that orders by file, then offset: files stay under
# 2^24 and offsets under 2^40.
const _FILE_SHIFT: ulong = 40;

_position(file: ulong, offset: ulong): ulong {
    return (file << _FILE_SHIFT) | offset;
}

# Where each declaration with a place starts (`_position`), sorted: an
# error belongs to the last one starting at or before it. A closure's struct
# is not one, as its body is part of its function's.
_declaration_starts(module: Module): ulong[] {
    var starts = Array<ulong>();
    for (var function in module.functions) {
        _add_start(starts, function.loc);
    }
    for (var st in module.structs) {
        if (is_closure_struct(st.name)) {
            continue;
        }
        _add_start(starts, st.loc);
        for (var method in st.method_members) {
            _add_start(starts, method.loc);
        }
        for (var method in st.generic_methods) {
            _add_start(starts, method.loc);
        }
        for (var constructor in st.constructors) {
            _add_start(starts, constructor.loc);
        }
    }
    for (var t in module.traits) {
        _add_start(starts, t.loc);
        for (var method in t.methods) {
            _add_start(starts, method.loc);
        }
    }
    for (var extension in module.extensions) {
        _add_start(starts, extension.loc);
        for (var method in extension.methods) {
            _add_start(starts, method.loc);
        }
    }
    for (var e in module.enums) {
        _add_start(starts, e.loc);
    }
    for (var global in module.globals) {
        _add_start(starts, global.loc);
    }
    starts.sort();
    return starts;
}

_add_start(starts: ulong[], at: Loc) {
    if (!at.is_none()) {
        starts.append(_position(at.file as ulong, at.span.start));
    }
}

## Counts the steps, and stops at the first error or at the limit.
struct _Steps {
    var ran: ulong = 0;
    var limit: ulong;
    var state: PassState;
    var errors: Diagnostic[] = Array<Diagnostic>();
    # With `PEPC_TRACE_STEPS` set, the time each step took, by step.
    var timed: bool = false;
    var mark: os.Instant = os.Instant.now();
    var spent: HashMap<ulong, ulong> = HashMap<ulong, ulong>();
    # Each traced step's pass, when the loop or the last steps name it.
    var names: HashMap<ulong, String> = HashMap<ulong, String>();

    # With `-T passes`, when the last step ended.
    var pass_mark: os.Instant = os.Instant.now();

    construct(limit: ulong, state: PassState) {
        this.limit = limit;
        this.state = state;
        state.step_names = Array<String>();
        var trace = os.environment("PEPC_TRACE_STEPS");
        timed = trace.is_value() and !trace.value().is_empty;
    }

    ## Names step `ran`, which just ran, in `PassState.step_names`, and with
    ## `-T passes` adds its time to its pass's when `timed_pass` (the steps
    ## after the struct bodies are made are timed, not those before).
    record_step(call: String, timed_pass: bool) {
        state.step_names.append(call);
        if (state.pass_times.is_value()) {
            var now = os.Instant.now();
            if (timed_pass) {
                state.pass_times.value().add(call, (now - pass_mark).nanoseconds());
            }
            pass_mark = now;
        }
    }

    ## After a step: whether to stop, at its error or at the limit.
    stepped(name: String = ""): bool {
        record_step(name, true);
        if (taken()) {
            return true;
        }
        if (timed and !name.is_empty) {
            names[ran] = name;
        }
        lap();
        ran += 1;
        return ran >= limit;
    }

    ## Adds the time since the last step to step `ran`'s.
    lap() {
        if (!timed) {
            return;
        }
        var now = os.Instant.now();
        var before = spent.try_get(ran);
        spent[ran] = (before.is_value() ? before.value() : 0) + (now - mark).milliseconds() as ulong;
        mark = now;
    }

    ## Prints each step's time, the slowest first.
    report() {
        if (!timed) {
            return;
        }
        var all = Array<(ulong, ulong)>();
        for (var (step, ms) in spent) {
            all.append((step, ms));
        }
        all.sort((a, b) => {
            var (_, x) = a;
            var (_, y) = b;
            return x > y ? -1 : (x < y ? 1 : 0);
        });
        for (var (step, ms) in all) {
            if (ms > 0) {
                var name = names.try_get(step);
                io.File.stderr().write_all($"step {step}: {ms} ms {name.is_value() ? name.value() : ""}\n");
            }
        }
    }

    ## Whether a pass that is not a step of its own reported an error.
    taken(): bool {
        if (state.pass_times.is_value()) {
            pass_mark = os.Instant.now();
        }
        var taken = state.take_errors();
        if (taken.is_empty) {
            return false;
        }
        errors = taken;
        return true;
    }
}

## The second pass: specializing can expose further generic uses, so the
## specializations repeat until no new one appears.
_specialization_loop(module: Module, state: PassState, steps: _Steps) {
    for (var round in 0..4096) {
        var structs = module.structs.count;
        var functions = module.functions.count;
        gather_generics(module, state);
        if (steps.stepped("gather_generics(module)")) {
            return;
        }
        check_specializations(module, state);
        if (steps.stepped("constraints::check_specializations(module)")) {
            return;
        }
        specialize_structs(module, state);
        if (steps.stepped("specialize_structs(module)")) {
            return;
        }
        specialize_functions(module, state);
        if (steps.stepped("specialize_functions(module)")) {
            return;
        }
        check_ranges(module, state);
        if (steps.stepped("ranges::check_ranges(module)")) {
            return;
        }
        # The `static` blocks of what the round specialized.
        var expanded = expand(module, state, true);
        if (steps.taken()) {
            return;
        }
        # A generic method call, or a call to an overloaded function, whose
        # arguments the round just typed is typed only now.
        if (expanded or has_generic_methods(module) or has_overloads(module)) {
            resolve_implicit_types(module, state);
            if (steps.stepped("resolve_implicit_types(module)")) {
                return;
            }
        }
        var used_added = specialize_used_methods(module, state);
        var methods_added = specialize_methods(module, state);
        var methods_expanded = expand(module, state, true);
        var copies_added = synthesize_copies(module, state);
        if (steps.taken()) {
            return;
        }
        if (module.structs.count != structs
            or module.functions.count != functions
            or methods_added
            or used_added
            or copies_added
            or expanded
            or methods_expanded) {
            continue;
        }
        # Done only when gathering asks for nothing new.
        var struct_specs = module.struct_specs.count;
        var func_specs = module.func_specs.count;
        gather_generics(module, state);
        if (steps.stepped("gather_generics(module)")) {
            return;
        }
        if (module.struct_specs.count == struct_specs and module.func_specs.count == func_specs) {
            drop_unused_methods(module, state);
            return;
        }
    }
}

## The steps once every specialization is made: generic code's `static`
## blocks go, then the checks and conversions repeat over the specialized
## code.
_after_specializing(module: Module, state: PassState, steps: _Steps) {
    remove_from_generic_code(module);
    check_interpolations(module, state);
    if (steps.stepped("interpolation::check_interpolations(module)")) {
        return;
    }
    # A call of a member a constrained extension withheld.
    check_withheld(module, state);
    if (steps.stepped("constraints::check_withheld(module)")) {
        return;
    }
    check_simd_shapes(module, state);
    if (steps.stepped("check_simd_shapes::check_simd_shapes(module)")) {
        return;
    }
    convert_intrinsics(module, state);
    if (steps.stepped("convert_intrinsics(module)")) {
        return;
    }
    resolve_resolvables(module, false, state);
    if (steps.stepped("resolve_resolvables(module, false)")) {
        return;
    }
    # The extensions of the specializations made in the loop.
    apply_extensions(module, state);
    if (steps.stepped("apply_extensions(module, true)")) {
        return;
    }
    expand(module, state, true);
    if (steps.stepped("static_blocks::expand(module, true)")) {
        return;
    }
    convert_member_refs(module, state);
    if (steps.stepped("convert_member_refs(module)")) {
        return;
    }
    synthesize_function_types(module, state);
    if (steps.stepped("synthesize_function_types(module)")) {
        return;
    }
    # Methods, structs and specializations used as values become closures.
    reference_functions(module, state);
    if (steps.stepped("function_references::reference_functions(module)")) {
        return;
    }
    # Destructors release their struct fields.
    release_field_refs(module, state);
    if (steps.stepped("release_field_refs(module)")) {
        return;
    }
    # Implicit types once more, with overloads settled by how many
    # arguments they take.
    state.settle_overloads_by_arity = true;
    resolve_implicit_types(module, state);
    state.settle_overloads_by_arity = false;
    if (steps.stepped("resolve_implicit_types_settling(module)")) {
        return;
    }
    check_tries(module, state);
    if (steps.stepped("check_tries::check_tries(module)")) {
        return;
    }
    # Named arguments no binding took.
    check_unbound(module, state);
    if (steps.stepped("named_arguments::check_unbound(module)")) {
        return;
    }
    # The parameter names of literal arguments, for inlay hints.
    record_argument_names(module, state);
    check_type_arguments(module, state);
    if (steps.stepped("type_arguments::check_type_arguments(module)")) {
        return;
    }
    check_overloads(module, state);
    if (steps.stepped("overloads::check_overloads(module)")) {
        return;
    }
    # Once implicit types are resolved, operator overloading may exist.
    resolve_operators(module, state);
    if (steps.stepped("resolve_operators(module)")) {
        return;
    }
    # A call left as an assignment's target, which nothing can store into.
    check_assignment_targets(module, state);
    if (steps.stepped("resolve_operators::check_assignment_targets(module)")) {
        return;
    }
    # A struct value in a boolean context needs its own `!!`.
    check_conditions(module, state);
    if (steps.stepped("unary_operators::check_conditions(module)")) {
        return;
    }
    # Undeclared names and calls are reported here.
    resolve_resolvables(module, true, state);
    if (steps.stepped("resolve_resolvables(module, true)")) {
        return;
    }
    # Destructures read their tuple; labels become positions.
    lower_destructures(module, state);
    if (steps.stepped("tuples::lower_destructures(module)")) {
        return;
    }
    # Types inferred by the final resolve (`var f = square;`).
    synthesize_function_types(module, state);
    if (steps.stepped("synthesize_function_types(module)")) {
        return;
    }
    # Closure types nothing inferred must be written.
    check_closures(module, state);
    if (steps.stepped("closures::check_closures(module)")) {
        return;
    }
    # Plain and `shared` function values flowing into each other's slots,
    # once every type is final.
    shared_functions(module, state);
    if (steps.stepped("shared_functions::shared_functions(module)")) {
        return;
    }
    synthesize_function_types(module, state);
    if (steps.stepped("synthesize_function_types(module)")) {
        return;
    }
    # How value structs are used: identity, `const`, changes to copies.
    check_value_structs(module, state);
    if (steps.stepped("crate::value_structs::check(module)")) {
        return;
    }
    # Struct values flowing into trait-typed slots, once every type is
    # final.
    convert_to_traits(module, state);
    if (steps.stepped("convert_to_traits::convert_to_traits(module)")) {
        return;
    }
    # A literal of bytes that are not UTF-8 is not a `String`.
    check_string_bytes(module, state);
    if (steps.stepped("literals::check_string_bytes(module)")) {
        return;
    }
    check_function_types(module, state);
    if (steps.stepped("check_function_types::check_function_types(module)")) {
        return;
    }
    # `as` and `unsafe_cast` convert only what their kind allows.
    check_casts(module, state);
    if (steps.stepped("check_casts::check_casts(module)")) {
        return;
    }
    check_shared_types(module, state);
    if (steps.stepped("check_shared_types::check_shared_types(module)")) {
        return;
    }
    # What `with` blocks over `[Isolated]` guards may do, `[Move]`
    # arguments, and the guards' own rules, once every type is final.
    # Link summaries recorded with a checked unit hold while the joins of
    # their trait calls stay the same; the checked bodies the others need
    # come back from the stash on demand.
    check_confinement(module, state);
    if (steps.stepped("check_confinement::check_confinement(module)")) {
        return;
    }
    # The rest lower bodies, which checked ones have been already.
    stash_bodies(module, state);
    # `with` conditions need the final types of `enter()`.
    lower_with_blocks(module, state);
    if (steps.stepped("lower_with_blocks(module)")) {
        return;
    }
    # Warnings only: uses of deprecated fields, methods and enum cases, by
    # final type; before `lower_matches`, which turns the patterns that
    # name cases into tests.
    check_deprecated_members(module, state);
    if (steps.stepped("check_deprecated_members::check_deprecated_members(module)")) {
        return;
    }
    # `match` arms need the final type of the value matched.
    lower_matches(module, state);
    if (steps.stepped("crate::enums::lower_matches(module)")) {
        return;
    }
    # Struct keys whose `==` and `hash<T>` disagree.
    check_hash_keys(module, state);
    if (steps.stepped("check_hash_keys::check_hash_keys(module)")) {
        return;
    }
    # `[__Reads]` methods of `[__Lazy]` structs, which run on a null `this`.
    check_lazy(module, state);
    if (steps.stepped("check_lazy::check_lazy(module)")) {
        return;
    }
    # `[Export]`ed functions C can call, once every type is final.
    collect_exports(module, state);
    if (steps.stepped("exports::collect_exports(module)")) {
        return;
    }
    # Last, over every body (checked ones are back): which literals can be
    # shared reads the callees' bodies.
    restore_bodies(module, state);
    share_string_literals(module, state);
    if (steps.stepped("static_strings::share_string_literals(module)")) {
        return;
    }
    # A checked build's assertion: no injected construct is left half
    # resolved for code generation to meet.
    var verify = os.environment("PEPC_VERIFY_INJECTED");
    if (verify.is_value() and !verify.value().is_empty) {
        # Not a step of its own: the steps a build names stay the same.
        verify_injected(module, state);
        steps.taken();
    }
}

## Runs step `index` (from 0), and returns the errors it reports.
_step(index: ulong, module: Module, state: PassState): Diagnostic[] {
    match (index) {
        0 => {
            # A struct whose method is checked again has a new body.
            var rechecked = HashSet<String>();
            for (var key in state.rechecked_methods) {
                rechecked.insert(key.split(" ")[1]);
            }
            return _reported(state, apply_platform_filters(module, state.target, rechecked));
        }
        1 => {
            # `[Equatable]` structs get their `==` and `__hash` first, so
            # every later step treats them as declared.
            state.take_errors();
            return _reported(state, derive_equatable(module));
        }
        2 => {
            # Enum names are integer types from here on; closure literals become
            # structs, so they get bodies below. Checked declarations' bodies
            # stay out of the passes. A new compilation unit: no checked struct
            # extended yet, nothing found for it.
            module.extended_checked = HashSet<String>();
            # A struct whose method is checked again is walked as extended.
            for (var key in state.rechecked_methods) {
                var owner = key.split(" ")[1];
                module.extended_checked.insert(owner);
                state.extended_checked.insert(owner);
            }
            module.own_decls = Optional<UnitDecls>.Empty;
            stash_bodies(module, state);
            state.install_enums(module.enums);
            lift_closures(module, state);
            return state.take_errors();
        }
        3 => {
            # Names synthesized from a file are numbered by now, so dropping
            # the cached units' bodies cannot renumber anything.
            strip_bodies(module);
            return state.take_errors();
        }
        4 => {
            resolve_type_aliases(module, state);
            return state.take_errors();
        }
        5 => {
            return _reported(state, synthesize(module, state));
        }
        6 => {
            check_attributes(module, state);
            return state.take_errors();
        }
        7 => {
            expand_module_blocks(module, state);
            return state.take_errors();
        }
        8 => {
            expand(module, state);
            return state.take_errors();
        }
        9 => {
            resolve_enum_cases(module, state);
            return state.take_errors();
        }
        10 => {
            lower_main_arguments(module, state);
            return state.take_errors();
        }
        11 => {
            check_bindings(module, state);
            return state.take_errors();
        }
        12 => {
            check_named_attributes(module, state);
            return state.take_errors();
        }
        13 => {
            check_link_attributes(module, state);
            return state.take_errors();
        }
        14 => {
            bind_calls(module, state);
            return state.take_errors();
        }
        15 => {
            synthesize_function_types(module, state);
            return state.take_errors();
        }
        16 => {
            resolve_literals(module);
            return state.take_errors();
        }
        17 => {
            name_overloads(module, state);
            return state.take_errors();
        }
        18 => {
            resolve_injected(module);
            return state.take_errors();
        }
        19 => {
            gather_generics(module, state);
            return state.take_errors();
        }
        20 => {
            resolve_implicit_types(module, state);
            return state.take_errors();
        }
        21 => {
            check_tries(module, state);
            return state.take_errors();
        }
        22 => {
            # Resolve as much as possible.
            resolve_resolvables(module, false, state);
            return state.take_errors();
        }
        23 => {
            # Apply generic and concrete extensions.
            apply_extensions(module, state, defer = true);
            return state.take_errors();
        }
        24 => {
            # Parameter names against the traits', between the steps; then
            # the values interpolated outside generic code.
            check_parameter_names(module, state);
            check_interpolations(module, state);
            return state.take_errors();
        }
        25 => {
            # Generic constraints, before any specialization clones a body.
            check_constraints(module, state);
            return state.take_errors();
        }
        26 => {
            # Constrained generic code, in the generic itself.
            check_bounds(module, state);
            return state.take_errors();
        }
        27 => {
            # The template stage ends here: every specialization is cloned
            # from the generic bases as they are now.
            module.templates = freeze_templates(module);
            specialize_structs(module, state);
            return state.take_errors();
        }
        28 => {
            specialize_functions(module, state);
            return state.take_errors();
        }
        29 => {
            # `a..b` over a non-integer, before the runtime's `Range<T>`
            # fails inside.
            check_ranges(module, state);
            return state.take_errors();
        }
        30 => {
            specialize_methods(module, state);
            return state.take_errors();
        }
        31 => {
            # The specializations' `static` blocks, with lowered strings.
            expand(module, state, true);
            return state.take_errors();
        }
        32 => {
            synthesize_function_types(module, state);
            return state.take_errors();
        }
        33 => {
            convert_intrinsics(module, state);
            return state.take_errors();
        }
        34 => {
            # Resolve what remains.
            resolve_resolvables(module, false, state);
            return state.take_errors();
        }
        35 => {
            # Specialized extensions.
            apply_extensions(module, state, defer = true);
            return state.take_errors();
        }
        36 => {
            convert_member_refs(module, state);
            return state.take_errors();
        }
        37 => {
            resolve_implicit_types(module, state);
            return state.take_errors();
        }
        38 => {
            resolve_operators(module, state);
            return state.take_errors();
        }
        else => {
            return state.take_errors();
        }
    }
}

# `error`, a step's own, as reported with any the step's passes reported.
_reported(state: PassState, error: Diagnostic?): Diagnostic[] {
    if (error is Value(found)) {
        state.report(found);
    }
    return state.take_errors();
}

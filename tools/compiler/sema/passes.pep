## The sema passes, in the order the Rust compiler runs them
## (`pepper_sema::checked::run_steps`): one step per pass run, so each can
## be compared with `pep-build --emit-model-step N`, the Rust model after
## its first N steps. The passes ported so far are the first
## `PORTED_STEPS`, then the specialization loop, whose steps a program
## runs as many rounds of as it needs.

import [Diagnostic, SourceText] from compiler.diagnostic;
import [Target] from compiler.link;
import [apply_extensions, check_parameter_names] from "apply_extensions";
import [check_unbound, record_argument_names] from "argument_names";
import [check_assignment_targets] from "assignment_targets";
import [check_bindings] from "bindings";
import [check_casts] from "casts";
import [check_bounds] from "check_bounds";
import [check_tries] from "check_tries";
import [check_closures, lift_closures] from "closures";
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
import [with_instantiation] from "instantiation";
import [check_interpolations] from "interpolation";
import [convert_string_literals, resolve_literals] from "literals";
import [lower_matches] from "matches";
import [Module] from "model";
import [bind_calls, check_link_attributes, check_named_attributes] from "named_arguments";
import [check_overloads] from "overload_checks";
import [has_overloads] from "overload_select";
import [name_overloads] from "overloads";
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
import [PassState] from "state";
import [check_attributes, expand, expand_module_blocks, remove_from_generic_code] from "static_blocks";
import [share_string_literals] from "static_strings";
import [strip_bodies] from "strip_bodies";
import [synthesize] from "synthesize";
import [resolve_type_aliases] from "type_aliases";
import [check_type_arguments] from "type_argument_checks";
import [check_value_structs] from "value_structs";
import [lower_with_blocks] from "with_blocks";
import [check_withheld] from "withheld";

## How many of the Rust compiler's steps come before the specialization
## loop.
export const PORTED_STEPS: ulong = 39;

## Runs the first `limit` steps of the passes over `module` (all those
## ported, through the specialization loop, when `limit` is larger),
## stopping at the first that reports an error.
##
## @param module the model `merge` built, changed in place
## @param target the compile target
## @param limit how many steps to run
## @param sources the program's files' text, by file index
## @returns how many steps ran, or the error a step reported
export run_steps(
    module: Module, target: Target, limit: ulong, sources: SourceText[] = Array<SourceText>()
): Result<ulong, Diagnostic> {
    var state = PassState(target);
    state.sources = sources;
    return run_steps_with(module, state, limit);
}

## Runs every step of the passes over `module`, for code generation.
##
## @param module the model `merge` built, changed in place
## @param target the compile target
## @param sources the program's files' text, by file index
## @returns the passes' state, which code generation reads, or the error a step reported
export run_passes(module: Module, target: Target, sources: SourceText[]): Result<PassState, Diagnostic> {
    var state = PassState(target);
    state.sources = sources;
    var ran = run_steps_with(module, state, 0xffffffffffffffff);
    if (ran.is_err()) {
        return Result<PassState, Diagnostic>.Err(ran.error());
    }
    return Result<PassState, Diagnostic>.Ok(state);
}

## `run_steps` with the passes' state given.
##
## @param module the model, changed in place
## @param state the passes' state
## @param limit how many steps to run
## @returns how many steps ran, or the error a step reported
export run_steps_with(module: Module, state: PassState, limit: ulong): Result<ulong, Diagnostic> {
    var steps = _Steps(limit, state);
    while (steps.ran < limit and steps.ran < PORTED_STEPS) {
        var error = _step(steps.ran, module, state);
        if (error.is_value()) {
            steps.error = error;
            break;
        }
        steps.ran += 1;
    }
    if (!steps.error.is_value() and steps.ran == PORTED_STEPS and steps.ran < limit) {
        _specialization_loop(module, state, steps);
        if (!steps.error.is_value() and steps.ran < limit) {
            _after_specializing(module, state, steps);
        }
    }
    if (steps.error.is_value()) {
        # An error in a specialization notes the uses that asked for it.
        return Result<ulong, Diagnostic>.Err(with_instantiation(module, steps.error.value()));
    }
    return Result<ulong, Diagnostic>.Ok(steps.ran);
}

## Counts the steps as `checked::run_steps`' `step!` does, and stops at the
## first error or at the limit.
struct _Steps {
    var ran: ulong = 0;
    var limit: ulong;
    var state: PassState;
    var error: Diagnostic? = Optional<Diagnostic>.Empty;

    construct(limit: ulong, state: PassState) {
        this.limit = limit;
        this.state = state;
    }

    ## After a step: whether to stop, at its error or at the limit.
    stepped(): bool {
        if (taken()) {
            return true;
        }
        ran += 1;
        return ran >= limit;
    }

    ## Whether a pass that is not a step of its own reported an error.
    taken(): bool {
        error = state.take_error();
        return error.is_value();
    }
}

## The second pass: specializing can expose further generic uses, so the
## specializations repeat until no new one appears, as in
## `checked::run_steps`.
_specialization_loop(module: Module, state: PassState, steps: _Steps) {
    for (var round in 0..4096) {
        var structs = module.structs.count;
        var functions = module.functions.count;
        gather_generics(module);
        if (steps.stepped()) {
            return;
        }
        check_specializations(module, state);
        if (steps.stepped()) {
            return;
        }
        specialize_structs(module, state);
        if (steps.stepped()) {
            return;
        }
        specialize_functions(module, state);
        if (steps.stepped()) {
            return;
        }
        check_ranges(module, state);
        if (steps.stepped()) {
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
            if (steps.stepped()) {
                return;
            }
        }
        var methods_added = specialize_methods(module, state);
        var methods_expanded = expand(module, state, true);
        var copies_added = synthesize_copies(module, state);
        if (steps.taken()) {
            return;
        }
        if (module.structs.count == structs
            and module.functions.count == functions
            and !methods_added
            and !copies_added
            and !expanded
            and !methods_expanded) {
            # Done only when gathering asks for nothing new.
            var struct_specs = module.struct_specs.count;
            var func_specs = module.func_specs.count;
            gather_generics(module);
            if (steps.stepped()) {
                return;
            }
            if (module.struct_specs.count == struct_specs and module.func_specs.count == func_specs) {
                return;
            }
        }
    }
}

## The steps once every specialization is made, as far as they are
## ported: generic code's `static` blocks go, then the checks and
## conversions repeat over the specialized code.
_after_specializing(module: Module, state: PassState, steps: _Steps) {
    remove_from_generic_code(module);
    check_interpolations(module, state);
    if (steps.stepped()) {
        return;
    }
    # A call of a member a constrained extension withheld.
    check_withheld(module, state);
    if (steps.stepped()) {
        return;
    }
    check_simd_shapes(module, state);
    if (steps.stepped()) {
        return;
    }
    convert_intrinsics(module, state);
    if (steps.stepped()) {
        return;
    }
    resolve_resolvables(module, false, state);
    if (steps.stepped()) {
        return;
    }
    # The extensions of the specializations made in the loop.
    apply_extensions(module, state);
    if (steps.stepped()) {
        return;
    }
    expand(module, state, true);
    if (steps.stepped()) {
        return;
    }
    convert_member_refs(module, state);
    if (steps.stepped()) {
        return;
    }
    synthesize_function_types(module, state);
    if (steps.stepped()) {
        return;
    }
    # Methods, structs and specializations used as values become closures.
    reference_functions(module, state);
    if (steps.stepped()) {
        return;
    }
    # Destructors release their struct fields.
    release_field_refs(module, state);
    if (steps.stepped()) {
        return;
    }
    # Implicit types once more, with overloads settled by how many
    # arguments they take.
    state.settle_overloads_by_arity = true;
    resolve_implicit_types(module, state);
    state.settle_overloads_by_arity = false;
    if (steps.stepped()) {
        return;
    }
    check_tries(module, state);
    if (steps.stepped()) {
        return;
    }
    # Named arguments no binding took.
    check_unbound(module, state);
    if (steps.stepped()) {
        return;
    }
    # The parameter names of literal arguments, for inlay hints.
    record_argument_names(module, state);
    check_type_arguments(module, state);
    if (steps.stepped()) {
        return;
    }
    check_overloads(module, state);
    if (steps.stepped()) {
        return;
    }
    # Once implicit types are resolved, operator overloading may exist.
    resolve_operators(module, state);
    if (steps.stepped()) {
        return;
    }
    # A call left as an assignment's target, which nothing can store into.
    check_assignment_targets(module, state);
    if (steps.stepped()) {
        return;
    }
    # A struct value in a boolean context needs its own `!!`.
    check_conditions(module, state);
    if (steps.stepped()) {
        return;
    }
    # Undeclared names and calls are reported here.
    resolve_resolvables(module, true, state);
    if (steps.stepped()) {
        return;
    }
    # Destructures read their tuple; labels become positions.
    lower_destructures(module, state);
    if (steps.stepped()) {
        return;
    }
    # Types inferred by the final resolve (`var f = square;`).
    synthesize_function_types(module, state);
    if (steps.stepped()) {
        return;
    }
    # Closure types nothing inferred must be written.
    check_closures(module, state);
    if (steps.stepped()) {
        return;
    }
    # Plain and `shared` function values flowing into each other's slots,
    # once every type is final.
    shared_functions(module, state);
    if (steps.stepped()) {
        return;
    }
    synthesize_function_types(module, state);
    if (steps.stepped()) {
        return;
    }
    # How value structs are used: identity, `const`, changes to copies.
    check_value_structs(module, state);
    if (steps.stepped()) {
        return;
    }
    # Struct values flowing into trait-typed slots, once every type is
    # final.
    convert_to_traits(module, state);
    if (steps.stepped()) {
        return;
    }
    check_function_types(module, state);
    if (steps.stepped()) {
        return;
    }
    # `as` and `unsafe_cast` convert only what their kind allows.
    check_casts(module, state);
    if (steps.stepped()) {
        return;
    }
    check_shared_types(module, state);
    if (steps.stepped()) {
        return;
    }
    # What `with` blocks over `[Isolated]` guards may do, `[Move]`
    # arguments, and the guards' own rules, once every type is final.
    check_confinement(module, state);
    if (steps.stepped()) {
        return;
    }
    # `with` conditions need the final types of `enter()`.
    lower_with_blocks(module, state);
    if (steps.stepped()) {
        return;
    }
    # `match` arms need the final type of the value matched.
    lower_matches(module, state);
    if (steps.stepped()) {
        return;
    }
    # Warnings only: uses of deprecated fields and methods, by final type.
    check_deprecated_members(module, state);
    if (steps.stepped()) {
        return;
    }
    # Struct keys whose `==` and `hash<T>` disagree.
    check_hash_keys(module, state);
    if (steps.stepped()) {
        return;
    }
    # `[Export]`ed functions C can call, once every type is final.
    collect_exports(module, state);
    if (steps.stepped()) {
        return;
    }
    # Last, over every body: which literals can be shared reads the
    # callees' bodies.
    share_string_literals(module, state);
    if (steps.stepped()) {
        return;
    }
}

## Runs step `index` (from 0), and returns the error it reports.
_step(index: ulong, module: Module, state: PassState): Diagnostic? {
    match (index) {
        0 => {
            return apply_platform_filters(module, state.target);
        }
        1 => {
            # `[Equatable]` structs get their `==` and `__hash` first, so
            # every later step treats them as declared.
            state.take_error();
            return derive_equatable(module);
        }
        2 => {
            # Enum names are integer types from here on; closure literals
            # become structs, so they get bodies below.
            state.install_enums(module.enums);
            lift_closures(module, state);
            return state.take_error();
        }
        3 => {
            # Names synthesized from a file are numbered by now, so dropping
            # the cached units' bodies cannot renumber anything.
            strip_bodies(module);
            return Optional<Diagnostic>.Empty;
        }
        4 => {
            resolve_type_aliases(module, state);
            return state.take_error();
        }
        5 => {
            return synthesize(module, state);
        }
        6 => {
            check_attributes(module, state);
            return state.take_error();
        }
        7 => {
            expand_module_blocks(module, state);
            return state.take_error();
        }
        8 => {
            expand(module, state);
            return state.take_error();
        }
        9 => {
            resolve_enum_cases(module, state);
            return state.take_error();
        }
        10 => {
            lower_main_arguments(module, state);
            return state.take_error();
        }
        11 => {
            check_bindings(module, state);
            return state.take_error();
        }
        12 => {
            check_named_attributes(module, state);
            return state.take_error();
        }
        13 => {
            check_link_attributes(module, state);
            return state.take_error();
        }
        14 => {
            bind_calls(module, state);
            return state.take_error();
        }
        15 => {
            synthesize_function_types(module, state);
            return state.take_error();
        }
        16 => {
            resolve_literals(module);
            return Optional<Diagnostic>.Empty;
        }
        17 => {
            name_overloads(module, state);
            return state.take_error();
        }
        18 => {
            convert_string_literals(module);
            return Optional<Diagnostic>.Empty;
        }
        19 => {
            gather_generics(module);
            return Optional<Diagnostic>.Empty;
        }
        20 => {
            resolve_implicit_types(module, state);
            return state.take_error();
        }
        21 => {
            check_tries(module, state);
            return state.take_error();
        }
        22 => {
            # Resolve as much as possible.
            resolve_resolvables(module, false, state);
            return state.take_error();
        }
        23 => {
            # Apply generic and concrete extensions.
            apply_extensions(module, state);
            return state.take_error();
        }
        24 => {
            # Parameter names against the traits', between the steps; then
            # the values interpolated outside generic code.
            check_parameter_names(module, state);
            check_interpolations(module, state);
            return state.take_error();
        }
        25 => {
            # Generic constraints, before any specialization clones a body.
            check_constraints(module, state);
            return state.take_error();
        }
        26 => {
            # Constrained generic code, in the generic itself.
            check_bounds(module, state);
            return state.take_error();
        }
        27 => {
            # The template stage ends here: every specialization is cloned
            # from the generic bases as they are now.
            module.templates = freeze_templates(module);
            specialize_structs(module, state);
            return state.take_error();
        }
        28 => {
            specialize_functions(module, state);
            return state.take_error();
        }
        29 => {
            # `a..b` over a non-integer, before the runtime's `Range<T>`
            # fails inside.
            check_ranges(module, state);
            return state.take_error();
        }
        30 => {
            specialize_methods(module, state);
            return state.take_error();
        }
        31 => {
            # The specializations' `static` blocks, with lowered strings.
            expand(module, state, true);
            return state.take_error();
        }
        32 => {
            synthesize_function_types(module, state);
            return state.take_error();
        }
        33 => {
            convert_intrinsics(module, state);
            return state.take_error();
        }
        34 => {
            # Resolve what remains.
            resolve_resolvables(module, false, state);
            return state.take_error();
        }
        35 => {
            # Specialized extensions.
            apply_extensions(module, state);
            return state.take_error();
        }
        36 => {
            convert_member_refs(module, state);
            return state.take_error();
        }
        37 => {
            resolve_implicit_types(module, state);
            return state.take_error();
        }
        38 => {
            resolve_operators(module, state);
            return state.take_error();
        }
        else => {
            return Optional<Diagnostic>.Empty;
        }
    }
}

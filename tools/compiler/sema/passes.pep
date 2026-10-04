## The sema passes, in the order the Rust compiler runs them
## (`pepper_sema::checked::run_steps`): one step per pass run, so each can
## be compared with `pep-build --emit-model-step N`, the Rust model after
## its first N steps. The passes ported so far are the first
## `PORTED_STEPS`.

import [Diagnostic, SourceText] from compiler.diagnostic;
import [Target] from compiler.link;
import [apply_extensions, check_parameter_names] from "apply_extensions";
import [check_bindings] from "bindings";
import [check_bounds] from "check_bounds";
import [check_tries] from "check_tries";
import [lift_closures] from "closures";
import [check_constraints] from "constraints";
import [lower_main_arguments] from "entry_point";
import [resolve_enum_cases] from "enums";
import [derive_equatable] from "equatable";
import [synthesize_function_types] from "function_types";
import [specialize_methods] from "generic_methods";
import [gather_generics] from "generics";
import [check_interpolations] from "interpolation";
import [convert_string_literals, resolve_literals] from "literals";
import [Module] from "model";
import [bind_calls, check_link_attributes, check_named_attributes] from "named_arguments";
import [name_overloads] from "overloads";
import [apply_platform_filters] from "platform";
import [check_ranges] from "ranges";
import [resolve_implicit_types] from "resolve_implicit_types";
import [resolve_resolvables] from "resolve_resolvables";
import [specialize_functions] from "specialize_functions";
import [freeze_templates, specialize_structs] from "specialize_structs";
import [PassState] from "state";
import [check_attributes, expand, expand_module_blocks] from "static_blocks";
import [strip_bodies] from "strip_bodies";
import [synthesize] from "synthesize";
import [resolve_type_aliases] from "type_aliases";

## How many of the Rust compiler's steps the Pepper passes run.
export const PORTED_STEPS: ulong = 31;

## Runs the first `limit` steps of the passes over `module` (all those
## ported when `limit` is larger), stopping at the first that reports an
## error.
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
    ulong ran = 0;
    while (ran < limit and ran < PORTED_STEPS) {
        var error = _step(ran, module, state);
        if (error.is_value()) {
            return Result<ulong, Diagnostic>.Err(error.value());
        }
        ran += 1;
    }
    return Result<ulong, Diagnostic>.Ok(ran);
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
        else => {
            return Optional<Diagnostic>.Empty;
        }
    }
}

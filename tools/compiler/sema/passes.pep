## The sema passes, in the order the Rust compiler runs them
## (`pepper_sema::checked::run_steps`): one step per pass run, so each can
## be compared with `pep-build --emit-model-step N`, the Rust model after
## its first N steps. The passes ported so far are the first
## `PORTED_STEPS`.

import [Diagnostic] from compiler.diagnostic;
import [Target] from compiler.link;
import [lift_closures] from "closures";
import [derive_equatable] from "equatable";
import [Module] from "model";
import [apply_platform_filters] from "platform";
import [PassState] from "state";
import [strip_bodies] from "strip_bodies";
import [synthesize] from "synthesize";
import [resolve_type_aliases] from "type_aliases";

## How many of the Rust compiler's steps the Pepper passes run.
export const PORTED_STEPS: ulong = 6;

## Runs the first `limit` steps of the passes over `module` (all those
## ported when `limit` is larger), stopping at the first that reports an
## error.
##
## @param module the model `merge` built, changed in place
## @param target the compile target
## @param limit how many steps to run
## @returns how many steps ran, or the error a step reported
export run_steps(module: Module, target: Target, limit: ulong): Result<ulong, Diagnostic> {
    var state = PassState(target);
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
        else => {
            return Optional<Diagnostic>.Empty;
        }
    }
}

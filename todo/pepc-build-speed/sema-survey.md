# pepc sema survey for separate compilation (10-05, #225 thread)

Classification of each sema step: (a) local to a declaration/body, (b) needs other files' declarations/signatures, (c) needs other files' bodies or a whole-program fixpoint.

## Non-modular facts that must change first
- Method overload naming: an extension in file B adding `get(int)` to struct X renames A's `get` to `get$1` (overloads.pep:395-416, apply_extensions.pep:47-75). A's symbols depend on a downstream file. Fix: number per declaring file or mangle by signature.
- static_strings `_indirectly_called` (static_strings.pep:390-432): a use-as-value or trait slot anywhere changes `caller_copies` of the callee. Fix: thunk in the using unit.
- `state.next_subject` (named_arguments.pep:866): program-wide counter; make per body.
- Externs first-wins by C name in file order.
- `Loc.file` is a program-wide index; persisted data must key by namespace/path.
- resolve_implicit_types caps at 8 rounds whole-program; per-unit runs could accept longer chains.
- Concrete overrides change linkonce_odr instantiation copies everywhere: orphan rule fixes this.

## (c) passes and what an interface carries
- expand_module_blocks: computed static constants.
- bind_calls: default-argument expressions plus stable symbols for private helpers they name.
- resolve_implicit_types: final inferred signatures (functions, globals, fields), overload sets with visibility.
- name_overloads/apply_extensions: per struct, the method set including applied extensions.
- specialize_*: frozen templates (post-step-26), lifted closure structs, generic methods/extensions, private helper declarations with external symbols, full layouts, summaries, override table.
- check_confinement: per-function link summaries (already has `_recorded` seeds, confinement.pep:721-760).
- share_string_literals: `|s=` facts in summaries.

## Already ported from Rust phase 2b
strip_bodies.pep, confinement record/read summaries, static_strings `_recorded_facts`, `stripped` honored in function_references/resolve_implicit_types/exports. Missing: driver never sets cached_files/record_summaries, no interface hash (position-free printer), no summaries store, no codegen unit filter, no --verify-cache, no model deserializer (433 to_json, no from_json).

## Recommended order
1. Body skipping in pepc (interface hash, recorded summaries, cached_files, codegen unit filter, --verify-cache).
2. Remove the non-modular naming/ABI facts above.
3. Model serialization with file re-keying; port the checked runtime (crates/pepper-sema/src/checked.rs:226-363).
4. Check units in topological order in one process, each on its dependencies' checked modules.
5. Separate processes reading serialized checked modules; shrink to a real interface.

Critical files: sema/passes.pep, sema/model.pep, driver/build.pep, sema/overloads.pep, sema/apply_extensions.pep, sema/static_strings.pep.

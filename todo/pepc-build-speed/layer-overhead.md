# Per-layer overhead (#225, 10-07)

Per-file units (plan step 4) mean ~100+ layers instead of 12, so every cost a
layer pays in proportion to the *whole* module so far, rather than to its own
files, multiplies. Measured on Linux (4 CPUs), self-build, pepc from main
d57862e4, edit to `main.pep` only: 12 layers load, one (`main`, 357 lines) is
checked.

| Build phase | Time |
|---|---|
| load 12 layer records | 3.5 s |
| check layer `main` (357 lines) | 10.7 s |

Whole-run profile (`perf record -F 499 --call-graph dwarf`), inclusive %:

| Where | % | What scales with the module |
|---|---|---|
| `run_steps_with` (layer `main`) | 46.5 | passes walk or rebuild tables over every declaration |
| `resolve_implicit_types` | 10.9 | `_bind_values` 2.8, `used_trait_types`/`trait_types_of` 3.5, `_ImplicitTables` 2.1, `sync_closures` 2.3 |
| parse + link of every file | 12.5 | parse 6.0, `check_visibility` 2.5, `compute_overrides` 2.8, `_visible_types` 2.5 |
| codegen, whole module | 11.7 | `codegen_struct` copies every method (`FunctionDef.copy` 4.0) |
| `load_checked` | 7.2 | reads the records (deserialize) |
| `share_string_literals` | 4.1 | `_Literals.seed` walks checked bodies |
| `_base_params` (`check_function_types`) | 4.0 | |
| `StructTable` | 4.0 | rebuilt per pass that needs it |
| `Overloads._build` | 3.1 | |
| `check_confinement` + `drop_stale_summaries` | 5.7 | `_dispatch_owners` 1.9 |
| `check_value_structs` (`_mutating_methods`) | 2.5 | |
| `check_casts` | 2.1 | |
| `gather_generics` | 1.7 | |

Store (delta write) and interface hash, also whole-module, add 0.4-4 s per
layer on top (#753).

## Plan
Each step measured on the `main.pep` edit (layer `main` time) and on cold:
1. Passes skip checked declarations: iterate only the unchecked ones, and
   keep derived tables (StructTable, overload sets, trait types,
   conformances) for checked declarations in the record instead of
   rebuilding them.
2. Front end only for files that changed: parse, link and visibility for
   the dirty files; checked files come from records.
3. Codegen only for the units whose objects miss.
4. Store and interface hash proportional to what the layer added.

## Done (step 1, first pass)
Self-build of pepc, `main.pep` edit, pepc built from each commit:

| | base (d57862e4) | after |
|---|---|---|
| layer `main` | 10.53 s | 7.55 s |
| edit build | 22.56 s | 18.78 s |
| cold build | 495.7 s | 445.6 s |

- `_Bases` replaces the quadratic generic-base scans in
  `check_function_types` and `check_casts`.
- One `StructTable` of the checked declarations per layer, which each
  pass's table falls back to; it and the checked trait-types snapshot are
  rebuilt when the checked structs' field or method counts change.
- `drop_stale_summaries` only recomputes summaries whose dispatches name a
  trait of a struct the layer adds or changes.
- `check_confinement` decodes checked summaries on first use.
- `share_string_literals` takes a checked callee's recorded `|s=` facts.
- `codegen_struct` copies a method only when it generates its body.
- `function_value_search` builds `Overloads` only when a site needs it.

Checked: every layer's interface hash (`PEPC_TRACE_INTERFACE`) of the
self-build equals the base compiler's; `passes_test` passes; the stage-2
pepc builds and runs all docs examples like main's.

Next, by the layer `main` profile: `resolve_implicit_types` step 20
(0.97 s; `_ImplicitTables`, `Overloads._build`, `sync_closures`),
`share_string_literals` (0.64 s), `check_value_structs`
(`_mutating_methods` walks checked bodies, 0.55 s), then steps 2-4 above
(`load_checked` reading checked bodies, parse/link of every file, codegen).

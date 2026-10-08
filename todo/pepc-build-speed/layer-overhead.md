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

## Done (second pass)
Same source tree, `main.pep` edit: layer `main` 7.60 → 7.10 s, edit build
18.82 → 17.90 s, cold 456.9 → 427.4 s (main at 87590ab4 vs this pass).
Checked structs' method lists and arities memoized in `ImplicitMemo`; no
array per declaration in the closure-site walk; `visible_names` (link)
re-walks a file only when the exports it reads change.

Edit build now: front end (parse + link of every file) ~3.5 s, checked
records 2.4 s (half of it decoding bodies), layer `main` 7.1 s, codegen
2.2 s, objects 0.3-1.1 s, `ld` 1.5 s.

## Done: link bodies only for the layers checked
`main.pep` edit build 17.90 → 16.97 s (main 18.82 s): linking splits into
binding and rewriting (`link.PendingLink`); a build links and checks
(visibility, deprecation) the bodies of only the files from the first
layer it checks on (182 ms). A layer whose files warn is not stored.

## Next: front end only for the files that changed
The files of layers below the first one whose files changed are unchanged,
and so is everything they import: their linking, visibility and parse
checks find what they found when the layer was checked. Plan:
1. Parse every file's declarations, skipping function bodies (brace
   matching on the tokens), enough for imports and layering.
2. Find the cached prefix of layers (their records exist for the key
   chain).
3. Parse the remaining files in full and link the program with the
   prefix's bodies left out; `check_visibility` only over those files.
Steps 2-3 are done for linking (above). Left: parsing declarations only
(~0.6 s), which reports a syntax error in a body from `driver.build`
instead of `load_program`; how pepc prints that has to stay the same.
Left as is: `check_value_structs` walks the checked value structs' bodies
on each layer; keeping their facts in the record needs a field on
`Checked`, which comes from the Rust model.

## Done (third pass)
On the 4-core Xeon the session moved to, same tree, `main.pep` edit:
main before #761 12.13 s, this pass 8.08 s (layer `main` 4.75 → 3.51 s,
codegen 1.65 → 0.84 s, cold 303 → 289 s).
- codegen: held-back unowned bodies by place; a waiting method is copied
  to be renamed only when generated (was 4.7% of the edit build).
- `Overloads` memoizes checked structs' members; `check_value_structs`
  takes checked value structs' mutating methods from the record
  (`VALUE_FACTS` in `Checked.summaries`), 516 → 79 ms.
- `share_string_literals` skips checked structs in its indirect scan.
- Declarations-only parsing for the files of layers loaded from the cache.

Checked: docs examples byte-identical to main's pepc's builds (same output
name and cache path); the self-built pepc identical but for the paths it
embeds and the build ID; `passes_test`, `build_cache_test` pass.

Left: `Checked` comes from `crates/pepper-sema` through
`scripts/gen-sema-model.py`; the generators should read `model.pep`.

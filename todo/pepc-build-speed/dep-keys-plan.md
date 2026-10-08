# Layers keyed on their dependencies (#225 plan step 3c)

## Why

Layers form one chain today: the runtime, then each unit's layer in a
topological order. A layer's key hashes its files and the interface of
every layer before it in the chain, and its record is a delta on the
module the layer before left. So an interface change in one layer
rechecks every layer after it in the chain, related or not.

With module-sized units (12 layers for pepc) that costs one or two
layers. With per-file units (plan step 4, about 100 layers for pepc) an
interface change in a file would recheck on average half the program.
Step 4 only pays off once a layer depends on what it reads, not on
where it sits in the chain.

## What changes

1. **Dependencies per layer.** `layers()` already computes what each
   unit reads: imports, module siblings and the extensions it sees. The
   layer keeps the transitive closure of the layers it reads (the
   runtime always).
2. **Own interface hash.** Each layer's record carries the interface
   hash of what that layer added, not of the whole module so far.
3. **Key.** A layer's key hashes its files and, in a fixed order, the
   own-interface hashes of the layers in its closure. A change outside
   the closure keeps the key.
4. **Checked on its closure only.** A layer is checked on a module that
   holds exactly its closure's layers. Otherwise its record would depend
   on unrelated layers loaded before it in the chain: specializations
   they made, synthesized-name counters, overload sets that span
   modules.
5. **Records merged on load.** Records stop being positional deltas on
   the chain. Each holds what its layer added, with references to its
   closure's elements by content hash. That is the hash the delta writer
   already uses to find them (`DeltaBase._places`). Loading a layer's
   closure applies its records in topological order onto an empty
   module, resolving references by hash.

## What has to become per layer

- **Specializations.** Two unrelated layers may both instantiate
  `Array<Foo>` for a shared `Foo`. Each record keeps its own copy. A
  merge keeps the first and drops identical ones (same name and
  fingerprint). Codegen already emits specializations as linkonce_odr.
- **Synthesized names** (closures, lambdas, literals): a per-layer prefix
  and counter (plan design item 5), so they stay the same whatever else
  is loaded.
- **Overload sets and other module maps** (`overload_sets`,
  `caller_copies`, summaries): merged by key. Entries from different
  layers can't collide, because overload sets are signature-named
  (#759).
- **Module-ordered lists** that passes read with first-wins rules:
  merged in topological order, which is the order the closure is
  checked in.

## Order of PRs

1. Per-layer dependency closure and own-interface hashes, computed and
   traced (`PEPC_TRACE_INTERFACE`) but not yet used in keys. No
   behaviour change.
2. Synthesized names with a per-layer prefix. Generated code changes,
   so verify against `--no-cache` builds: the 265 programs, four
   expected diffs.
3. Records that refer to their base by content hash, applied in order
   onto a merged module. The chain build still loads everything before
   the layer; verify the delta round trip (`PEPC_VERIFY_DELTA`) and the
   byte-identical stage 2.
4. Check each layer on its closure only, and key it on the closure's
   own interfaces. Verify with build_cache_test plus new tests:
   - an interface change in a layer that another doesn't read keeps
     that layer's record;
   - two layers that both specialize `Array<Foo>` merge.

## Risks

- Passes that read module-wide state can give different results on a
  closure than on the whole chain. Step 4 is checked against `--no-cache`
  builds of every docs example and of pepc itself, built three ways:
  layered, `--no-cache`, and stage 2.
- Record size: a layer that references many elements of its closure
  pays one hash per reference, instead of a place index. Measure it with
  `PEPC_RECORD_STATS`.

## How each module field changes across layers (measured 10-08)

From a cold pepc self-build, with the delta writer counting, per layer, the
base elements that moved, the new elements inserted inside the base's list,
and the fields written whole:

| Field | Across a layer | Merge |
|---|---|---|
| `functions`, `traits`, `extensions`, `static_blocks`, `enums`, `struct_specs`, `func_specs`, `withheld`, `properties`, `constrained_aliases`, `templates` | appended | concatenate in topological order |
| `structs` | appended; 1-5 base structs patched per layer (methods, specializations added) | concatenate; patches merge by struct name |
| `globals` | sorted by the program's initialization order (`build_on`) | concatenate, then the same stable sort |
| `externs` | stable-sorted by file (`build_on`) | concatenate, then the same sort |
| `trait_types` | rebuilt sorted by name (`convert_to_traits`) | union by name, sorted |
| `conversions` | rebuilt by `convert_to_traits`; 1-12 change per layer | union; changed ones are the layer's |
| `type_uses`, `use_contexts` | appended per file with index links (`_join`) | concatenate, offsetting `context` |
| `imports` | appended per file, some move | concatenate |
| `argument_names` | rebuilt from scratch, sorted by place; drops entries | the layer's own, merged by place |
| `type_aliases`, `recorded_summaries`, `summaries_to_record` | replaced by `resume_checked` | as now |
| sets and maps | only gain entries | union; a key two layers both change is a conflict to detect |

## Status (10-08)

- PR 1 (#772): closures and own interfaces, traced.
- PR 2 (#773): records hold a layer's new elements and their places.
- PR 3 (this one): each layer is keyed on its files and its closure's own
  interfaces, checked on its closure's records merged, and loaded the same
  way. Merging (`RecordIn.merging`) puts each record's new elements after
  the base's; a struct or function the layer changed is found by name; a
  list that does not keep the base's order (a few structs' constructors)
  is written whole and replaces the base's; `conversions` and
  `argument_names` are each layer's own. `settle_merged` then sorts
  externs by file and trait types by name, keeps one copy of a
  specialization two layers both made, and marks every extension applied;
  the driver sorts globals by their files' initialization order.

Known limits, for per-file units:
- A whole list replaces the base's: two layers that both rewrite the same
  struct's constructors keep the later one's.
- Each checked layer merges its closure's records again from bytes:
  O(closure) reads per layer. With ~100 per-file layers this needs a cache
  of merged modules (copy on check).
- Each checked layer indexes its merged base for its delta (cold self-build
  9.1 s in all, structs' member lists 3.9 s of it): it grows with the
  closure, so per-file units want each record's element hashes kept.
- A layer's own interface is what its delta adds, changes or drops
  (`DeltaBase.own`), kept beside its record (`.own`), so keys need no
  record read and no listing of the module before and after.

# Canonical specialization, and a cached checked runtime

Status: proposed (2026-09-30), option C of the runtime-reuse decision: B
(skip sema when nothing changed) first, then this.

## 1. Goal

Sema checks the runtime again for every program. A warm `hello` spends 84
percent of its compile in sema, almost all of it on runtime code: by
expression count, 59 percent is the runtime's own specializations
(`Array<char>`, `HashMap<String, int>`), 30 percent generic bases, 11
percent plain declarations (2b already skips plain bodies).

The goal is to check the runtime once, keep the result (on disk for the
CLI, in memory for the language server and the JIT test harnesses), and
check a program against it: only the program's own declarations and the
specializations it adds go through the passes.

## 2. Why the checked runtime cannot be reused today

A specialization's content depends on **when** it is created, not only on
its generic and type arguments:

- `specialize_structs`, `specialize_functions` and `specialize_methods`
  clone the base **as it is at that moment**. Bases created in phase 1
  (`transform_pass`, line ~96) have been through fewer passes than those
  created in a fixpoint round (~116), which have also been through
  `convert_intrinsics`, `convert_member_refs`, another
  `resolve_implicit_types`, and, for generic free functions,
  `resolve_operators`. Which round a user type's `Array<Point>` appears in
  depends on the whole program.
- Several passes are not idempotent, so a clone of a finished base cannot
  simply rejoin the pipeline: `release_field_refs` appends releases to every
  destructor, `struct_body::finish` wraps constructors and pushes the
  refcount methods again, and `resolve_enum_cases` adds the built-in enum
  functions on each run.
- Names are numbered by program-wide counters in creation order:
  `resolve_operators`' `INDEX_TEMPORARIES` (`_idx_tmp_N`), and the per-file
  closure counter that `function_references` and `shared_functions`
  continue after `lift_closures`, in the order specializations sit in
  `module.structs` and `module.functions`.
- Some state is keyed by `Loc`, which a base shares with all its clones:
  `call_targets`, `bind_function_values`' rewrites, `interpolation`'s
  override test, constraint deduplication.
- Content is added to a specialization after it exists, depending on the
  rest of the program: `synthesize_copies` adds `__copy` methods only
  when something copies the type, and `specialize_methods` adds `m<U>`
  instances as calls to them are found.

So "a checked runtime plus fresh user code" cannot produce the same program
as whole-program sema, and the build cache's verifying oracle (every hit
regenerated and compared) would reject it.

## 3. Design: a specialization is a function of its generic and arguments

Split sema into two stages, and give every declaration the same pass
history whenever it is created.

1. **Template stage.** Every generic base (struct, free function, generic
   method, and the generic closure structs lifted from them) goes once
   through the passes that make sense on generic code and do not depend on
   any instantiation: enum cases, literals, string literals, overload
   naming, type aliases, extensions applied to the base
   (`extend Box<T>`), implicit types in generic mode, intrinsics, member
   references. The result is the base's **template**, frozen.
2. **Instance stage.** Every concrete declaration (plain code, and each
   specialization as it is created) goes through the same **instance
   pipeline**, from its first pass to its last, as a worklist item:
   substitute the template's type parameters, then run the instance passes
   (operators, implicit types, closures, function references, releases,
   the checks). A specialization created while another is being processed
   is queued and runs the whole pipeline itself; it never joins halfway.

This needs each pass to be able to run on **a set of declarations** (the
worklist item) while reading the whole module for lookups, and every
program-wide counter to become per-declaration:

- `_idx_tmp_N` numbered per function, not per program;
- closure structs synthesized after lifting (function references, shared
  adapters) named after the declaration and position that creates them
  (`__closure@Array<int>.map#2`), not a per-file counter;
- `Loc`-keyed maps keyed by (declaration, `Loc`);
- `synthesize_copies` and `specialize_methods` add their members as
  separate worklist items (`Array<Point>.__copy`, `Box<int>.map<long>`),
  each a function of its owner specialization and arguments, rather than
  mutating a finished specialization.

Whole-program output changes once (deterministically) when this lands;
after that the verifying oracle holds as today.

## 4. The cached checked runtime

With specializations canonical, the checked runtime is:

- the runtime's plain declarations, checked (bodies kept only where 2b
  keeps them);
- the templates of its generic bases;
- every specialization it created, checked, by (generic, arguments).

A program is checked by loading that, marking all of it **checked**
(passes read it, never walk or rewrite it), adding the program's own
declarations to the worklist, and running the instance pipeline. A
specialization the program needs that the runtime already has is reused as
is; any other is created from its template.

Fallback: a program that declares a concrete override of a runtime generic
(`hash<int>`) can change the runtime's own instances, so it is checked
whole, as today.

Keys and storage:

- key: the runtime units' interface hashes (§2c), forced imports, the
  compiler;
- disk: `<cache>/v1/<target>/runtime/<key>.checked`, `serde` + `postcard` on
  the sema model (as `.pepi` does for the AST);
- memory: the language server and test harnesses keep the loaded checked
  runtime in a process-wide cache (one per key) and clone it per analysis.

## 5. Verification

- `--verify-cache` (CI) also checks every program whole and requires the
  same code for every unit, as the 2b trial does.
- A test compiles each documentation example both ways.
- Byte-identical objects across processes (the §7 reproducibility test)
  keep holding.

## 6. Phases

1. **Per-declaration pass scopes and counters**: passes take a declaration
   set; `_idx_tmp_N`, synthesized closure names and `Loc`-keyed maps become
   per declaration. Output changes once; nothing else yet.
2. **Template and instance stages**: freeze templates; specializations run
   the instance pipeline from the start as worklist items; copies and
   method instances become their own items. Fix the generic-method blind
   spots the inventory found (aliases, literals and string literals never
   reach `generic_methods`) on the way, since templates need them.
3. **Checked declarations**: a `checked` mark every pass honours; the
   runtime checked alone, then reused in memory (test harnesses, language
   server). Measure.
   Done: `sema/src/checked.rs`. The memory cache is keyed by the target
   and the runtime files' places, names and texts (not interface hashes
   yet). Sema for a small test program drops from about 240 ms to 30 ms
   after the first. The CLI still checked programs whole until phase 4.
4. **On disk**: serde on the sema model, `.checked` files, CLI.
   Done: the build cache's `runtime/<key>.checked` (`impl RuntimeStore
   for Cache`), keyed by the target and the runtime files' names,
   namespaces and texts, renumbered with `with_file_map`. The CLI checks every program on
   the checked runtime, so the runtime units' interface hashes come from
   that one mode. Sema for a hello-world compile drops from about 260 ms
   (build and passes) to about 100 ms with the runtime on disk.

Each phase lands with its INTERNALS.md changes and keeps the full suite and
the verifying oracle green.

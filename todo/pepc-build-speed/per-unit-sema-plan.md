# pepc per-unit sema: an edit costs only its unit

Written 23:05 PT 10-05 by the #225 thread, for Justin's approval before the overnight build.

## Why

#722 strips the bodies of cached units, but sema still runs on the whole program. Every file's declarations, every generic specialization and every global pass run on every build. As a result, a one-line edit still costs 76-86 s of sema on Windows (32 CPUs) and 100-120 s on Linux (4 CPUs). A single-file change should check only that file, as Justin asked.

## Goal and acceptance

| Build (self-build, -O2 pepc) | Now, Linux 4 CPUs | Now, Windows 32 CPUs | Target | cargo dev / release, Linux |
|---|---|---|---|---|
| Body edit in one file (driver/linker.pep) | 137 s | 88 s | under 3 s | 1.7 s / 13 s |
| Body edit in one sema file | 187 s | 104 s | under 5 s | 4.9 s / 59 s |
| Interface edit (a signature changes) | same as cold | same as cold | dependents only | n/a |
| Cold | 222 s | 122 s | at most cargo release (65 s) | 77 s / 65 s |

Each PR must also meet these conditions:
- Every compiled test program builds and passes: pepper-tests.sh, plus `cmp_progs.sh` across all 366 programs compared with main.
- Tests run at least as fast as main.
- Before/after numbers on Linux and Windows are posted as soon as they exist.

## Design

1. **Checked-unit records.**
   - After sema, each unit writes a binary record beside its objects, under the same cache key. The record holds:
     - its declarations as sema left them: resolved types, signatures, inferred return types, struct layouts, trait conformances and overrides;
     - its generic templates, which are checked generic bodies;
     - its link summaries: confinement and static strings;
     - the list of specializations it instantiated.
   - The serializer and reader are generated from the sema model by `gen-sema-model.py`, which already generates `fingerprint()`. They are not hand-written.
   - The interface hash from #722 becomes the hash of the declaration part of the record.

2. **Sema on dirty units only.**
   - Clean units are loaded from their records. Their declarations go in as already checked and are marked imported, so no pass walks them.
   - Dirty units are parsed and go through every pass.
   - A dirty unit instantiates the specializations it needs from the templates in the records and emits them as linkonce_odr/comdat, which #706 already supports. Clean units' objects already contain theirs.
   - Lazy method specialization (in progress) keeps this set down to the methods actually used.

3. **Early cutoff on the interface.**
   - When a dirty unit's interface hash is unchanged, its dependents stay clean. This includes inferred return types and summaries.
   - When the hash changes, the driver rechecks its direct dependents, and so on in waves until hashes stop changing.

4. **Per-file units.**
   - Today a module's roughly 100 files form one unit, so editing `sema/passes.pep` rechecks all of sema.
   - Instead, each file becomes a unit. It depends on the files whose names it uses, which the linker already resolves, including sibling files it does not import.
   - Module-private names are carried in the record, visible to the module only.
   - Import cycles are not a problem. Interfaces depend only on declarations, plus inferred returns that early cutoff handles. Only interface changes ripple.

5. **Global passes made modular.**
   - **Confinement and static-string summaries** are computed bottom-up from the dependencies' records, with a fixpoint inside the dirty set only. A cycle across units whose summary changes is checked together as one set.
   - **Closure and lambda names** get a per-unit prefix and a counter, so they stay stable when other units change.
   - **Specialization names** are already structural, so no change is needed.
   - **Overrides:** the orphan rule from #698 already places each override with T or with f, so a unit's record carries its overrides.

6. **Parallel sema in processes for cold builds.**
   - First, a declarations phase for all units, run on one core.
   - Then the bodies of units, in parallel in `pepc --check-unit` child processes, one per CPU, ordered by the dependency graph. Each child writes its unit's record and part.
   - This reuses the `--compile-part` child machinery. Processes avoid the threads-share-only-`[Shared]` limit.

## PR order (built overnight, one PR at a time through Tickets)

Update 23:40 PT 10-05: the Rust compiler already has half of design item 2. Its `checked.rs` checks the runtime alone and saves the result as a record (postcard). The program is then checked on top of it: the passes read the checked declarations but neither walk nor change them. pepc never ported this. So the first step is to port it, and the next step generalizes its two layers to one per unit.

0. **#728** (bug: the Windows crash fix and part diagnostics) merges first, then **lazy method specialization** (about 10% of sema, and half the codegen).
1. **Record serializer:** binary write and read for every sema model type and the AST types it holds, generated from the model and from `ast.pep`. It includes a round-trip test and has no behaviour change.
2. **Checked runtime** (a port of `checked.rs`): the runtime is checked once and its record is cached, so every build checks only the program. This also speeds up the test suites, which build many small programs.
3. **One checked layer per unit** (design items 2, 3 and 5):
   - Units are checked in dependency order. Each unit's record holds only what that unit added, including its specializations.
   - An edit loads the records of everything clean and checks the dirty units.
   - Early cutoff on each unit's interface hash.
4. **Per-file units** (design item 4): an edit rechecks one file.
5. **Parallel sema:** independent units are checked in child processes, one per CPU (design item 6).
6. **Windows final timings** for all four rows against cargo, then the cutover and #709 last, as already planned.

## Risks and the defaults taken

- **Rust parity in passes_test.** Records are pepc-only. passes_test keeps comparing the whole-program path, which is still used with `--no-cache`.
- **Reproducibility of incremental builds.** For each PR, a test builds clean and incrementally and compares the objects and test output byte for byte.
- **The record format:** binary, versioned by compiler identity, so a new pepc never reads an old record. The JSON model writer is too slow to use.
- **Fallback:** if a pass cannot yet treat imported declarations as checked, the unit falls back to whole-program sema with a trace line, and the build stays correct.
- If a step stalls, I land what has a measured gain and report it rather than spin.

## What's needed from Justin

Approve this. Nothing else needs a decision; the defaults above go ahead.

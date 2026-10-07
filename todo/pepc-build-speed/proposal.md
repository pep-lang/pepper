# pepc build speed: reaching Rust/C++ parity

Written 12:10 PT 10-05 by the #225 thread, at Justin's request: "compile and link full and incremental/editing use cases as fast or faster than Rust or C++. If there is an architectural problem that needs solving to do this, then propose it."

## 1. The bar, measured

The same compiler exists in both languages: pepc (Pepper, about 85k lines, plus about 65k lines of runtime and 6k of pepper-llvm) and pep-build (Rust, about 73k lines plus crates.io dependencies). Every number below was measured in the same 4-CPU container. "Sema edit" appends a line to one file of the type checker (`sema/closure_sites.pep` or `passes/closures.rs`); "driver edit" does the same to the linker driver (`driver/linker.pep` or `linker.rs`).

| Build | cargo release | cargo dev (incremental) | pepc -O2 (#695) | pepc -O0 (#695) |
|---|---|---|---|---|
| Cold | 65 s* | 77 s | 210 s | 177 s |
| Nothing changed | under 1 s | under 1 s | 1.9 s | 1.8 s |
| Sema edit | 59 s | **4.9 s** | 190 s | 163 s |
| Driver edit | 13 s | **1.7 s** | 154 s | 162 s |

\* Some dependencies were already built from an aborted run, so a truly cold cargo release build is somewhat slower.

The gap:
- **Cold builds:** about 3x slower than cargo.
- **Edits:** 30 to 90x slower than cargo dev. That is the main problem.

## 2. Where pepc's time goes

| Stage | -O0 cold | -O0 driver edit |
|---|---|---|
| Sema | 137 s | 139 s |
| Codegen (whole program) | 7.7 s | 8.5 s |
| LLVM objects (parallel, cached by unit) | 27 s | 9 s |
| Link | 1 s | 1 s |

Sema is 75 to 90% of every build, and it does not shrink with the edit. It runs single-threaded over all 156k lines on every build that changed anything, at about 1.1k lines/s.

## 3. The architectural problems

1. **Sema is whole-program.** The only thing reused between builds is an object file, so every edit re-checks the whole program. C++ re-checks one translation unit against headers. Rust re-checks one crate against its dependencies' metadata, and with incremental builds only the queries the edit touched. Both run independent units in parallel.
2. **Four language rules make whole-program sema necessary today.**
   - **Concrete overrides apply everywhere.** An override such as `hash<int>`, declared in any file, changes code in every unit that instantiates the generic. This is why #695 adds every override file to every unit's key.
   - **Return types are inferred across files.**
   - **Link summaries span the whole program.** Confinement and static strings are greatest fixed points over the whole call graph.
   - **Generic specialization is a whole-program fixpoint.** `resolve_implicit_types` runs about 27 rounds over the whole program in a self-build.
3. **Sema is structured as about 50 whole-program passes.** Each rewrites the whole tree, and several iterate to a fixpoint. The #689 profiles showed the cost spread flat across tree walks that are memory-latency bound. That is the constant factor behind the cold-build gap: rustc type-checks each function body once.

## 4. Proposal: separate compilation, with interfaces

**A. A unit is a file, or an import cycle of files, and it compiles on its own.**
- Each unit is checked by its own `pepc` process against the interface files of the units it uses. It writes its object(s) and an **interface**: its declarations, inferred signatures, generic bodies and link summaries.
- **Dependencies are known before sema.** The linker already resolves every name to its declaring file, so a file depends on exactly the files whose names it uses. This includes sibling files of its module that it does not import.
- **The driver becomes a build scheduler.** It walks the unit graph in dependency order and runs one process per CPU.
- **Early cutoff.** A unit's dependents are re-checked only when its interface hash changes, so an edit inside a function body re-checks one file.
- **Processes give parallel sema.** In-process parallel sema was dropped because threads can only share `[Shared]` values; processes avoid that limit.

**B. The four rules become modular.** One of these is a language change and needs your decision.
1. **Coherence for overrides (language change):** an override `f<T>` may be declared only in the file or module that declares `T`, or in the one that declares `f`. This is Rust's orphan rule. Without it, every unit depends on every override file.
2. **Inferred return types** stay as they are. A unit's interface records them, and a change that alters one cascades through early cutoff.
3. **Link summaries** are computed bottom-up, one unit at a time from its dependencies' interfaces, with a fixed point only within a unit.
4. **Generics** are instantiated in the unit that uses them, as now (`linkonce_odr`), from the checked generic body in the defining unit's interface. The specialization fixpoint runs per unit.

**C. Each function body goes through the body passes once.** After declarations are resolved, a body runs through all the body-level passes while it is hot in cache, instead of about 50 walks over the whole tree. This cuts the constant factor of sema, which still matters for cold builds and large units.

**D. The runtime comes precompiled.** The runtime's units (interfaces and objects) ship prebuilt in the cache. A hello-world build spends 2.3 s in sema today, almost all of it on the runtime. Test suites, which build many small programs, gain the most.

## 5. Expected results

These are estimates from the measurements above, not measured.

| Build | Now (-O0) | After A+B | After C+D | cargo dev |
|---|---|---|---|---|
| Driver edit (185-line file) | 162 s | about 1.5 s: about 0.2 s sema, codegen and LLVM for one file, 1 s link | about 1.2 s | 1.7 s |
| Sema edit (1.2k-line file) | 163 s | about 3 s | about 2 s | 4.9 s |
| Cold, -O0 | 177 s | about 70 s: sema in parallel over 4 CPUs, about 35-45 s with the longest dependency chain, plus about 27 s of LLVM | about 45 s | 77 s |
| Cold, -O2 | 210 s | about 110 s | about 70 s | 65 s |

Cold -O2 also needs the duplicated optimization of `linkonce_odr` instantiations reduced: each part re-optimizes the generic instantiations it uses. The options are a ThinLTO-style summary, or instantiating each generic in one unit and importing it.

## 6. Plan

1. **Interfaces and per-unit sema** (A, B2-B4): the bulk of the work. Sema's state (`Module`, `PassState`) gains a "declarations from interfaces" mode. An interface is serialized in a binary format, since the JSON model writer is too slow for this.
2. **The orphan rule** (B1), if approved: a check with a clang-style error and a docs chapter. It moves any override in the runtime or tools that breaks the rule.
3. **The build scheduler**, with process-per-unit parallel sema and early cutoff.
4. **The per-function body pipeline** (C).
5. **The precompiled runtime** (D).
6. **The cutover**, then the LSP on the shared parser, as planned.

Each step is measured with before/after numbers, the same way as above.

## 7. What is needed from Justin

- Approve the direction: separate compilation per file unit, with interfaces, process-per-unit parallel sema and early cutoff.
- Decide on the orphan rule for concrete overrides. The recommendation is to adopt it; the alternative keeps every override file in every unit's inputs.

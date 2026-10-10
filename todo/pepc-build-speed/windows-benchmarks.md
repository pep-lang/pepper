# pepc self-build on Windows (#225, 10-10)

pepc building itself on a 32-thread Windows 11 PC (LLVM 20.1.8, `-O2`), to
compare with the 4-core Linux numbers in `layer-overhead.md`. Main went from
cold 146 s / edit 67 s to **cold 133 s / edit 4 s** over the day.

## Method
The cloud session's recipe, run from `tools/`:
- **Builder:** the Rust `pep-build` from main @ 9edcb9ae8, kept fixed, builds
  the pepc under test from `compiler/main.pep`.
- **Cold:** `tools/.pep` removed, empty cache, then
  `pepc -O2 -T time -I . compiler/main.pep -o out`.
- **Edit:** `var _bench = 0; if (_bench == 1) { _bench = 2; }` added at the
  start of the first function in `compiler/sema/lazy_methods.pep`, rebuilt
  with the same cache, the file restored afterwards.
- **Times:** wall clock per build; phases from `-T time`; worker totals summed
  from `.pep/build/layers.*/*.stages`; the critical path from the
  `schedule` file there (each layer's start, end and dependencies), following
  each layer's latest-ending dependency back from the last layer.
- Layer workers default to one per logical CPU (32).

Windows setup it needed:
- `-L <llvm>/lib` on both `pep-build` and pepc, to find `LLVM-C.lib`.
- The pepc cache on the same drive as `tools/.pep`: pepc renames build
  outputs into the cache, which fails across drives.

## Results
Clean runs only (no other build running); several values = repeat runs.

| Commit | What | Cold s | Edit s |
|---|---|---|---|
| 930043d5 | main, #800 sema import cycle split | 133 | 4 |
| d8abe39e | main, #801 confinement + #802 pipelined layers | 139 / 140 / 139 | 4 |
| 08f6017a | main, #795 per-file layers in workers | 197 (fastest of 4) | 4 |
| 550b8f0d..e3ef3675 | layer-workers branch heads (6) | 197–200 | 4–5 |
| 5f11e027 | v14, per-file layers, objects in the main process | 221 | 21 |
| ae8f928 | main, module layers in process | 153 | 69 |
| 9edcb9ae8 | main, baseline | 146 | 67 |

Phases, in seconds:

| Commit | Cold layers (wall) | Worker CPU: check / object / merge | Cold objects | Edit layers | Edit objects |
|---|---|---|---|---|---|
| 930043d5 | 127.9 | 309 / 109 / 57 | in workers | 3.2 | in workers |
| d8abe39e | 134.3 | 343 / 129 / 51 | in workers | 3.1 | in workers |
| 08f6017a | 192.7 | 370 / 106 / 53 | in workers | 3.3 | in workers |
| 5f11e027 | 193.4 | 484 / – / 64 | 21.0 | 7.8 | 9.3 |
| 9edcb9ae8 | 106.0 (in process) | – | 20.5 | 52.1 | 8.6 |

## What the numbers say
- **Edit:** per-file layers took it from 67 s to 4 s: only the edited
  layer is checked again (about 1.6 s) and its object compiled (0.6 s), then
  a 0.2 s link. At 9edcb9ae8, 50 s of the 67 s was the
  `sema/apply_extensions` layer.
- **Cold, 08f6017a:** workers did about 560 s of CPU in 193 s wall, under
  3× parallel on 32 threads, because the layer graph is a long chain;
  `sema/apply_extensions` alone took 46.8 s.
- **Cold, d8abe39e:** pipelining (dependents check on a layer's record while
  its object compiles) and cheaper confinement summaries brought it to 139 s.
- **Cold, 930043d5:** with the sema cycle split, `sema/apply_extensions`
  takes 5.1 s. The critical path, ending at 127.5 s:
  `runtime` (0–16.5 s) → syntax, ast, link → `sema/builder`
  (17.3 s) → `sema/record_codec` (14.1 s) → 12 small sema layers one
  after another, to 100.6 s → `driver/interface`, `driver/cache`,
  `driver/layers`, `driver/build` in sequence (28 s). The longest layer,
  `codegen/address` (18.5 s), is off the path.

Next levers, by that path: `runtime` and `sema/builder` (34 s together), the
chain of 12 sema layers, and the four `driver/*` layers that run in sequence.

## Noise
Other builds on the same machine (other sessions, CI; up to 42 `pep-build`
and `pepc-stage1` processes) slow every phase by 10–100%, including object
compiling that no change touched, so single runs disagreed by up to 45 s.
With nothing else running, repeat runs agree within 1 s. Before trusting a
run, check that no other `pep-build*` or `pepc*` process ran during the timed
builds. A run stopped mid-build leaves its `pep-build` running.

Not measured cleanly: main @ 6d2df486 (#799) and 4e078ba3 (#806); every run
overlapped CI. Neither changes the compiler's passes.

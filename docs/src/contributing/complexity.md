# The complexity gate

CI keeps every function in `runtime/` and `tools/` at a cognitive
complexity of 25 or less. The score comes from
[pep-complexity](https://github.com/pep-lang/pepper-complexity), which
follows SonarSource's "Cognitive Complexity" white paper, as gocognit
does for Go. Each `if`, loop, `match` and `?:` adds 1, plus 1 for each
level it is nested at; each `else`, run of `&&` or `||`, and labeled
`break` or `continue` adds 1. Its README has the full table for every
Pepper construct. A function over 25 is hard to read and to test,
and is better split.

## What it checks

`scripts/complexity-check.sh` runs the gate. It builds pep-complexity from
its release tag (the `VERSION` the script names) with this checkout's own
parser (`tools/compiler/parse`) and runtime, so it reads the syntax this
checkout's compiler reads, never an older release's. It then runs

```bash
pep-complexity --max 25 --baseline .github/complexity-baseline.txt \
  --exclude '**/*_test.pep' --exclude 'runtime/**/test/**' --exclude '**/testdata/**' \
  --exclude tools/compiler/sema/record_codec.pep runtime tools
```

Tests, test data and the generated record codec
(`scripts/gen-sema-record.py`) are not checked.

The gate fails on:

- a function over 25 that the baseline does not list, such as a new one;
- a listed function whose score went over the one in the baseline.

The baseline, `.github/complexity-baseline.txt`, lists the functions that
were already over 25 when the gate started. Each line is `path name score`,
and a function may stay at its score or go down, but not up. When a listed
function improves, or is no longer over 25, the gate passes and prints a
note saying which line to lower or remove.

CI runs it in the `others` part of `test-linux`, after the Pepper tests,
with the `pep-build` those tests used. It adds about half a minute when its
build is cold, and a few seconds once the tests' build cache holds it.

## Running it

```bash
scripts/complexity-check.sh                 # with the installed toolchain's pep-build
scripts/complexity-check.sh path/to/folder  # with the pep-build in that folder
```

## When it fails

Split the function: move a loop body, a `match` arm or a group of checks
into a function of its own with a name that says what it does. The output
names each failing function with its file, line, cognitive score and
cyclomatic score.

## Updating the baseline

```bash
scripts/complexity-check.sh --write-baseline
```

rewrites `.github/complexity-baseline.txt` from the current sources: every
function over 25, each at its current score. Do this for two reasons only:

- to shrink it, after functions got simpler (the gate's notes say which
  ones), so they cannot get worse again;
- to raise or add an entry when a function over 25 cannot sensibly be
  split, such as a dispatch over every case of a large enum. Say why in
  the pull request, which then shows the line it adds or raises.

Never raise an entry only to get a change past the gate. Since the file is
sorted with one function per line, its diff shows exactly which functions
changed.

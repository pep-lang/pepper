---
name: platform-test
description: >
  Use when a change needs checking on an operating system other than the one
  you are working on — "does this build on Linux", "will this break macOS",
  "test this on all platforms", "run the suite on mac" — or when a failure
  looks platform-specific (linker flags, path handling, system libraries,
  `cfg(windows)` branches) and you cannot reproduce it locally. Also use it
  before merging a change to anything platform-conditional: the required CI
  check only covers Windows, so nothing else gets exercised unless you ask.
---

# Platform test

CI (`.github/workflows/ci.yml`) gates merges on Windows only, because that is
the platform the compiler currently works on. Anything cross-platform —
`cfg(windows)` branches, `scripts/setup-llvm.sh`, the linker's system-library
lists — is therefore unverified until you run it somewhere else. That is what
`.github/workflows/platform-test.yml` is for: it runs a command you choose on
the platforms you choose, on demand.

It is a diagnostic, not a gate. Some platforms are *expected* to fail right
now (see Interpreting results), so a red run here is information, not a
regression.

## Invoke it

```bash
gh workflow run platform-test.yml -f platforms=macos -f script="cargo test --workspace"
```

- `platforms`: comma-separated `linux`, `macos`, `windows` (aliases: `ubuntu`,
  `mac`/`osx`, `win`). Defaults to all three. An unknown platform fails the
  run rather than falling back to the default.
- `script`: any command, run with bash from the repo root. Defaults to
  `cargo test --workspace`.

Each selected platform provisions LLVM with the repo's setup script first, so
the command can build.

To exercise code that isn't merged yet, add `--ref`:

```bash
gh workflow run platform-test.yml --ref my-feature -f platforms=linux
```

`workflow_dispatch` only registers once the workflow is on the default branch,
but the run then executes the workflow file as it exists at `--ref` — so
`--ref` selects both the code under test and the workflow running it. Workflow
changes can therefore be exercised before they are merged, with one exception:
the accepted `-f` inputs are validated against the default branch's copy, so
an input that exists only on the branch is rejected with "Unexpected inputs
provided" until it is merged.

Dispatch is the only trigger. A `push` trigger can't be filtered on commit
message, so it would queue a job on every push just to find there was nothing
to do, and the command would have to be parsed back out of prose.

## Wait for the result

`gh workflow run` prints nothing useful, so resolve the run id, then watch it.
Note the id of the newest run *before* dispatching: `gh run list --limit 1`
returns the latest run whether or not it is yours, so polling for "any run"
will happily hand back the previous one, and `gh run watch` then returns its
stale verdict instantly.

```bash
before=$(gh run list --workflow platform-test.yml --limit 1 --json databaseId -q '.[0].databaseId')

gh workflow run platform-test.yml -f platforms=linux

# The run takes a moment to appear; wait for one that isn't the old one.
for _ in $(seq 15); do
  id=$(gh run list --workflow platform-test.yml --limit 1 --json databaseId -q '.[0].databaseId')
  [ -n "$id" ] && [ "$id" != "$before" ] && break
  id=''
  sleep 2
done

# Without this, a failed dispatch leaves $id empty or equal to $before, and
# watching the previous run reports its stale success as yours.
[ -n "$id" ] || { echo "no new platform-test run appeared; did the dispatch fail?" >&2; exit 1; }

gh run watch "$id" --exit-status   # blocks until done; non-zero if it failed
```

`gh run watch` can run for many minutes — a cold LLVM cache costs about five
per platform — so run it as a background/async command rather than blocking a
foreground call, and check back on it.

When it finishes:

```bash
gh run view "$id"                      # per-job status
gh run view "$id" --log-failed         # just the failing steps
gh run view "$id" --job <job-id> --log # one platform's full log
```

Report which platforms passed, and for failures quote the actual error rather
than the job name — the useful signal is nearly always a linker line or a
missing symbol, not "the macos job failed".

## Interpreting results

- **macOS is expected to fail in codegen today.** `macos-latest` is arm64, and
  the driver initializes only the x86 LLVM target (`Target::initialize_x86`,
  with inkwell's `target-x86` feature), so `Target::from_triple` cannot
  resolve an `aarch64-apple-darwin` triple. Adding arm64 support means adding
  the inkwell target feature *and* the initialization call — not a CI problem.
- **Linux is the useful signal** for the linker work, since it is the one
  platform whose `default_system_libraries()` entries (`m`, `dl`, `pthread`)
  have never been exercised.
- A failure inside `scripts/setup-llvm.sh` is about provisioning, not your
  change: check the release asset name for that platform first.
- Private-repo minutes are billed, and macOS runners cost several times Linux.
  Prefer naming the one platform you actually need over defaulting to all
  three.

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

CI (`.github/workflows/ci.yml`) gates merges on Windows, and also runs the
suite on Linux and macOS against the default LLVM. Other LLVM majors run only
in `.github/workflows/llvm-versions.yml`: on a release tag, before the
extension is packaged and the docs are published, or when dispatched.
Anything CI does not reach (another LLVM on a branch, a script, a probe of a
runner) stays unverified until you run it there. That is what
`.github/workflows/platform-test.yml` is for: it runs a command you choose on
the platforms you choose, on demand.

It is a diagnostic, not a gate — no job here is a required check. All three
platforms now pass end to end, though, so a red run is a regression or a real
platform gap, not an expected failure (see Interpreting results).

## Invoke it

```bash
gh workflow run platform-test.yml -f platforms=macos -f script="cargo test --workspace"
```

- `platforms`: comma-separated `linux`, `macos`, `windows` (aliases: `ubuntu`,
  `mac`/`osx`, `win`). Defaults to all three. An unknown platform fails the
  run rather than falling back to the default.
- `script`: any command, run with bash from the repo root. Defaults to
  `cargo test --workspace`.

- `provision`: `false` skips LLVM provisioning, for questions about what the
  bare runner image already has.

Each selected platform provisions LLVM with the repo's setup script first, so
the command can build. On Linux and macOS that is an apt or Homebrew install
taking seconds; only Windows downloads an archive.

Platform-specific facts are worth measuring on the platform rather than
reasoning about: `-f provision=false -f script="bash scripts/probe-llvm-packages.sh"`
reports which LLVM versions the image's package manager can serve and builds
and tests the workspace against each one.

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

## Make each run answer everything it can

A dispatch costs minutes, and **GitHub serves no partial log for a step that
is still running** — a hung job looks exactly like a working one. So the
workflow runs the requested command under `bash -euxo pipefail`, caps the job
at 30 minutes (provision 10, script 15 — the step caps must sum to less than
the job cap, or the job is cancelled before either fires and a cancelled job
reports nothing), and dumps a diagnostics block on failure *or cancellation*:
toolchain, host, the LLVM cargo actually sees with `--targets-built`, which
`clang` answered, and the build artifacts.

A probe that needs longer than 15 minutes should be split across dispatches
rather than raised — smaller questions come back sooner.

Two traps that each cost a run here:

- Those flags govern the *wrapper* shell. A dispatched `bash probe.sh` is a
  new shell, so a script **file** sets `set -euo pipefail` itself — otherwise
  it runs past every failure and the job reports success having answered
  nothing.
- macOS has no GNU `timeout`. Rely on `timeout-minutes`, or guard the call.

Put independent questions in one script with `=== section` markers, and never
pipe the interesting command through `tail`/`head` — filter noise by pattern.

## Interpreting results

- **All three platforms work end to end**, so a failure is a real finding, not
  an expected gap: the suite passes on Windows x64, Linux x64 (apt LLVM 18-20)
  and macOS arm64 (Homebrew 18-22), and each compiles, links and runs a `.pep`
  program. Codegen registers the *host's* backend
  (`crates/pepper-codegen/src/target.rs`); if a CLI run reports "No available
  targets are compatible with triple …", that registration is wrong for the
  host. The suite may not tell you: inkwell's JIT registers the host backend
  as a side effect, so whichever test creates an execution engine first can
  mask a wrong explicit registration.
- A failure inside `scripts/setup-llvm.sh` is about provisioning, not your
  change. On Linux and macOS that means apt or Homebrew; only Windows, and the
  last-resort fallback, involve a release asset.
- Private-repo minutes are billed, and macOS runners cost several times Linux.
  Prefer naming the one platform you actually need over defaulting to all
  three.

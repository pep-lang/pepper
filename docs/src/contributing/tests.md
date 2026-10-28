# Testing the runtime and the compiler

The tests are written in Pepper: `[Test]` functions (see
[Unit tests](../language/testing.md)) that `pepper test`
([`pep-test`](../tools/pep-test.md)) builds and runs. They cover the
runtime and the Pepper tools, the compiler written in Pepper
(`tools/compiler`) among them.

They are the whole suite: Pepper is written in Pepper, and so are its
tests.

## Where runtime tests live

| Code under test | Its tests |
| --- | --- |
| A module, `runtime/<module>/` | `runtime/<module>/test/<topic>_test.pep`, which imports the module |
| A prelude file, `runtime/<name>.pep` | `runtime/test/<topic>_test.pep` |
| A file's private functions | `[Test]` functions in that file itself |
| A Pepper tool, `tools/<tool>/` | `tools/<tool>/<topic>_test.pep`, which imports the tool's files (`import "format";`), or runs the built tool (see [Tests that run the tools](#tests-that-run-the-tools)) |

A `test/` folder holds no `module.pep`, so no program that imports the
module loads it. Its files are still files of the module, though: a test file
that imports one of the module's files (`import "../atomic";` in `runtime/async/test/`) sees its
unexported names. `pep-test` builds each
folder's tests into one program, so a helper (or test name) that two test
files of one folder declare collides; mark it `private` in each (as
`runtime/async/test/` does). Prefer it to tests inside a
source file, which only a test of private internals needs. The reference
generator and the doc-comment check skip `test/` folders, so a test file
needs no `##` comments.

## Running them

`scripts/pepper-tests.sh` runs them all:

```bash
sh scripts/install.sh --version 0.4.0-dev        # the build of main; see below
scripts/pepper-tests.sh                          # every runtime and tool test
scripts/pepper-tests.sh -f parses                # by name, in each run
scripts/pepper-tests.sh target/bin               # with a pep-build you built
```

The tests build with the installed toolchain's `pep-build`, the one
`pepper install which` names. Every merge into main that changes the
compiler, the runtime or the tools publishes the build of main as a
prerelease named `x.y.z-dev` (`pepper install list --available` shows it),
replacing the one before; CI and the workers install it with the install scripts
rather than building the compiler, and so can you (run the install again to
refresh it). The compiler's own tests (`tools/compiler/*_test.pep`) build
the compiler's sources into their test programs, so they test a change to
it. To run the whole suite with the changed compiler too, build it from
`tools/compiler` (see
[Building Pepper from source](building.md#building))
and pass its folder as the first argument.

The script builds the Pepper tools (`pepper`, `pep-test`, `pep-doc` and the
others) from the checkout with that `pep-build`, against the checkout's
runtime, into `target/pepper-tests/bin` beside a copy of the `pep-build`,
and runs `pepper test`:

- in `runtime/`, every runtime test;
- in `runtime/`, the `compress` tests again with `-D USE_ZLIB` and the
  `digest` tests with `-D USE_LIBCRYPTO`, which link the system's zlib and
  libcrypto (on Windows the zlib run needs `PEPPER_TEST_ZLIB_DIR`, a folder
  holding `zlib.lib`, and is skipped without it);
- in `tools/`, the tools' tests, each under its tool's `pep.toml`.

`PEPPER_TESTS_PART` runs part of them: `compiler` the compiler's tests
(`tools/compiler/`), `others` everything else; unset or `all`, both.

The tools' run, the longest, starts as soon as the tools its tests run
(`pepper`, `pep-test`, `pep-fmt`, `pep-profile`, `pep-package`,
`pep-run`, `pep-new` and `pep-init`) are
built, and runs beside the runtime's runs. Its output is interleaved with
theirs as it comes, each line starting `tools| `, so a slow test shows
while it runs.

Once `pepper` is built, run any part of them by hand:

```bash
cd runtime
pepper test                       # every runtime test
pepper test json/test             # one module's
pepper test -f parses test        # by name
```

Further arguments to `scripts/pepper-tests.sh` go to each of its `pepper
test` runs. `--shard I/N` splits every run into `N` parts and takes the
`I`th, so the `N` runs from `1/N` to `N/N`, on as many machines, run the
whole suite between them:

```bash
scripts/pepper-tests.sh target/compiler --shard 2/4
```

Tests run with `runtime/` as the current folder, so a test reads data
files kept beside it by a path from there (`archive/test/gnu.tar.gz`).
The builds go to `runtime/.pep/`, which git ignores. A test that writes
files uses a fresh folder under the system's temporary folder
(`TempFolder` in the `testing` module makes and removes one).

CI runs `scripts/pepper-tests.sh` with the installed build of main on
Linux, macOS and Windows, in two jobs on each: one runs the compiler's
tests (`PEPPER_TESTS_PART=compiler`), the other everything else
(`PEPPER_TESTS_PART=others`), and every build in a job shares one build
cache. A PR that changes the compiler (`tools/compiler/`) or stage 0's
pin (`.github/stage0`) is tested with that compiler instead: CI builds it
with stage 0 first (`scripts/ci-build-compiler.sh`, from a build cache CI
keeps between runs, keyed on stage 0's contents) and runs the suite with
it.

On a pull request, the docs examples (`tools/pep-doc/examples_test.pep`)
build and run in full only on Linux. The macOS and Windows jobs set
`PEPPER_DOCS_EXAMPLES=platform`, which keeps only the examples that select
code per platform: those with a line holding a `[Target(...)]` that names
an `OS(...)` or an `Arch(...)`. On main, and on every other event, every
OS runs every example. To run only those examples by hand:

```bash
PEPPER_DOCS_EXAMPLES=platform scripts/pepper-tests.sh target/compiler
```

Each job has
a time limit a little above its slowest passing runs, and prints the
runner's memory, swap, disk and biggest processes every minute beside the
tests (`scripts/ci-monitor.sh`). A job that fails, is cancelled or runs out
of time ends with a Diagnostics step (`scripts/ci-monitor.sh --report`):
the samples with the least memory free, every process still running with
its age and size (a hung build or test is the old one), the disks, and on
Linux the kernel's out-of-memory kills.

CI also builds the compiler for a commit that leaves `tools/compiler/`
alone when the published build of main is stale. The build of main
publishes only after main's CI passes, so a run cancelled by the next
push leaves it behind main's newest compiler change, and main's new
tests would run with the old compiler. `scripts/ci-published-compiler.sh`
decides: the published compiler is used only when the commit the
`v<VERSION>` tag is on is on the commit's history and its
`tools/compiler/` is the commit's. Otherwise, or when VERSION is not
published, CI builds the commit's compiler with stage 0. CI's `changes` job runs it on
pull requests, on pushes to main and on dispatches on main. It prints the
decision and its reason in its log and in the run's summary, under
"Compiler". To check a commit by hand:

```bash
scripts/ci-published-compiler.sh [<commit>]   # exit 0: the published compiler will do
```

### On iOS and Android

`scripts/mobile-test.sh` runs the runtime's tests in the iOS simulator and
the Android emulator, with `pep-test --target` (see
[Testing on iOS and Android](../tools/pep-test.md#testing-on-ios-and-android)),
from `runtime/` as above, then every docs example and the prototype apps
(see [iOS and Android](../language/mobile.md#the-prototype-apps)). By
hand, on a Mac with Xcode, or on Linux for Android:

```bash
bash scripts/openssl-android.sh fetch runtime     # once: the tls module's OpenSSL for Android
PEPPER_RUNTIME=$PWD/runtime bash scripts/mobile-test.sh target/compiler/pep-build /tmp/mobile android
```

Or only the tests, in a simulator or emulator already running:

```bash
cd runtime
pepper test --target x86_64-linux-android
```

CI's `mobile` workflow (`.github/workflows/mobile.yml`) runs the script on
GitHub-hosted runners, iOS on macOS and Android on Linux (where
`scripts/ci-provision-android.sh` sets up the emulator, with KVM), on
every push to main and nightly, but not on pull requests: the iOS job
takes about 40 minutes on a 3-core macOS runner and holds one of the
few macOS runners CI's own test jobs wait for. Each job builds the commit's compiler with
stage 0, from the build cache the test jobs keep, and the Android job
fetches the OpenSSL itself, so `gh workflow run mobile.yml --ref <branch>`
checks a branch with nothing else to set up. A test that cannot run there
(the runtime's need a Unix socket file or a hard link, which `adb shell`
may not make) leaves that part out with `[Target(!OS(Android))]`.

Two Pepper tools depend on packages in other repositories. The compiler
written in Pepper, `tools/compiler`, depends on `pep-lang/pepper-llvm`, and
the language server `tools/pep-lsp` depends on `pep-lang/pepper-lsp`. Both
are public, so the build clones them over HTTPS with no credentials.

## Stage 0

Stage 0 is the published compiler that builds the compiler: in CI, in the
release build and in `scripts/stage0-check.sh`. It is a pinned build of
main, named in `.github/stage0`: its version, the commit it is the build
of, and the SHA-256 sum of each archive. The build of main replaces its
archives on every merge, so the pinned ones are copies on the repository's
`stage0` release, named `<commit>-<asset>` with the commit's first 12 hex
digits. `scripts/ci-install-toolchain.sh` installs stage 0 by default
(`--newest` installs the newest published toolchain, `--version` a
release). A stage 0 that stays the same from run to run keeps the
compiler's build cache, which is keyed on it.

The `Stage 0` workflow (`.github/workflows/stage0.yml`) moves the pin. Every
night, and when dispatched, it takes the newest build of main once its
publish has passed, copies it onto the `stage0` release, and pushes the
branch `stage0/bump` that pins it. GitHub Actions may not open pull
requests in this repository, so the run's summary and a warning link to
open one. Its CI runs as any pull request's, building the compiler with
the new stage 0 and running the whole suite with it, so it may auto-merge.
While that pull request is open the branch stays put (a push with the
workflow's token would start no CI on it); the run after it merges pins
the next build. The `stage0` release keeps the newest 20 builds and the
one main pins, so an older branch whose pin is gone (a patch release made
from it, say) copies main's `.github/stage0` first.

```bash
gh workflow run stage0.yml                                  # pin the newest build of main now
git fetch origin stage0/bump:stage0/bump                    # then open its pull request
gh pr create --base main --head stage0/bump --fill
```

So runtime code may only use what stage 0 accepts. A runtime change that
needs a newer compiler than stage 0 dispatches the workflow and merges its
pull request first.

The branch's compiler can hide a runtime change that needs a compiler fix
stage 0 does not have, which breaks main's CI and the release, since both
build the compiler with stage 0. So a PR that changes `tools/compiler/` or
`runtime/` also runs, before it merges:

```bash
scripts/stage0-check.sh                    # with stage 0
scripts/stage0-check.sh --version 0.10.0   # with a release
```

It installs stage 0 with
`scripts/ci-install-toolchain.sh` into `target/pepper-home`, builds
`tools/compiler` with it (`scripts/ci-build-compiler.sh`, into
`target/compiler`), then runs the runtime's tests with stage 0's own
`pepper test`. Further arguments go to that `pepper test`. It needs
`GH_TOKEN` while the repository is private, and on macOS and Windows
LLVM's prefix, as `scripts/pepper-tests.sh` does (`PEPPER_LLVM_PREFIX`,
or this checkout's `.pep/llvm-prefix`).

## Tests that run the tools

Some tests run programs rather than call functions: `pep-build` on
programs, and the Pepper tools on files and folders, checking their
output and exit status as a user would see them.

| Test | What it runs |
| --- | --- |
| `tools/compiler/corpus_test.pep` | `pep-build -I tests` on each `tests/<Name>/test.pep`, then the program from the repository's root, which must exit with 0. With `WASI_SDK_PATH` set and wasmtime on the PATH (or `WASMTIME` naming it), each again for `wasm32-wasip1` under wasmtime; it says it skipped otherwise, except under CI on Linux, which provisions both (`scripts/ci-provision-wasi.sh`) and where it fails without them. A new `tests/<Name>/test.pep` joins the run. |
| `tools/compiler/programs_test.pep` | `pep-build` on the programs of `tools/compiler/testdata/`, each run with the arguments and environment it needs: `cli`'s `parse` and an `add_options` error, `os`'s environment and host, `time`'s zones (TZif files under `TZDIR`, `TZ`, the system's database), and `process`'s arguments, `exit` and the `atexit` handlers it runs, `main`'s arguments, children that are copies of the program, and `exec`; and a build with a runtime copied into a package's folder, which leaves that package's files out. |
| `tools/pep-doc/examples_test.pep` | `pep-build` on every example of the book, then the example (see [Building this documentation](docs.md)). |
| `tools/pep-fmt/repository_test.pep` | `format_source` in the test itself on every `.pep` file under `runtime/`, `tools/`, `tests/` and `docs/examples/`: each formats, formatting it again changes nothing, the syntax tree stays the same, and the files of `runtime/` and `tools/` are already formatted (`pep-fmt -w` fixes one that is not). |
| `tools/pep-fmt/cli_test.pep` | `pep-fmt` on standard input and on files and folders (`--check`, `-w`), its syntax errors and usage errors. |
| `tools/pepper/pepper_test.pep` | `pepper`, copied beside stand-in tools built from `tools/pepper/testdata/`; and every tool's `--version` against the version in each `tools/*/main.pep` (and pep-lsp's `tools/pep-lsp/arguments.pep`). |
| `tools/pep-test/pep_test_test.pep` | `pep-test` on test files it writes (tests that pass, fail, time out, leak an allocation or release one too many), from `tools/pep-test/testdata/` (named `.pep.txt` so that the suite's own run skips them). |
| `tools/pep-package/package_test.pep` | `pep-package` and `pep-build` on projects whose dependencies are bare git repositories in a test folder, and archives on a loopback server, including builds of one project side by side, which fetch once under `.pep/fetch.lock`; skipped without git. |
| `tools/pep-run/pep_run_test.pep` | `pep-run` building and running the programs in `tools/pep-run/testdata/` with a Pepper home of its own: arguments, exit status, working folder, the up-to-date rerun, compile errors and the options it refuses. |
| `tools/pep-new/pep_new_test.pep` | `pep-new` and `pep-init` scaffolding programs and packages into temporary folders, which `pepper build` and `pepper test` then build and test (a package with itself on the import path, as its `tests/run.sh` puts it); the refusal to overwrite, and the name and license errors. |
| `tools/pep-profile/profile_test.pep` | `pep-profile` on the recordings in `tools/pep-profile/testdata/`, and on a real program when samply or a working perf is installed (skipped otherwise). |

They find `pep-build` and the tools beside the test program or on the
PATH (`process.find_companion`), where `scripts/pepper-tests.sh` puts the
ones it builds from the checkout, so they test this checkout's tools. To
run one by hand, put that folder first on the PATH (after a run of the
script, or with the tools built there as the script builds them):

```bash
export PATH="$PWD/target/pepper-tests/bin:$PATH"
cd tools && pepper test pep-fmt/cli_test.pep
```

The `tool_testing` module (`tools/tool_testing/`) holds what they share:
`tool(name)` finds a tool, `run` and `run_with_input` run a
`process.Command` and read its output with Windows' line ends made
`\n`, `build_program` builds a program with `pep-build`, and
`expect_exit`, `expect_contains`, `expect_starts_with` and
`expect_ends_with` show the program's output when they fail.
`tool_testing.server`'s `serve_folder` serves a folder over HTTP on
loopback, for a test that downloads (`pep-install`, `pep-package`).

## Leaks fail a test

Each test counts the runtime's live allocations before and after it runs,
and fails when they differ:

```text
error: test 'parses_components' left 2 allocations behind
```

So a test needs no census of its own: every object it made must be
released by the time it returns. What the program keeps for good, such as
a global made on first use (`async.Lazy`), is made inside
`keep_for_the_program(() => { ... })` at the start of the test, which
leaves it out of the count.

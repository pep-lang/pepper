# Pepper TODO: current state

Refreshed 2026-10-17 (US Pacific times) from GitHub: open and closed issues and merged PRs of justinboswell/pepper at main `0bf270c3`. `issue-order.md` (owned by the Tickets thread, in its project files) is not readable from the machine that wrote this refresh, so the order below is GitHub's: bugs first, then the open tickets by number. Sources: `todo/backlog.md` (open tickets and standing rules), `todo/662.md` (the closed #662 handoff), `todo/225.md` (the closed #225 handoff).

## 1. Rules in force

- The self-hosting pause is over: #225 closed 2026-10-11 and the Rust compiler is gone (#803). Any ticket can run; bugs still go ahead of everything. Details: [backlog.md](todo/backlog.md#the-225-self-hosting-pause-ended).
- Merges: no merge queue (dropped 2026-10-10: no slots, no GO). Work threads validate locally and push draft PRs; the Tickets thread (cmsg_012Zh7b8ZDj18Ad9iEy5pFgNHKh2Ckw3CD3AmjkNwVz2SW, never resolved) merges latest main in and squash-merges with the full SHA. Bug fixes first; merges are not serialized or reordered. Details: [backlog.md](todo/backlog.md#merge-rules).
- Pre-merge checks: `scripts/pepper-tests.sh` (for a `tools/compiler` change, build the compiler from the tree with `scripts/ci-build-compiler.sh` and pass `target/compiler`); `target/pepper-tests/bin/pep-doc check`; after runtime changes `target/pepper-tests/bin/pep-fmt --check runtime tools`. Details: [backlog.md](todo/backlog.md#pre-merge-checks).
- CI runs on pushes to main and by hand, not on pull requests (#849); validate a PR locally or on the Mac Worker before its merge.
- Perf and profiling runs go on the Windows Worker (SDG-JBOSWELL), -O builds; state baseline SHA, build level, warm/cold.
- Releases: a `vX.Y.Z` tag publishes (Release, then Docs and VSIX). The Windows Worker pushes the tag after Justin's typed go in its thread.

## 2. In progress

### v0.9.3 release
- Version bump #896 merged as `7c5aac82` on 2026-10-16; the first Release run (tag on `7c5aac82`) failed at `--lto=full` on Windows (comdat) and macOS (undefined `PArray<Expression>.__release`), plus network failures on Linux and Docs during an outage. #903 fixed `--lto=full` (merged `7beef757`).
- Tag `v0.9.3` was force-moved to `9470e4e0` on 2026-10-16 20:59 PT (Justin, direct instruction); Release run 39000868057 and Docs run 39000868058 were building when this was written. v0.9.3 ships with #908 (`pep-lsp --version` prints `0.4.0-dev`) unless fixed before the release publishes; the fix is with the Mac Worker.
- Windows verification: main `7beef757` 398/0, 2/0, 409/0; `9470e4e0` 402/0, 2/0, 409/0; `43747167` 402/0, 2/0, 409/0; `--lto=full` builds of `tools/pepper` and `tools/pep-lsp` pass on `7beef757`.

### #697 Release a pepper-install-only archive; installer scripts bootstrap through it
- Part 1 merged: #890 (release the archive; `pep-install setup` and `uninstall`; verified on Windows 2026-10-16). Part 2: draft PR #894 "Install scripts bootstrap through pepper-install"; its `install.ps1` check passed on Windows at `b1c1abf0` (install, uninstall, expected failure for a home without uninstall support).
- Open bugs next to it: #891 (macOS archive holds AppleDouble `._*` files, so `pepper install add 0.9.2` fails on Macs), #908.

## 3. Open tickets (GitHub order: bugs, then by number)

- **#908** (bug) `pep-lsp --version` reports `0.4.0-dev`: `set-version.sh` never stamps it and the release test skips it. Fix with the Mac Worker.
- **#891** (bug) macOS 0.9.2 release archive holds `._*` files.
- **#823** pep-lsp: an edit right after a cold first analysis waits for the cache filler (58-94 s). It waited for #810 (closed 2026-10-17); #902 (merged) re-checks on the whole-program record. Check the 58-94 s case before closing.
- **#709** pepc: clean up `main.pep`, use the `cli` module, replace the `--compile-part` hack. Open.
- **#697** see section 2.
- **#635** skip zeroing new objects whose constructor writes every field (low priority).
- **#632** move the copy context and async worker keys onto native `[ThreadLocal]`.
- **#604** HTTP/2 client and server.
- **#571** io_uring multishot receive with a provided-buffer ring.
- **#393** tooling gaps (deprecation warnings for compiler-written calls, LSP warnings in imported files, debugger payload enums).
- **#280** yaml package.

Approaches and decisions for each: [backlog.md](todo/backlog.md).

## 4. Closed since the 2026-10-06 plan (each was PAUSED or STOPPED there)

| ticket | closed | landed as |
|---|---|---|
| #225 Self-host the compiler | 2026-10-11 | Rust removed #803 (10-10); pepc ships as pep-build #784; Pepper pep-lsp everywhere #806; releases v0.9.0, v0.9.1, v0.9.2 |
| #662 Pre-merge test pass too slow | 2026-10-12 | #748 (10-06), #838, #844; see [662.md](todo/662.md) |
| #810 cold self-build slower than the Rust-era compiler | 2026-10-17 | #857-#895 series; #887/#888 and #897/#903 for Windows and `--lto=full`; see [225.md](todo/225.md) |
| #712 pep-install `--force`, `--path` | 2026-10-13 | #854 |
| #713 CI and workers install the published toolchain | 2026-10-07 | closed on GitHub |
| #714 vscode-pepper finds toolchains, offers install | 2026-10-16 | #901 |
| #696 all tools are `pep.toml` projects | 2026-10-16 | #889 |
| #757 `pepper run` and `--entry` | 2026-10-16 | #898, #900 |
| #758 README | 2026-10-16 | #899 |
| #658 early-outs pass | 2026-10-17 | #905 runtime, #906 compiler, #907 pep-package |
| #805 `os.set_environment` | 2026-10-17 | #904 |
| #631 `[ThreadLocal]` on non-thread-safe types | 2026-10-17 | closed on GitHub |
| #128 `except` for `export * from` | 2026-10-17 | closed on GitHub |
| #245 text module, #237 json module | 2026-10-07 | closed on GitHub (landed earlier: #254, #412, #423, #472) |
| Windows hangs and cache bugs: #842, #843, #851, #852 | 2026-10-13 | #850, #853, #856, #855 |

# Pepper TODO: seamless handoff plan

Written 2026-10-06 (US Pacific times). Sources: `backlog.md` (ticket backlog, issue-order.md order), `662.md` (#662 handoff), `225.md` (#225 handoff). Nothing here is new fact; it is copied or summarized from those files.

## 1. Rules in force

- Self-hosting pause (Justin 07:56 PT 10-05): only #225 work and bugs run; every other ticket waits for the #225 cutover. No new Rust-compiler work. Bugs go ahead of everything. Exception: the pause is lifted for #662 only (662.md, 19:25 PT 10-06). Details: [backlog.md](todo/backlog.md#the-225-self-hosting-pause-justin-0756-pt-10-05).
- Merge queue lives in the Tickets thread (cmsg_012Zh7b8ZDj18Ad9iEy5pFgNREA47wPgk1ipqFeaYrnYz1); never resolve it; one merge at a time, bugs first; owners merge only after GO naming the main SHA. Details: [backlog.md](todo/backlog.md#merge-queue-rules).
- Pre-merge checks (no `cargo test`): `cargo build --release`; `scripts/pepper-tests.sh`; `target/release/pep-doc check`; after runtime changes `target/release/pep-fmt --check runtime tools`. Details: [backlog.md](todo/backlog.md#pre-merge-checks).
- Perf and profiling runs go on the Windows Worker (SDG-JBOSWELL), -O builds; state baseline SHA, build level, warm/cold.
- No new work assigned (Justin 12:20 PT 10-06, per 662.md): the #225 and #662 threads are both STOPPED, with no work in progress and nothing assigned. The merge queue is empty. Remaining work is recorded as backlog for a fresh session.

## 2. Active work items

### #225 Self-host the compiler
- Handoff: [225.md](todo/225.md) and [backlog.md](todo/backlog.md#225-self-host-the-compiler-write-pepper-in-pepper)
- State (from 225.md, 19:25 PT 10-06): STOPPED after PR #747 merged as 81f64c08 (no longer in flight); no work in progress. main.pep edit rebuild 34.6 s to 14.0 s, driver edit 61 s to 41.5 s, cold 332-360 s to 301 s (about 210 s without layers). Next: main-layer sema (about 6.5 s), cold overhead, Windows timings, per-unit parallel sema, cutover, #709 last.

### #662 Faster pre-merge test pass
- Handoff: [662.md](todo/662.md) and [backlog.md](todo/backlog.md#662-pre-merge-test-pass-is-too-slow-profile-and-cut-it)
- State (662.md): STOPPED after PR #748 merged as ecfd183c (pepper-tests.sh 235 s vs 393 s on main, A/B on SDG-JBOSWELL). No work in progress and nothing assigned; the post-PR backlog is listed in 662.md.

## 3. Ticket backlog (issue-order.md order)

### Already done, close on GitHub
- Handoff: [backlog.md](todo/backlog.md#already-done-close-on-github)
- **#245** text module (Utf8, Utf16, Ascii). Landed in #254 (`runtime/text/`); the issue was never closed.
- **#237** json module. Part 1 `JsonValue` (#412), part 2 struct encode/decode (#423) and the #425 follow-ups (#472) are merged.

### #662 Pre-merge test pass is too slow: profile and cut it
- Handoff: [backlog.md](todo/backlog.md#662-pre-merge-test-pass-is-too-slow-profile-and-cut-it) and [662.md](todo/662.md)
- Priority: top of the feature list (Justin 10-04 23:09 PT "Those tests are taking way too long"). STOPPED after PR #748.
- Status: partly done. `cargo test` removed (#666, 595eb9a5); doc-comment and tool-page checks moved into `pep-doc check` (#667); docs examples became a Pepper test (#670, 146397b0). Remaining work is the three items in todo/662.md (-O2 vs -O1 on six slow passes tests, Rust sema cache-miss ticket, rebalance pep-doc examples tests).
- Depends on: nothing.
- Approach: measure per stage and per suite on optimized builds and post the numbers; cut the biggest costs (run independent stages in parallel, drop redundant rebuilds and reruns, share build artifacts, cache dependency fetches since tools tests clone packages, warm builds in the environment setup); post before/after timings. Perf runs go to the Windows Worker.

### #225 Self-host the compiler: write Pepper in Pepper
- Handoff: [backlog.md](todo/backlog.md#225-self-host-the-compiler-write-pepper-in-pepper) and [225.md](todo/225.md)
- Priority: critical path. NOT paused; the only feature work that runs. Owner threads: "#225" (pepc) and "#225 Shared parser, pepper-lsp and Pepper LSP".
- Status: through #746 on main (SHA 5592c683); parse step 6 `parse_recovering` merged as #731 (a710d6c2); PR #747 (StructTable reuses checked structs' entries) has a GO in flight. Sema is still the wall; recent -O2 numbers (4 Linux CPUs): cold ~301 s, main.pep edit ~14 s, driver edit ~41 s.
- Decisions (Justin 10-02, ticket comment): the Rust compiler stays stage 0 until the Pepper compiler passes everything, then builds switch to the previous release; a separate rewrite checked against the same test corpus, no glue between the two; `pep-doc` is ported to Pepper too (done, #693); LLVM pinned to 20.
- Acceptance (Justin 11:39 PT 10-05): compile AND link, full and incremental/editing builds, as fast or faster than rustc/clang on comparable work; measure against rustc/clang baselines and post numbers; run final timings on the Windows Worker once separate compilation lands; tests pass at least as fast as main. Every speedup with a measured gain lands (gains stack); never park one for being small; do not burn hours on a stuck sub-problem. Plans: `todo/pepc-build-speed/proposal.md`, `per-unit-sema-plan.md`, `sema-survey.md`; codegen plan in memory (pepc-codegen-plan).
- Remaining plan: parallel sema (tasks or a process per unit), modular overload naming, scheduler, Windows timings, cutover, then #709 last.
- Last step of the cutover (Justin 10-04/10-05): one straight-to-AST parser shared by the compiler, pep-fmt and a Pepper LSP; rewrite the LSP in Pepper on a generic Tower-style framework (repo `justinboswell/pepper-lsp`: LanguageServer trait, serve_stdio, Client, TextDocument UTF-16), pep-lsp built on it. Plan: `/mnt/project-files/shared-parser/plan.md` (steps 1-6 done, step 7 after cutover). The Pepper pep-lsp (tools/pep-lsp) is now the editor server that releases and the vsix ship; the Rust tools/lsp is built nowhere (Pepper sema speed at last measurement, front-end ms load/merge/sema at last measurement: hello 104/37/1516; compiler main.pep 1175/629/102859, since improved).
- Ticket comment (error recovery): speed is not the blocker for the LSP (full parse 789 ms for 666 files); error recovery on half-typed code was the risk, now covered by #731.
- Rule: parse no slower than main.

### #712 pep-install: `--force` on add and update, `--path` to search more toolchain folders
- Handoff: [backlog.md](todo/backlog.md#712-pep-install---force-on-add-and-update---path-to-search-more-toolchain-folders)
- Priority: HIGH. PAUSED (Justin chose "Keep pause" 16:39 PT 10-05; Justin lifts it). Depends on: nothing; relates to #697 and #713.
- Status: not started.
- Approach (ticket): `--force` on `pep-install add` and `update` reinstalls over an existing toolchain (download, verify, unpack over a clean directory so no stale files remain, keep the old one if the new install fails). `--path <dir>` (repeatable) adds folders searched for toolchains besides the Pepper home; decide how `list`, `which`, `use`, `remove` and `pepper +<version>` treat toolchains found through it; default `PEPPER_TOOLCHAIN_PATH` mirroring the flag. Document every option in `docs/src/tools/pep-install.md` and the `pepper` page; tests in `tools/pep-install/install_test.pep`. The installer scripts pass options through, so flags must work from them.

### #713 CI and workers install the published toolchain; releases made on merge
- Handoff: [backlog.md](todo/backlog.md#713-ci-and-workers-install-the-published-toolchain-releases-made-on-merge)
- Priority: HIGH. PAUSED. Depends on: #697 (bootstrap archive and thin installers), a working release flow, and #712; keep consistent with #696.
- Status: not started.
- Approach (ticket): CI (`ci.yml`, `platform-test.yml`, `docs.yml`) and worker setups install the toolchain by running `scripts/install.sh` / `install.ps1`, then build and test with that toolchain; no job runs `cargo build --release` for the compiler; `scripts/pepper-tests.sh` and the pre-merge checks use the installed toolchain. Workers run `pep-install update`. When a merged PR changes the compiler or runtime (decide paths, e.g. `tools/compiler/`, `runtime/`, `crates/`), a release is made automatically with the minor SemVer bumped (`release.yml`, `scripts/release-build.sh`). Decide how a change needing its own new compiler is tested before its release exists (build the PR's compiler with the published one, for that PR's tests only).

### #696 Convert all tools to pep.toml projects after the cutover; update CI and release
- Handoff: [backlog.md](todo/backlog.md#696-convert-all-tools-to-peptoml-projects-after-the-cutover-update-ci-and-release)
- Priority: normal. PAUSED: starts after the #225 cutover is complete (Justin 10-05 11:58 PT).
- Approach (ticket): give each tool under `tools/` a `pep.toml` (`[package]`, `[build] entry/output`); shared code (`tools/syntax`, `tools/toolchain`) becomes a path dependency instead of `-I tools`; build every tool through the self-hosted driver's project mode in CI, `scripts/pepper-tests.sh` and `scripts/release-build.sh` with the #225 build cache; update the release archive build, smoke test and docs (`AGENTS.md`, `docs/src/tools/*.md`, `docs/src/contributing/`); remove the `-I tools` builds.

### #697 Release a pepper-install-only archive; installer scripts bootstrap through it
- Handoff: [backlog.md](todo/backlog.md#697-release-a-pepper-install-only-archive-installer-scripts-bootstrap-through-it)
- Priority: normal. PAUSED. Depends on: nothing hard; #712 and #713 build on it.
- Approach (ticket): `scripts/release-build.sh` and `release.yml` also publish `pepper-install-<version>-<target>.tar.gz` (`.zip` on Windows) with a `.sha256` and an entry in `SHA256SUMS`. `install.sh` / `install.ps1` download it, verify the checksum, extract `pepper-install` to a temp dir, run it with the user's options (latest toolchain by default) and clean up. Move installer logic `pepper-install` lacks into it (toolchain home layout, PATH setup, prerequisite checks, post-install check program, `--uninstall`, token for a private repo). Keep current script options working. Update `scripts/release-smoke-test.sh`, the install test and docs.

### #714 vscode-pepper: find existing Pepper toolchains, offer install or upgrade
- Handoff: [backlog.md](todo/backlog.md#714-vscode-pepper-find-existing-pepper-toolchains-offer-install-or-upgrade)
- Priority: LOW. PAUSED. Relates to #697 and #712.
- Approach (ticket, `tools/vscode-pepper`): find toolchains in `~/.pepper/toolchains`, the default toolchain, `PEPPER_TOOLCHAIN`, the one a project's `pep.toml` pins, and `--path` folders; when none or an old one is found, offer to install or upgrade via `pep-install` (or the install script) with progress and errors; use the found toolchain for the language server instead of assuming `PATH`; document in the extension README and `docs/src/tools/`.

### #709 pepc: clean up main.pep, use the cli module, replace the --compile-part hack
- Handoff: [225.md](todo/225.md) (item 6 of the #225 list)
- Handoff: [backlog.md](todo/backlog.md#709-pepc-clean-up-mainpep-use-the-cli-module-replace-the---compile-part-hack)
- Priority: LOW. Owned by the #225 thread, LAST item of the #225 list (not independently paused, but meant to be last).
- Approach (ticket): use the runtime `cli` module for argument parsing in `tools/compiler/main.pep`; replace the `args[1] == "--compile-part"` special case (runs part of a split build, `driver/parts.pep`) with a real documented option or subcommand. Run `build_cache_test` and `test_main_test` after.

### #658 Early-outs pass across runtime, compiler, tools and modules
- Handoff: [backlog.md](todo/backlog.md#658-early-outs-pass-across-runtime-compiler-tools-and-modules)
- Priority: normal. PAUSED: after #225 is complete (Justin 10-04 21:36 PT). Depends on: #225 done.
- Approach (ticket): rewrite deeply nested if/else (arrow pattern) as guard clauses and early returns, `continue` or `break`; one PR per area (runtime, compiler, tools, modules); no behavior changes, existing tests pass unchanged; run `pep-fmt` over changed files.

### #632 Move the copy context and async worker keys onto native `[ThreadLocal]`
- Handoff: [backlog.md](todo/backlog.md#632-move-the-copy-context-and-async-worker-keys-onto-native-threadlocal)
- Priority: normal (perf). PAUSED. Follow-up to #625 (PR #628).
- Approach (ticket): `_pep_copies()` in `runtime/copy.pep` and `_async_worker_key` in `runtime/async/task.pep` use OS thread-local keys (`pthread_getspecific` / `FlsGetValue`); move them to native `[ThreadLocal]` variables; measure a copy-heavy and a task-heavy benchmark and post before/after numbers (Windows Worker).

### #393 Tooling gaps: deprecation warnings for compiler-written calls, LSP warnings in imported files, debugger payload enums
- Handoff: [backlog.md](todo/backlog.md#393-tooling-gaps-deprecation-warnings-for-compiler-written-calls-lsp-warnings-in-imported-files-debugger-payload-enums)
- Priority: normal (assigned to justinboswell). PAUSED.
- Approach (ticket): warn when a deprecated method is called by compiler-written code (`for` loop `next()`/`current()`, `with` `enter()`, operator overloads), reported at the `for`/`with`/operator token with a note at the declaration; LSP publishes warnings for every program file (or at least open files), which needs an extension reinstall; debugger formatters in `runtime/debuggers/` (LLDB/GDB/natvis) switch on the tag to show only the active payload case (the union-layout issue for value enums changes the layout they read). Do the compiler part in the Pepper compiler only (no new Rust-compiler work).

### #280 yaml package: read and write YAML 1.2
- Handoff: [backlog.md](todo/backlog.md#280-yaml-package-read-and-write-yaml-12)
- Priority: normal. PAUSED. Repo: `justinboswell/pepper-yaml` (private, GitHub repo empty); package repos commit straight to their own main.
- Decisions (ticket, Justin 2026-09-30 and 10-02 comment): same shape as `json` (#237) and `toml`; YAML 1.2 core schema only (`yes`/`no`/`on`/`off` are strings); safe by default (unknown tags are errors); anchors and aliases with an expansion limit; multiple documents (`parse_all`); located clang-style errors; round trip keeps comments, key order and block/flow style (option to drop); struct conversion through reflection with the shared attributes `[Name]`, `[Ignore]`, `[Required]`, `[Tag]`, `[Untagged]`; keys keep their case. **Streaming comes later**: first version ships the tree reader and writer; an event-based reader only if a large-file use case shows up.

### #571 io_uring: multishot receive with a provided-buffer ring
- Handoff: [backlog.md](todo/backlog.md#571-io_uring-multishot-receive-with-a-provided-buffer-ring)
- Priority: LOW (Justin 10-03). PAUSED. Follow-up to #395.
- Approach (ticket): use `IORING_OP_RECV` with `IORING_RECV_MULTISHOT` (Linux 6.0) over a provided-buffer ring (`IORING_REGISTER_PBUF_RING`, 5.19); `read(buffer, max)` copies out of the completed ring buffer, keeps leftovers, returns the buffer; per-socket cap and backpressure; size the ring per worker; handle `ENOBUFS` by a one-shot fallback; keep #395's cancellation/timeout/`_forget` guarantees; kernels before 6.0 keep the one-shot path; optionally register file descriptors. Measure with `/mnt/project-files/event-loop-design/bench/echo.pep` at 64, 1,024, 4,096 connections vs epoll, with `perf`.

### #604 HTTP/2 client and server
- Handoff: [backlog.md](todo/backlog.md#604-http2-client-and-server)
- Priority: normal. PAUSED. Builds on #389 (streaming bodies, connection reuse via `Session`).
- Approach (ticket): ALPN negotiation (`h2` falling back to `http/1.1`), RFC 9113 frames, HPACK (RFC 7541, static and dynamic tables, Huffman), streams with states and errors, connection and stream flow control both ways; same request/response API as HTTP/1.1; reuse connections through `Session` (per-task `client.session()`); the server serves both versions. Done when a client fetches over HTTP/2 from a local test server with several concurrent streams, HPACK passes the RFC 7541 appendix C examples, and the `http` docs and doc comments describe it.

### #631 Allow `[ThreadLocal]` on types that are not thread-safe
- Handoff: [backlog.md](todo/backlog.md#631-allow-threadlocal-on-types-that-are-not-thread-safe)
- Priority: LOW (Justin 10-04: "finish other work first"). PAUSED. Follow-up to #625.
- Approach (ticket): allow `[ThreadLocal]` module-scope variables of non-thread-safe types (plain struct, `Array<T>`) with a confinement check that keeps references from leaving the thread; release the value at thread exit; update the language docs.

### #635 Skip zeroing new objects whose constructor writes every field
- Handoff: [backlog.md](todo/backlog.md#635-skip-zeroing-new-objects-whose-constructor-writes-every-field)
- Priority: LOW (Justin 10-04). PAUSED. Follow-up to #600 and #633. The self-hosted compiler must mirror the change.
- Approach (ticket): `_pep_malloc` always zeroes; when codegen can prove a constructor writes every field before any read, call a non-zeroing entry point (for example `_pep_malloc_uninit`), handling `__refcount` and any padding that hashing or equality reads.

### #128 Consider `except` for `export * from` re-exports
- Handoff: [backlog.md](todo/backlog.md#128-consider-except-for-export--from-re-exports)
- Priority: deferred on purpose. PAUSED. Pick it up only if the problem shows up (a module wants almost all of a file's exports but a few and the list form goes stale, or two `export *` sources collide on a few names).
- Sketch (ticket): `export * from <source> except [name, ...];`; unknown names are errors located at that name; excluded names do not count as re-exported; update the modules chapter, `tools/syntax/parser.pep` and pep-fmt.

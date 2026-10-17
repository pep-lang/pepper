# Ticket backlog and working rules (handoff)

Source: GitHub issues and merged PRs of justinboswell/pepper at main `0bf270c3`, refreshed 2026-10-17. `/mnt/project-files/issue-order/issue-order.md` (owned by the Tickets thread) was not readable from the machine that wrote this refresh, so ticket order here is GitHub's: bugs first, then by number. 11 issues open: 2 bugs (#908, #891) and 9 others. Times are US Pacific.

Read a ticket AND all its comments before starting it. Follow its approach. Check design history (project files, memory) before proposing anything, and never invent a technical default that could contradict the ticket.

## The #225 self-hosting pause ended

- #225 closed 2026-10-11 and the Rust compiler was removed (#803); there is one compiler. Every ticket may run now; the pause (Justin 07:56 PT 10-05) no longer applies, and "PAUSED" in older notes is obsolete.
- No Rust-compiler work exists any more.
- Bugs of any kind are NOT paused and go ahead of everything.
- #712 and #713 are closed (#854; 2026-10-07).


## Open tickets (GitHub order: bugs, then by number)

### #908 (bug) pep-lsp --version reports 0.4.0-dev
- `scripts/set-version.sh` never stamps `tools/pep-lsp`, and the release test (`every_tool_reports_the_release_version`) skips it. Found 2026-10-16 on the Windows Worker (`pep-lsp.exe --version` printed `pep-lsp 0.4.0-dev`). Fix is with the Mac Worker; v0.9.3 ships with it unless fixed first.

### #891 (bug) macOS 0.9.2 release archive holds AppleDouble `._*` files
- `pepper install add 0.9.2` is broken on Macs; the archive carries `._*` files. Fix the release build (`scripts/release-build.sh`), check the archive listing in the smoke test.

### #823 pep-lsp: an edit right after a cold first analysis waits for the cache filler (58-94 s)
- Depended on #810 (closed 2026-10-17). #902 (merged `0bf270c3`) makes an edit re-check on the whole-program record while the cache fills. Re-measure the 58-94 s case on a cold start before closing.

### #697 Release a pepper-install-only archive; installer scripts bootstrap through it
- Priority: normal. Depends on: nothing hard; #712 and #713 build on it.
- Approach (ticket): `scripts/release-build.sh` and `release.yml` also publish `pepper-install-<version>-<target>.tar.gz` (`.zip` on Windows) with a `.sha256` and an entry in `SHA256SUMS`. `install.sh` / `install.ps1` download it, verify the checksum, extract `pepper-install` to a temp dir, run it with the user's options (latest toolchain by default) and clean up. Move installer logic `pepper-install` lacks into it (toolchain home layout, PATH setup, prerequisite checks, post-install check program, `--uninstall`, token for a private repo). Keep current script options working. Update `scripts/release-smoke-test.sh`, the install test and docs.

### #709 pepc: clean up main.pep, use the cli module, replace the --compile-part hack
- Priority: LOW. Owned by the #225 thread, LAST item of the #225 list.
- Approach (ticket): use the runtime `cli` module for argument parsing in `tools/compiler/main.pep`; replace the `args[1] == "--compile-part"` special case (runs part of a split build, `driver/parts.pep`) with a real documented option or subcommand. Run `build_cache_test` and `test_main_test` after.

### #632 Move the copy context and async worker keys onto native `[ThreadLocal]`
- Priority: normal (perf). Follow-up to #625 (PR #628).
- Approach (ticket): `_pep_copies()` in `runtime/copy.pep` and `_async_worker_key` in `runtime/async/task.pep` use OS thread-local keys (`pthread_getspecific` / `FlsGetValue`); move them to native `[ThreadLocal]` variables; measure a copy-heavy and a task-heavy benchmark and post before/after numbers (Windows Worker).

### #393 Tooling gaps: deprecation warnings for compiler-written calls, LSP warnings in imported files, debugger payload enums
- Priority: normal (assigned to justinboswell).
- Approach (ticket): warn when a deprecated method is called by compiler-written code (`for` loop `next()`/`current()`, `with` `enter()`, operator overloads), reported at the `for`/`with`/operator token with a note at the declaration; LSP publishes warnings for every program file (or at least open files), which needs an extension reinstall; debugger formatters in `runtime/debuggers/` (LLDB/GDB/natvis) switch on the tag to show only the active payload case (the union-layout issue for value enums changes the layout they read). Do the compiler part in the Pepper compiler only (no new Rust-compiler work).

### #280 yaml package: read and write YAML 1.2
- Priority: normal. Repo: `justinboswell/pepper-yaml` (private, GitHub repo empty); package repos commit straight to their own main.
- Decisions (ticket, Justin 2026-09-30 and 10-02 comment): same shape as `json` (#237) and `toml`; YAML 1.2 core schema only (`yes`/`no`/`on`/`off` are strings); safe by default (unknown tags are errors); anchors and aliases with an expansion limit; multiple documents (`parse_all`); located clang-style errors; round trip keeps comments, key order and block/flow style (option to drop); struct conversion through reflection with the shared attributes `[Name]`, `[Ignore]`, `[Required]`, `[Tag]`, `[Untagged]`; keys keep their case. **Streaming comes later**: first version ships the tree reader and writer; an event-based reader only if a large-file use case shows up.

### #571 io_uring: multishot receive with a provided-buffer ring
- Priority: LOW (Justin 10-03). Follow-up to #395.
- Approach (ticket): use `IORING_OP_RECV` with `IORING_RECV_MULTISHOT` (Linux 6.0) over a provided-buffer ring (`IORING_REGISTER_PBUF_RING`, 5.19); `read(buffer, max)` copies out of the completed ring buffer, keeps leftovers, returns the buffer; per-socket cap and backpressure; size the ring per worker; handle `ENOBUFS` by a one-shot fallback; keep #395's cancellation/timeout/`_forget` guarantees; kernels before 6.0 keep the one-shot path; optionally register file descriptors. Measure with `/mnt/project-files/event-loop-design/bench/echo.pep` at 64, 1,024, 4,096 connections vs epoll, with `perf`.

### #604 HTTP/2 client and server
- Priority: normal. Builds on #389 (streaming bodies, connection reuse via `Session`).
- Approach (ticket): ALPN negotiation (`h2` falling back to `http/1.1`), RFC 9113 frames, HPACK (RFC 7541, static and dynamic tables, Huffman), streams with states and errors, connection and stream flow control both ways; same request/response API as HTTP/1.1; reuse connections through `Session` (per-task `client.session()`); the server serves both versions. Done when a client fetches over HTTP/2 from a local test server with several concurrent streams, HPACK passes the RFC 7541 appendix C examples, and the `http` docs and doc comments describe it.

### #635 Skip zeroing new objects whose constructor writes every field
- Priority: LOW (Justin 10-04). Follow-up to #600 and #633. The self-hosted compiler must mirror the change.
- Approach (ticket): `_pep_malloc` always zeroes; when codegen can prove a constructor writes every field before any read, call a non-zeroing entry point (for example `_pep_malloc_uninit`), handling `__refcount` and any padding that hashing or equality reads.

## Merge queue rules

- The queue lives in the Tickets thread (cmsg_012Zh7b8ZDj18Ad9iEy5pFgNREA47wPgk1ipqFeaYrnYz1). Never resolve that thread. One merge at a time; bugs go first, and a bug waits only for the merge already holding the slot.
- On an owner's request: check main (`git fetch origin main; git log -1 --format=%H origin/main`), then send GO naming the current main SHA. The owner merges main down if it moved, runs the pre-merge checks in its own container, squash-merges if green, and reports before and after with full SHAs. GitHub CI runs on pushes to main and by hand, not on pull requests (#849), so validate locally or on the Mac/Windows Worker before the merge.
- After each merge the Tickets thread verifies it on GitHub (`git log`, `git diff --stat <prev> origin/main`), checks whether an extension reinstall is needed, updates issue-order.md, and replies with the full SHA and diff size.
- Always merge main down before merging a PR, even when the diff looks unrelated. Never bundle kills with pushes. One topic per PR; a follow-up or a bug fix gets its own PR; never add follow-up work to a PR that is ready or being merged.
- Perf claims always state the baseline SHA and build level (`-O2` pepc self-build on N CPUs); perf and profiling runs go to the Windows Worker via the coordinator; numbers are reported in chat the moment they arrive.
- Threads: width 2 at a time; list the title as the ticket summary (not a bare number); prefer reusing an idle finished thread; keep the Windows Worker and Mac Worker threads alive (never resolve or stop them); call update_status before every command or wait; never block in one long wait, poll in short steps.

## Pre-merge checks

Run, in the owner's container, with the build of main installed (`sh scripts/install.sh --version "$(cat VERSION)"`):
1. `scripts/pepper-tests.sh` (for a `tools/compiler` change, also build pepc from it and pass its folder: see the README's "Build and test")
2. `target/pepper-tests/bin/pep-doc check`
3. After runtime changes: `target/pepper-tests/bin/pep-fmt --check runtime tools` (run `pep-fmt -w runtime tools` first when formatting is needed)

About 4 min warm, 10 min after a `tools/compiler` change, 12 min cold. Cloud threads need `justinboswell/pepper-llvm` and `justinboswell/pepper-lsp` attached (`add_repo`, read access) or tests fail with "could not read Username". If `tools/compiler` tests fail with "'Visibility' is not exported by 'llvm'", the container's `tools/compiler/.pep/deps` pepper-llvm is older than `pep.lock`: check out the locked commit or run `pep-package -C tools/compiler fetch`. Cloud container setup: `apt-get install llvm-20-dev libpolly-20-dev` (or `scripts/setup-llvm.sh`); perf: `linux-tools-generic`. Each worktree needs its own `PEPPER_TARGET_DIR` (or its own checkout's `target/`).

## Extension-reinstall rule

- The VS Code extension runs `tools/pep-lsp`, which builds on the compiler's front end, so reinstall it when a merge touches `tools/pep-lsp`, `tools/compiler`, `tools/syntax`, `runtime/` or the extension (`tools/vscode-pepper`). Check with: `git diff --stat <prev> origin/main | grep -E 'tools/(pep-lsp|compiler|syntax|vscode-pepper)/|runtime/'`.
- The reinstall (`scripts/install-vscode-extension.ps1`) runs ONLY from main, via the Windows Worker through the coordinator, after the change has merged. Last reinstalled on the Windows Worker at c7cea3f3 (#901, 14:54 PT 10-16, pepper-language 0.9.3); #902 (pep-lsp, 0bf270c3) merged after that and needs a reinstall.

## Other standing rules

- Design: simplicity and safety, code easy to read and reason about; concurrent code as easy as possible to write and reason about; no feature that masquerades as something else. Prefer early outs (guard clauses). Where user data drives recursion depth, use an explicit stack.
- Tests for runtime and non-compiler code go in Pepper (`pep-test` via `pepper test`), not Rust; one test program per module test folder.
- Documentation lands in the same PR as the change (see `AGENTS.md`); run `pep-fmt -w runtime tools` before committing; Pass non-trivial strings to CLI tools through files.
- Package repos (pepper-llvm, pepper-yaml, pepper-zip, pepper-lsp) commit straight to their own main when no compiler change is involved. Cloud sessions cannot push tags; the Windows Worker (RC session on Justin's machine) tags releases after Justin's typed go in its thread (v0.9.2 pushed 2026-10-12; v0.9.3 tag moved to 9470e4e0 on 2026-10-16). A tag push or force-move may be denied by the permission check until a Bash rule allows it.
- Nothing waits on Justin: pick the default, go, record his decisions. Do not delete `pepper-toml` (bundle in `/mnt/project-files/pepper-toml`) without his explicit go-ahead.


# Working in this repository

Conventions that apply to any agent (or person) working here. Tool-specific
workflows live in `.agents/skills/`; this file is for rules that hold
everywhere.

## Workflow

- Before doing any work, start a new branch from the current default.
- When the todo list completes, open a pull request for that branch (use
  `gh pr create --body-file` per the string rule above).

## Response style

- Keep responses as concise as possible.
- Lead with the answer; no pleasantries.
- Prefer bulleted lists to prose.

## Pass non-trivial strings to CLI tools through files, never inline

Any string longer than a few plain words — commit messages, PR bodies, review
text, JSON payloads, scripts — goes into a file, and the tool reads the file:

```bash
git commit -F message.txt                       # not -m "$(cat <<'EOF' ...)"
gh pr create --body-file body.md                # not --body "..."
gh api ... --input payload.json                 # not -f body='...'
gh api ... -F body=@body.md
```

Inline heredocs and quoted substitutions look fine and then fail in ways that
are easy to miss:

- **Backticks get evaluated.** A commit message containing `` `gh run watch` ``
  passed through `git commit -m "$(cat <<'EOF' … EOF)"` actually *executed*
  `gh run watch`, whose usage error was spliced into the message and left git
  parsing the remainder as pathspecs. A quoted heredoc delimiter is not
  sufficient protection once another shell layer is involved.
- **Quotes and `$` interpolate or vanish.** Apostrophes, `"`, `$var`, `!`, and
  newlines each have their own failure mode depending on the quoting layer that
  happens to be in play.
- **Truncation is silent.** A mangled argument frequently still produces a
  successful-looking command, so the damage surfaces later — as a wrong commit
  message, a half-written PR body, or a corrupted API payload.

There is no length at which inline becomes "safe enough" to be worth the risk;
writing a file costs one extra step and removes the whole class of failure.
Delete the temporary file afterwards, and keep it out of commits — or write it
somewhere already ignored.

In GitHub Actions, the same rule takes a different form: untrusted or
non-trivial values reach a `run:` body through `env:`, never through `${{ }}`
interpolation, which splices text into the script before bash parses it.

## Make cross-platform CI runs fail fast, and say why

A `platform-test` dispatch is a slow, expensive question: minutes of wall
clock, and GitHub exposes **no partial log for a step that is still running**,
so a job that hangs looks identical to one that is working. Every run that
ends without a usable answer costs another round. So:

- **Scripts run under `bash -euxo pipefail`.** Without `-e` the script
  continues past the failure you care about and buries it hundreds of lines
  up; without `-x` the log is output with no indication of which command
  produced it. Something that must continue past a failure says `|| true` at
  that line, deliberately.

  Those flags govern the *wrapper* shell only. A dispatched
  `bash probe.sh` is a new shell with its own options, so a script **file**
  sets `set -euo pipefail` itself — otherwise it sails past every failure and
  the job reports success having answered nothing, which is a wasted run that
  looks like a good one.
- **Bound every phase**, but note macOS ships no GNU `timeout`: the job's and
  steps' `timeout-minutes` are the portable bound, and a script that wraps
  individual commands has to tolerate the command being absent.
- **Never pipe the interesting command through `tail` or `head`.** A
  `| tail -8` around a provisioning step once hid the one line that explained
  a 25-minute stall, and cost two extra runs to recover. Filter *noise*
  (progress bars, `Reading database …`) by pattern, not by position.
- **Collect the state a failure is about in the same run.** The workflow has
  an `if: failure() || cancelled()` diagnostics step (toolchain, host, the
  LLVM cargo actually sees, which `clang` answered, build artifacts) —
  cancellation is included because a job killed by its timeout is exactly
  when that state is wanted, and `failure()` is false then. Extend it rather
  than re-dispatching to ask a follow-up question.
- **Ask several questions per run.** Independent checks belong in one script
  with clear `=== section` markers, since the cost is per run, not per check.


## Reference counting is std::shared_ptr<T> passed by value — always

Every struct reference in Pepper behaves exactly like a `std::shared_ptr<T>`
value. For any construct, ask what C++ would do if that expression were a
`shared_ptr<T>`, and emit the acquire/release calls in exactly that order. No
ad-hoc refcount rules, no extra categories of references, and **no such thing
as a borrowed reference** — if a design needs a "borrow" concept, it is wrong
under this model.

The whole model, as a construct mapping:

- `var x = Foo();` ≡ `shared_ptr<T> x = make_shared<T>();` — construction
  leaves `__refcount == 0`; the slot that first receives the value acquires
  (the "first owner").
- Reading a place (`x`, `x.f`, `x[i]`) yields a **reference** to the stored
  value, like C++ `T&`. The read itself does no refcount work. Copying that
  reference into a new shared_ptr — var init, assignment RHS, function
  argument, return — is a `shared_ptr` copy: acquire.
- `y = z;` ≡ `shared_ptr::operator=`: acquire the new value, release the
  slot's old occupant. Self-assignment (`a = a`, including `x[i] = x[i]`) is
  a no-op, as in C++.
- By-value parameter ≡ pass by value: acquire at entry, release at function
  exit — exactly like a shared_ptr local going out of scope.
- `x.m()` ≡ `x->m()`: the receiver is accessed as `this`, a reference — no
  copy, no refcount work on the receiver. The call result is a temporary
  owning one reference: the return site acquires when it copies `this`, a
  field, or an element; for an owned local its ref moves out (emitted as
  acquire-at-return plus the slot's normal exit release — net-identical to a
  move, no moved-from tracking).
- A discarded temporary (call/ctor result not bound to anything) is an
  unnamed shared_ptr destroyed at the end of the full expression: release
  once. That includes a call result used as an argument after the call and
  the receiver of `f().g()`.

Everything else — scope exit, parameter exit, store-release-old — follows
from "every owned value releases exactly once when it goes out of scope".

## Compiler errors are clang-style diagnostics, located at the exact token

Every error the compiler, the language server, or a test harness shows is a
`pepper_parser::diagnostic::Diagnostic`, rendered like clang:

```
main.pep:3:16: error: use of undeclared identifier 'nope'
    3 |     return a + nope;
      |                ^~~~
main.pep:1:1: note: declared here
    1 | ...
```

- **Always attach a location.** An error without `file:line:col` and a caret
  is a bug. Locate it at the token the user must change: the name, the
  operator, the attribute. Do not use the enclosing statement or function.
  Use a note (`with_note(message, Some(loc))`) when a second place explains
  the first, such as "declared here", "to match this '{'", or "type alias X
  declared here".
- **Word messages like clang.** Start in lowercase, with no trailing period.
  Put identifiers and types in single quotes (`'x'`, `'Box<int>'`). Say what
  is wrong and, when it is cheap, what to do instead.
  - `use of undeclared identifier 'x'`
  - `no member named 'm' in 'S'`
  - `too many arguments to 'f': expected 2, have 3`
  - `expected ';'`
- **Report errors; never panic** on anything a user can write. Each layer has
  its own way to do this:
  - **Parser:** record what was expected at the failure with `expected()` or
    `cut_expecting()`. The furthest failure wins. `parse_source_diag` turns it
    into the diagnostic.
  - **Sema builder:** return `Diagnostic` with `.at(loc(span))`. `loc` stamps
    the file being built.
  - **Sema passes:** call `errors::report(diagnostic)` and carry on.
    `transform_pass` stops after the pass that reported and returns the first
    error.
  - **Codegen:** return `Err(String)` from inside a located node.
    `locate`/`error_loc` attach the innermost node's location, so a new model
    node that can fail must carry a `loc` and go through the `*_unlocated`
    wrapper pattern.
- **Every model node that names something carries a `Loc`.** That covers
  references, calls, operators and declarations. Nodes that sema synthesizes
  copy the `Loc` of the source they stand for (a `for` loop's hidden iterator
  uses the iterable's). Use `Loc::NONE` only when no source exists.
- **Render only at the boundary.** Driver entry points and test harnesses
  return `String`s rendered with `module.sources` (or `Program`). Nothing
  below that formats `file:line:col` by hand.
- **Test the rendered output** for a new error in
  `crates/pepper-driver/tests/diagnostic_tests.rs`: the header line, the
  source line, and the caret.

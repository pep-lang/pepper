# Working in this repository

Conventions that apply to any agent (or person) working here. Tool-specific
workflows live in `.agents/skills/`; this file is for rules that hold
everywhere.

[`INTERNALS.md`](INTERNALS.md) is the map of the compiler: where each stage
lives, how it works, and the patterns the code follows. User-facing
documentation is the book in `docs/` (see `docs/src/contributing/docs.md`).

## Workflow

- Before doing any work, start a new branch from the current default.
- When the todo list completes, open a pull request for that branch (use
  `gh pr create --body-file` per the string rule above).
- Update the documentation in the same PR as the change it describes (see
  below).

## Keep the documentation current

Documentation changes land in the same PR as the code they describe. Before
opening a PR, check each of these against the diff:

- **Language behavior** (syntax, semantics, a new or changed error, a lifted
  limitation): update the chapter in `docs/src/language/` that covers it,
  including any limitation it states ("not supported yet"), and add or
  change an example in `docs/examples/`. A new feature with no chapter gets
  one, listed in `docs/src/SUMMARY.md`. A deprecation also gets a row in the
  table in `docs/src/language/compiler-errors.md`. Grep the whole book for
  the limitation a change lifts ("not supported", "not yet", "cannot"), since
  it is often repeated in other chapters and in the "Current status" list of
  `docs/src/introduction.md`.
- **Runtime or library API**: write or update its `##` doc comment (see
  [the standard](#library-code-is-documented-with--doc-comments)), then run
  `cargo run -p pepper-docgen -- reference` and commit the regenerated
  `docs/src/reference/`.
- **Compiler structure** (a crate, stage, pass, file, or pattern that
  INTERNALS.md names moves, is added, or changes): update INTERNALS.md.
- **CLI, setup, or tooling**: document every option, command and
  environment variable in the tool's page, `docs/src/tools/<tool>.md`
  (`cargo setup`'s is `docs/src/contributing/setup.md`); update README.md
  and, when it affects writing the docs, `docs/src/contributing/docs.md`.

CI enforces what it can: `runtime_docs_tests` fails on an undocumented
public runtime declaration, `tool_docs_tests` on a tool option missing from
its page, `docs_examples_tests` compiles and runs every
example, and `pep-doc check` fails when the reference is stale. It
cannot tell whether prose still matches the compiler, so that part is on
the author.

## Response style

- Keep responses as concise as possible.
- Lead with the answer; no pleasantries.
- Prefer bulleted lists to prose.

## Reuse helpers; never copy them

Before writing a helper, look for one that already does the job, and when a
second place needs a helper, move it somewhere both can share rather than
pasting a copy. Copies drift: an audit once found 20 identical copies of one
test helper, and near-copies that had quietly diverged.

- **Rust integration tests** (`crates/pepper-driver/tests/integration/`):
  shared helpers live in `support/mod.rs` (`compile_jit_with_runtime`,
  `jit_census`, `sema`, `compile_error`, `repo_root`, `parallel_map`, ...).
  Import them (`use crate::support::jit_census;`); a helper a second test
  file needs moves there.
- **Pepper code** (`runtime/`, `tools/`, examples): use the runtime's API
  (`String.find`, `split`, `replace`, interpolation, `math.parse_int`, ...)
  instead of a hand-rolled byte loop, and add a missing function to the
  runtime rather than writing a private one in each caller.

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
  The one exception is where the copy is made, never whether: for a
  `String` parameter the function neither keeps nor changes
  (`passes::static_strings`), the caller makes the copy before the call
  and drops it after, as the Itanium C++ ABI does, so a shared string
  literal passes with no count step.
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

Threads do not change the model. A struct declared `[Shared]` (and every
`shared` function type, `shared (T) => R`) steps its counts atomically, like
`shared_ptr`'s control block; every other struct, and every plain function
type, uses plain increments and must stay on one thread.
`check_shared_types` requires a `[Shared]` struct's fields to be `const` and
thread-safe. Every module-scope variable, exported or not, is implicitly
`[Shared]`: any thread can reach it, so it must be `const` and thread-safe
too (a global that changes is an `Atomic<T>` or a `ThreadLocal<T>`).

`__weak<T>` is `std::weak_ptr<T>`, and the same rules apply to it on the weak
count: copies acquire, scope exit releases. `__weak_from<T>(t)` is
`weak_ptr(t)` and `__weak_upgrade<T>(w)` is `w.lock()`; both return a new
reference (an owned temporary). Neither kind converts to the other
implicitly.

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
  `crates/pepper-driver/tests/integration/diagnostic_tests.rs`: the header line, the
  source line, and the caret.

## Names follow the Pepper naming conventions

All Pepper code here (the runtime, `tools/`, `docs/examples/`, `tests/`, and
Pepper source embedded in Rust tests) follows
[`docs/src/language/naming.md`](docs/src/language/naming.md):

- Types (structs, traits, type aliases) are `PascalCase`; acronyms are words
  (`IoError`).
- Generic parameters are one capital letter (`T`) or `PascalCase` (`TValue`).
- Data members, methods, free functions, parameters, locals, and module-scope
  variables are `snake_case`.
- Constants (a `const` holding a fixed value such as a number, string, or
  character) are `SCREAMING_CASE` (`LINE_WIDTH`); a `const` holding an object
  (`Atomic<int>`) is a variable and stays `snake_case`.
- A private data member or method starts with `_` (`_size`, `_grow`), and so
  does a runtime helper shared between files but not public (`_pep_malloc`).
- Spell words out (`iterate`, `index`, not `iter`, `idx`).
- `extern` declarations keep the C library's name (`GetCurrentThreadId`).

Renaming a public runtime function, method, type, or variable keeps the old
name working behind `[Deprecated("use 'new_name' instead", "new_name")]` (see
"Deprecating" below) and migrates the runtime's own uses in the same PR. A
data member cannot answer to two names, so a renamed public field changes
outright; say so in the PR.

## Attributes go one per line, above their target

In all Pepper code, each attribute sits on its own line, and the declaration
it applies to starts on the next line, as `pep-fmt` writes it:

```pepper
[Target(OS(Linux))]
[Deprecated("use 'open' instead", "open")]
export open_file(path: String): int { ... }
```

The exception is a parameter: its attributes stay on its line, in front of
it (`construct([Sending] T value)`).

## Run pep-fmt over runtime/ and tools/ before committing

Every `.pep` file under `runtime/` and `tools/` is kept in `pep-fmt`'s
style, and `pep_fmt_sources_are_formatted` fails CI on any file that is
not. So any change there, a new file or an edit, goes through `pep-fmt`
before it is committed:

```bash
cargo run --release -- -I tools tools/pep-fmt/main.pep -o pep-fmt
./pep-fmt -w runtime tools     # rewrite what is not formatted
./pep-fmt --check runtime tools  # lists nothing when all is formatted
```

After a merge from the default branch that touches these folders, run it
again: a conflict resolved by hand is rarely formatted. Code whose layout
must stay as written goes between `# format: off` and `# format: on`.

## Library code is documented with `##` doc comments

Every public declaration in library code (`runtime/`, and any library added
later) carries a doc comment directly above it (above its attributes, with
no blank line between): a run of `##` lines in a JSDoc-like format. Pepper's
only comment syntax is `#`; a doc comment is just `#` comments starting
`##`. Public means exported and not `_`-prefixed, plus every
non-`_` field, constructor, and method of such a struct, trait, or
extension. `_`-prefixed names (`_pep_malloc`, `_io_sys_open`) are internals
shared between runtime files and are exempt.

```pepper
## Removes and returns the element at `index`, shifting later elements down.
##
## Runs in O(count - index).
##
## @param index position of the element to remove
## @returns the removed element
## @panics if `index` is not less than `count()`
## @example
##     var a = Array<int>();
##     a.append(1);
##     a.append(2);
##     var x = a.remove_at(0);   # x == 1; a holds [2]
T remove_at(ulong index) { ... }
```

- **Description first**: what it does, in the third person ("Returns …",
  "Appends …"), then what a caller needs: edge cases, ownership, cost,
  platform differences. Markdown; code in backticks.
- **Tags**, each described (lowercase start, no trailing period):
  `@typeParam T` for each generic parameter of a generic struct, trait,
  alias, or function; `@param name` for each parameter, constructors
  included; `@returns` whenever a value is returned (for `IoResult<T>`, say
  what the value is and when it fails); `@panics` for every `assert`/`panic`
  a caller can trigger. Optional: `@example` (indented code), `@see`,
  `@note`.
- A field or type alias may use a single line: `## The byte length.`
- A `##` block at the top of a file, followed by a blank line, introduces
  that file's page in the reference.
- Keep implementation notes that only matter to maintainers in `#` comments
  inside the body; the doc comment is the API contract.
- **Compiler built-ins** (`reflect.*`) are documented the same way, by a
  declaration in the runtime marked `[__BuiltIn]` (`[__BuiltIn("reflect.name")]`
  when the built-in's name is not the declaration's), with an empty body.
  The compiler ignores it; the reference and the language server read it.
- **Deprecating** a public API: put `[Deprecated("use 'x' instead", "x")]`
  between its doc comment and the declaration, and start the description
  with "Deprecated: use `x` instead." (the reference shows the attribute
  only inside the signature). Every use outside a deprecated declaration
  then warns, in every program, so migrate the runtime's own uses in the
  same PR.
- **Enforced**: `crates/pepper-driver/tests/integration/runtime_docs_tests.rs` runs
  `pepper_parser::doc::check_documented` over every `.pep` file under
  `runtime/` and fails with a clang-style error for each public declaration
  without a comment, description, or required tag, and for tags naming a
  parameter that does not exist. The language server shows these comments on
  hover.

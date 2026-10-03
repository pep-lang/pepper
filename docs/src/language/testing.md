# Unit tests

A unit test is a function marked `[Test]`: it takes no parameters, returns
nothing, and passes when it returns. It checks what the code under test
does with `expect_equal` and the other `expect_*` functions, which are in
the prelude, so a test file needs no import:

```pepper
{{#include ../../examples/testing-basics.pep}}
```

`pepper test` (the [`pep-test`](../tools/pep-test.md) tool) builds the
tests and runs them:

```text
$ pepper test words_test.pep
running 3 tests
test counts_the_words ... ok
test an_empty_string_has_no_words ... ok
test reading_past_the_last_word_panics ... ok
3 passed, 0 failed
```

Given a folder, or nothing (the current folder), it runs every test in the
`.pep` files under it. Its exit status is 0 only when every test passes.

## Checks

Each check panics when it fails, as `assert` does, and reports what it
compared at the line of the call, so a failing test says where and why:

```text
words_test.pep:14:5: panic: expect_equal failed
  actual:   2
  expected: 3
```

| Check | Fails when |
| --- | --- |
| `expect_equal(actual, expected)` | `actual == expected` is false; prints both |
| `expect_not_equal(actual, unexpected)` | the two are equal; prints the value |
| `expect_true(condition)` | `condition` is false |
| `expect_false(condition)` | `condition` is true |

`expect_equal` and `expect_not_equal` take two values of one type that has
`==` and a text form (see `to_string` in [String
interpolation](interpolation.md)). `assert` and `panic` fail a test too:
any panic does.

## Tests that should panic

`[ShouldPanic]` turns a test around: it passes only when it panics. With a
message, `[ShouldPanic("out of bounds")]`, the panic's message must also
contain that text, so a test does not pass on some other panic. A
`[ShouldPanic]` test that returns fails.

## How tests run

Each test runs in a child process of its own, so a panic, a crash or a
test that never ends fails only that test, and the others carry on. Tests
run in parallel, one per logical CPU (`--jobs 1` runs them one at a time,
in order), and a test still running after 60 seconds fails (`--timeout`
changes the limit). Tests share no state: each process starts fresh.

A test also fails when it leaks: the test program counts the live
allocations before and after the test, and a test that returns with more
(or fewer) than it started with fails, saying how many it left behind:

```text
error: test 'counts_the_words' left 1 allocation behind
```

What a program makes once and keeps until it ends, such as a global made
on first use, is not a leak. A test that is first to use it wraps that
use in `keep_for_the_program`, which runs it and leaves what it allocates
out of the count:

```pepper
keep_for_the_program(() => {
    tls.TlsConnector.create();   # loads the TLS library, which stays loaded
});
```

There is no setup or teardown: a fixture is a plain function that a test
calls, and what it makes is released when the test's scope ends, as
everywhere else. A struct whose destructor cleans up makes a fixture that
tears itself down. `TempFolder`, which every test file can use, is one: a
fresh folder under the system's temporary folder, removed with what is in
it when the test returns:

```pepper
import io;

[Test]
writes_a_file() {
    var folder = TempFolder("writes_a_file");
    var path = folder.path.join("notes.txt");
    io.File.write_text(path, "hello");
    expect_equal(io.File.read_to_string(path).value(), "hello");
}
```

## Where tests live

A test can sit beside the code it tests, where it can call the file's
private functions, as above. Or tests can live in their own files, such as
a module's `tests/` folder, where they import the module and see its public
API; `pepper test -I <dir>` adds the folder that holds the module to the
import path:

```text
geometry/
  module.pep
  shapes.pep
  tests/
    area_test.pep      # import geometry; [Test] functions
```

```bash
pepper test -I . geometry/tests
```

`pep-test` looks at each `.pep` file under the folders it is given and
builds those with a line that starts with `[Test]`: each such file is the
entry file of one test program, and its own `[Test]` functions are the
program's tests. Folders whose names start with `.` are skipped.

## Test builds

A normal build leaves `[Test]` functions out, so they cost nothing, and a
file of tests can keep a `main` of its own. `pep-build --test`, which
`pep-test` uses, builds the test program instead:

- it keeps the `[Test]` functions and defines the
  [build option](build-options.md) `TEST`, so code only the tests use
  (a fixture that would be unused otherwise) can be marked
  `[BuildOption("TEST")]`;
- it replaces the entry file's `main` with one that answers `--list` (each
  test, one per line) and `--run NAME` (run one test), which is how
  `pep-test` drives it.

A `[Test]` function that takes parameters, returns a value or is generic is
an error, as are `[Test]` on a method and `[ShouldPanic]` without `[Test]`:

```text
main.pep:2:8: error: test 'checks' must take no parameters
    2 | checks(x: int) {}
      |        ^
```

Since `[Test]` bodies are left out of a normal build, the language server
does not check them unless it analyzes with the build option `TEST`: add
`"TEST"` to the `pepper.buildOptions` setting (see
[pep-lsp](../tools/pep-lsp.md)).

Tests that compare a program's printed output with an expected file are
not supported yet.

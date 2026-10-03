# Testing with pep-test

`pep-test` builds the `[Test]` functions of Pepper files and runs them,
each in a child process of its own, reporting which pass. Writing tests is
covered in [Unit tests](../language/testing.md).

```bash
pepper test                          # every test under the current folder
pepper test src/words_test.pep       # the tests of one file
pepper test -f words src             # only tests whose name contains "words"
pepper test --list src               # list them without running them
pepper test -I . geometry/tests      # tests that import the module geometry
```

```text
running 3 tests
test counts_the_words ... ok
test an_empty_string_has_no_words ... ok
test reading_past_the_last_word_panics ... ok
3 passed, 0 failed
```

`pep-test` is written in Pepper (`tools/pep-test`). Build it with the
compiler and put it next to `pepper` and `pep-build`, so that `pepper test`
finds it and it finds the compiler:

```bash
target/release/pep-build tools/pep-test/main.pep -o target/release/pep-test
```

## Usage and options

```text
pep-test [options] [path]...
```

| Option | What it does | Default |
| --- | --- | --- |
| `<path>` | A `.pep` file to test, or a folder to search for files holding `[Test]` functions; repeatable | the current folder |
| `-f <text>`, `--filter <text>` | Run only the tests whose name contains the text; repeated, any of them | every test |
| `-l`, `--list` | List the tests instead of running them | |
| `-j <count>`, `--jobs <count>` | How many tests run at once | one per logical CPU |
| `-t <seconds>`, `--timeout <seconds>` | Fail a test still running after this long; `0` for no limit | 60 |
| `-I <dir>`, `--import-path <dir>` | A folder `pep-build` searches for imports; repeatable | |
| `-D <option>`, `--define <option>` | A [build option](../language/build-options.md) for `pep-build`, `NAME` or `NAME=VALUE`; repeatable | |
| `-h`, `--help` | Prints the usage and these options | |
| `-V`, `--version` | Prints `pep-test` and its version | |

The exit status is 0 when every file builds and every test passes, 1 when
a test fails or a file does not build, and 2 for a usage error.

## What it does

1. **Finds the files.** A file named on the command line is tested as it
   is. In a folder, and the folders below it (except those whose names
   start with `.`), it takes each `.pep` file with a line that starts with
   `[Test]`.
2. **Builds a test program for each,** with `pep-build --test` (found next
   to `pep-test`, else on the `PATH`), in parallel. A file that does not
   build is reported with the compiler's errors, and the other files'
   tests still run.
3. **Lists each program's tests** with `--list` and keeps those that match
   `--filter`. With `--list` it prints them and stops: the test's name, or
   `file::name` when the tests come from more than one file.
4. **Runs each test** as `program --run NAME --timeout SECONDS`, up to
   `--jobs` at once, and prints `test NAME ... ok` or `... FAILED` as each
   ends (in order with `--jobs 1`). A test passes when its process exits
   with 0; a `[ShouldPanic]` test passes when its process panics with a
   message that contains the attribute's text.
5. **Reports the failures,** each with what the test printed (the panic's
   message and location) and why it failed, then a summary:
   `2 passed, 1 failed`, with the number of tests `--filter` left out and of
   files that did not build when there are any.

The test programs are built in a temporary folder that is removed at the
end. A test runs in the current folder, with `PEPPER_BACKTRACE=0` unless
`PEPPER_BACKTRACE` is set, so a panic prints its message without a
backtrace.

## The test program

`pep-build --test` builds a file's test program (see [pep-build](pep-build.md#--test)),
which `pep-test` runs with one of two requests:

- `--list` prints a line per test, its fields separated by tabs: the name,
  `file:line`, `returns` or `panics` (a `[ShouldPanic]` test), and the text
  the panic must contain.
- `--run NAME [--timeout SECONDS]` runs one test and exits with 0 when it
  returns. A panic aborts the program; a test that runs past the timeout
  ends it with exit status 124.

On Windows, a test program turns off Windows Error Reporting for its
crashes and `abort()`, so a test that panics or crashes ends at once,
without a dialog.

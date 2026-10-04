<!-- Generated from runtime/testing/runner.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# TestRunner

The `main` of a test program: `TestRunner` holds the tests of the files
it was built from and answers `pep-test`'s `--list` and `--run NAME`.

Source: `runtime/testing/runner.pep`

## keep_for_the_program

```pepper
keep_for_the_program(body: () => void)
```

Runs `body` and lets what it leaves allocated stay without failing the
test's leak check: for what a program makes once, on first use, and keeps
until it ends, such as a lazily made global (`async.Lazy`), when a test is
the first to use it.

Call it at the start of the test, with the first use alone, so the rest
of the test is still checked.

**Parameters**
- `body` — the code that makes what the program keeps

**Example**
```pepper
import tls;

[Test]
connects() {
    # The first connector loads the TLS library, which stays loaded.
    keep_for_the_program(() => {
        tls.TlsConnector.create();
    });
    # ... the checks, under the leak check as usual
}
```

## TestMain

```pepper
[Attribute] struct TestMain
```

Marks the `main` that `pep-build --test` generates: in a test build it
replaces the entry file's own `main`.

## TestRunner

```pepper
struct TestRunner
```

The tests of one test program, which its generated `main` registers and
then runs with the program's arguments.

The program answers two requests, both made by `pep-test`:

- `--list` prints one line per test, its fields separated by tabs: the
  name, `file:line`, `returns` or `panics` (for `[ShouldPanic]`), and the
  text the panic must contain (empty for any panic or none).
- `--run NAME [--timeout SECONDS]` runs the test `NAME` (or `file::NAME`,
  which tells apart tests of one name in two files) and exits with 0
  when it returns, or with 1 when it left an allocation behind (or
  released one too many); a panic aborts the program. With a timeout above 0, a
  test still running after that many seconds ends the program with exit
  status 124 and a message on standard error.

### Constructor

#### TestRunner()

```pepper
construct(file: String)
```

Creates a runner for the tests of `file`.

**Parameters**
- `file` — the entry file's path, as `pep-build` was given it, or the folder of the files of a test program built from several

### Methods

#### from_file

```pepper
from_file(file: String)
```

Makes `file` the file of the tests registered after this call.

**Parameters**
- `file` — the path of the file that declares them, as `pep-build` was given it

#### add

```pepper
add(name: String, body: () => void, line: int)
```

Registers a test that passes when `body` returns.

**Parameters**
- `name` — the test function's name
- `body` — the test function
- `line` — the line that declares it

#### add_should_panic

```pepper
add_should_panic(name: String, body: () => void, line: int, message: String)
```

Registers a `[ShouldPanic]` test, which passes only when `body`
panics with a message containing `message`.

**Parameters**
- `name` — the test function's name
- `body` — the test function
- `line` — the line that declares it
- `message` — text the panic's message must contain; empty for any panic

#### run

```pepper
run(args: String[]): int
```

Answers the request `args` makes (see the struct's description).

**Parameters**
- `args` — the program's arguments, the program first

**Returns**
- the program's exit status: 0 when the request succeeded, 2 for a request it does not understand or a test it does not have

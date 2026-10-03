<!-- Generated from runtime/testing/runner.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# TestRunner

The `main` of a test program: `TestRunner` holds the entry file's tests
and answers `pep-test`'s `--list` and `--run NAME`.

Source: `runtime/testing/runner.pep`

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
- `--run NAME [--timeout SECONDS]` runs the test `NAME` and exits with 0
  when it returns; a panic aborts the program. With a timeout above 0, a
  test still running after that many seconds ends the program with exit
  status 124 and a message on standard error.

### Constructor

#### TestRunner()

```pepper
construct(file: String)
```

Creates a runner for the tests of `file`.

**Parameters**
- `file` — the entry file's path, as `pep-build` was given it

### Methods

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

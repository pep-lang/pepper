## The `main` of a test program: `TestRunner` holds the entry file's tests
## and answers `pep-test`'s `--list` and `--run NAME`.

import async;
import [File] from io;
import process;

extern void memcpy(void* destination, void* source, ulong size);

## Marks the `main` that `pep-build --test` generates: in a test build it
## replaces the entry file's own `main`.
[Attribute]
export struct TestMain {}

# One `[Test]` function, as the generated `main` registers it.
struct _TestCase {
    var name: String;
    var body: () => void;
    var line: int;
    var should_panic: bool;
    var panic_message: String;

    construct(name: String, body: () => void, line: int, should_panic: bool, panic_message: String) {
        this.name = name;
        this.body = body;
        this.line = line;
        this.should_panic = should_panic;
        this.panic_message = panic_message;
    }
}

## The tests of one test program, which its generated `main` registers and
## then runs with the program's arguments.
##
## The program answers two requests, both made by `pep-test`:
##
## - `--list` prints one line per test, its fields separated by tabs: the
##   name, `file:line`, `returns` or `panics` (for `[ShouldPanic]`), and the
##   text the panic must contain (empty for any panic or none).
## - `--run NAME [--timeout SECONDS]` runs the test `NAME` and exits with 0
##   when it returns; a panic aborts the program. With a timeout above 0, a
##   test still running after that many seconds ends the program with exit
##   status 124 and a message on standard error.
export struct TestRunner {
    var _file: String;
    var _tests: Array<_TestCase>;

    ## Creates a runner for the tests of `file`.
    ##
    ## @param file the entry file's path, as `pep-build` was given it
    construct(file: String) {
        _file = file;
        _tests = Array<_TestCase>();
    }

    ## Registers a test that passes when `body` returns.
    ##
    ## @param name the test function's name
    ## @param body the test function
    ## @param line the line that declares it
    add(name: String, body: () => void, line: int) {
        _tests.append(_TestCase(name, body, line, false, ""));
    }

    ## Registers a `[ShouldPanic]` test, which passes only when `body`
    ## panics with a message containing `message`.
    ##
    ## @param name the test function's name
    ## @param body the test function
    ## @param line the line that declares it
    ## @param message text the panic's message must contain; empty for any
    ##   panic
    add_should_panic(name: String, body: () => void, line: int, message: String) {
        _tests.append(_TestCase(name, body, line, true, message));
    }

    ## Answers the request `args` makes (see the struct's description).
    ##
    ## @param args the program's arguments, the program first
    ## @returns the program's exit status: 0 when the request succeeded, 2
    ##   for a request it does not understand or a test it does not have
    run(args: String[]): int {
        if (args.count == 2 and args[1] == "--list") {
            for (var test in _tests) {
                var kind = test.should_panic ? "panics" : "returns";
                print($"{test.name}\t{_file}:{test.line}\t{kind}\t{_one_line(test.panic_message)}");
            }
            return 0;
        }
        if ((args.count == 3 or args.count == 5) and args[1] == "--run") {
            ulong seconds = 0;
            if (args.count == 5) {
                var parsed = ulong.parse(args[4]);
                if (args[3] != "--timeout" or parsed.is_empty()) {
                    return _usage();
                }
                seconds = parsed.value();
            }
            for (var test in _tests) {
                if (test.name == args[2]) {
                    return _run(test, seconds);
                }
            }
            File.stderr().write_all($"error: no test named '{args[2]}' in {_file}\n");
            return 2;
        }
        return _usage();
    }

    # Runs `test`, ending the program after `seconds` (when not 0).
    _run(test: _TestCase, seconds: ulong): int {
        _end_crashes_at_once();
        if (seconds > 0) {
            var name = test.name;
            var limit = seconds;
            var message = $"error: test '{name}' timed out after {limit} {limit == 1 ? "second" : "seconds"}\n";
            var text = _pep_malloc(message.size + 1) as __ptr<char>;
            memcpy(text, message.c_str(), message.size + 1);
            # The watchdog is left running: the program ends when the test
            # returns, or the watchdog ends it.
            async.Thread.spawn(() => {
                async.Thread.sleep(limit * 1000);
                _pep_write_error(text);
                process.exit(124);
            });
        }
        var body = test.body;
        body();
        return 0;
    }

    _usage(): int {
        File.stderr().write_all(
            "error: this is a test program: run it with 'pepper test', or give it '--list' or '--run NAME [--timeout SECONDS]'\n"
        );
        return 2;
    }
}

# `text` on one line, for a tab-separated field: tabs and line breaks
# become spaces.
_one_line(text: String): String {
    return text.replace("\t", " ").replace("\r", " ").replace("\n", " ");
}

[Target(OS(Windows))]
extern uint _set_abort_behavior(uint flags, uint mask);
[Target(OS(Windows))]
extern uint SetErrorMode(uint mode);

# By default Windows hands `abort()`, and so a panic, and a crash to Windows
# Error Reporting, which can take seconds before the process ends (long
# enough for the timeout to fire) or open a dialog. A test that fails
# should end at once.
[Target(OS(Windows))]
_end_crashes_at_once() {
    # _WRITE_ABORT_MSG | _CALL_REPORTFAULT
    _set_abort_behavior(0, 3);
    # SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX
    SetErrorMode(3);
}

[Target(!OS(Windows))]
_end_crashes_at_once() {}

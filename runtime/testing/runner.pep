## The `main` of a test program: `TestRunner` holds the tests of the files
## it was built from and answers `pep-test`'s `--list` and `--run NAME`.

import async;
import [File] from io;
import process;

extern void memcpy(void* destination, void* source, ulong size);

# How many allocations the calls to `keep_for_the_program` left behind,
# which the leak check does not count against the test.
const _testing_kept = async.Atomic<long>(0);

## Runs `body` and lets what it leaves allocated stay without failing the
## test's leak check: for what a program makes once, on first use, and keeps
## until it ends, such as a lazily made global (`async.Lazy`), when a test is
## the first to use it.
##
## Call it at the start of the test, with the first use alone, so the rest
## of the test is still checked.
##
## @param body the code that makes what the program keeps
## @example
##     import tls;
##
##     [Test]
##     connects() {
##         # The first connector loads the TLS library, which stays loaded.
##         keep_for_the_program(() => {
##             tls.TlsConnector.create();
##         });
##         # ... the checks, under the leak check as usual
##     }
export keep_for_the_program(body: () => void) {
    var before = _pep_live_allocs();
    body();
    _testing_kept.fetch_add(_pep_live_allocs() - before);
}

## Marks the `main` that `pep-build --test` generates: in a test build it
## replaces the entry file's own `main`.
[Attribute]
export struct TestMain {}

# One `[Test]` function, as the generated `main` registers it.
struct _TestCase {
    var file: String;
    var name: String;
    var body: () => void;
    var line: int;
    var should_panic: bool;
    var panic_message: String;

    construct(file: String, name: String, body: () => void, line: int, should_panic: bool, panic_message: String) {
        this.file = file;
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
## - `--run NAME [--timeout SECONDS]` runs the test `NAME` (or `file::NAME`,
##   which tells apart tests of one name in two files) and exits with 0
##   when it returns, or with 1 when it left an allocation behind (or
##   released one too many); a panic aborts the program. With a timeout above 0, a
##   test still running after that many seconds ends the program with exit
##   status 124 and a message on standard error, and ends every process the
##   test started with it (a job object on Windows, a process group
##   elsewhere), so none holds `pep-test`'s pipes to its output open.
export struct TestRunner {
    var _file: String;
    var _adding: String;
    var _tests: Array<_TestCase>;

    ## Creates a runner for the tests of `file`.
    ##
    ## @param file the entry file's path, as `pep-build` was given it, or
    ##   the folder of the files of a test program built from several
    construct(file: String) {
        _file = file;
        _adding = file;
        _tests = Array<_TestCase>();
    }

    ## Makes `file` the file of the tests registered after this call.
    ##
    ## @param file the path of the file that declares them, as `pep-build`
    ##   was given it
    from_file(file: String) {
        _adding = file;
    }

    ## Registers a test that passes when `body` returns.
    ##
    ## @param name the test function's name
    ## @param body the test function
    ## @param line the line that declares it
    add(name: String, body: () => void, line: int) {
        _tests.append(_TestCase(_adding, name, body, line, false, ""));
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
        _tests.append(_TestCase(_adding, name, body, line, true, message));
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
                print($"{test.name}\t{test.file}:{test.line}\t{kind}\t{_one_line(test.panic_message)}");
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
                if (test.name == args[2] or $"{test.file}::{test.name}" == args[2]) {
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
            var tree = _own_the_process_tree();
            # The watchdog is left running: the program ends when the test
            # returns, or the watchdog ends it. The test waits until the
            # watchdog sleeps, so that nothing the new thread allocates as
            # it starts counts against the test.
            var sleeping = async.Atomic<int>(0);
            async.Thread.spawn(() => {
                sleeping.store(1);
                async.Thread.sleep(limit * 1000);
                _pep_write_error(text);
                _end_the_process_tree(tree, 124);
            });
            while (sleeping.load() == 0) {
                async.Thread.sleep(1);
            }
        }
        var body = test.body;
        # The first `Thread.current()` makes the main thread's `Thread` and
        # keeps it for the program's life: make it now, so a test that joins a
        # thread is not charged for it.
        async.Thread.current();
        var before = _pep_live_allocs();
        body();
        var leaked = _pep_live_allocs() - before - _testing_kept.load();
        if (leaked != 0) {
            var count = leaked == 1 or leaked == -1 ? "allocation" : "allocations";
            var what = leaked > 0 ? $"left {leaked} {count} behind" : $"released {-leaked} {count} too many";
            File.stderr().write_all($"error: test '{test.name}' {what}\n");
            return 1;
        }
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

# A timeout ends the processes the test started too, not just the program:
# one left running holds pep-test's pipes to the program's output open,
# and pep-test, reading them to their end, waits for it forever (#842).
# The program starts its own process tree before the test runs, and the
# timeout ends that tree.
#
# On Windows the tree is a job object (null when the program cannot join
# one); every process the test starts joins it, unless it breaks away.
[Target(OS(Windows))]
type _ProcessTree = __ptr<void>;

[Target(OS(Windows))]
extern void* CreateJobObjectW(void* attributes, ushort* name);
[Target(OS(Windows))]
extern int AssignProcessToJobObject(void* job, void* process);
[Target(OS(Windows))]
extern int TerminateJobObject(void* job, uint code);
[Target(OS(Windows))]
extern void* GetCurrentProcess();

[Target(OS(Windows))]
_own_the_process_tree(): _ProcessTree {
    var job = CreateJobObjectW(__null, __null);
    if (job == __null) {
        return job;
    }
    if (AssignProcessToJobObject(job, GetCurrentProcess()) == 0) {
        return __null;
    }
    return job;
}

[Target(OS(Windows))]
_end_the_process_tree(tree: _ProcessTree, code: int) {
    if (tree != __null) {
        # Ends the program too, with `code`.
        TerminateJobObject(tree, code as uint);
    }
    process.exit(code);
}

# On POSIX the tree is a process group the program leads, which its
# children and theirs join, unless they start a group of their own. The
# program's first group is kept (-1 when it cannot lead one), to step
# back into before it ends the group, so that it exits with its own code
# rather than the kill's signal. A program in a group of its own no longer
# gets the terminal's Ctrl-C; its timeout still ends it.
[Target(!OS(Windows) && !OS(Wasi))]
type _ProcessTree = int;

[Target(!OS(Windows) && !OS(Wasi))]
extern int getpgrp();
[Target(!OS(Windows) && !OS(Wasi))]
extern int setpgid(int pid, int group);
[Target(!OS(Windows) && !OS(Wasi))]
extern int getpid();
[Target(!OS(Windows) && !OS(Wasi))]
extern int kill(int pid, int signal);

[Target(!OS(Windows) && !OS(Wasi))]
_own_the_process_tree(): _ProcessTree {
    var first = getpgrp();
    if (setpgid(0, 0) != 0) {
        return -1;
    }
    return first;
}

[Target(!OS(Windows) && !OS(Wasi))]
_end_the_process_tree(tree: _ProcessTree, code: int) {
    if (tree != -1) {
        # When stepping back fails, the kill ends the program too.
        var group = getpid();
        setpgid(0, tree);
        kill(-group, 9);  # SIGKILL
    }
    process.exit(code);
}

# WASI starts no processes.
[Target(OS(Wasi))]
type _ProcessTree = int;

[Target(OS(Wasi))]
_own_the_process_tree(): _ProcessTree {
    return 0;
}

[Target(OS(Wasi))]
_end_the_process_tree(tree: _ProcessTree, code: int) {
    process.exit(code);
}

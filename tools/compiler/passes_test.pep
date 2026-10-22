# The compiler's sema passes accept every program of the corpus, and of
# the curated programs below, accept or reject each as its first line says
# (`# expect: accepted`, or the first line of the error a pass reports).
# Those expectations were recorded when pepc's passes matched the Rust
# compiler's byte for byte (the self-hosting cutover); a change that alters one
# changes a diagnostic or what the language accepts, on purpose or not.

import [Diagnostic, render_all] from compiler.diagnostic;
import io;
import [Directory, File, Path] from io;
import compiler.link;
import compiler.sema;
import [TempFolder] from testing;
import [check_programs as check_expected, headline, headlines] from "expected_outcomes";

# The programs are split in parts, each a test of its own, to keep each
# within the time a test may take. The programs that use much of the
# runtime take the longest, so each is a test of its own.
[Test]
runs_the_passes_over_the_test_programs_part_1() {
    runs_passes(0);
}

[Test]
runs_the_passes_over_the_test_programs_part_2() {
    runs_passes(1);
}

[Test]
runs_the_passes_over_the_test_programs_part_3() {
    runs_passes(2);
}

[Test]
runs_the_passes_over_the_test_programs_part_4() {
    runs_passes(3);
}

[Test]
runs_the_passes_over_the_test_programs_part_5() {
    runs_passes(4);
}

[Test]
runs_the_passes_over_the_test_programs_part_6() {
    runs_passes(5);
}

[Test]
runs_the_passes_over_the_test_programs_part_7() {
    runs_passes(6);
}

[Test]
runs_the_passes_over_the_test_programs_part_8() {
    runs_passes(7);
}

[Test]
runs_the_passes_over_the_test_programs_part_9() {
    runs_passes(8);
}

[Test]
runs_the_passes_over_the_test_programs_part_10() {
    runs_passes(9);
}

[Test]
runs_the_passes_over_the_test_programs_part_11() {
    runs_passes(10);
}

[Test]
runs_the_passes_over_the_test_programs_part_12() {
    runs_passes(11);
}

[Test]
runs_the_passes_over_the_test_programs_part_13() {
    runs_passes(12);
}

[Test]
runs_the_passes_over_the_test_programs_part_14() {
    runs_passes(13);
}

[Test]
runs_the_passes_over_the_test_programs_part_15() {
    runs_passes(14);
}

[Test]
runs_the_passes_over_the_test_programs_part_16() {
    runs_passes(15);
}

[Test]
runs_the_passes_over_the_test_programs_part_17() {
    runs_passes(16);
}

[Test]
runs_the_passes_over_the_test_programs_part_18() {
    runs_passes(17);
}

[Test]
runs_the_passes_over_the_test_programs_part_19() {
    runs_passes(18);
}

[Test]
runs_the_passes_over_the_test_programs_part_20() {
    runs_passes(19);
}

[Test]
runs_the_passes_over_the_atomics_test() {
    runs_passes_over(Path("../tests/Atomic.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_generic_shared_constraints_test() {
    runs_passes_over(Path("../tests/Generic.SharedConstraint").join("test.pep"));
}

[Test]
runs_the_passes_over_the_globals_test() {
    runs_passes_over(Path("../tests/Globals.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_io_test() {
    runs_passes_over(Path("../tests/Io.Basic").join("test.pep"));
}

[Test]
runs_the_passes_over_the_threads_copy_example() {
    runs_passes_over(Path("../docs/examples").join("threads-copy.pep"));
}

[Test]
runs_the_passes_over_the_threads_lock_body_example() {
    runs_passes_over(Path("../docs/examples").join("threads-lock-body.pep"));
}

const PARTS = 20;

# The corpus's programs with tests of their own.
slow_programs(): String[] {
    return ["Atomic.Basic", "Generic.SharedConstraint", "Globals.Basic", "Io.Basic"];
}

# Runs the passes over `program`, which they must accept.
runs_passes_over(program: Path) {
    expect_true(program.is_file(), "the program is found from tools/");
    expect_equal(outcome(program, true), "accepted");
}

# Runs the passes over every `PARTS`th program of the corpus and the
# documentation's programs of several files, from the `part`th, which
# they must accept.
runs_passes(part: ulong) {
    var programs = Array<Path>();
    # The corpus: one `test.pep` per folder.
    var listing = Directory.open(Path("../tests"));
    expect_true(listing.is_ok(), "the corpus is found from tools/");
    var names = Array<String>();
    for (var entry in listing.value().entries().value()) {
        if (entry.is_directory) {
            names.append(entry.name);
        }
    }
    names.sort((a, b) => a.compare(b));
    for (var name in names) {
        var program = Path("../tests").join(name).join("test.pep");
        if (program.is_file() and !slow_programs().contains(name)) {
            programs.append(program);
        }
    }
    # The documentation's programs of several files and modules.
    for (var name in [
        "modules-files",
        "modules-folders",
        "modules-reexports",
        "overloading-modules",
        "visibility-modules",
        "visibility-namespaces"
    ]) {
        programs.append(Path("../docs/examples").join(name).join("main.pep"));
    }
    # The documentation's programs with `static` blocks and attributes, and
    # with copies.
    for (var name in [
        "build-options.pep",
        "debugging-static.pep",
        "reflection-attributes.pep",
        "reflection-functions.pep",
        "structs-static.pep",
        # Assignment through chained indexers.
        "structs-indexers.pep",
        "reflection-module/main.pep",
        # Copies (`threads-copy.pep` and the census of a locked value in
        # `threads-lock-body.pep` have tests of their own).
        "memory-copy-traits.pep",
        "memory-copyable.pep"
    ]) {
        programs.append(Path("../docs/examples").join(name));
    }
    expect_true(programs.count > 40, "the corpus has its programs");
    ulong rejected = 0;
    ulong i = part;
    while (i < programs.count) {
        var ended = outcome(programs[i], true);
        if (ended != "accepted") {
            print($"{programs[i]}: {ended}");
            rejected += 1;
        }
        i += PARTS;
    }
    expect_equal(rejected, 0 as ulong);
}

# Programs without the runtime whose platform attributes a pass rejects:
# each error, its place and its message are the expected ones.
[Test]
reports_pass_errors() {
    var folder = TempFolder("passes_errors");
    expect_equal(check_programs(folder, error_programs()), 0 as ulong);
}

# Programs without the runtime with `with` blocks, `match`es and
# `[Export]`s the last passes check once types are final: each error
# is the expected one.
[Test]
reports_late_pass_errors() {
    var folder = TempFolder("passes_match_errors");
    expect_equal(check_programs(folder, late_pass_programs()), 0 as ulong);
}

late_pass_programs(): String[] {
    return [
        # `with` blocks: a `void` binding, `else` on an `int`, assignment to
        # the binding, and a scope without `enter()`.
        "# expect: main.pep:8:15: error: cannot bind 'l': 'enter()' returns 'void'\nstruct Lock {\n    construct() {}\n    enter() {}\n    exit() {}\n}\nmain(): int {\n    with (var l = Lock()) {\n    }\n    return 0;\n}\n",
        "# expect: main.pep:8:15: error: 'else' requires 'enter()' to return a struct reference, but it returns 'int'\nstruct Counter {\n    construct() {}\n    int enter() { return 1; }\n    exit() {}\n}\nmain(): int {\n    with (var n = Counter()) {\n    } else {\n    }\n    return 0;\n}\n",
        "# expect: main.pep:12:9: error: cannot assign to 'r': it is bound by a 'with' block\nstruct Res {\n    construct() {}\n}\nstruct Pool {\n    construct() {}\n    enter(): Res { return Res(); }\n    exit() {}\n}\nmain(): int {\n    with (var r = Pool()) {\n        r = Res();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:6:11: error: 'Plain' cannot be used in a 'with' block: it has no 'enter()' method\nstruct Plain {\n    construct() {}\n}\nmain(): int {\n    with (Plain()) {\n    }\n    return 0;\n}\n",
        # `match`es that miss a case, repeat one, need `else` on an integer,
        # repeat a range, miss a nested case and a tuple's value, mix arm
        # types, name no case, match a struct, and bind a case without
        # values; and two that pass.
        "# expect: main.pep:5:5: error: match on 'Color' does not handle 'Blue'\nenum Color { Red, Green, Blue }\nmain(): int {\n    var c = Color.Red;\n    match (c) {\n        Red => { return 1; }\n        Green => { return 2; }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:7:9: error: case 'Red' is already handled\nenum Color { Red, Green, Blue }\nmain(): int {\n    var c = Color.Red;\n    match (c) {\n        Red => { return 1; }\n        Red => { return 2; }\n        else => { return 3; }\n    }\n}\n",
        "# expect: main.pep:4:5: error: match on 'int' needs an 'else' arm\nmain(): int {\n    var n = 3;\n    match (n) {\n        0 => { return 1; }\n        1 => { return 2; }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:6:9: error: pattern '5..8' is already handled\nmain(): int {\n    var n = 3;\n    match (n) {\n        0..10 => { return 1; }\n        5..8 => { return 2; }\n        else => { return 3; }\n    }\n}\n",
        "# expect: main.pep:6:5: error: match on 'Pick' does not handle 'Some(Green)'\nenum Color { Red, Green }\nenum Pick { Nothing, Some(c: Color) }\nmain(): int {\n    var p = Pick.Some(Color.Red);\n    match (p) {\n        Nothing => { return 0; }\n        Some(Red) => { return 1; }\n    }\n    return 2;\n}\n",
        "# expect: main.pep:5:5: error: match on '(bool, bool)' does not handle '(false, false)'\nmain(): int {\n    var a = true;\n    var b = false;\n    match ((a, b)) {\n        (true, _) => { return 1; }\n        (false, true) => { return 2; }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:5:50: error: 'match' arm has a value of type 'Color', but the first arm's is 'int'\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.Red;\n    var x = match (c) { Red => 1, Green => Color.Red };\n    return 0;\n}\n",
        "# expect: main.pep:6:9: error: no case named 'Blue' in 'Color'\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.Red;\n    match (c) {\n        Blue => { return 1; }\n        else => { return 0; }\n    }\n}\n",
        "# expect: main.pep:7:12: error: cannot match on a value of 'S': 'match' needs an enum, an integer, 'char', 'bool' or 'String'\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var s = S();\n    match (s) {\n        else => { return 0; }\n    }\n}\n",
        "# expect: main.pep:6:13: error: case 'Red' of 'Color' carries no values to bind\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.Red;\n    match (c) {\n        Red(x) => { return 1; }\n        else => { return 0; }\n    }\n}\n",
        "# expect: accepted\nenum Pick { Nothing, Some(v: int) }\nmain(): int {\n    var p = Pick.Some(1);\n    match (p) {\n        Some(1..5) => { return 1; }\n        Some(2) => { return 2; }\n        else => { return 0; }\n    }\n}\n",
        "# expect: accepted\ntrait Shape {\n    area(): int;\n}\nstruct Circle {\n    construct() {}\n    area(): int { return 3; }\n}\nextend Circle with Shape;\nmain(): int {\n    Shape s = Circle();\n    match (s) {\n        Circle(c) => { return 1; }\n    }\n    return 0;\n}\n",
        # `[Export]`: misplaced, a bad name, a type C cannot hold, a symbol
        # taken twice or by a handle function, `main`, an unknown argument,
        # and one that passes enums, pointers and a C function pointer.
        "# expect: accepted\nstruct S {\n    construct() {}\n    [Export]\n    run() {}\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:16: error: '2bad' is not a C identifier\n[Export(name = \"2bad\")]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:6: error: cannot export 'f': C cannot hold 'V'\n[Value]\nstruct V {\n    var x: int;\n}\n[Export]\nf(v: V): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:1: error: two functions are exported as 'same'\n[Export(name = \"same\")]\nf(): int { return 1; }\n[Export(name = \"same\")]\ng(): int { return 2; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: cannot export a function as 'main'\n[Export(name = \"main\")]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:8:1: error: 'counter_retain' is exported already, as the handle function of 'Counter'\nstruct Counter {\n    construct() {}\n}\n[Export]\nmake(): Counter { return Counter(); }\n[Export]\ncounter_retain(): int { return 0; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:9: error: 'Export' takes only 'name', the C symbol: [Export(name = \"c_name\")]\n[Export(size = 3)]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:6: error: cannot export 'f': C cannot hold '__tuple<int, int>'\n[Export]\nf(x: (int, int)): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: accepted\nenum Color { Red, Green }\n[Export]\nf(c: Color, p: __ptr<Color>, cb: extern (int, double) => int): int { return 1; }\nmain(): int { return 0; }\n"
    ];
}

# Programs with the runtime that a check after the specializations
# rejects: each error is the expected one.
# Each test takes an eighth, to keep within the time a test may take.
[Test]
reports_errors_in_specialized_code_part_1() {
    reports_specialized_errors(0);
}

[Test]
reports_errors_in_specialized_code_part_2() {
    reports_specialized_errors(1);
}

[Test]
reports_errors_in_specialized_code_part_3() {
    reports_specialized_errors(2);
}

[Test]
reports_errors_in_specialized_code_part_4() {
    reports_specialized_errors(3);
}

[Test]
reports_errors_in_specialized_code_part_5() {
    reports_specialized_errors(4);
}

[Test]
reports_errors_in_specialized_code_part_6() {
    reports_specialized_errors(5);
}

[Test]
reports_errors_in_specialized_code_part_7() {
    reports_specialized_errors(6);
}

[Test]
reports_errors_in_specialized_code_part_8() {
    reports_specialized_errors(7);
}

# A thread's closure capturing what is not thread-safe: `async` makes the
# program slow enough to take a test of its own.
[Test]
reports_thread_capture_errors() {
    var folder = TempFolder("passes_thread_capture");
    var programs = [
        "# expect: main.pep:6:46: error: closure passed as 'shared () => void' captures 'name' of type 'String', which is not thread-safe\nimport async;\n\nmain(): int {\n    var name = \"worker\";\n    var t = async.Thread.spawn(() => { print(name); });\n    t.join();\n    return 0;\n}\n",
    ];
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

# Programs with `async` that `check_confinement` rejects: each loads the
# runtime's threads, so each takes a test of its own.
[Test]
reports_confinement_errors_part_1() {
    reports_confinement_error(0);
}

[Test]
reports_confinement_errors_part_2() {
    reports_confinement_error(1);
}

[Test]
reports_confinement_errors_part_3() {
    reports_confinement_error(2);
}

[Test]
reports_confinement_errors_part_4() {
    reports_confinement_error(3);
}

[Test]
reports_confinement_errors_part_5() {
    reports_confinement_error(4);
}

[Test]
reports_confinement_errors_part_6() {
    reports_confinement_error(5);
}

[Test]
reports_confinement_errors_part_7() {
    reports_confinement_error(6);
}

[Test]
reports_confinement_errors_part_8() {
    reports_confinement_error(7);
}

[Test]
reports_confinement_errors_part_9() {
    reports_confinement_error(8);
}

[Test]
reports_confinement_errors_part_10() {
    reports_confinement_error(9);
}

[Test]
reports_confinement_errors_part_11() {
    reports_confinement_error(10);
}

reports_confinement_error(index: ulong) {
    var folder = TempFolder($"passes_confinement_{index}");
    var programs = [confinement_error_programs()[index]];
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

confinement_error_programs(): String[] {
    return [
        # A value from outside moved into a locked one, and part of a locked
        # value kept outside it.
        "# expect: main.pep:9:21: error: 'line' cannot move into the value locked by 'names'\nimport async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var line = \"x\";\n    with (var list = names.lock()) {\n        list.append(line);\n    }\n    return 0;\n}\n",
        "# expect: main.pep:9:17: error: 'list[0]' is part of the value locked by 'names' and cannot outlive the lock\nimport async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var first = \"\";\n    with (var list = names.lock()) {\n        first = list[0];\n    }\n    return 0;\n}\n",
        # A `move` of a local another references, and a use after a `move` in
        # a loop.
        "# expect: main.pep:9:24: error: 'a' cannot be moved: 'b' also references its value\nimport async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var a = Array<String>();\n    var b = a;\n    names.replace(move(a));\n    return 0;\n}\n",
        "# expect: main.pep:9:28: error: 'a' is used after its value was moved\nimport async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var a = Array<String>();\n    while (true) {\n        names.replace(move(a));\n    }\n    return 0;\n}\n",
        # A guard kept in a variable, and a `[Move]` argument that is not new.
        "# expect: main.pep:7:19: error: 'MutexGuard<Array<String>>' can only be the scope of a 'with' block\nimport async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var g = names.lock();\n    return 0;\n}\n",
        "# expect: main.pep:8:16: error: 'line' is not a new value, but parameter 'value' takes a value that nothing else references\nimport async;\n\nconst lines = async.Channel<String>();\n\nmain(): int {\n    var line = \"hello\";\n    lines.send(line);\n    return 0;\n}\n",
        # A call through a `shared` function value given a local, which its
        # result may share, located at the callee.
        "# expect: main.pep:10:16: error: 'f(b)' is not a new value, but parameter 'value' takes a value that nothing else references\nimport async;\n\nkeep(b: Array<int>): Array<int> { return b; }\n\nmain(): int {\n    var locals = async.ThreadLocal<Array<int>>();\n    shared (Array<int>) => Array<int> f = keep;\n    var b = Array<int>();\n    locals.set(f(b));\n    return 0;\n}\n",
        # A `[Locked]` closure that keeps part of the locked value.
        "# expect: main.pep:11:26: error: 'queue[0]' is part of the value locked by 'queue' and cannot outlive the lock\nimport async;\n\nconst jobs = async.Mutex<Array<String>>(Array<String>());\nconst ready = jobs.condition();\n\nmain(): int {\n    var saved = Array<String>();\n    with (var list = jobs.lock()) {\n        ready.wait_while((queue: Array<String>): bool => {\n            saved.append(queue[0]);\n            return queue.count == 0;\n        });\n    }\n    return 0;\n}\n",
        # A captured value cannot move while a closure that holds it can
        # still be reached: one still in scope, one stored in a field, and
        # one a call returned (#173).
        "# expect: main.pep:18:17: error: 'b' cannot be moved: 'bump' also references its value\nimport async;\n\nstruct Box {\n    var n: int;\n\n    construct(n: int) {\n        this.n = n;\n    }\n}\n\nmain(): int {\n    var c = async.Channel<Box>();\n    var b = Box(1);\n    var bump = () => {\n        b.n += 1;\n    };\n    c.send(move(b));\n    bump();\n    return 0;\n}\n",
        "# expect: main.pep:25:17: error: 'b' cannot be moved: 'h' also references its value\nimport async;\n\nstruct Box {\n    var n: int;\n\n    construct(n: int) {\n        this.n = n;\n    }\n}\n\nstruct Holder {\n    var f: () => void;\n\n    construct(f: () => void) {\n        this.f = f;\n    }\n}\n\nstore(h: Holder, c: async.Channel<Box>) {\n    var b = Box(1);\n    h.f = () => {\n        b.n += 1;\n    };\n    c.send(move(b));\n}\n\nmain(): int {\n    store(Holder(() => {}), async.Channel<Box>());\n    return 0;\n}\n",
        "# expect: main.pep:20:17: error: 'b' cannot be moved: 'get' also references its value\nimport async;\n\nstruct Box {\n    var n: int;\n\n    construct(n: int) {\n        this.n = n;\n    }\n}\n\nwrap(b: Box): () => int {\n    return () => b.n;\n}\n\nmain(): int {\n    var c = async.Channel<Box>();\n    var b = Box(1);\n    var get = wrap(b);\n    c.send(move(b));\n    return get();\n}\n"
    ];
}

const _SPECIALIZED_PARTS: ulong = 8;

reports_specialized_errors(part: ulong) {
    var all = specialized_error_programs();
    var programs = Array<String>();
    ulong i = part;
    while (i < all.count) {
        programs.append(all[i]);
        i += _SPECIALIZED_PARTS;
    }
    var folder = TempFolder($"passes_specialized_errors_{part}");
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

# Programs whose errors only the checks after the specialization loop
# find.
specialized_error_programs(): String[] {
    return [
        # A module-scope `String`, inferred.
        "# expect: main.pep:2:7: error: module-scope variable 'greeting' has type 'String', which is not thread-safe\nconst greeting = String(\"hi\");\nmain(): int { return 0; }\n",
        # A field of a value struct in an array, and a const value
        # iterator driven by `for`.
        "# expect: main.pep:17:14: error: cannot assign to field 'end' of a temporary 'Span'\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var spans = Array<Span>();\n    spans.append(Span());\n    spans[0].end = 3;\n    return 0;\n}\n",
        "# expect: main.pep:5:19: error: cannot call mutating method 'next' on const variable 'it'\nmain(): int {\n    var values = Array<int>();\n    const it = values.iterate();\n    for (var x in it) {\n        return x;\n    }\n    return 0;\n}\n",
        # Closures and method values in `shared` and C function pointer
        # slots that capture what they cannot, and a C function pointer
        # type C cannot pass.
        "# expect: main.pep:4:18: error: closure returned as 'shared () => int' captures 's' of type 'String', which is not thread-safe\nmake(): shared () => int {\n    var s = \"x\";\n    return () => s.length as int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:41: error: closure stored as 'shared () => int' captures 'this' of type 'S', which is not thread-safe\nstruct S {\n    var n: int;\n    construct(this.n = 0) {}\n    run() {\n        var f: shared () => int = () => n;\n    }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:10:19: error: method value passed as 'shared () => int' captures its receiver of type 'P', which is not thread-safe\nstruct P {\n    var x: int;\n    construct(this.x = 0) {}\n    get(): int { return x; }\n}\ntake(f: shared () => int): int { return f(); }\nmain(): int {\n    var p = P(3);\n    return take(p.get);\n}\n",
        "# expect: main.pep:5:43: error: closure passed as C function pointer type 'extern (__ptr<void>, __ptr<void>) => int' captures 'bias'; a C function pointer cannot hold captured values\nextern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);\nmain(): int {\n    var bias = 1;\n    qsort(_pep_malloc(4), 0, 4, (a, b) => bias);\n    return 0;\n}\n",
        "# expect: main.pep:4:12: error: C function pointer type 'extern (String) => int' cannot use 'String'; C passes only numbers, 'bool' and pointers\ntake(s: String): int { return 0; }\nmain(): int {\n    var f: extern (String) => int = take;\n    return 0;\n}\n",
        # `[MoveSource]` and `[Locked]` outside the runtime, and the old
        # name of `[Move]`.
        "# expect: main.pep:2:6: error: '[MoveSource]' is only allowed in the runtime\ntake([MoveSource] s: String): String {\n    return s;\n}\n\nmain(): int {\n    return 0;\n}\n",
        "# expect: main.pep:2:6: error: unknown parameter attribute '[Sending]'\nkeep([Sending] s: String) {\n}\n\nmain(): int {\n    return 0;\n}\n",
        "# expect: main.pep:2:7: error: '[Locked]' is only allowed in the runtime\ncheck([Locked] predicate: (int) => bool): bool {\n    return predicate(1);\n}\n\nmain(): int {\n    return 0;\n}\n",
        # Hash keys whose `==` and hash disagree, and an override of an
        # `[Equatable]` struct's derived hash.
        "# expect: main.pep:5:5: error: 'K' declares '==' but no 'hash<K>', so as a HashMap or HashSet key, equal values will not find each other\nstruct K {\n    var x: int;\n    construct(this.x = 0) {}\n    ==(other: K): bool { return x == other.x; }\n}\nmain(): int {\n    var m = HashMap<K, int>();\n    m[K(1)] = 2;\n    return 0;\n}\n",
        "# expect: main.pep:6:1: error: 'hash<K>' is overridden but 'K' declares no '==', so HashMap and HashSet keys still compare by identity\nstruct K {\n    var x: int;\n    construct(this.x = 0) {}\n}\nhash<K>(value: K): u64 { return value.x as u64; }\nmain(): int {\n    var s = HashSet<K>();\n    s.insert(K(1));\n    return 0;\n}\n",
        "# expect: main.pep:7:1: error: 'K' is '[Equatable]', so its hash is derived and 'hash<K>' cannot be overridden\n[Equatable]\nstruct K {\n    var x: int;\n    construct(this.x = 0) {}\n}\nhash<K>(value: K): u64 { return value.x as u64; }\nmain(): int {\n    return 0;\n}\n",
        # A closure parameter whose type nothing inferred.
        "# expect: main.pep:3:14: error: cannot infer the type of parameter 'x'; write it: (x: Type) => ...\nmain(): int {\n    var f = (x) => x;\n    return 0;\n}\n",
        # Destructures of the wrong count and of a non-tuple, and tuple
        # elements assigned to or out of range.
        "# expect: main.pep:6:21: error: cannot destructure '(int, int)' into 3 values: it has 2 elements\npair(): (int, int) {\n    return (1, 2);\n}\nmain(): int {\n    var (a, b, c) = pair();\n    return 0;\n}\n",
        "# expect: main.pep:4:18: error: cannot destructure 'String': it is not a tuple\nmain(): int {\n    var s = \"x\";\n    var (a, b) = s;\n    return 0;\n}\n",
        "# expect: main.pep:7:7: error: cannot assign to element 0 of tuple '(int, int)': tuple elements are immutable\npair(): (int, int) {\n    return (1, 2);\n}\nmain(): int {\n    var t = pair();\n    t.0 = 3;\n    return 0;\n}\n",
        "# expect: main.pep:7:14: error: no member named '2' in '(int, int)': its elements are '0' to '1'\npair(): (int, int) {\n    return (1, 2);\n}\nmain(): int {\n    var t = pair();\n    return t.2;\n}\n",
        # A method's tuple that is not the type argument takes none of its
        # labels.
        "# expect: main.pep:9:23: error: no member named 'a' in '(int, int)': its elements are '0' to '1'\nstruct Box<T> {\n    var value: T;\n    construct(value: T) { this.value = value; }\n    pair(): (int, int) { return (1, 2); }\n}\nmain(): int {\n    var box = Box<(a: int, b: int)>((a: 1, b: 2));\n    return box.pair().a;\n}\n",
        # Nor does a generic function's.
        "# expect: main.pep:6:49: error: no member named 'a' in '(int, int)': its elements are '0' to '1'\npair<T>(value: T): (int, int) {\n    return (1, 2);\n}\nmain(): int {\n    return pair<(a: int, b: int)>((a: 1, b: 2)).a;\n}\n",
        # Nor does a generic method's.
        "# expect: main.pep:8:51: error: no member named 'a' in '(int, int)': its elements are '0' to '1'\nstruct S {\n    var n: int = 0;\n    pair<T>(value: T): (int, int) { return (1, 2); }\n}\nmain(): int {\n    var s = S();\n    return s.pair<(a: int, b: int)>((a: 1, b: 2)).a;\n}\n",
        # A tuple inferred from literals names its elements as programs do:
        # `int`, not the `i32` a literal is typed (#156).
        "# expect: main.pep:7:14: error: no member named 'a' in '(int, int)': its elements are '0' to '1'\npass<T>(value: T): T {\n    return value;\n}\nmain(): int {\n    var g = pass((1, 2));\n    return g.a;\n}\n",
        "# expect: main.pep:8:29: error: no member named 'a' in '(int, double)': its elements are '0' to '1'\nstruct S {\n    var n: int = 0;\n    pass<T>(value: T): T { return value; }\n}\nmain(): int {\n    var s = S();\n    return s.pass((1, 2.5)).a;\n}\n",
        # `[ThreadLocal]` on a field.
        "# expect: main.pep:3:5: error: 'ThreadLocal' applies only to a module-scope variable, not a field\nstruct Counter {\n    [ThreadLocal]\n    var hits: int;\n}\nmain(): int { return 0; }\n",
        # A struct value as a condition, and as an operand of `!`.
        "# expect: main.pep:7:9: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'\nstruct Node {\n    int value;\n}\nmain(): int {\n    var node = Node();\n    if (node) {\n        return 1;\n    }\n    return 0;\n}\n",
        "# expect: main.pep:7:31: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'\nstruct Node {\n    int value;\n}\nmain(): int {\n    var node = Node();\n    return node.value > 0 && !node ? 1 : 0;\n}\n",
        # An undeclared name passed to a generic function.
        "# expect: accepted\nwrap<T>(value: T): T {\n    return value;\n}\n\nmain(): int {\n    wrap(nope);\n    return 0;\n}\n",
        # Assignment through an indexer that has no setter.
        "# expect: main.pep:9:5: error: cannot assign through '[]': 'G' declares a '[]' getter but no setter\nstruct G {\n    construct() {}\n    [](i: int): int { return i; }\n}\nmain(): int {\n    var a = Array<G>();\n    a.append(G());\n    a[0][1] = 3;\n    return 0;\n}\n",
        # Assignment to a call.
        "# expect: main.pep:4:5: error: expression is not assignable\nget(): int { return 1; }\nmain(): int {\n    get() = 3;\n    return 0;\n}\n",
        # Overloads nothing settled: an ambiguous call and method call,
        # and a set used as a value without a type.
        "# expect: main.pep:4:22: error: call to 'f' is ambiguous\nf(x: long): int { return 1; }\nf(x: short): int { return 2; }\nmain(): int { return f(1); }\n",
        "# expect: main.pep:6:37: error: call to 'get' is ambiguous\nstruct S {\n    get(x: long): int { return 1; }\n    get(x: short): int { return 2; }\n}\nmain(): int { var s = S(); return s.get(1); }\n",
        "# expect: main.pep:5:13: error: cannot infer the type of 'g' from overloaded function 'f'\nf(x: int): int { return 1; }\nf(x: long): int { return 2; }\nmain(): int {\n    var g = f;\n    return 0;\n}\n",
        # Type arguments nothing gave: a generic method and function used
        # as values, and calls that leave one or all unbound.
        "# expect: main.pep:8:25: error: cannot infer the type arguments of method 'map' of 'Box<int>' used as a value; write them (map<U>) or give the value a function type\nstruct Box<T> {\n    T value;\n    construct(v: T) { value = v; }\n    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }\n}\nmain(): int {\n    var m = Box<int>(1).map;\n    return 0;\n}\n",
        "# expect: main.pep:4:13: error: cannot infer the type arguments of 'larger' used as a value; write them (larger<T>) or give the value a function type\nlarger<T>(a: T, b: T): T { return a > b ? a : b; }\nmain(): int {\n    var f = larger;\n    return 0;\n}\n",
        "# expect: main.pep:4:13: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)\nmake<T>(): T { return __default<T>(); }\nmain(): int {\n    var x = make();\n    return 0;\n}\n",
        "# expect: main.pep:4:12: error: cannot infer the type argument 'U' of 'make' from its arguments; write it: make<T, U>(...)\nmake<T, U>(a: T): int { return 0; }\nmain(): int {\n    return make<int>(1);\n}\n",
        "# expect: main.pep:7:14: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)\nstruct S {\n    make<T>(): int { return 0; }\n}\nmain(): int {\n    var s = S();\n    return s.make();\n}\n",
        # A variadic extern used as a value, and a method of `this` stored
        # in a field of `this`.
        "# expect: main.pep:4:13: error: variadic extern 'snprintf' cannot be a function value; wrap a call to it in a closure\nextern int snprintf(char* buffer, ulong size, char* format, ...);\nmain(): int {\n    var f = snprintf;\n    return 0;\n}\n",
        "# expect: main.pep:6:15: error: storing a method of 'this' in field 'measure' of 'this' creates a reference cycle that is never freed\nstruct Widget {\n    int size;\n    () => int measure;\n    area(): int { return size; }\n    setup() { measure = this.area; }\n}\nmain(): int { return 0; }\n",
        # A lane count that is not a power of two, and one past 64.
        "# expect: main.pep:4:30: error: lane count of 'Vector<int, 3>' must be a power of two from 1 to 64, not '3'\nimport simd;\nmain(): int {\n    var v = simd.Vector<int, 3>(1);\n    return 0;\n}\n",
        "# expect: main.pep:4:23: error: lane count of 'Mask<128>' must be a power of two from 1 to 64, not '128'\nimport simd;\nmain(): int {\n    var m = simd.Mask<128>();\n    return 0;\n}\n",
        # A member a constrained extension withholds from a specialization.
        "# expect: main.pep:5:15: error: no member named 'square_root' in 'Vector<int, 4>'\nimport simd;\nmain(): int {\n    var v = simd.Vector<int, 4>(4);\n    var r = v.square_root();\n    return 0;\n}\n",
        "# expect: main.pep:21:9: error: no member named 'label' in 'Box<Circle>'\ntrait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Named> {\n    label(): String { return item.name(); }\n}\nmain(): int {\n    var box = Box<Circle>(Circle());\n    box.label();\n    return 0;\n}\n"
    ];
}

# Programs the platform filters, the closures lifting and the struct
# synthesis change, without the runtime.
[Test]
rewrites_programs() {
    var folder = TempFolder("passes_programs");
    expect_equal(check_programs(folder, rewritten_programs()), 0 as ulong);
}

# Programs with the runtime that the passes after the specialization loop
# Decimal literals past `long`'s range fit only a `ulong`, and none fits
# past `ulong`'s (#158). With the runtime, which `convert_to_traits`, the
# pass that checks them, needs.
[Test]
reports_literals_too_large_for_their_type() {
    var folder = TempFolder("passes_literal_range");
    var programs = [
        "# expect: main.pep:3:14: error: integer literal is too large for type 'long'\nmain(): int {\n    long a = 9223372036854775808;\n    return 0;\n}\n",
        "# expect: main.pep:6:17: error: integer literal is too large for type 'int'\ntake(x: int): int {\n    return x;\n}\nmain(): int {\n    return take(18446744073709551615);\n}\n",
        "# expect: main.pep:4:9: error: integer literal is too large for type 'long'\nmain(): int {\n    long c = 0;\n    c = 9223372036854775808;\n    return 0;\n}\n",
        "# expect: main.pep:2:19: error: integer literal is too large for type 'long'\nconst BIG: long = 9223372036854775808;\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:12: error: integer literal is too large for type 'long'\nbig(): long {\n    return 9223372036854775808;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:15: error: integer literal is too large to be represented in a 64-bit integer\nmain(): int {\n    ulong a = 18446744073709551616;\n    return 0;\n}\n",
        "# expect: main.pep:3:14: error: integer literal is too large to be represented in a 64-bit integer\nmain(): int {\n    long a = -9223372036854775809;\n    return 0;\n}\n",
        # A build option is a `long`.
        "# expect: main.pep:2:29: error: build option 'BIG' cannot be compared with 9223372036854775808: a build option is a 'long'\n[Target(BuildOption(BIG) == 9223372036854775808)]\nbig(): int { return 1; }\nmain(): int { return 0; }\n"
    ];
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

# rewrite: function values converted between plain, `shared` and C slots.
[Test]
rewrites_function_values() {
    var folder = TempFolder("passes_function_values");
    var programs = [
        # A `shared` value in a plain slot, through an adapter.
        "# expect: accepted\napply(f: () => int): int { return f(); }\nmain(): int {\n    var g: shared () => int = () => 1;\n    var h: () => int = g;\n    return apply(g) + h();\n}\n",
        # A named function and a closure that captures nothing, as C
        # function pointers.
        "# expect: accepted\nextern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);\ncompare(a: __ptr<void>, b: __ptr<void>): int { return 0; }\nmain(): int {\n    qsort(_pep_malloc(4), 0, 4, compare);\n    qsort(_pep_malloc(4), 0, 4, (a, b) => 0);\n    return 0;\n}\n"
    ];
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

# A file's own functions named like the runtime's (`print`, `to_string`)
# join the runtime's sets, and may not repeat a runtime member's
# parameters.
[Test]
joins_the_runtime_overload_sets() {
    var folder = TempFolder("passes_runtime_overloads");
    var programs = [
        "# expect: accepted\nstruct Point {\n    var x: int;\n    construct(x: int) { this.x = x; }\n}\nprint(p: Point) { print($\"Point({p.x})\"); }\nto_string(p: Point): String { return \"point\"; }\nmain(): int {\n    print(Point(1));\n    print(\"text\");\n    var s = to_string(Point(2)) + to_string(3);\n    return s.size == 6 ? 0 : 1;\n}\n",
        "# expect: main.pep:2:1: error: redefinition of 'print'\nprint(text: String) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: redefinition of 'to_string'\nto_string(value: int): String { return \"\"; }\nmain(): int { return 0; }\n",
        # Another return type does not make a new member.
        "# expect: main.pep:2:1: error: functions that differ only in their return type cannot be overloaded\nto_string(value: int): int { return value; }\nmain(): int { return to_string(0); }\n"
    ];
    expect_equal(check_programs(folder, programs, true), 0 as ulong);
}

# Deprecated methods the compiler calls for the source: a `for` loop's
# `next()` and `current()`, a `with` block's `enter()`, and operator
# overloads, reported at `for`, `with` and the operator.
[Test]
reports_deprecated_methods_the_compiler_calls() {
    var folder = TempFolder("passes_deprecated_calls");
    var programs = [
        "# expect: main.pep:36:5: warning: 'next' is deprecated: use 'advance' instead [deprecated]\n# expect: main.pep:17:5: note: 'next' declared here\n# expect: main.pep:36:5: warning: 'current' is deprecated: old [deprecated]\n# expect: main.pep:20:5: note: 'current' declared here\n# expect: main.pep:39:5: warning: 'enter' is deprecated: old [deprecated]\n# expect: main.pep:24:5: note: 'enter' declared here\n# expect: main.pep:43:15: warning: '+' is deprecated: old [deprecated]\n# expect: main.pep:30:5: note: '+' declared here\n# expect: main.pep:44:11: warning: '==' is deprecated: old [deprecated]\n# expect: main.pep:32:5: note: '==' declared here\n# expect: main.pep:44:21: warning: '==' is deprecated: old [deprecated]\n# expect: main.pep:32:5: note: '==' declared here\nstruct Steps {\n    var n: int;\n    iterate(): Steps { return this; }\n    [Deprecated(\"use 'advance' instead\", \"advance\")]\n    next(): bool { n += 1; return n < 3; }\n    advance(): bool { n += 1; return n < 3; }\n    [Deprecated(\"old\")]\n    current(): int { return n; }\n}\nstruct Session {\n    [Deprecated(\"old\")]\n    enter(): Session { return this; }\n    exit() {}\n}\nstruct V {\n    var x: int;\n    [Deprecated(\"old\")]\n    +(other: V): V { return this; }\n    [Deprecated(\"old\")]\n    ==(other: V): bool { return true; }\n}\nmain(): int {\n    var total = 0;\n    for (var i in Steps()) {\n        total += i;\n    }\n    with (var s = Session()) {\n        total += 1;\n    }\n    var a = V();\n    var b = a + a;\n    if (a != b or a == b) {\n        total += 1;\n    }\n    return total;\n}\n"
    ];
    expect_equal(check_expected(folder, programs, (path: Path): String => warnings_of(path)), 0 as ulong);
}

# The warnings the passes give the program rooted at `root`, with the
# runtime, as `headlines` lists them.
warnings_of(root: Path): String {
    var program = link.load_program(root, link.Setup());
    if (program.is_err()) {
        return headline(program.error(), root);
    }
    var built = sema.merge(program.value());
    if (built.is_err()) {
        return headline(built.error(), root);
    }
    var state = sema.run_passes(built.value(), program.value().target, program.value().sources());
    if (state.is_err()) {
        return headline(render_all([state.error()], program.value().sources()), root);
    }
    return headlines(render_all(state.value().notes, program.value().sources()), root);
}

# `check_programs` with the passes, with the runtime or without.
check_programs(folder: TempFolder, programs: String[], runtime: bool = false): ulong {
    return check_expected(folder, programs, (path: Path): String => outcome(path, runtime));
}

# How the passes end on the program rooted at `root`: `accepted`, or the
# first line of the error that loading, merging or a pass reports, its
# file named from the program's folder (`main.pep`) or the runtime's
# (`runtime/...`).
outcome(root: Path, runtime: bool): String {
    var setup = link.Setup();
    setup.runtime = runtime;
    var program = link.load_program(root, setup);
    if (program.is_err()) {
        return headline(program.error(), root);
    }
    var built = sema.merge(program.value());
    if (built.is_err()) {
        return headline(built.error(), root);
    }
    var ran = sema.run_steps(built.value(), program.value().target, ALL_STEPS, program.value().sources());
    if (ran.is_err()) {
        return headline(render_all([ran.error()], program.value().sources()), root);
    }
    return "accepted";
}

# More steps than any program runs: all of them.
const ALL_STEPS: ulong = 1000000;

# Programs a pass rejects.
error_programs(): String[] {
    return [
        # Shared struct fields, module-scope variables and thread-locals
        # that are not const, not thread-safe or not constant.
        "# expect: main.pep:4:9: error: field 'count' of shared struct 'Counter' must be 'const'\n[Shared]\nstruct Counter {\n    int count;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:18: error: field 'inner' of shared struct 'Config' has type 'Plain', which is not thread-safe\nstruct Plain { int x; }\n[Shared]\nstruct Config {\n    const inner: Plain;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:5: error: module-scope variable 'hits' must be 'const'\nvar hits = 0;\nmain(): int { return hits; }\n",
        "# expect: main.pep:2:6: error: module-scope variable 'total' must be 'const'\nlong total = 0;\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:12: error: module-scope variable 'hits' must be 'const'\nexport var hits = 0;\nmain(): int { return hits; }\n",
        "# expect: main.pep:3:15: error: module-scope variable 'origin' has type 'Plain', which is not thread-safe\nstruct Plain { var x: int; }\nconst origin: Plain = Plain();\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:22: error: module-scope variable 'origin' has type 'Plain', which is not thread-safe\nstruct Plain { var x: int; }\nexport const origin: Plain = Plain();\nmain(): int { return 0; }\n",
        "# expect: main.pep:8:13: error: module-scope variable 'unit' has type 'Shape', which is not thread-safe\ntrait Shape { int area(); }\n[Shared]\nstruct Square { construct() {} }\nextend Square with Shape { int area() { return 1; } }\n\n\nconst unit: Shape = Square();\nmain(): int { return 0; }\n",
        "# expect: main.pep:10:13: error: 'make<String>' requires thread-safe type arguments; 'String' is not thread-safe\n[Shared]\nstruct Cell<T> {\n    const value: T;\n}\n\nmake<T>(): Cell<T> { return Cell<T>(); }\n\nmain(): int {\n    var c = make<String>();\n    return 0;\n}\n",
        "# expect: main.pep:4:14: error: field 'f' of shared struct 'H' has type '() => void', which is not thread-safe\n[Shared]\nstruct H {\n    const f: () => void;\n    construct(this.f = () => {}) {}\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:14: error: thread-local variable 'scratch' has type 'Plain', which is not thread-safe\nstruct Plain { var x: int; }\n[ThreadLocal]\nvar scratch: Plain;\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:18: error: thread-local variable 'depth' must start from a constant\nstart(): int { return 4; }\n[ThreadLocal]\nvar depth: int = start();\nmain(): int { return depth; }\n",
        # Casts their kind does not allow.
        "# expect: main.pep:7:15: error: cannot cast 'S' to '__ptr<void>'\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var s = S();\n    var p = s as __ptr<void>;\n    return 0;\n}\n",
        "# expect: main.pep:4:13: error: 'unsafe_cast' cannot convert 'float' to 'ulong': the sizes differ; use 'as' to convert the value\nmain(): int {\n    var f: float = 1.0;\n    var n = unsafe_cast<ulong>(f);\n    return 0;\n}\n",
        "# expect: main.pep:4:15: error: cannot cast '__ptr<char>' to '__ptr<byte>' with 'as'; use 'unsafe_cast<__ptr<byte>>(...)' to reinterpret\nmain(): int {\n    var p: __ptr<char> = __null;\n    var q = p as __ptr<byte>;\n    return 0;\n}\n",
        "# expect: main.pep:7:13: error: 'unsafe_cast' cannot convert '__ptr<char>' to 'S': it reinterprets only pointers and numbers\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var p: __ptr<char> = __null;\n    var s = unsafe_cast<S>(p);\n    return 0;\n}\n",
        "# expect: main.pep:11:15: error: cannot cast 'T' to 'int'; use 'as?' to convert a trait value, which gives 'int?'\ntrait T {\n    f(): int;\n}\nstruct S {\n    f(): int { return 1; }\n}\nextend S with T;\nmain(): int {\n    var t: T = S();\n    var n = t as int;\n    return 0;\n}\n",
        # Values that do not match their slots: function, enum, struct,
        # pointer, weak and tuple types, `void` used as a value, calls with
        # the wrong arity, bare returns, and enum and struct comparisons.
        "# expect: main.pep:4:30: error: cannot initialize variable 'f' of type '(String) => int' with a value of type '(int) => int'\nsquare(x: int): int { return x * x; }\nmain(): int {\n    var f: (String) => int = square;\n    return 0;\n}\n",
        "# expect: main.pep:5:12: error: too many arguments to function of type '(int) => int': expected 1, have 2\nsquare(x: int): int { return x * x; }\nmain(): int {\n    var f = square;\n    return f(1, 2);\n}\n",
        "# expect: main.pep:4:9: error: non-void function 'f' should return a value\nf(x: int): int {\n    if (x > 0) {\n        return;\n    }\n    return 1;\n}\nmain(): int {\n    return f(1);\n}\n",
        "# expect: main.pep:5:11: error: cannot initialize variable 's' of type 'S' with a value of type '__ptr<void>'\nstruct S { int x = 0; }\nmain(): int {\n    var p: __ptr<void> = __null;\n    S s = p;\n    return 0;\n}\n",
        "# expect: main.pep:4:32: error: cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'\nmain(): int {\n    var g = () => {};\n    var f: shared () => void = g;\n    return 0;\n}\n",
        "# expect: main.pep:4:34: error: cannot initialize variable 'f' of type 'extern (int) => int' with a value of type '(int) => int'; only a named function or a closure that captures nothing converts to a C function pointer\nmain(): int {\n    var g: (int) => int = (x) => x;\n    var f: extern (int) => int = g;\n    return 0;\n}\n",
        "# expect: main.pep:3:28: error: cannot initialize variable 't' of type '(int, String)' with a value of type '(int, int)'\nmain(): int {\n    var t: (int, String) = (1, 2);\n    return 0;\n}\n",
        "# expect: main.pep:4:19: error: cannot initialize variable 'x' of type 'int' with a value of type 'Color'\nenum Color { Red }\nmain(): int {\n    int x = Color.Red;\n    return x;\n}\n",
        "# expect: main.pep:10:26: error: cannot initialize variable 'circle' of type 'Circle' with a value of type 'T'\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Circle {\n}\nkeep<T: Shape>(item: T): int {\n    var shape: Shape = item;\n    var circle: Circle = item;\n    return 0;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:48: error: invalid operands to binary expression ('T' and 'T')\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nsmaller<T: Shape>(a: T, b: T): bool { return a < b; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:11: error: invalid operands to binary expression ('T' and 'T')\ntrait Addable {\n    +(other: this): this;\n}\ngrow<T: Addable>(a: T, b: T): T {\n    var total = a;\n    total += b;\n    return total;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:18: error: cannot use a value of type 'void' as variable 'x'\nf() {}\nmain(): int {\n    var x: int = f();\n    return 0;\n}\n",
        "# expect: main.pep:6:12: error: cannot return a value of type 'int' from 'f', which returns 'S'\nstruct S {\n    var x: int;\n}\nf(): S {\n    return 1;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:24: error: cannot initialize variable 'w' of type '__weak<S>' with a value of type 'S'; use '__weak_from<S>(...)' to make one\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var s = S();\n    var w: __weak<S> = s;\n    return 0;\n}\n",
        "# expect: main.pep:7:14: error: cannot compare 'S' with an integer\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var s = S();\n    return s == 1 ? 1 : 0;\n}\n",
        "# expect: main.pep:8:20: error: cannot initialize variable 'n' of type 'int' with a value of type '() => int'; call it with '()'\nstruct S {\n    var x: int;\n    get(): int { return x; }\n}\nmain(): int {\n    var s = S();\n    var n: int = s.get;\n    return n;\n}\n",
        "# expect: main.pep:7:14: error: cannot compare a value of type 'Color' with a value of type 'Size'\nenum Color { Red, Green }\nenum Size { Small, Large }\nmain(): int {\n    var c = Color.Red;\n    var s = Size.Small;\n    return c == s ? 1 : 0;\n}\n",
        "# expect: main.pep:9:17: error: cannot pass a value of type 'long' as argument 1 of 'take', which has type 'Meters'\nstruct Meters {\n    var v: long;\n    construct(v: long) { this.v = v; }\n}\ntake(m: Meters): long { return m.v; }\nmain(): int {\n    long n = 2;\n    return take(n) as int;\n}\n",
        "# expect: error: incompatible operand types ('S' and 'int')\nstruct S {\n    var x: int;\n}\nmain(): int {\n    var s = S();\n    var n = true ? s : 1;\n    return 0;\n}\n",
        "# expect: main.pep:5:13: error: invalid operand to unary expression ('Color'): an enum only compares with '==' and '!='\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.Red;\n    var d = -c;\n    return 0;\n}\n",
        # Struct values in trait slots they do not conform to, trait values
        # of another trait, a number as a trait value, a static trait member
        # called on a value, and a covariant return that does not conform.
        "# expect: main.pep:9:15: error: 'Circle' does not conform to trait 'Shape'\ntrait Shape {\n    int area();\n}\nstruct Circle {\n    construct() {}\n}\nmain(): int {\n    Shape s = Circle();\n    return 0;\n}\n",
        "# expect: main.pep:15:15: error: 'unit' is static and cannot be called on a value of trait type 'Shape'\ntrait Shape {\n    int area();\n    static this unit();\n}\nstruct Square {\n    construct() {}\n}\nextend Square with Shape {\n    int area() { return 1; }\n    static Square unit() { return Square(); }\n}\nmain(): int {\n    Shape s = Square();\n    var u = s.unit();\n    return 0;\n}\n",
        "# expect: main.pep:20:19: error: 'Box<String>' does not conform to trait 'Shape'\ntrait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Shape> with Shape {\n    area(): int { return item.area() * 2; }\n}\nmain(): int {\n    Shape shape = Box<String>(\"x\");\n    return 0;\n}\n",
        "# expect: main.pep:9:5: error: 'int' cannot be converted to trait 'Doubled': only structs and enums whose cases carry values can be trait values\ntrait Doubled {\n    doubled(): int;\n}\nextend int with Doubled {\n    doubled(): int { return this * 2; }\n}\nmain(): int {\n    Doubled d = 3;\n    return 0;\n}\n",
        "# expect: main.pep:14:16: error: cannot convert a value of trait type 'A' to trait type 'B'\ntrait A {\n    f(): int;\n}\ntrait B {\n    g(): int;\n}\nstruct S {\n    f(): int { return 1; }\n}\nextend S with A;\nmain(): int {\n    var a: A = S();\n    var b: B = a;\n    return 0;\n}\n",
        "# expect: main.pep:9:5: error: 'make' in 'Other' returns 'Plain', which does not conform to 'Shape' as trait 'Shape' requires\ntrait Shape {\n    make(): Shape;\n}\nstruct Plain {\n    var x: int;\n}\nstruct Other {\n    make(): Plain { return Plain(); }\n}\nextend Other with Shape;\nmain(): int { return 0; }\n",
        # Value structs used as objects, containing themselves, passed to
        # C, and changed through a const, a temporary or a closure's copy.
        "# expect: main.pep:17:14: error: 'Span' is a value struct and has no identity; use '==' to compare values\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    var b = Span();\n    return a === b ? 1 : 0;\n}\n",
        "# expect: main.pep:16:14: error: value struct 'Span' cannot be null\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    return a == __null ? 1 : 0;\n}\n",
        "# expect: main.pep:15:12: error: '__weak' needs a reference type; 'Span' is a value struct\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var w: __weak<Span>;\n    return 0;\n}\n",
        "# expect: main.pep:16:23: error: 'Span' is a value struct and has no object\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    return __refcount(a);\n}\n",
        "# expect: main.pep:4:12: error: value struct 'A' contains itself through field 'b'\n[Value]\nstruct A {\n    var b: B;\n}\n\n[Value]\nstruct B {\n    var a: A;\n}\n\nmain(): int {\n    return 0;\n}\n",
        "# expect: main.pep:7:14: error: value struct 'S' cannot be passed to C; pass a pointer\n[Value]\nstruct S {\n    var x: int;\n}\n\nextern int f(S s);\n\nmain(): int {\n    return 0;\n}\n",
        "# expect: main.pep:16:7: error: cannot assign to field 'end' of const variable 's'\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    const s = Span(1, 2);\n    s.end = 3;\n    return 0;\n}\n",
        "# expect: main.pep:19:12: error: cannot call mutating method 'grow' on a temporary 'Span'\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmake(): Span {\n    return Span(1, 2);\n}\n\nmain(): int {\n    make().grow(1);\n    return 0;\n}\n",
        "# expect: main.pep:16:7: error: cannot call mutating method 'grow' on const variable 's'\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    const s = Span(1, 2);\n    s.grow(1);\n    return 0;\n}\n",
        "# expect: main.pep:8:24: error: cannot change 'this' in a closure: the closure holds a copy of 'Span'\n[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    later(): () => void {\n        return () => { end = 5; };\n    }\n}\n\nmain(): int {\n    return 0;\n}\n",
        # A misspelled OS, in code that would be dropped anyway.
        "# expect: main.pep:2:1: error: unknown OS value `Windoze` (expected Windows, Mac, MacOS, Linux, Wasi, IOS, Android) in [Target(OS(Windoze))]\n[Target(OS(Windoze))]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        # A build option comparison with no literal.
        "# expect: main.pep:2:24: error: '==' cannot compare two build options; compare a 'BuildOption(...)' with a literal\n[Target(BuildOption(A) == BuildOption(B))]\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        # A malformed predicate inside a dropped block.
        "# expect: main.pep:4:9: error: unknown Arch value `z80` (expected x64, aarch64, wasm32) in [Target(Arch(z80))]\nmain(): int {\n    [Target(OS(Windows))] {\n        [Target(Arch(z80))] {\n            return 1;\n        }\n    }\n    return 0;\n}\n",
        # A test that takes a parameter, and one that returns a value.
        "# expect: main.pep:3:3: error: test 't' must take no parameters\n[Test]\nt(x: int) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: test 't' must return nothing, not 'int'\n[Test]\nt(): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:2: error: 'ShouldPanic' applies only to a '[Test]' function\n[ShouldPanic]\nt() {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:6: error: 'Test' applies only to a free function\nstruct S {\n    [Test]\n    t() {}\n}\nmain(): int { return 0; }\n",
        # A captured local that is assigned.
        "# expect: main.pep:5:5: error: cannot assign to 'n' because a closure captures it\nmain(): int {\n    var n = 1;\n    var f = () => n + 1;\n    n = 2;\n    return f();\n}\n",
        # `this` in a closure of a static method.
        "# expect: main.pep:5:22: error: a closure in a static method cannot use 'this' or an instance member of 'S': a static method has none\nstruct S {\n    var x: int;\n    static make(): () => int {\n        return () => x;\n    }\n}\nmain(): int { return 0; }\n",
        # A closure capturing `this` stored in a field of `this`.
        "# expect: main.pep:6:9: error: storing a closure that captures 'this' in field 'f' of 'this' creates a reference cycle that is never freed\nstruct S {\n    var x: int;\n    var f: () => int;\n    set() {\n        f = () => x;\n    }\n}\nmain(): int { return 0; }\n",
        # Misplaced and contradictory `[Equatable]`.
        "# expect: main.pep:2:1: error: '[Equatable]' does not apply to enum 'E': its cases carry no values, so it already compares and hashes by case\n[Equatable]\nenum E { A, B }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:5: error: '[Equatable]' on a field applies only to a field of an '[Equatable]' struct\nstruct S {\n    [Equatable(exclude = true)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: '[Equatable]' on 'S' takes no arguments; 'include' and 'exclude' apply to its fields\n[Equatable(include = true)]\nstruct S {\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "# expect: error: call to undeclared function 'hash'\n[Equatable]\nstruct S {\n    [Equatable(include = true, exclude = false)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:26: error: 'include' of '[Equatable]' must be 'true' or 'false'\n[Equatable]\nstruct S {\n    [Equatable(include = 1)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: '[Equatable]' does not apply to value type 'S': a value already compares and hashes by its fields\n[Equatable]\n[Value]\nstruct S {\n    var x: int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:5: error: 'S' is '[Equatable]', so its '==' is derived and cannot be declared\n[Equatable]\nstruct S {\n    var x: int;\n    ==(other: S): bool { return true; }\n}\nmain(): int { return 0; }\n",
        # Type aliases: a cycle, too many arguments, a missing one.
        "# expect: main.pep:2:6: error: type alias 'A' refers to itself\ntype A = B;\ntype B = Box<A>;\nstruct Box<T> { var v: T; }\nmain(): int { return 0; }\n",
        "# expect: error: type alias 'P' takes 1 type argument(s), 2 given\ntype P<T> = Box<T>;\nstruct Box<T> { var v: T; }\nf(p: P<int, int>) {}\nmain(): int { return 0; }\n",
        "# expect: error: type alias 'P' requires a type argument for parameter 'U'\ntype P<T, U> = Box<T>;\nstruct Box<T> { var v: T; }\nf(p: P<int>) {}\nmain(): int { return 0; }\n",
        # A constructor parameter that names no field.
        "# expect: main.pep:2:8: error: constructor parameter 'this.y' has no matching field in 'S'\nstruct S {\n    var x: int;\n    construct(this.y = 0) {}\n}\nmain(): int { return 0; }\n",
        # Attributes an `[Attribute]` struct cannot take, and one that
        # cannot be an attribute.
        "# expect: main.pep:5:4: error: no case named 'B' in 'K'\nenum K { A }\n[Attribute]\nstruct T { var k: K; }\n[T(K.B)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:1: error: too few arguments to attribute 'A': missing 'x'\n[Attribute]\nstruct A {\n    var x: int;\n    construct(x: int) { this.x = x; }\n}\n[A()]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:19: error: field 'x' of attribute 'A' must be a number, 'bool', 'char', 'String' or an enum, not 'Array<int>'\n[Attribute]\nstruct A { var x: int[]; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:7: error: too many arguments to attribute 'A': expected 1, have 2\n[Attribute]\nstruct A { var x: int; }\n[A(1, 2)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:4: error: no parameter named 'y' in attribute 'A'\n[Attribute]\nstruct A { var x: int; }\n[A(y = 1)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:4: error: an attribute argument must be a constant: a number, 'bool', character, string or enum case\n[Attribute]\nstruct A { var x: int; }\n[A(f())]\nstruct P { var y: int; }\nf(): int { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:11: error: 'x' of attribute 'A' is given twice\n[Attribute]\nstruct A { var x: int; }\n[A(1, x = 2)]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:4: error: cannot use a string for 'x' of attribute 'A', which is a 'int'\n[Attribute]\nstruct A { var x: int; }\n[A(\"s\")]\nstruct P { var y: int; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:31: error: 'P' has no attribute 'A'; test it with 'has_attribute<A>()' first\n[Attribute]\nstruct A { var x: int; }\nstruct P { var y: int; }\nmain(): int {\n    static {\n        reflect.print(reflect.attribute<P, A>());\n    }\n    return 0;\n}\n",
        "# expect: main.pep:2:2: error: unknown attribute 'Nope'\n[Nope]\nstruct P { var x: int; }\nmain(): int { return 0; }\n",
        # Static blocks: what a block cannot evaluate, `reflect` misused,
        # `reflect.error` and `reflect.assert`, and a module-scope block.
        "# expect: main.pep:4:31: error: 'name' takes 1 type argument: 'reflect.name<T>()'\nmain(): int {\n    static {\n        reflect.print(reflect.name<int, int>());\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:26: error: nope\nmain(): int {\n    static {\n        reflect.assert(1 == 2, \"nope\");\n    }\n    return 0;\n}\n",
        # A type argument with commas of its own (pepper#149).
        "# expect: main.pep:4:17: error: (int, (String) => bool)\nmain(): int {\n    static {\n        reflect.error(reflect.name<(int, (String) => bool)>());\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:9: error: 'reflect' is used through its functions, such as 'reflect.properties<T>()'\nmain(): int {\n    static {\n        reflect = 3;\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:31: error: build option 'NOPE' is not defined\nmain(): int {\n    static {\n        reflect.print(reflect.build_option(\"NOPE\"));\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:48: error: invalid build option name '1x'; a name is a letter or '_' followed by letters, digits and '_'\nmain(): int {\n    static {\n        reflect.print(reflect.has_build_option(\"1x\"));\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:9: error: 'foo' cannot be called at compile time\nmain(): int {\n    static {\n        foo();\n    }\n    return 0;\n}\nfoo() {}\n",
        "# expect: main.pep:5:17: error: 'P' is not an enum\nstruct P { var x: int; }\nmain(): int {\n    static {\n        reflect.cases<P>();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:13: error: a compile-time condition must be a 'bool', not a integer\nmain(): int {\n    static {\n        if (3) {\n        }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:19: error: division by zero in a 'static' block\nmain(): int {\n    static {\n        var x = 1 / 0;\n    }\n    return 0;\n}\n",
        "# expect: main.pep:6:13: error: 'reflect.properties<P>()' is a compile-time list, which emitted code cannot use; emitted code can use numbers, 'bool', strings and enum cases\nstruct P { var y: int; }\nmain(): int {\n    var n = 0;\n    static (n) {\n        n = reflect.properties<P>();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:5:21: error: bad A\nmain(): int {\n    static {\n        for (var c in reflect.cases<K>()) {\n            reflect.error($\"bad {c.name}\");\n        }\n    }\n    return 0;\n}\nenum K { A, B }\n",
        "# expect: main.pep:4:23: error: index 5 is out of range for a list of 1\nmain(): int {\n    static {\n        reflect.print(reflect.cases<K>()[5]);\n    }\n    return 0;\n}\nenum K { A }\n",
        "# expect: main.pep:6:29: error: no member named 'nope' in compile-time member\nstruct P { var x: int; }\nmain(): int {\n    static {\n        for (var f in reflect.properties<P>()) {\n            reflect.print(f.nope);\n        }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:3:13: error: module\nstatic {\n    reflect.error(\"module\");\n    const X = 1;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:23: error: a 'for' in a 'static' block needs a compile-time list, such as 'reflect.properties<T>()'; this is a integer\nmain(): int {\n    static {\n        for (var x in 3) {\n        }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:17: error: 'Nope' is not a struct\nmain(): int {\n    static {\n        reflect.properties<Nope>();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:37: error: integer overflow in a 'static' block\nmain(): int {\n    static {\n        var x = 9223372036854775807 + 1;\n    }\n    return 0;\n}\n",
        "# expect: main.pep:5:17: error: 'K' is an enum; use 'reflect.cases<K>()'\nenum K { A }\nmain(): int {\n    static {\n        reflect.properties<K>();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:17: error: no function named 'nope' in 'reflect'\nmain(): int {\n    static {\n        reflect.nope<int>();\n    }\n    return 0;\n}\n",
        "# expect: main.pep:5:23: error: 'n' is a runtime value; add it to the static block's capture list\nmain(): int {\n    var n = 1;\n    static {\n        reflect.print(n);\n    }\n    return 0;\n}\n",
        "# expect: main.pep:8:19: error: 'set' cannot change value 'r': a case's values are fixed once made\nenum S { C(r: int) }\nmain(): int {\n    var s = S.C(1);\n    static (s) {\n        for (var k in reflect.cases<S>()) {\n            for (var v in k.values) {\n                v.set(s, 2);\n            }\n        }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:23: error: 'reflect' is used through its functions, such as 'reflect.properties<T>()'\nmain(): int {\n    static {\n        reflect.print(reflect.properties<int>);\n    }\n    return 0;\n}\n",
        "# expect: main.pep:4:9: error: a compile-time 'while' ran 100000 times; is its condition ever false?\nmain(): int {\n    static {\n        while (true) {\n        }\n    }\n    return 0;\n}\n",
        # Enum cases and value types' methods; `main`'s parameters; names
        # declared twice and const bindings assigned; `[Alias]` and
        # `[Rename]`; `[Link]`.
        "# expect: main.pep:3:17: error: no parameter named 'b'\nstruct S {\n    [Alias(\"a\", \"b\")]\n    m(x: int) {}\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:13: error: no parameter named 'y'\n[Alias(\"a\", \"y\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: 'Alias' takes two strings: [Alias(\"alias\", \"parameter\")]\n[Alias(\"a\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:8: error: 'x' is a parameter\n[Alias(\"x\", \"x\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:14: error: cannot assign to const variable 'x'\nstruct S {\n    const x: int = 1;\n    set() {\n        this.x = 2;\n    }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:9: error: cannot assign to const variable 'x'\nstruct S {\n    const x: int = 1;\n    set() {\n        x = 2;\n    }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:5: error: cannot assign to const variable 'G'\nconst G = 1;\nmain(): int {\n    G += 2;\n    return G;\n}\n",
        "# expect: main.pep:4:5: error: cannot assign to const variable 'x'\nmain(): int {\n    const x = 1;\n    x++;\n    return x;\n}\n",
        "# expect: main.pep:4:5: error: cannot assign to const variable 'x'\nmain(): int {\n    const x = 1;\n    x = 2;\n    return x;\n}\n",
        "# expect: main.pep:4:15: error: cannot convert a value to enum 'Color' with 'as'\nenum Color { Red, Green }\nmain(): int {\n    var c = 1 as Color;\n    return 0;\n}\n",
        "# expect: main.pep:4:19: error: 'from_value' is a method of 'Color': call it as 'Color.from_value(...)'\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.from_value;\n    return 0;\n}\n",
        "# expect: main.pep:4:19: error: no case named 'Blue' in 'Color'\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.Blue;\n    return 0;\n}\n",
        "# expect: main.pep:4:19: error: no member named 'nope' in 'Color'\nenum Color { Red, Green }\nmain(): int {\n    var c = Color.nope();\n    return 0;\n}\n",
        "# expect: main.pep:8:18: error: 'twice' is not static: call it on a value of 'Color', such as 'Color.Red.twice()'\nenum Color {\n    Red,\n    Green,\n    twice(): int { return 2; }\n}\nmain(): int {\n    return Color.twice();\n}\n",
        "# expect: main.pep:3:8: error: cannot extend enum 'Color' without a trait: declare its methods inside the enum\nenum Color { Red, Green }\nextend Color {\n    f(): int { return 1; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:14: error: 'Link' argument 'path' must not be empty\n[Link(path = \"\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: 'Link' needs a library or a symbol: [Link(\"lib\")], [Link(name = \"sym\")]\n[Link]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:7: error: 'Link' has no argument named 'nope'; use 'lib', 'path' or 'name'\n[Link(nope = \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:12: error: library given twice in one 'Link'\n[Link(\"m\", lib = \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:1: error: 'LinkName' was removed; use '[Link(name = \"g\")]'\n[LinkName(\"g\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:12: error: 'Link' takes one positional argument, the library; name the others\n[Link(\"m\", \"n\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:13: error: 'Link' argument 'lib' must be a string\n[Link(lib = 1)]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:7: error: extern 'f' has more than one symbol name\n[Link(name = \"a\")]\n[Link(name = \"b\")]\nextern int f();\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:6: error: 'main(args: String[])' needs '_pep_arguments' from the runtime\nmain(args: String[]): int { return 0; }\n",
        "# expect: main.pep:2:9: error: 'main' must take no parameters or one 'String[]'\nmain(a: int): int { return 0; }\n",
        "# expect: main.pep:2:19: error: 'main' must take no parameters or one 'String[]'\nmain(a: String[], b: int): int { return 0; }\n",
        "# expect: main.pep:3:14: error: operator '*' of 'int' cannot take an operand of type 'double': the built-in operator applies\nextend int {\n    *(other: double): int { return 1; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:5: error: operator '+' in an extension of 'int' must take one operand: the 'int' is the left operand\nextend int {\n    +(a: int, b: int): int { return a; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:9: error: redefinition of 'x'\nmain(): int {\n    var x = 1;\n    var x = 2;\n    return x;\n}\n",
        # A local that repeats a parameter, of a function or a closure (#129).
        "# expect: main.pep:3:9: error: redefinition of 'x'\nf(x: bool): int {\n    var x = 5;\n    return x;\n}\nmain(): int { return f(true); }\n",
        "# expect: main.pep:4:13: error: redefinition of 'x'\nmain(): int {\n    var f = (x: int) => {\n        var x = 2;\n        return x;\n    };\n    return f(1);\n}\n",
        "# expect: main.pep:2:11: error: redefinition of 'x'\nf(x: int, x: int): int { return x; }\nmain(): int { return f(1, 2); }\n",
        # Extension and trait methods are checked too, a declaration included.
        "# expect: main.pep:5:13: error: redefinition of 'k'\nstruct P { var n: int; }\nextend P {\n    twice(k: int): int {\n        var k = 2;\n        return n * k;\n    }\n}\nmain(): int { return P().twice(1); }\n",
        "# expect: main.pep:5:13: error: redefinition of 'k'\ntrait Shape {\n    sides(): int;\n    doubled(k: int): int {\n        var k = 2;\n        return sides() * k;\n    }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:18: error: redefinition of 'a'\ntrait Shape {\n    area(a: int, a: int): int;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:13: error: redefinition of 'z'\nmain(): int {\n    var g = (y: int) => {\n        var z = 2;\n        var z = 3;\n        return z;\n    };\n    return g(1);\n}\n",
        "# expect: main.pep:7:13: error: cannot construct enum 'Doc' directly: its values are made by its cases\nenum Doc {\n    Line,\n    Text(text: int),\n}\nmain(): int {\n    var d = Doc();\n    return 0;\n}\n",
        "# expect: main.pep:7:17: error: case 'Text' of 'Doc' takes 2 values: 'Doc.Text(text, more)'\nenum Doc {\n    Line,\n    Text(text: int, more: int),\n}\nmain(): int {\n    var d = Doc.Text;\n    return 0;\n}\n",
        "# expect: main.pep:7:17: error: no case named 'Nope' in 'Doc'\nenum Doc {\n    Line,\n    Text(text: int),\n}\nmain(): int {\n    var d = Doc.Nope;\n    return 0;\n}\n",
        "# expect: main.pep:3:8: error: 'old' is already another name of a parameter\n[Rename(\"old\", \"x\")]\n[Alias(\"old\", \"x\")]\nf(x: int) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:8: error: 'int' does not implement 'twice', required by trait 'Twice'\ntrait Twice {\n    twice(): int;\n}\nextend int with Twice {\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: redefinition of 'main'\nmain(): int { return 0; }\nmain(): int { return 1; }\n",
        # A misnamed argument, with and without a likely meaning.
        "# expect: main.pep:4:10: error: no parameter named 'betta' in 'f'; did you mean 'beta'?\nf(alpha: int, beta: int = 2) {}\nmain(): int {\n    f(1, betta = 3);\n    return 0;\n}\n",
        "# expect: main.pep:4:10: error: no parameter named 'zzz' in 'f'\nf(alpha: int, beta: int = 2) {}\nmain(): int {\n    f(1, zzz = 3);\n    return 0;\n}\n",
        # Too many arguments, one given twice, and one missing.
        "# expect: main.pep:4:13: error: too many arguments to 'f': expected at most 2, have 4\nf(a: int, b: int = 2) {}\nmain(): int {\n    f(1, 2, 3, b = 4);\n    return 0;\n}\n",
        "# expect: main.pep:4:10: error: argument for 'a' given twice\nf(a: int, b: int = 2) {}\nmain(): int {\n    f(1, a = 2);\n    return 0;\n}\n",
        "# expect: main.pep:4:5: error: missing argument for parameter 'a' in call to 'f'\nf(a: int, b: int = 2) {}\nmain(): int {\n    f(b = 1);\n    return 0;\n}\n",
        # Overloads none of which fit, and ones that bind differently.
        "# expect: main.pep:5:7: error: no matching function for call to 'f'\nf(a: int) {}\nf(b: String) {}\nmain(): int {\n    f(c = 1);\n    return 0;\n}\n",
        "# expect: main.pep:5:7: error: named arguments bind differently in the overloads of 'f'\nf(a: int, b: int) {}\nf(b: double, a: double) {}\nmain(): int {\n    f(b = 1, a = 2);\n    return 0;\n}\n",
        # A named argument to an extern, and to a method called bare.
        "# expect: main.pep:4:14: error: cannot name arguments in a call to extern function 'e'\nextern int e(int x);\nmain(): int {\n    return e(x = 1);\n}\n",
        "# expect: main.pep:4:15: error: no parameter named 'frist' in 'S.m'; did you mean 'first'?\nstruct S {\n    m(first: int) {}\n    run() { m(frist = 1); }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:22: error: no parameter named 'valu' in 'Box'; did you mean 'value'?\nstruct Box<T> {\n    var v: T;\n    construct(value: T) { v = value; }\n}\nmain(): int {\n    var b = Box<int>(valu = 1);\n    return 0;\n}\n",
        "# expect: main.pep:3:11: error: no parameter named 'b' in 'f'; did you mean 'a'?\nf(a: int) {}\nvar g = f(b = 1);\nmain(): int { return 0; }\n",
        # Overloads that clash: free functions, externs, constructors,
        # methods, a trait's methods, and concrete overrides.
        "# expect: main.pep:3:1: error: redefinition of 'f'\nf(x: int) {}\nf(y: i32) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: functions that differ only in their return type cannot be overloaded\nf(x: int): int { return 0; }\nf(x: int): bool { return true; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: redefinition of generic 'f'; to override it for a type, each type argument must name a struct this file can see\nf<T>(x: T) {}\nf<U>(y: U) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:1: error: extern 'puts' cannot be overloaded; rename it and overload Pepper functions named 'puts' that call it\nextern int puts(__ptr<char> s);\nputs(x: int): int { return x; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:12: error: extern 'puts' cannot be overloaded; rename it and overload Pepper functions named 'puts' that call it\nputs(x: int): int { return x; }\nextern int puts(__ptr<char> s);\nmain(): int { return 0; }\n",
        "# expect: main.pep:3:13: error: extern 'puts' cannot be overloaded; rename it and overload Pepper functions named 'puts' that call it\nextern int puts(__ptr<char> s);\nextern long puts(__ptr<char> s);\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:5: error: constructor of 'P' cannot be redeclared\nstruct P {\n    var x: int;\n    construct(a: int) {}\n    construct(b: i32) {}\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:12: error: static method 'get' cannot share its name with an instance method of 'P'\nstruct P {\n    get(): int { return 0; }\n    static get(i: int): int { return i; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:5: error: redefinition of 'get'\nstruct P {\n    get(i: int): int { return 0; }\n    get(j: int): int { return j; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:5: error: functions that differ only in their return type cannot be overloaded\ntrait R {\n    read(): int;\n    read(): long;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:1: error: override 'hash<int>' matches none of the overloads of 'hash'; it must match exactly one\nhash<T>(value: T): ulong { return 0; }\nhash<T>(value: T, seed: ulong): ulong { return seed; }\nhash<int>(value: int, a: int, b: int): ulong { return 1; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:1: error: override 'f<int>' matches several of the overloads of 'f'; it must match exactly one\nf<T>(a: T, b: int) {}\nf<T>(a: int, b: T) {}\nf<int>(a: int, b: int) {}\nmain(): int { return 0; }\n",
        # `?` on what is neither a Result nor an Optional, and in a function
        # returning another kind.
        "# expect: main.pep:4:16: error: '?' requires a Result or an Optional, not 'int'\nf(): int { return 1; }\ng(): int {\n    var x = f()?;\n    return x;\n}\nmain(): int { return g(); }\n",
        "# expect: main.pep:5:16: error: '?' requires the enclosing function to return an Optional\nstruct Optional<T> {}\nf(): Optional<int> { return Optional<int>(); }\ng(): int {\n    var x = f()?;\n    return 0;\n}\nmain(): int { return g(); }\n",
        # A trait member an extension leaves out, and one it declares with
        # another type.
        "# expect: main.pep:6:8: error: 'Box' does not implement 'area', required by trait 'Shape'\ntrait Shape {\n    area(): int;\n}\nstruct Box {}\nextend Box with Shape;\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:5: error: 'area' in 'Box' has type '() => long', but trait 'Shape' declares '() => int'\ntrait Shape {\n    area(): int;\n}\nstruct Box {}\nextend Box with Shape {\n    area(): long { return 1; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:8:8: error: 'Box' does not implement property 'size', required by trait 'Sized'\ntrait Sized {\n    var size: int { get; }\n}\nstruct Box {\n    var other: int;\n}\nextend Box with Sized;\nmain(): int { return 0; }\n",
        # A value `print` cannot convert.
        "# expect: main.pep:5:11: error: cannot print a value of type 'S': it has no 'to_string()' method and no 'to_string' overload\nprint<T>(value: T) {}\nstruct S {}\nmain(): int {\n    print(S());\n    return 0;\n}\n",
        # Constraints that name no trait, a trait named `Shared`, and type
        # arguments that do not conform (a number, a type parameter, a
        # struct).
        "# expect: main.pep:3:6: error: 'S' is not a trait; a constraint must name a trait\nstruct S {}\nf<T: S>(x: T) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:7: error: trait 'Shared' takes the name of the built-in constraint 'Shared'; rename it\ntrait Shared {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:17: error: 'int' does not conform to trait 'Named', required by 'T' in 'Box'\ntrait Named {\n    name(): int;\n}\nstruct Box<T: Named> {}\nmain(): int {\n    var b = Box<int>();\n    return 0;\n}\n",
        "# expect: main.pep:6:13: error: 'U' does not conform to trait 'Named', required by 'T' in 'Box'\ntrait Named {\n    name(): int;\n}\nstruct Box<T: Named> {}\nf<U>(b: Box<U>) {}\nmain(): int { return 0; }\n",
        "# expect: main.pep:8:17: error: 'S' does not conform to trait 'Named', required by 'T' in 'Box'\ntrait Named {\n    name(): int;\n}\nstruct S {}\nstruct Box<T: Named> {}\nmain(): int {\n    var b = Box<S>();\n    return 0;\n}\n",
        # Constrained generic code uses only what its constraints offer.
        "# expect: main.pep:6:45: error: no member named 'perimeter' in 'T'\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.perimeter(); }\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:45: error: no member named 'radius' in 'T'\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.radius; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:37: error: cannot construct 'T': a constrained type parameter has no constructor\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(item: T): T { return T(); }\nmain(): int { return 0; }\n",
        "# expect: main.pep:8:57: error: 'name' is declared by both 'Named' and 'Titled'; call it through one of them\ntrait Named {\n    name(): String;\n}\ntrait Titled {\n    name(): String;\n}\nlabel<T: Named & Titled>(item: T): String { return item.name(); }\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:45: error: too many arguments to 'scale': expected 1, have 2\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(1, 2); }\nmain(): int { return 0; }\n",
        "# expect: accepted\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(\"twice\"); }\nmain(): int { return 0; }\n",
        "# expect: main.pep:10:26: error: cannot initialize variable 'circle' of type 'Circle' with a value of type 'T'\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Circle {\n}\nkeep<T: Shape>(item: T): int {\n    var shape: Shape = item;\n    var circle: Circle = item;\n    return 0;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:48: error: invalid operands to binary expression ('T' and 'T')\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nsmaller<T: Shape>(a: T, b: T): bool { return a < b; }\nmain(): int { return 0; }\n",
        "# expect: accepted\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Gallery<T: Shape> {\n    var items = Array<T>();\n    first(): int { return items[0].depth(); }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:6:32: error: no member named 'unit' in 'T'\ntrait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(): T { return T.unit(); }\nmain(): int { return 0; }\n",
        "# expect: main.pep:7:11: error: invalid operands to binary expression ('T' and 'T')\ntrait Addable {\n    +(other: this): this;\n}\ngrow<T: Addable>(a: T, b: T): T {\n    var total = a;\n    total += b;\n    return total;\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:34: error: invalid argument type 'T' to unary expression\ntrait Shape {\n    area(): int;\n}\nflip<T: Shape>(a: T): T { return -a; }\nmain(): int { return 0; }\n",
        "# expect: main.pep:5:36: error: type 'T' cannot be indexed\ntrait Shape {\n    area(): int;\n}\npick<T: Shape>(a: T): int { return a[0]; }\nmain(): int { return 0; }\n",
        # Range bounds must be integers.
        "# expect: main.pep:4:16: error: range bounds must be integers, not 'double'\n_range<T>(a: T, b: T, inclusive: bool): int { return 0; }\nmain(): int {\n    var r = 1.5..3.0;\n    return 0;\n}\n",
        "# expect: main.pep:4:16: error: cannot infer the type arguments of '_range' from its arguments; write them: _range<T>(...)\n_range<T>(a: T, b: T, inclusive: bool): int { return 0; }\nmain(): int {\n    var r = \"a\"..>\"z\";\n    return 0;\n}\n",
        # A generic method's constraints, at its specialization.
        "# expect: main.pep:10:23: error: 'int' does not conform to trait 'Named', required by 'T' in 'get'\ntrait Named {\n    name(): int;\n}\nstruct Box {\n    get<T: Named>(x: T): int { return 0; }\n}\nmain(): int {\n    var b = Box();\n    return b.get<int>(1);\n}\n",
        "# expect: accepted\nstruct Box {\n    get<T>(x: T): T { return x; }\n}\nmain(): int {\n    var b = Box();\n    var f = b.get<int>;\n    return b.get<int>(1) + f(2) + b.missing<int>(3);\n}\n",
        # A specialization's `static` block emits a lowered string.
        "# expect: accepted\npick<T>(x: T): T {\n    var s = x;\n    static (s) {\n        var t = \"ab\";\n        s = t;\n    }\n    return s;\n}\nmain(): int {\n    var p = pick<int>(1);\n    return 0;\n}\n",
        # Intrinsics: function pointers, `__ptr<T>`, typed intrinsics and SIMD arity.
        "# expect: main.pep:5:32: error: use of undeclared identifier 'g'\nf(): int { return 1; }\nmain(): int {\n    var p = __function_pointer(f);\n    var q = __function_pointer(g);\n    return 0;\n}\n",
        "# expect: main.pep:6:13: error: too few arguments to '__simd_add': expected 2, have 1\nmain(): int {\n    var x: __ptr<int> = null;\n    var y = __address<int>(x);\n    var b = __is_pod<__ptr<char>>();\n    var v = __simd_add<int>(1);\n    return 0;\n}\n",
        "# expect: main.pep:6:17: error: too many arguments to '__function_pointer': expected 1, have 2\nstruct S {\n    static h(): int { return 2; }\n    m(): int {\n        var p = __function_pointer(h);\n        var q = __function_pointer(1, 2);\n        return 0;\n    }\n}\nmain(): int { return 0; }\n",
        "# expect: accepted\nmain(): int {\n    var x: __ptr<int> = null;\n    var y = __address<int>(x);\n    var b = __is_pod<__ptr<char>>();\n    return 0;\n}\n",
        # Bare names in methods: an undeclared one, in a concrete struct, a
        # specialization and a trait's default method.
        "# expect: main.pep:4:25: error: use of undeclared identifier 'zork' in a method of 'S'\nstruct S {\n    var n: int;\n    get(): int { return zork; }\n}\nmain(): int { return 0; }\n",
        "# expect: main.pep:4:25: error: use of undeclared identifier 'zork' in a method of 'B'\nstruct B<T> {\n    var v: T;\n    get(): int { return zork + 1; }\n}\nmain(): int { var b = B<int>(); return 0; }\n",
        "# expect: main.pep:3:27: error: use of undeclared identifier 'n' in a method of 'S'\ntrait Counted {\n    count(): int { return n; }\n}\nstruct S {\n    var n: int;\n}\nextend S with Counted;\nmain(): int { return 0; }\n",
        # Copies that cannot be made: a destructor (through a field), a raw
        # pointer field, `[NotCopyable]` and a plain function value.
        "# expect: main.pep:12:13: error: cannot copy 'H' because it contains 'R', which is not trivially copyable\nstruct R {\n    var n: int;\n    destruct { n = 0; }\n}\nstruct H {\n    var r: R;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var h = H();\n    var c = copy(h);\n    return 0;\n}\n",
        "# expect: main.pep:7:13: error: cannot copy 'P', which is not trivially copyable\nstruct P {\n    var p: __ptr<char>;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(P());\n    return 0;\n}\n",
        "# expect: main.pep:20:13: error: cannot copy 'W' because it contains 'F', which cannot be copied\n[Attribute]\nstruct NotCopyable {\n    var reason: String;\n}\nstruct String {\n    var data: __ptr<char>;\n    construct(raw: __ptr<char>, size: long, length: long) {}\n}\n[NotCopyable(\"it owns a handle\")]\nstruct F {\n    var n: int;\n}\nstruct W {\n    var f: F;\n    var g: (int) => int;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(W());\n    return 0;\n}\n",
        "# expect: main.pep:7:13: error: cannot copy 'W' because it contains '(int) => int', which is a plain function value\nstruct W {\n    var g: (int) => int;\n}\ncopy<T>(value: T): T { return value; }\nmain(): int {\n    var c = copy(W());\n    return 0;\n}\n",
        # 'Cold' takes no arguments
        "# expect: main.pep:2:2: error: 'Cold' takes no arguments\n[Cold(\"rarely\")]\nf(): int {\n    return 1;\n}\n\nmain(): int {\n    return f();\n}\n",
        # 'Cold' applies only to a function, method or constructor
        "# expect: main.pep:2:2: error: 'Cold' applies only to a function, method or constructor\n[Cold]\nstruct S {}\n\nmain(): int {\n    return 0;\n}\n",
        # A closure whose struct does not conform to the trait its slot's
        # function type returns: a plain function, a generic one, a
        # constructor argument, and a struct with a method of the wrong type.
        "# expect: main.pep:12:24: error: 'Plain' does not conform to trait 'Source'\ntrait Source {\n    next(): int;\n}\nstruct Plain {\n    construct() {}\n}\ntake(make: (int) => Source): int {\n    return 0;\n}\nmain(): int {\n    return take((n) => Plain());\n}\n",
        "# expect: main.pep:12:37: error: 'Plain' does not conform to trait 'Source<int>'\ntrait Source<T> {\n    next(): T;\n}\nstruct Plain {\n    construct() {}\n}\ntake<T, U>(item: T, make: (T) => Source<U>): int {\n    return 0;\n}\nmain(): int {\n    return take<int, int>(1, (n) => Plain());\n}\n",
        "# expect: main.pep:15:27: error: 'Plain' does not conform to trait 'Source'\ntrait Source {\n    next(): int;\n}\nstruct Plain {\n    construct() {}\n}\nstruct Holder {\n    (int) => Source make;\n    construct(make: (int) => Source) {\n        this.make = make;\n    }\n}\nmain(): int {\n    var h = Holder((n) => Plain());\n    return 0;\n}\n",
        "# expect: main.pep:15:24: error: 'Wrong' does not conform to trait 'Source'\ntrait Source {\n    next(): int;\n}\nstruct Wrong {\n    construct() {}\n    next(): bool {\n        return true;\n    }\n}\ntake(make: (int) => Source): int {\n    return 0;\n}\nmain(): int {\n    return take((n) => Wrong());\n}\n"
    ];
}

# Programs the steps ported so far rewrite.
rewritten_programs(): String[] {
    return [
        # Implicit constructor calls, from a variable and a literal.
        "# expect: accepted\nstruct Meters {\n    var v: long;\n    [Implicit]\n    construct(v: long) { this.v = v; }\n}\ntake(m: Meters): long { return m.v; }\nmain(): int {\n    int n = 2;\n    var m: Meters = n;\n    return (take(3) + take(m)) as int;\n}\n",
        # Methods, a struct and a specialization used as values.
        "# expect: accepted\nstruct P {\n    var x: int;\n    get(): int { return x; }\n    static make(): P { return P(); }\n}\npick<T>(a: T, b: T): T { return a; }\nmain(): int {\n    var p = P();\n    var f = p.get;\n    var g = P.get;\n    var h = P.make;\n    var k = pick<int>;\n    var n = P;\n    return f() + g(p) + h().x + k(1, 2) + n().x;\n}\n",
        # Declarations, members, enum cases and blocks for one platform.
        "# expect: accepted\n[Target(OS(Windows))]\nf(): int { return 1; }\n[Target(!OS(Windows))]\nf(): int { return 2; }\nstruct S {\n    var x: int;\n    [Target(OS(Linux))]\n    linux(): int { return 1; }\n    [Target(OS(Mac))]\n    mac(): int { return 2; }\n}\nenum E {\n    A,\n    [Target(OS(Windows))]\n    B,\n    C,\n}\nmain(): int {\n    var n = 0;\n    [Target(OS(Linux))] {\n        n = 1;\n    }\n    if (n == 0) {\n        [Target(OS(Windows))] {\n            n = 2;\n        }\n    } else {\n        [Target(Arch(x64))] {\n            n = 3;\n        }\n    }\n    while (n > 10) {\n        [Target(Arch(aarch64))] {\n            n = 4;\n        }\n    }\n    return f() + n;\n}\n",
        # A test, kept only in a test build.
        "# expect: accepted\n[Test]\nchecks() {}\nmain(): int { return 0; }\n",
        # Closures: captures, nesting, `this`, bare members, statics, a
        # parameter default, a field default and a global.
        "# expect: main.pep:2:5: error: module-scope variable 'g' must be 'const'\nvar g: () => int = () => 1;\nstruct S {\n    var x: int;\n    var h: () => int = () => 2;\n    get(): int { return x; }\n    static twice(n: int): int { return n * 2; }\n    run(k: int): int {\n        var a = 3;\n        var f = (b: int) => {\n            var inner = () => a + b + k + x + get() + twice(a);\n            return inner();\n        };\n        var m = get;\n        return f(1) + this.x;\n    }\n}\nf(g: () => int = () => 5): int { return g(); }\nmain(): int {\n    var s = S();\n    return s.run(1) + f() + g();\n}\n",
        # Closures in a generic struct, an extension, a trait's default
        # method and a deprecated function.
        "# expect: accepted\nstruct Box<T> {\n    var v: T;\n    map(): () => T { return () => v; }\n}\nextend Box<U> {\n    other(): () => U { return () => this.v; }\n}\ntrait Shape {\n    area(): int;\n    twice(): () => int { return () => area() * 2; }\n}\n[Deprecated(\"old\")]\nold(): () => int { return () => 1; }\nmain(): int { return 0; }\n",
        # `[Equatable]`: all fields, one field, an excluded one, none.
        "# expect: error: call to undeclared function 'hash'\n[Equatable]\nstruct P {\n    var x: int;\n    var y: int;\n}\n[Equatable]\nstruct Q {\n    var x: int;\n    [Equatable(exclude = true)]\n    var cache: int;\n}\n[Equatable]\nstruct R {\n    [Equatable(false)]\n    var x: int;\n}\nmain(): int { return 0; }\n",
        # Type aliases: generic with a default, nested, a static receiver,
        # an explicit generic argument and a value that shares a name.
        "# expect: main.pep:9:5: error: module-scope variable 'g' must be 'const'\nstruct Box<T> {\n    var v: T;\n    static make(v: T): Box<T> { var b = Box<T>(); b.v = v; return b; }\n}\ntype Id = int;\ntype B<T = Id> = Box<T>;\ntype BB<T> = B<B<T>>;\nvar g: B = Box<int>();\ng2<T>(x: T): T { return x; }\nf(b: BB<long>, n: Id): B<Id> {\n    var c = B.make(n);\n    var d = g2<B<Id>>(c);\n    var size = sizeof<B<Id>>();\n    return d;\n}\nmain(): int { return 0; }\n",
        # Struct synthesis: counted, shared, value and generic structs,
        # field parameters, enum and float fields, and a reference enum.
        "# expect: main.pep:4:22: error: field 'n' of shared struct 'Counter' must be 'const'\nenum Color { Red = 1, Green = 2 }\n[Shared]\nstruct Counter { var n: int; }\n[Value]\nstruct V {\n    var x: int;\n    construct(this.x = 0) {}\n}\nstruct Box<T> {\n    var v: T;\n    var w: Box<T>;\n    var p: __ptr<int>;\n}\nstruct S {\n    var c: Color;\n    var f: double;\n    var v: V;\n    var t: (int, bool);\n    var s: S;\n    var k: int = 7;\n    construct(this.k = 1, extra: int = 2) {\n        c = Color.Green;\n    }\n    construct() {}\n    destruct {}\n}\nenum Shape {\n    Dot,\n    Circle(r: double),\n}\nmain(): int { return 0; }\n",
        # Static blocks over properties, fields, value and reference enum
        # cases, attribute values, functions with an attribute, loops and
        # compile-time arithmetic, emitted branches, methods and
        # constructors, and module-scope constants.
        "# expect: accepted\nenum Kind { Flag, Value }\n\n[Attribute]\nstruct Opt {\n    const long_name: String;\n    const short_name: String;\n    const kind: Kind;\n    const count: int = 1;\n    const ratio: double;\n\n    construct(long_name: String, short_name: String = \"\", kind: Kind = Kind.Value) {\n        this.long_name = long_name;\n        this.short_name = short_name;\n        this.kind = kind;\n    }\n}\n\n[Attribute]\nstruct Tag {\n    var text: String;\n    var weight: int;\n}\n\nstruct Args {\n    [Opt(\"verbose\", \"v\", kind = Kind.Flag)]\n    var verbose: bool;\n    [Opt(\"out\" + \"put\")]\n    [Tag(\"t\", -3)]\n    var output: String;\n    var plain: int;\n}\n\nmain(): int {\n    var a = Args();\n    static (a) {\n        for (var f in reflect.properties<Args>()) {\n            if (f.has_attribute<Opt>()) {\n                var o = f.attribute<Opt>();\n                reflect.print(o);\n                reflect.print($\"{o.long_name}/{o.short_name}/{o.kind}/{o.count}/{o.ratio}\");\n            }\n            if (f.has_attribute<Tag>()) {\n                reflect.print(f.attribute<Tag>().weight);\n            }\n        }\n        reflect.print(reflect.has_attribute<Args, Opt>());\n    }\n    return 0;\n}\n",
        "# expect: accepted\nenum Color { Red, Green = 5, Blue }\n\nmain(): int {\n    var c = Color.Green;\n    static (c) {\n        for (var k in reflect.cases<Color>()) {\n            if (k.matches(c)) {\n                reflect.print($\"{k.name} {k.value} {k.index} {k.is_last}\");\n            }\n            var v = k.get();\n        }\n    }\n    return 0;\n}\n",
        "# expect: main.pep:5:37: error: use of undeclared identifier 'reflect' in a method of 'A'\n[Attribute]\nstruct A {\n    var x: int;\n    construct(x: int) { this.x = x; reflect.print(\"hi\"); }\n}\nmain(): int { return 0; }\n",
        "# expect: accepted\nstruct P { var x: int; var y: int; }\n\nmain(): int {\n    var p = P();\n    var n = 0;\n    static (p, n) {\n        for (var f in reflect.properties<P>()) {\n            if (f.get(p) == 0) {\n                n += 1;\n            } else {\n                n -= 1;\n            }\n        }\n    }\n    return n;\n}\n",
        "# expect: accepted\nstruct Point {\n    var x: int;\n    var _y: int;\n}\n\nmain(): int {\n    var p = Point();\n    static (p) {\n        for (var f in reflect.fields<Point>()) {\n            reflect.print(f.name);\n        }\n    }\n    return 0;\n}\n",
        "# expect: accepted\n[Attribute]\nstruct Command {\n    var name: String;\n}\n\n[Command(\"b\")]\nrun_b(): int { return 2; }\n\n[Command(\"a\")]\nrun_a(): int { return 1; }\n\nmain(): int {\n    var total = 0;\n    static (total) {\n        for (var f in reflect.functions_with<Command>()) {\n            reflect.print($\"{f.name} {f.attribute<Command>().name}\");\n            total += f.call();\n        }\n    }\n    return total;\n}\n",
        "# expect: accepted\nmain(): int {\n    var out = 0;\n    static (out) {\n        var i = 0;\n        var s = \"\";\n        while (i < 5) {\n            i += 1;\n            if (i == 2) {\n                continue;\n            }\n            if (i == 4) {\n                break;\n            }\n            s = s + $\"{i}\";\n            out += i;\n        }\n        var list = reflect.cases<K>();\n        reflect.print(list.count);\n        reflect.print(list[1]);\n        reflect.print(s.length);\n        reflect.print(1.5 * 2);\n        reflect.print(7 / 2);\n        reflect.print(7 % 3);\n        reflect.print(-7.5 % 2);\n        reflect.print(\"a\" < \"b\");\n        reflect.print(1 < 2.5);\n        reflect.print(10.0 / 4);\n        reflect.print(1e21);\n        reflect.print(0.1 + 0.2);\n        reflect.print(s.starts_with(\"1\"));\n        reflect.print(true and false or !false);\n        reflect.print(i == 4 ? \"four\" : \"other\");\n        reflect.assert(i == 4, \"i is four\");\n        reflect.print(reflect.name<Array<int>>());\n        reflect.print(reflect.is_struct<K>());\n        reflect.print(reflect.is_enum<K>());\n        reflect.print(reflect.is_reference<String>());\n        reflect.print(reflect.is_same<int, i32>());\n        reflect.print(reflect.is_same<__ptr<int>, i32*>());\n        reflect.print(reflect.has_build_option(\"X\"));\n        reflect.print(reflect.build_option(\"X\", \"dflt\"));\n        reflect.print(\"q\\\"uote\\n\");\n    }\n    return out;\n}\n\nenum K { A, B }\n",
        "# expect: accepted\nstruct P {\n    var x: int;\n    var y: int;\n\n    sum(): int {\n        var total = 0;\n        static (total) {\n            for (var f in reflect.properties<P>()) {\n                total += f.get(this);\n            }\n        }\n        return total;\n    }\n\n    construct() {\n        static {\n            reflect.print(\"ctor\");\n        }\n    }\n}\n\nmain(): int {\n    return P().sum();\n}\n",
        "# expect: accepted\nenum Level { Low, High }\n\nstatic {\n    var n = 0;\n    for (var c in reflect.cases<Level>()) {\n        n += c.value + 1;\n    }\n    const COUNT = n;\n    const NAME = \"lvl\" + $\"{n}\";\n    const RATE = 2.5;\n    const ON = n > 1;\n    const TOP = Level.High;\n}\n\nmain(): int {\n    return COUNT;\n}\n",
        "# expect: accepted\nstruct Point {\n    var x: int;\n    var y: double;\n    const name: String = \"p\";\n    var _hidden: int;\n    var label: String { get { return name; } }\n}\n\nmain(): int {\n    var p = Point();\n    var total = 0;\n    static (p, total) {\n        for (var field in reflect.properties<Point>()) {\n            reflect.print($\"{field.name} {field.index} {field.is_last} {field.type_name} {field.is_const} {field.is_property}\");\n            if (reflect.is_same<field.Type, int>()) {\n                total += field.get(p);\n                field.set(p, 3);\n            }\n        }\n    }\n    return total;\n}\n",
        "# expect: accepted\nenum Shape {\n    Circle(radius: double),\n    Rect(w: int, h: int),\n    Empty,\n}\n\nmain(): int {\n    var s = Shape.Circle(1.5);\n    var n = 0;\n    static (s, n) {\n        for (var k in reflect.cases<Shape>()) {\n            if (k.matches(s)) {\n                n += 1;\n            }\n            for (var v in k.values) {\n                reflect.print($\"{v.name} {v.type_name}\");\n            }\n        }\n    }\n    return n;\n}\n",
        # Enum cases, built-in and static methods, value type extensions
        # and their trait defaults; `main(args)`; shadowing and const
        # fields set in a constructor; `[Alias]`, `[Rename]` and `[Link]`.
        "# expect: accepted\n[Alias(\"w\", \"width\")]\n[Rename(\"old\", \"height\")]\nf(width: int, height: int) {}\nstruct S {\n    var x: int;\n    [Alias(\"ex\", \"x\")]\n    construct(this.x = 0) {}\n}\nmain(): int { return 0; }\n",
        "# expect: accepted\nconst G = 1;\nstruct S {\n    const x: int;\n    construct() { x = 1; this.x = 2; }\n}\nmain(): int {\n    var x = 1;\n    {\n        var x = 2;\n    }\n    var y = x;\n    y += 1;\n    return y;\n}\n",
        "# expect: main.pep:26:5: error: module-scope variable 'g' must be 'const'\nenum Color: u8 { Red = 2, Green, Blue = 0 }\nenum Doc {\n    Line,\n    Text(text: int),\n    static make(): Doc { return Doc.Line; }\n}\nextend int {\n    doubled(): int { return this * 2; }\n    static zero(): int { return 0; }\n}\ntrait Twice {\n    twice(): int;\n    thrice(): int { return twice() + 1; }\n}\nextend int with Twice {\n    twice(): int { return this * 2; }\n}\nenum Level {\n    Low,\n    High,\n    up(): Level { return next(); }\n    next(): Level { return Level.High; }\n    static first(): Level { return Level.Low; }\n}\nvar g: Color;\nstruct S {\n    var c: Color = Color.Green;\n    f(c: Color = Color.Blue): Color { return c; }\n}\nf(c: Color = Color.Red): Color { return c; }\nmain(): int {\n    Color c;\n    var d = Doc.Line;\n    var l = Level.first();\n    var v = Color.from_value(1);\n    var z = int.zero();\n    if (c == Color.Red) {\n        Level k;\n    }\n    return 0;\n}\n",
        "# expect: accepted\n[Link(\"m\", path = \"/usr/lib\")]\n[Link(name = \"cos\")]\nextern double my_cos(double x);\nmain(): int { return 0; }\n",
        "# expect: accepted\n_pep_arguments(): String[] { return Array<String>(); }\nmain(args: String[]): int { return args.count as int; }\n",
        "# expect: accepted\n_pep_arguments(): String[] { return Array<String>(); }\nmain(args: String[]) {}\n",
        # Named arguments: skipped defaults, reordering that evaluates first, constructors, a bare method, a former name, overloads, generics and a global.
        "# expect: main.pep:17:5: error: module-scope variable 'global' must be 'const'\nf(a: int, b: int = 2, c: int = 3): int { return a + b + c; }\ng(): int { return 1; }\nstruct P {\n    var x: int;\n    var y: int;\n    construct(x: int = 0, y: int = 0) { this.x = x; this.y = y; }\n    m(first: int, second: int = 1): int { return first + second; }\n    call(): int { return m(second = 2, first = 1); }\n    other(): P { return this; }\n}\n[Rename(\"old\", \"b\")]\nh(a: int, b: int) {}\nk(a: int, b: int) {}\nk(a: double, b: double) {}\nid<T>(value: T, times: int = 1, scale: T = value): T { return value; }\nvar global = f(c = 1, a = 2);\nmain(): int {\n    var n = f(1, c = 4);\n    n += f(c = g(), a = n);\n    n += f(c = -1, a = 5);\n    var p = P(y = 2);\n    var q = P(y = g(), x = -1);\n    var r = p.other().m(second = 1, first = n);\n    h(1, old = 2);\n    k(b = 1, a = 2);\n    var i = id(scale = 2, value = 3);\n    var j = id<long>(value = 1);\n    return n + p.call() + i;\n}\n",
        "# expect: accepted\nstruct Box<T> {\n    var v: T;\n    construct(value: T, extra: int = 0) { v = value; }\n}\nmain(): int {\n    var f = (a: int) => a;\n    var x = f(1);\n    var b = Box<int>(extra = 2, value = x);\n    return 0;\n}\n",
        # Function, tuple and weak reference types; negated literals;
        # overload sets of functions, methods and constructors, and
        # concrete overrides.
        "# expect: main.pep:6:18: error: field 'n' of shared struct 'Hub' must be 'const'\nstruct Node {\n    var next: __weak<Node>;\n}\n[Shared]\nstruct Hub { var n: int; }\ntrait Shape {\n    area(): int;\n}\nstruct Box<T> { var w: __weak<T>; }\nf(t: (int, bool), g: shared (int) => int, h: (int) => (int) => bool): (bool, double) {\n    var w: __weak<Hub>;\n    var s: __weak<Shape>;\n    var p: __ptr<__tuple<int, long>>;\n    var k = (a: int) => a + 1;\n    return (true, 1.0);\n}\nvar global: ((int, int)) => void;\nmain(): int { return 0; }\n",
        "# expect: main.pep:2:5: error: module-scope variable 'g' must be 'const'\nvar g = -5;\nf(x: int = -1): double { return -2.5 + -x; }\nstruct S {\n    var v: int;\n    construct() { v = -3; }\n    get(): long { return -9223372036854775807 - 1; }\n    destruct { var d = -0.0; }\n}\nmain(): int { return -(-1); }\n",
        "# expect: accepted\nscale(x: int): int { return x * 2; }\nscale(x: double): double { return x * 2.0; }\nscale<T>(x: T, times: int): T { return x; }\nhash<T>(value: T): ulong { return 0; }\nhash<T>(value: T, seed: ulong): ulong { return seed; }\nhash<int>(value: int): ulong { return 1; }\ndescribe<T>(value: T): int { return 0; }\ndescribe<String>(value: String): int { return 1; }\nstruct P {\n    var x: int;\n    construct() {}\n    construct(x: int) { this.x = x; }\n    get(): int { return x; }\n    get(i: int): int { return i; }\n    static make(): P { return P(); }\n}\ntrait Reader {\n    read(): int;\n    read(count: int): int;\n}\nextern int puts(__ptr<char> s);\nextern int puts(__ptr<char> s);\nmain(): int { return scale(1); }\n",
        # String literals in bodies, globals, `String` defaults, trait
        # defaults, generic methods and extensions.
        "# expect: main.pep:6:5: error: module-scope variable 'greeting' must be 'const'\nstruct String {\n    var data: __ptr<char>;\n    construct(raw: __ptr<char>, size: long, length: long) {}\n}\nvar greeting = \"héllo\";\nf(name: String = \"wörld\", raw: __ptr<char> = \"c\"): String { return \"a\" + \"\"; }\ntrait Named {\n    name(): String { return \"named\"; }\n}\nstruct Box<T> {\n    var v: T;\n    add<U>(u: U): String { return \"add\"; }\n    construct(label: String = \"box\") {}\n}\nextend int {\n    text(): String { return \"int\"; }\n}\nmain(): int {\n    var s = \"日本\";\n    return 0;\n}\n",
        # Generic uses: fields, methods, locals in nested blocks, an
        # extension of the base, globals, calls and a function value.
        "# expect: main.pep:4:17: error: 'Box' is specialized 65 levels deep, past the limit of 64; a generic whose instance asks for a larger instance of itself never ends\nstruct Box<T> {\n    var v: T;\n    var others: Box<Box<T>>;\n    var ints: Box<int>;\n    get(b: Box<long>): Box<short> { var local: Box<bool>; return Box<short>(); }\n    construct() { var c: Box<char>; }\n}\nstruct Pair<A, B> { var a: A; var b: B; }\nextend Box<T> {\n    wrap(): Box<T> { return Box<T>(); }\n    twice(): Box<double> { return Box<double>(); }\n}\nlarger<T>(a: T, b: T): T { return a; }\nmake<U>(u: U): Box<U> { var p: Pair<U, int>; return Box<U>(); }\nvar global: Pair<int, bool> = Pair<int, bool>();\nvar picked = larger<long>(1, 2);\nmain(): int {\n    var x = larger<int>(1, 2);\n    var f = larger<double>;\n    if (x > 0) {\n        Pair<String, int> p;\n    } else {\n        while (x < 0) {\n            Box<uint> q;\n        }\n    }\n    var m = make<byte>(1);\n    return x;\n}\n",
        # Operators on structs and enums: overloads, indexes, unary operators
        # and truth tests.
        "# expect: main.pep:25:5: error: module-scope variable 'origin' must be 'const'\nstruct V {\n    var x: int;\n    construct(x: int) { this.x = x; }\n    +(other: V): V { return V(x + other.x); }\n    +(other: int): V { return V(x + other); }\n    ==(other: V): bool { return x == other.x; }\n    -(): V { return V(0 - x); }\n    !!(): bool { return x != 0; }\n    +=(other: int) { x = x + other; }\n}\nstruct Grid {\n    var cells: __ptr<int>;\n    var values: V;\n    __index_get(i: int): int { return cells[i]; }\n    __index_set(i: int, value: int) { cells[i] = value; }\n    total(): int { return this[0] + values.x; }\n}\nenum Level {\n    Low,\n    High,\n    <(other: Level): bool { return false; }\n    __index_get(i: int): int { return i; }\n}\nvar origin = V(1) + V(2);\nmain(): int {\n    var a = V(1);\n    var b = a + V(2) + 3;\n    var c = -a;\n    a += 4;\n    if (a) { b = c; }\n    var t = !a;\n    var u = a and b;\n    var ne = a != b;\n    var g = Grid();\n    g[1] = 2;\n    g[1] += 3;\n    g[2] *= g[1];\n    var p: __ptr<int> = null;\n    var q = p[3];\n    var l = Level.Low < Level.High;\n    var w = Level.Low[2];\n    return g[0];\n}\n"
    ];
}

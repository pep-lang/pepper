# `for` loops: the hidden `next()` passes the loop's location to an
# iterator's `next(location: __ptr<char>)` overload when it declares one,
# so a check in it reports the loop, not the iterator (#319).

import [Path] from io;
import process;
import [TempFolder] from testing;
import [build_program, expect_contains, run, write_file] from tool_testing;
import toolchain;

# An iterator whose located `next` panics with the location it is given.
const _PROGRAM = "struct Count {\n    var left: int = 2;\n    var at: int = 0;\n\n    next(): bool {\n        return next(\"no location\");\n    }\n\n    next(location: __ptr<char>): bool {\n        assert(left > 1, \"stopped\", location);\n        left -= 1;\n        at += 1;\n        return true;\n    }\n\n    current(): int {\n        return at;\n    }\n}\n\nextend Count with Iterator<int>;\n\nmain(): int {\n    for (var n in Count()) {\n        print(n);\n    }\n    return 0;\n}\n";

[Test]
passes_the_loop_location_to_a_located_next() {
    var folder = TempFolder("for_loop_next_location");
    var source = folder.path.join("main.pep");
    write_file(source, _PROGRAM);
    var program = folder.path.join(Path("main" + toolchain.executable_suffix()));
    var error = build_program(source, program, folder.path.join("build"));
    expect_equal(error.value_or(""), "");
    var ran = run(process.Command(program.to_string()));
    expect_contains(ran.stderr, "main.pep:24:5: panic: stopped");
}

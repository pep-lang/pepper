# `pep-build --test` adds a test `main` to a test file that registers and
# runs its `[Test]` functions.

import compiler.driver;
import [Path] from io;
import compiler.link;

## The target of a test build: the host's, with `TEST` defined.
_test_build(): link.Target {
    var target = link.Target();
    target.build_options[link.TEST_BUILD_OPTION] = "1";
    return target;
}

[Test]
registers_each_test_with_its_line() {
    var text = driver.add_test_main(
        Path("t.pep"),
        "[Test]\nfirst() {}\n\n[Test]\n[ShouldPanic(\"out of \\\"range\\\"\")]\nsecond() {}\n",
        _test_build()
    );
    expect_true(text.contains("_pep_tests.add(\"first\", first, 2);"));
    expect_true(text.contains("_pep_tests.add_should_panic(\"second\", second, 6, \"out of \\\"range\\\"\");"));
    expect_true(text.contains("TestRunner(\"t.pep\")"));
    expect_true(text.contains("[TestMain]\nmain(args: String[]): int {\n"));
}

[Test]
leaves_a_file_that_does_not_parse() {
    expect_equal(driver.add_test_main(Path("t.pep"), "main( {", _test_build()), "main( {");
}

[Test]
leaves_out_a_test_that_target_drops() {
    var text = driver.add_test_main(
        Path("t.pep"),
        "[Target(BuildOption(NEVER_DEFINED))]\n[Test]\ndropped() {}\n\n[Test]\nkept() {}\n",
        _test_build()
    );
    expect_false(text.contains("dropped, "));
    expect_true(text.contains("_pep_tests.add(\"kept\", kept, 6);"));
}

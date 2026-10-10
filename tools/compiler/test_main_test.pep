# `pep-build --test` adds a test `main` to a test file that registers and
# runs its `[Test]` functions.

import compiler.driver;
import [Path] from io;

[Test]
registers_each_test_with_its_line() {
    var text = driver.add_test_main(
        Path("t.pep"), "[Test]\nfirst() {}\n\n[Test]\n[ShouldPanic(\"out of \\\"range\\\"\")]\nsecond() {}\n"
    );
    expect_true(text.contains("_pep_tests.add(\"first\", first, 2);"));
    expect_true(text.contains("_pep_tests.add_should_panic(\"second\", second, 6, \"out of \\\"range\\\"\");"));
    expect_true(text.contains("TestRunner(\"t.pep\")"));
    expect_true(text.contains("[TestMain]\nmain(args: String[]): int {\n"));
}

[Test]
leaves_a_file_that_does_not_parse() {
    expect_equal(driver.add_test_main(Path("t.pep"), "main( {"), "main( {");
}

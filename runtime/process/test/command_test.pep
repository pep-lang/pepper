# process: a Command whose program cannot start reports why, both when it
# runs as a child and when it would replace this process. process_tests.rs
# keeps the checks that need a whole program: its arguments, its exit code,
# and children that are copies of it.

import io;
import process;

[Test]
run_reports_a_missing_program() {
    var missing = process.Command("no-such-program-for-pepper").run();
    expect_true(missing.is_err());
    expect_true(missing.error().is_not_found());
}

[Test]
exec_returns_why_the_program_cannot_start() {
    var before = process.working_directory().value();
    var missing = process.Command("pep-no-such-program").working_directory(io.Path("..")).exec();
    expect_true(missing.is_not_found());
    # A failed exec leaves the working directory as it was.
    expect_equal(process.working_directory().value(), before);
    var piped = process.Command("pep-no-such-program").stdout(process.Stream.Pipe).exec();
    expect_true(piped.is_invalid_input());
}

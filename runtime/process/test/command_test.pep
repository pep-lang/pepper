# process: a Command whose program cannot start reports why, both when it
# runs as a child and when it would replace this process. The checks that
# need a whole program (its arguments, its exit code, and children that are
# copies of it) are in tools/compiler/programs_test.pep.

import io;
import os;
import process;

[Test]
run_reports_a_missing_program() {
    # Android's posix_spawnp reports no failed exec (#251).
    [Target(OS(Android))]
    {
        return;
    }
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

# A child started in another folder through fork and exec, the path for a
# glibc without posix_spawn_file_actions_addchdir_np (before 2.29), which
# `PEPPER_PROCESS_FORK_SPAWN` forces: the test sets it and checks the
# child's folder and the errors it reports. Only Linux has the path; a
# process test on another thread meanwhile takes it too, which is as valid.
[Test]
starts_a_child_in_a_folder_by_fork_and_exec() {
    if (os.system_name() != "linux") {
        return;
    }
    os.set_environment("PEPPER_PROCESS_FORK_SPAWN", "1");
    var root = process.Command("pwd").working_directory(io.Path("/")).run();
    expect_true(root.is_ok());
    expect_equal(root.value().stdout, "/\n");
    var missing = process.Command("pep-no-such-program").working_directory(io.Path("/")).run();
    expect_true(missing.is_err());
    expect_true(missing.error().is_not_found());
    var nowhere = process.Command("pwd").working_directory(io.Path("/no-such-folder-for-pepper")).run();
    expect_true(nowhere.is_err());
    expect_true(nowhere.error().is_not_found());
    os.remove_environment("PEPPER_PROCESS_FORK_SPAWN");
}

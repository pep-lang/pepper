# process.fork: the copy goes on from the call, with the parent's memory,
# and the parent waits for it like any child.

import process;

[Test]
fork_starts_a_copy_the_parent_waits_for() {
    var value = 41;
    var forked = process.fork();
    if (forked.is_err()) {
        # Windows and WASI start processes only from a program.
        return;
    }
    if (!forked.value().is_value()) {
        # The copy has the parent's memory as it was at the fork.
        process.exit(value + 1);
    }
    var status = forked.value().value().wait();
    expect_true(status.is_ok());
    expect_equal(status.value().code().value(), 42);
}

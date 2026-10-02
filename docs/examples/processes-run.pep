import io;
import process;

# Runs a copy of this program as a child, so the example needs no other
# program on any system: the child's first argument says what to do.
main(args: String[]): int {
    if (args.count > 1) {
        io.File.stdout().write_all("hello from " + args[1]);
        io.File.stderr().write_all("a warning");
        return 3;
    }

    var self = process.executable_path().value().to_string();
    var output = process.Command(self).argument("the child").run().value();
    assert(output.stdout == "hello from the child", "standard output is collected");
    assert(output.stderr == "a warning", "and so is standard error");
    assert(!output.status.success(), "the child failed");
    assert(output.status.code().value() == 3, "with exit code 3");

    # A program that is not found fails to start.
    var missing = process.Command("no-such-program").run();
    assert(missing.is_err() && missing.error().is_not_found(), "not found");
    return 0;
}

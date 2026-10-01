import io;
import process;

extern char* getenv(char* name);

main(args: String[]): int {
    if (args.count() > 1) {
        var name = "GREETING";
        var value = getenv(name.c_str());
        io.File.stdout().write_all(value == __null ? "unset" : String(value));
        return 0;
    }

    var self = process.executable_path().value().to_string();
    var greeted = process.Command(self).argument("child").environment("GREETING", "hello").run().value();
    assert(greeted.stdout == "hello", "the child sees the variable");

    var cleared = process.Command(self).argument("child").clear_environment().run().value();
    assert(cleared.stdout == "unset", "an empty environment");

    # The child starts in another directory; the parent's stays as it was.
    var before = process.working_directory().value();
    var elsewhere = process.Command(self).argument("child").working_directory(io.Directory.temp()).run();
    assert(elsewhere.is_ok(), "started in the temporary directory");
    assert(process.working_directory().value() == before, "unchanged");
    return 0;
}

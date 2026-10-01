import io;
import process;

main(args: String[]): int {
    if (args.count() > 1) {
        # The child: read standard input to the end, and write it back in
        # capitals.
        var text = io.File.stdin().read_string().value();
        io.File.stdout().write_all(text.upper());
        return 0;
    }

    var self = process.executable_path().value().to_string();
    var child = process.Command(self)
        .argument("upper")
        .stdin(process.Stream.Pipe)
        .stdout(process.Stream.Pipe)
        .spawn()
        .value();
    child.stdin().write_all("pear and apple");
    child.stdin().close();  # the child reads to the end, so end it
    var shouted = child.stdout().read_string().value();
    var status = child.wait().value();
    assert(shouted == "PEAR AND APPLE", "the child's output");
    assert(status.success(), "the child succeeded");
    return 0;
}

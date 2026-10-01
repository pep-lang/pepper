import [File, Directory, Path] from io;

main(): int {
    var dir = Directory.temp().join("pepper-iteration-streams-example");
    Directory.remove_all(dir);
    assert(Directory.create_all(dir).is_ok(), "created the folder");
    assert(File.write_text(dir.join("notes.txt"), "first\nsecond\r\nthird").is_ok(), "wrote notes");
    assert(File.write_text(dir.join("todo.txt"), "").is_ok(), "wrote todo");

    # A Directory yields its entries one at a time, each an IoResult<DirEntry>.
    var names = 0;
    for (var entry in Directory.open(dir).value()) {
        if (entry.is_err()) {
            print(entry.error().message);
            break;
        }
        assert(entry.value().is_file, "both entries are files");
        names += 1;
    }
    assert(names == 2, "two entries");

    # A File's lines() yields each line, without its line ending.
    var file = File.open(dir.join("notes.txt")).value();
    var lines = Array<String>();
    for (var line in file.lines()) {
        lines.append(line.value());
    }
    assert(lines.count() == 3 && lines[1] == "second", "three lines, \\r\\n removed");

    # Adapters work on streams too: number the lines.
    var again = File.open(dir.join("notes.txt")).value();
    var last = "";
    for (var (i, line) in again.lines().enumerate()) {
        last = $"{i}: {line.value()}";
    }
    assert(last == "2: third", "the last line, numbered");

    assert(Directory.remove_all(dir).is_ok(), "cleaned up");
    return 0;
}

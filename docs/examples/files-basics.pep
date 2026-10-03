# Write, read, list and remove files with io.
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-files-basics-example");
    io.Directory.remove_all(folder);
    io.Directory.create_all(folder.join("notes")).value();

    # Whole files at once.
    var path = folder.join("notes").join("today.txt");
    io.File.write_text(path, "buy milk\n").value();
    assert(io.File.read_to_string(path).value() == "buy milk\n", "read back");

    # An open File, with OpenOptions for anything but read or replace.
    var log = io.OpenOptions().append(true).create(true).open(folder.join("log.txt")).value();
    log.write_all("started\n").value();
    log.close().value();

    # Metadata, and a directory's entries.
    var m = path.metadata().value();
    assert(m.is_file && m.size == 9, "a 9-byte file");
    var names = Array<String>();
    for (var entry in io.Directory.open(folder).value()) {
        names.append(entry.value().name);
    }
    assert(names.count == 2, "log.txt and notes");

    io.Directory.remove_all(folder).value();
    return 0;
}

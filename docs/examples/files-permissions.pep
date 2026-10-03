# Permission bits and timestamps: make a script executable, protect a file,
# and copy a modification time.
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-files-permissions-example");
    io.Directory.remove_all(folder);
    # 448 is octal 700: only the owner may list or enter it (POSIX only).
    io.Directory.create(folder, mode = 448).value();

    # Created with mode 493 (octal 755, rwxr-xr-x) less the umask, so the
    # script is never readable by others without being executable.
    var script = folder.join("run.sh");
    var file = io.OpenOptions().write(true).create_new(true).mode(493).open(script).value();
    file.write_all("#!/bin/sh\necho hello\n").value();
    file.close().value();

    # The portable way: add an execute bit where there is a read bit.
    var notes = folder.join("notes.sh");
    io.File.write_text(notes, "#!/bin/sh\n").value();
    notes.set_executable(true).value();
    [Target(OS(Linux) || OS(Mac))] {
        assert((notes.metadata().value().permissions & 64) != 0, "the owner may run it");
    }

    # Read-only: no write bits on POSIX, FILE_ATTRIBUTE_READONLY on Windows.
    [Target(!OS(Wasi))] {
        notes.set_read_only(true).value();
        assert(notes.metadata().value().read_only, "read-only");
        notes.set_read_only(false).value();
    }

    # Give the script the same modification time as the notes.
    var modified = notes.metadata().value().modified;
    script.set_modified(modified).value();
    assert(script.metadata().value().modified == modified, "same time");

    io.Directory.remove_all(folder).value();
    return 0;
}

# Symbolic links: make one to a file and one to a directory, and read them.
import io;

main(): int {
    var folder = io.Directory.temp().join("pepper-files-symlinks-example");
    io.Directory.remove_all(folder);
    io.Directory.create_all(folder.join("releases").join("1.2")).value();
    io.File.write_text(folder.join("app-1.2.conf"), "port = 80\n").value();

    # Windows needs Developer Mode or an administrator to make symlinks.
    [Target(!OS(Windows))] {
        # A relative target is resolved from the folder holding the link.
        var config = folder.join("app.conf");
        io.File.symlink(io.Path("app-1.2.conf"), config).value();
        assert(io.File.read_to_string(config).value() == "port = 80\n", "read through the link");
        assert(config.read_link().value() == io.Path("app-1.2.conf"), "the stored target");
        assert(config.symlink_metadata().value().is_symlink, "the link itself");

        var current = folder.join("current");
        io.Directory.symlink(io.Path("releases").join("1.2"), current).value();
        assert(current.is_directory(), "a directory through the link");
    }

    # remove_all removes links, never what they point to.
    io.Directory.remove_all(folder).value();
    return 0;
}

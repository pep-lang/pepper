import [File, Directory, Path, IoResult, IoError] from io;

# IoResult<T> is Result<T, IoError>: the same methods, a richer error.
read_setting(Path path): String {
    var text = File.read_to_string(path);
    if (text.is_err()) {
        if (text.error().is_not_found()) {
            return "default";
        }
        return "error: " + text.error().message;
    }
    return text.value();
}

main(): int {
    var dir = Directory.temp().join("pepper-results-io-example");
    var created = Directory.create_all(dir);
    assert(created.is_ok(), "created the folder");

    var path = dir.join("setting.txt");
    assert(read_setting(path) == "default", "a missing file gives the default");

    IoResult<void> written = File.write_text(path, "blue");
    assert(written.is_ok(), "wrote the file");
    assert(read_setting(path) == "blue", "the file's contents");

    assert(Directory.remove_all(dir).is_ok(), "cleaned up");
    return 0;
}

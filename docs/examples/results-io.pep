import [File, Directory, Path, IoResult, IoError, ErrorKind] from io;

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

# kind() sorts the platform's code into an ErrorKind, for a match.
describe(error: IoError): String {
    return match (error.kind()) {
        NotFound => "missing",
        PermissionDenied => "not allowed",
        else => error.message,
    };
}

main(): int {
    var dir = Directory.temp().join("pepper-results-io-example");
    var created = Directory.create_all(dir);
    assert(created.is_ok(), "created the folder");

    var path = dir.join("setting.txt");
    assert(read_setting(path) == "default", "a missing file gives the default");
    var missing = File.open(path);
    assert(missing.is_err() && missing.error().kind() == ErrorKind.NotFound, "the kind of the error");
    assert(describe(missing.error()) == "missing", "a match on the kind");

    IoResult<void> written = File.write_text(path, "blue");
    assert(written.is_ok(), "wrote the file");
    assert(read_setting(path) == "blue", "the file's contents");

    assert(Directory.remove_all(dir).is_ok(), "cleaned up");
    return 0;
}

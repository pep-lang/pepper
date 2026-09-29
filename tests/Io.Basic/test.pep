# The io module from the runtime search path: a Path computation and a file
# round trip in the temp directory.
import io;
import [File, Path] from io;

main(): int {
    var p = io.Path("dir/name.txt");
    if (!(p.extension() == "txt")) { return 1; }
    if (!(p.parent().Value == "dir")) { return 2; }

    var f = io.Directory.temp().join_str("pepper_corpus_io_basic.txt");
    if (File.write_text(f, "corpus").is_err()) { return 3; }
    var back = File.read_to_string(f);
    if (back.is_err()) { return 4; }
    if (!(back.Value == "corpus")) { return 5; }
    if (File.remove(f).is_err()) { return 6; }
    if (f.exists()) { return 7; }
    return 0;
}

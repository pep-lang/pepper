# Hand an open File to another thread with into_transfer and adopt.
import async;
import io;

main(): int {
    var path = io.Directory.temp().join("pepper-files-transfer-example.txt");
    io.File.write_text(path, "read on another thread").value();
    var file = io.File.open(path).value();
    # A File is not thread-safe; its transfer token is.
    var transfer = file.into_transfer();
    var size = async.Atomic<ulong>(0);
    var reader = async.Thread.spawn(() => {
        var mine = io.File.adopt(transfer).value();
        size.store(mine.read_all().value().count);
    });
    reader.join();
    assert(size.load() == 22, "the other thread read the file");
    assert(!file.is_open(), "the File it came from is closed");
    io.File.remove(path);
    return 0;
}

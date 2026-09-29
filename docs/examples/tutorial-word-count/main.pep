import [File, Directory, Path] from io;
import "counter";

# Reads the file at `path` and counts its words.
count_file(path: Path): Result<WordCounter> {
    var text = File.read_to_string(path);
    if text.is_err() {
        return Result<WordCounter>.err(Error(text.Error.Message));
    }
    var counter = WordCounter();
    counter.add_text(text.Value);
    return Result<WordCounter>.ok(counter);
}

main(): int {
    # Write a small file to read back.
    var dir = Directory.temp().join_str("pepper-word-count");
    Directory.create_all(dir);
    var path = dir.join_str("poem.txt");
    File.write_text(path, "the cat sat on the mat and the dog sat too");

    var result = count_file(path);
    assert(result.is_ok(), "the file we just wrote can be read");
    var counter = result.value();
    for (var word in counter.order) {
        print(word);
        print(counter.count(word));
    }
    assert(counter.total == 11, "eleven words");
    assert(counter.count("the") == 3, "'the' appears three times");
    assert(counter.count("sat") == 2, "'sat' appears twice");
    assert(counter.count("bird") == 0, "'bird' does not appear");

    var missing = count_file(dir.join_str("missing.txt"));
    assert(missing.is_err(), "a missing file is an error, not a crash");
    print(missing.Error.Message);

    Directory.remove_all(dir);
    return 0;
}

# io.Reader and io.Writer on types of a program's own: lines() and chunks()
# from read, print and print_line from write and write_all, as trait values
# and generic constraints; a File as both; and the standard streams as Files.

import io;

# Gets print and print_line from write and write_all.
struct Collector {
    var bytes: u8[];

    construct() {
        bytes = Array<u8>();
    }

    write(data: u8[]): io.IoResult<ulong> {
        write_all(data);
        return io.IoResult<ulong>.ok(data.count);
    }

    write_all(data: u8[]): io.IoResult<void> {
        for (var b in data) {
            bytes.append(b);
        }
        return io.IoResult<void>.ok();
    }
}

extend Collector with io.Writer;

# Gets lines() and chunks() from read: it hands out its text two bytes at a
# time, so lines and chunks span reads.
struct Pieces {
    var data: u8[];
    var position: ulong;

    construct(text: String) {
        data = text.bytes();
    }

    read(buffer: u8[], max: ulong): io.IoResult<ulong> {
        ulong count = 0;
        while (count < max && count < 2 && position < data.count) {
            buffer.append(data[position]);
            position += 1;
            count += 1;
        }
        return io.IoResult<ulong>.ok(count);
    }
}

extend Pieces with io.Reader;

# Any Writer, through a constraint.
greet<T: io.Writer>(out: T) {
    out.print_line("hello");
}

# Any Reader, as a trait value.
joined_lines(source: io.Reader): String {
    var text = "";
    for (var line in source.lines()) {
        text = text + line.value() + "|";
    }
    return text;
}

# Any Reader, through a constraint.
total_size<R: io.Reader>(source: R, size: ulong): ulong {
    ulong count = 0;
    for (var chunk in source.chunks(size)) {
        expect_true(chunk.value().count <= size);
        count += chunk.value().count;
    }
    return count;
}

[Test]
print_trait_writes_text() {
    var collector = Collector();
    expect_true(collector.print("n = ").is_ok());
    expect_true(collector.print_line(3).is_ok());
    collector.print_line((1.5, true));
    greet(collector);
    expect_equal(String._from_bytes(collector.bytes), "n = 3\n(1.5, true)\nhello\n");
}

[Test]
reader_trait_reads_lines_and_chunks() {
    expect_equal(joined_lines(Pieces("one\r\ntwo\n\nlast")), "one|two||last|");
    expect_equal(total_size(Pieces("abcdefg"), 3), 7);
}

[Test]
stdout_is_a_file() {
    var out = io.File.stdout();
    expect_true(out.is_open());
    expect_true(out.write_all("io-stdout-ok\n").is_ok());
    # Closing a standard stream only forgets it: fd 1 stays usable.
    expect_true(out.close().is_ok());
    expect_false(out.is_open());
    expect_true(io.File.stdout().write_all("still open\n").is_ok());
    expect_true(io.File.stderr().is_open());
    expect_true(io.File.stdin().is_open());
}

[Test]
a_file_is_a_reader() {
    var folder = TempFolder("a_file_is_a_reader");
    var path = folder.path.join("reader.txt");
    expect_true(io.File.write_text(path, "alpha\nbeta\n").is_ok());
    expect_equal(joined_lines(io.File.open(path).value()), "alpha|beta|");
    expect_equal(total_size(io.File.open(path).value(), 4), 11);
    var chunks = 0;
    for (var chunk in io.File.open(path).value().chunks(100)) {
        chunks += 1;
    }
    expect_equal(chunks, 1);  # one read takes the whole small file
}

[Test]
a_file_is_a_writer() {
    var folder = TempFolder("a_file_is_a_writer");
    var path = folder.path.join("writer.txt");
    var file = io.File.create(path).value();
    greet(file);
    file.print(42);
    file.close();
    expect_equal(io.File.read_to_string(path).value(), "hello\n42");
}

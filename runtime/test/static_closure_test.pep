# Closures written in a `static` block's emitted statements are lifted like
# any other closure (#673), and capture the runtime locals the block declares.

struct Reader {
    var check: (String) => bool = __null;
}

struct Fields {
    var name = "n";
    var count = 2;
}

reads_nonempty<T>(text: String): bool {
    return !text.is_empty;
}

reader_of<T>(): Reader {
    var reader = Reader();
    static (reader) {
        if (!reflect.is_same<T, String>()) {
            reader.check = (text: String) => reads_nonempty<T>(text);
        }
    }
    return reader;
}

[Test]
lifts_a_closure_in_a_static_block() {
    var reader = reader_of<int>();
    expect_true(reader.check("1"));
    expect_false(reader.check(""));
    expect_true(reader_of<String>().check === __null);
}

[Test]
captures_the_locals_a_static_block_declares() {
    var fields = Fields();
    var calls = Array<() => String>();
    static (fields, calls) {
        for (var field in reflect.fields<Fields>()) {
            var text = $"{field.name}={field.get(fields)}";
            calls.append(() => text);
        }
    }
    expect_equal(calls.count, 2);
    expect_equal(calls[0](), "name=n");
    expect_equal(calls[1](), "count=2");
}

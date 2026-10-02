# A struct with a destructor is not trivially copyable, so it implements
# `Copyable<T>` to say how `copy` copies it.
struct Buffer {
    __ptr<u8> data;
    ulong size;
    String label;

    construct(size: ulong) {
        data = _pep_malloc(size);
        this.size = size;
        label = "buffer";
    }

    destruct {
        _pep_free(data);
    }

    copy(): Buffer {
        var made = Buffer(size);
        var i: ulong = 0;
        while (i < size) {
            made.data[i] = data[i];
            i = i + 1;
        }
        # The free function `copy`: it continues the running copy.
        made.label = copy(label);
        return made;
    }
}

extend Buffer with Copyable<Buffer>;

struct Message {
    Buffer body;
    Buffer again;
}

main(): int {
    var message = Message();
    message.body = Buffer(4);
    message.body.data[0] = 9;
    message.again = message.body;

    var copied = copy(message);
    copied.body.data[0] = 1;
    copied.body.label.append(" (copy)");
    assert(message.body.data[0] == 9, "the original buffer is unchanged");
    assert(message.body.label == "buffer", "the original label is unchanged");
    # The buffer appears twice, so its copy is one object.
    assert(copied.again === copied.body, "one copy of the shared buffer");
    return 0;
}

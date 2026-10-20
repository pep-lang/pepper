# A generic method may return what its generic overload returns, called
# bare: in `read<Item>()`, `read<T>(Mode.Skip)` calls the other `read`,
# whose specialization does not exist yet, and not the free function
# `read` of the same name (#32, where POSIX's `read` took the call). On
# Linux and macOS the runtime's `read` also makes linking rename this
# file's, which must not rename the call.

enum Mode {
    Keep,
    Skip,
}

read(handle: int): int {
    return handle;
}

struct Item {
    var name: String = "item";
}

struct Reader {
    var skipped: int = 0;

    read<T>(): Result<T?, String> {
        return read<T>(Mode.Skip);
    }

    read<T>(mode: Mode): Result<T?, String> {
        if (mode is Skip) {
            skipped += 1;
        }
        return Result<T?, String>.ok(Optional<T>.Value(T()));
    }
}

main(): int {
    var reader = Reader();
    var item = reader.read<Item>();
    if (item.value().value().name != "item" or reader.skipped != 1) {
        return 1;
    }
    return read(0);
}

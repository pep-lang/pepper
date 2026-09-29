# Module-scope variables are `const` and thread-safe: a number, an
# Atomic<T>, or a [Shared] struct.
[Shared]
struct Label {
    const Length: ulong;
    construct(String text) { Length = text.length(); }
}

const limit = 7;
const counter = Atomic<int>(7);
const name = Label("pepper");

main(): int {
    # Read a global.
    if (limit != 7 || counter.load() != 7) { return -1; }

    # Change state through a global, then read it back.
    counter.fetch_add(3);
    if (counter.load() != 10) { return -2; }

    # Struct globals built by a constructor keep their value.
    if (name.Length != 6) { return -3; }

    return 0;
}

import async;

# Declaring variables: inferred, explicitly typed, constant, and module-level.

# Module-level variables (globals) live for the whole program. Any thread
# can reach them, so they are const and of a thread-safe type: a number, or
# an Atomic for state that changes.
const MAX_REQUESTS = 10;
const request_count = async.Atomic<int>(0);
const total_bytes = async.Atomic<long>(0);

record(bytes: int) {
    request_count.fetch_add(1);
    total_bytes.fetch_add(bytes);
}

main(): int {
    # 'var' infers the type from the initializer.
    var answer = 42;          # int: integer literals are int
    var ratio = 0.25;         # double: floating-point literals are double
    var ready = true;         # bool
    var name = "Pepper";      # String

    # Write the type first, C style...
    int width = 80;
    float scale = 1.5;

    # ...or after the name with a colon.
    var height: int = 24;
    var offset: long = 5000000000;

    # A variable declared without a value starts at zero.
    var hits: int;
    assert(hits == 0, "numbers start at zero");

    # 'const' declares a name that should not be reassigned.
    const LIMIT = 3;

    record(100);
    record(250);
    assert(request_count.load() == 2, "two requests recorded");
    assert(total_bytes.load() == 350, "350 bytes in total");
    assert(request_count.load() < MAX_REQUESTS, "globals are visible in every function");

    assert(answer + width + height == 146, "sum of ints");
    assert(ratio * 4 == 1.0 && scale == 1.5, "floating point");
    assert(ready && name == "Pepper", "bool and String");
    assert(offset > 4000000000 && LIMIT == 3, "long and const");
    return 0;
}

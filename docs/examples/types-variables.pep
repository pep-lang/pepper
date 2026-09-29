# Declaring variables: inferred, explicitly typed, constant, and module-level.

# Module-level variables (globals) live for the whole program.
var request_count = 0;
long total_bytes = 0;
var greeting: String = "hello";

record(bytes: int) {
    request_count += 1;
    total_bytes += bytes;
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
    assert(request_count == 2, "two requests recorded");
    assert(total_bytes == 350, "350 bytes in total");
    assert(greeting == "hello", "globals are visible in every function");

    assert(answer + width + height == 146, "sum of ints");
    assert(ratio * 4 == 1.0 && scale == 1.5, "floating point");
    assert(ready && name == "Pepper", "bool and String");
    assert(offset > 4000000000 && LIMIT == 3, "long and const");
    return 0;
}

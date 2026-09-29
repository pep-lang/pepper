# Declaring and calling functions.

# Parameters are written 'name: Type'; the return type follows the ')'.
area(width: int, height: int): int {
    return width * height;
}

# The C-style form puts the return type first and the type before each name.
int perimeter(int width, int height) {
    return 2 * (width + height);
}

# A function that returns nothing leaves out the return type
# (or writes ': void', or 'void' in front).
var log_count = 0;
log(message: String) {
    log_count += 1;
    print("log: " + message);
}

# Functions can call themselves, and can be declared in any order.
factorial(n: int): long {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
}

main(): int {
    assert(area(3, 4) == 12, "3 x 4");
    assert(perimeter(3, 4) == 14, "2 x (3 + 4)");
    assert(factorial(20) == 2432902008176640000, "20!");
    assert(is_even(10), "declared after main, still callable");

    log("starting");
    log("done");
    assert(log_count == 2, "logged twice");
    return 0;
}

is_even(n: int): bool {
    return n % 2 == 0;
}

# Default parameter values.

# Parameters with defaults come last; a call may leave them out.
greet(name: String, greeting: String = "Hello", punctuation: String = "!"): String {
    return greeting + ", " + name + punctuation;
}

# Defaults work with the C-style form too.
int clamp(int value, int low = 0, int high = 100) {
    if (value < low) { return low; }
    if (value > high) { return high; }
    return value;
}

# A default can be any expression: an interpolated string, a literal.
labels(prefix: String = $"v{2}" + ".", sizes: int[] = [1, 2]): String {
    return $"{prefix}{sizes.count}";
}

main(): int {
    assert(labels() == "v2.2", "computed defaults");
    assert(greet("Ada") == "Hello, Ada!", "both defaults");
    assert(greet("Ada", "Hi") == "Hi, Ada!", "one default");
    assert(greet("Ada", "Hi", ".") == "Hi, Ada.", "no defaults");

    assert(clamp(150) == 100, "clamped to the default high");
    assert(clamp(-5) == 0, "clamped to the default low");
    assert(clamp(-5, -10) == -5, "low given");
    return 0;
}

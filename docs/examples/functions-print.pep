# print writes a value's text and a line break.
main(): int {
    print("Hello, world!");
    print(42);                            # any value with a text form
    print((1.5, true));                   # (1.5, true)
    var name = "Pepper";
    var count = 42;
    print($"{name} has {count} items");   # interpolate other values
    print("{0} + {1} = {2}", 3, 4, 3 + 4); # or format them: "3 + 4 = 7"
    print("{braces} alone print as written");
    return 0;
}

# Output:
# Hello, world!
# 42
# (1.5, true)
# Pepper has 42 items
# 3 + 4 = 7
# {braces} alone print as written

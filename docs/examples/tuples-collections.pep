main(): int {
    # A tuple can be a key: here, a grid position.
    var grid = HashMap<(int, int), String>();
    grid[(0, 0)] = "start";
    grid[(2, 3)] = "goal";
    assert(grid[(2, 3)] == "goal", "looked up by value");

    # Tuples compare element by element.
    assert((1, "a") == (1, "a"), "equal");
    assert((1, "a") != (1, "b"), "different");

    # A HashMap yields (key, value) tuples; destructure them in the loop.
    var ages = HashMap<String, int>();
    ages["ada"] = 36;
    ages["grace"] = 85;
    var total = 0;
    for (var (name, age) in ages) {
        total += age;
    }
    assert(total == 121, "every entry");

    # An array of tuples.
    var pairs = Array<(String, int)>();
    pairs.append(("x", 1));
    pairs.append(("y", 2));
    for (var (name, count) in pairs) {
        print($"{name}: {count}");
    }
    return 0;
}

# Output:
# x: 1
# y: 2

import os;

main(): int {
    # An optional: none when the variable is not set.
    var runtime = os.environment("PEPPER_RUNTIME").value_or("runtime");
    assert(!runtime.is_empty, "a fallback when unset");
    assert(os.environment("PEPPER_SURELY_NOT_SET").is_empty(), "unset");

    var count = 0;
    for (var (name, value) in os.environment_variables()) {
        if (name.starts_with("PEPPER_")) {
            print($"{name}={value}");
        }
        count = count + 1;
    }
    assert(count > 0, "a process has an environment");
    return 0;
}

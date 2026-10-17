import os;

main(): int {
    var name = "PEPPER_EXAMPLE_GREETING";
    os.set_environment(name, "hello");
    assert(os.environment(name).value() == "hello", "set");

    os.set_environment(name, "");
    assert(os.environment(name).value() == "", "set to nothing");

    os.remove_environment(name);
    assert(os.environment(name).is_empty(), "removed");
    return 0;
}

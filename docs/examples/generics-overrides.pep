# The generic version handles every type...
describe<T>(value: T): String {
    return "something";
}

# ...and these definitions replace it for two specific types.
describe<int>(value: int): String {
    return "an int";
}

describe<String>(value: String): String {
    return "a String";
}

main(): int {
    assert(describe<float>(1.5) == "something", "the generic version");
    assert(describe<int>(7) == "an int", "the int override");
    assert(describe<String>("hi") == "a String", "the String override");

    # The standard library's hash<String> is such an override: it hashes
    # a String by its content instead of by identity.
    assert(hash<String>("pepper") == hash<String>("pepper"), "content hash");
    return 0;
}

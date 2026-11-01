# Attributes, each on its own line above what it applies to.

[Target(OS(Windows))]
system_name(): String {
    return "Windows";
}

[Target(!OS(Windows))]
system_name(): String {
    return "not Windows";
}

[Deprecated("use 'system_name' instead", "system_name")]
os_name(): String {
    return system_name();
}

# A parameter's attributes stay on its line, in front of it.
keep([Move] names: Array<String>): ulong {
    return names.count;
}

main(): int {
    print(system_name().size > 0);
    var names = ["a", "b"];
    print(keep(move(names)));
    return 0;
}

# Output:
# true
# 2

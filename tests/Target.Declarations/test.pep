# [Target(...)] on type aliases and module-scope variables: each pair declares
# one name per platform, and only the matching half may survive. Without
# filtering, the alias pair resolved "last definition wins" and the variable
# pair declared a duplicate global.

[Target(OS(Windows))] type Handle = long;
[Target(!OS(Windows))] type Handle = int;

[Target(OS(Windows))] var platform_code = 1;
[Target(!OS(Windows))] var platform_code = 2;

main(): int {
    Handle h = 0;
    var expected = -1;
    [Target(OS(Windows))] {
        expected = 1;
        # Handle is 8 bytes only where the Windows alias survived.
        if (sizeof<Handle>() != 8) { return 10; }
    }
    [Target(!OS(Windows))] {
        expected = 2;
        if (sizeof<Handle>() != 4) { return 11; }
    }
    if (platform_code != expected) { return 12; }
    return h;
}

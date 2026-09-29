# One name, a different declaration per platform.

# Type aliases: a Windows HANDLE is a pointer, a POSIX descriptor an int.
[Target(OS(Windows))] type Handle = __ptr<void>;
[Target(!OS(Windows))] type Handle = int;

# Module-scope variables.
[Target(OS(Windows))] var executable_suffix = ".exe";
[Target(!OS(Windows))] var executable_suffix = "";

# Functions.
[Target(OS(Windows))]
platform_name(): String { return "Windows"; }

[Target(OS(Mac))]
platform_name(): String { return "macOS"; }

[Target(OS(Linux))]
platform_name(): String { return "Linux"; }

# Structs, and methods inside them.
[Target(Arch(x64))]
struct Cpu {
    var name: String = "x64";
}

[Target(Arch(aarch64))]
struct Cpu {
    var name: String = "aarch64";
}

struct Word {
    [Target(Arch(x64) || Arch(aarch64))]
    bits(): int { return 64; }
}

main(): int {
    var name = platform_name();
    print(name);
    print(Cpu().name);
    assert(Word().bits() == 64, "every supported target is 64-bit");

    [Target(OS(Windows))] {
        assert(sizeof<Handle>() == 8, "a HANDLE is a pointer");
        assert(name == "Windows", "the Windows function was kept");
    }
    [Target(!OS(Windows))] {
        assert(sizeof<Handle>() == 4, "a descriptor is an int");
        assert(executable_suffix.size() == 0, "the POSIX variable was kept");
    }
    return 0;
}

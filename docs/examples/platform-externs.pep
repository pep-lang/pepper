# A portable wrapper over a C function that has a different name on
# each platform. kernel32 is linked by default on Windows, and getpid is
# in the C library everywhere else.

[Target(OS(Windows))] extern uint GetCurrentProcessId();
[Target(!OS(Windows))] extern int getpid();

process_id(): long {
    [Target(OS(Windows))] {
        return GetCurrentProcessId() as long;
    }
    [Target(!OS(Windows))] {
        return getpid() as long;
    }
}

main(): int {
    var id = process_id();
    print($"process {id}");
    assert(id > 0, "a running process has a positive id");
    return 0;
}

# A constrained generic used only in code a `[Target]` removes on this
# platform: that code is not compiled here, so its uses are not checked
# against the platform's conformances either.

trait Shape {
    area(): int;
}

struct Gallery<T: Shape> {
    var count: int;
}

[Target(OS(Linux))]
struct Poller {
    area(): int { return 1; }
}

[Target(OS(Linux))]
extend Poller with Shape {}

[Target(!OS(Linux))]
struct Port {
    area(): int { return 2; }
}

[Target(!OS(Linux))]
extend Port with Shape {}

[Target(OS(Linux))]
native(): int { return Gallery<Poller>().count; }

[Target(!OS(Linux))]
native(): int { return Gallery<Port>().count; }

main(): int {
    [Target(OS(Linux))]
    {
        var poller = Gallery<Poller>();
    }
    [Target(!OS(Linux))]
    {
        var port = Gallery<Port>();
    }
    return native();
}

# Type aliases: non-generic, generic with defaults, in locals/globals/fields.
type I = int;
type R<T, E=Error> = Result<T, E>;
type Pair = Result<int, Error>;

struct Box {
    var v: I;
    new(this.v = 0) {}
}

var global_alias_value: I = 3;

main(): int {
    # Non-generic alias in a local.
    var a: I = 42;
    if (a != 42) { return 1; }

    # Generic alias with both arguments.
    var b: R<int, Error> = Result<int>.ok(7);
    if (!b.is_ok() || b.unwrap() != 7) { return 2; }

    # Omitted second argument uses the parameter default (Error).
    var c: R<u32> = Result<u32>.err(Error("x"));
    if (c.is_ok()) { return 3; }
    if (c.ok_or(9) != 9) { return 4; }

    # Alias as a function return type.
    var d: R<int> = make();
    if (!d.is_ok() || d.unwrap() != 5) { return 5; }
    # Alias as the static-call target of a method.
    var p = Pair.ok(13);
    if (!p.is_ok() || p.unwrap() != 13) { return 8; }

    # Alias in a struct field and module global.
    var s = Box();
    if (s.v != 0) { return 6; }
    if (global_alias_value != 3) { return 7; }

    return 0;
}

make(): R<int> {
    return Result<int>.ok(5);
}

# Everything here is private to lib.pep unless it says `export`.

export struct Point {
    var x: int;
    var y: int;
}

export type Points = Point[];

export trait Describe {
    describe(): String;
}

export var points_made = 0;

export origin(): Point {
    return make(0, 0);
}

export at(x: int, y: int): Point {
    return make(x, y);
}

# Private: only lib.pep can call make().
make(x: int, y: int): Point {
    var p = Point();
    p.x = x;
    p.y = y;
    points_made = points_made + 1;
    return p;
}

# An exported extension: its methods are usable wherever Point is.
export extend Point with Describe {
    describe(): String {
        return "point";
    }
}

# A private extension: only lib.pep can call p.norm().
extend Point {
    norm(): int {
        return x * x + y * y;
    }
}

export norm_of(p: Point): int {
    return p.norm();
}

# `export` goes after attributes, directly before the declaration.
[Target(OS(Windows))] export platform_name(): String { return "Windows"; }
[Target(!OS(Windows))] export platform_name(): String { return "not Windows"; }

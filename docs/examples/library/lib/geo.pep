# A library for Pepper programs, built with
# `pepper build --lib pepper geo.pep -o lib/libgeo.a`.

export trait Shape {
    area(): int;

    describe(): String {
        return $"a shape of area {area()}";
    }
}

export struct Square {
    var side: int;

    construct(side: int) {
        this.side = side;
    }
}

extend Square with Shape {
    area(): int {
        return side * side;
    }
}

export pair<T>(value: T): T[] {
    return [value, value];
}

# A trait names a set of methods that a type provides.
trait Shape {
    area(): int;
    name(): String;

    # A method with a body is a default: every type with the trait gets it.
    describe(): String {
        return "a " + name();
    }
}

struct Square {
    var side: int = 1;
    construct(this.side = 1) {}
}

# `extend ... with` declares that Square has the Shape trait, and adds the
# trait's methods to it.
extend Square with Shape {
    area(): int {
        return side * side;
    }

    name(): String {
        return "square";
    }
}

# A trait can be generic, and can declare static methods; `this` as a type
# stands for the type that has the trait.
trait From<T> {
    static this from(T value);
}

extend Square with From<int> {
    static Square from(int side) {
        return Square(side);
    }
}

# A trait whose methods all have defaults needs no body: end the extension
# with `;`, the same as writing an empty `{}`.
trait Labeled {
    label(): String {
        return "shape";
    }
}

extend Square with Labeled;

main(): int {
    var sq = Square(3);
    assert(sq.area() == 9, "trait method called on the struct");
    assert(sq.name() == "square", "second trait method");
    assert(sq.describe() == "a square", "default method from the trait");
    assert(Square.from(4).area() == 16, "static method from a generic trait");
    assert(sq.label() == "shape", "default method from a bodiless extension");
    return 0;
}

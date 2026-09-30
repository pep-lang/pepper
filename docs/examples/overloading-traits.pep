struct Square {
    var side: int = 0;

    construct(this.side = 0) {}

    area(): int {
        return side * side;
    }
}

# An extension's methods join the struct's overload set of their name.
extend Square {
    area(scale: int): int {
        return area() * scale;
    }
}

# A trait may declare overloads too; each is its own member.
trait Shape {
    area(): int;
    area(scale: int): int;

    # A default joins the conforming type's set of its name.
    describe(): int {
        return area() * 100 + area(2);
    }
}

# Each trait member is implemented by the method with its parameter types.
extend Square with Shape {}

total(shape: Shape): int {
    return shape.area() + shape.area(10);
}

main(): int {
    var square = Square(3);
    assert(square.area(2) == 18, "the extension's overload");
    assert(total(square) == 99, "each call through the trait takes its own member");
    assert(square.describe() == 918, "the default body calls both");
    return 0;
}

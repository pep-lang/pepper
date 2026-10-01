# Constrained extensions give their members only to specializations that
# meet their constraints, and conditional conformance makes a
# specialization conform to a trait only when its argument does.

trait Shape {
    area(): int;
}

trait Named {
    name(): String;
}

struct Circle {
    area(): int { return 3; }
}

extend Circle with Shape {}

struct Square {
    area(): int { return 4; }
    name(): String { return "square"; }
}

extend Square with Shape {}
extend Square with Named {}

struct Box<T> {
    var item: T;
    construct(item: T) { this.item = item; }
    get(): T { return item; }
}

# Only a Box of something Named has a label.
extend Box<T: Named> {
    label(): String { return "box of " + item.name(); }
}

# A Box of shapes is a shape.
extend Box<T: Shape> with Shape {
    area(): int { return item.area() * 2; }
}

# Two conditional conformances to one trait: a Box conforms when it meets
# either.
trait Describe {
    describe(): int { return 7; }
}

extend Box<T: Shape> with Describe {}
extend Box<T: Named> with Describe {}

struct Tag {
    name(): String { return "tag"; }
}

extend Tag with Named {}

describe_it<T: Describe>(value: T): int { return value.describe(); }

total<T: Shape>(shapes: Array<T>): int {
    var sum = 0;
    for (var shape in shapes) {
        sum += shape.area();
    }
    return sum;
}

main(): int {
    var square = Box<Square>(Square());
    if (square.label() != "box of square") {
        return 1;
    }
    var boxes = Array<Box<Circle>>();
    boxes.append(Box<Circle>(Circle()));
    boxes.append(Box<Circle>(Circle()));
    if (total(boxes) != 12) {
        return 2;
    }
    Shape shape = Box<Box<Square>>(square);
    if (shape.area() != 16) {
        return 3;
    }
    # A Box of anything still has the struct's own members.
    var text = Box<String>("plain");
    if (text.get() != "plain") {
        return 4;
    }
    Describe described = Box<Circle>(Circle());
    if (described.describe() != 7 or describe_it(Box<Tag>(Tag())) != 7) {
        return 5;
    }
    return 0;
}

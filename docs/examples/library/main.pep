# Imports the library `geo` (`lib/geo.pep`), built with `--lib pepper`,
# with no source for it: `pepper build main.pep -L lib -o main`.
import geo;

struct Circle {
    var radius: int;

    construct(radius: int) {
        this.radius = radius;
    }
}

# A program's struct takes the library's trait, and its default method.
extend Circle with geo.Shape {
    area(): int {
        return 3 * radius * radius;
    }
}

main(): int {
    var shapes = Array<geo.Shape>();
    shapes.append(geo.Square(3));
    shapes.append(Circle(1));
    for (var shape in shapes) {
        print(shape.describe());
    }
    # The library's generic, at the program's type.
    print($"{geo.pair(Circle(2)).count} circles");
    return 0;
}

# Output:
# a shape of area 9
# a shape of area 3
# 2 circles

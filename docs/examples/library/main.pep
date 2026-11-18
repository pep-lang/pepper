# Imports the library `geo` (`lib/geo.pep`), built with `--lib pepper`,
# and `scene` (`lib/scene.pep`), built on `geo`, with no source for
# either: `pepper build main.pep -L lib -o main`.
import geo;
import scene;

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

# A method of the program's own on the library's struct.
extend geo.Square {
    perimeter(): int {
        return 4 * side;
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
    # A library that imports `geo`, called with the program's shapes.
    print($"total area {scene.total_area(shapes)}");
    print($"perimeter {geo.Square(3).perimeter()}");
    return 0;
}

# Output:
# a shape of area 9
# a shape of area 3
# 2 circles
# total area 12
# perimeter 12

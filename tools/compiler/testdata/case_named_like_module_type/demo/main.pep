# A file in the module's folder that imports the module, not `shapes.pep`:
# its `Circle` arm names `Shape`'s case, not the type `Circle` declared
# there, and `side` binds a value, not the function `side` declared there.
import [Shape] from demo;

main(): int {
    int total = 0;
    for (var shape in [Shape.Circle(3), Shape.Square(4), Shape.Dot]) {
        match (shape) {
            Circle(radius) => {
                total += radius;
            }
            Square(side) => {
                total += side * 10;
            }
            Dot => {
                total += 100;
            }
        }
    }
    return total;
}

# The same match without its `Dot` arm: the error is the missing case.
import [Shape] from demo;

main(): int {
    match (Shape.Dot) {
        Circle(radius) => {
            return radius;
        }
        Square(side) => {
            return side;
        }
    }
    return 0;
}

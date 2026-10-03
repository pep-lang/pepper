# Build with `-g` and step through `total`: each pass of the `static`
# block's loop stops on the `for` line, then on its body, with `field`
# holding the pass's member.
struct Point {
    var x: int = 1;
    var y: int = 2;
    var z: int = 3;
}

total(p: Point): int {
    var sum = 0;
    static (sum, p) {
        for (var field in reflect.properties<Point>()) {
            sum = sum + field.get(p);
        }
    }
    return sum;
}

main(): int {
    return total(Point()) - 6;
}

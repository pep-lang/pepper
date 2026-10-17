export struct Point {
    var x: int;
    var y: int;

    construct(x: int, y: int) {
        this.x = x;
        this.y = y;
    }
}

# Joins the runtime's `print(String)` wherever it is imported.
export print(p: Point) {
    print($"({p.x}, {p.y})");
}

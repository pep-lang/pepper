struct Point {
    var x: int;
}

# A string a module-scope static block computes is a constant, as a string
# literal is (#396).
static {
    const NAME = reflect.name<Point>();
}

main(): int {
    print(NAME);
    return 0;
}

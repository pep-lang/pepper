
trait XGetter {
    int getX();
}

struct Test {
    int x;

    new(this.x = 0) {}
}

extend Test with XGetter {
    int getX() { return x; }
}

main(): int {
    var t = Test();
    return t.getX();
}

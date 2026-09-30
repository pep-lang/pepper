
trait XGetter {
    int get_x();
}

struct Test {
    int x;

    construct(this.x = 0) {}
}

extend Test with XGetter {
    int get_x() { return x; }
}

main(): int {
    var t = Test();
    return t.get_x();
}

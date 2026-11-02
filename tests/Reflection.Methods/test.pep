# reflect.methods<T>() and reflect.constructors<T>() (#392): the struct's
# public methods in order, an attribute check, and calls of an instance
# method (receiver first), a static method and a constructor.

[Attribute]
struct Command {}

struct Point {
    var x: int;
    var y: int;

    construct(this.x = 0, this.y = 0) {}

    [Command]
    norm(): int {
        return x + y;
    }

    scaled(by: int): Point {
        return Point(x * by, y * by);
    }

    static origin(): Point {
        return Point(7, 0);
    }

    _hidden(): int {
        return 0;
    }
}

main(): int {
    var p = Point(1, 2);
    var o = Point();
    var names = "";
    var total = 0;
    var statics = 0;
    static (names, total, p, o, statics) {
        for (var m in reflect.methods<Point>()) {
            names = names + m.name + " ";
            if (m.has_attribute<Command>()) {
                total = total + m.call(p);
            }
            if (m.is_static) {
                o = m.call();
                statics = statics + 1;
            }
        }
        for (var c in reflect.constructors<Point>()) {
            names = names + c.name;
            p = c.call(3, 4);
        }
    }
    assert(names == "norm scaled origin Point", "names");
    assert(total == 3, "an instance method, its receiver first");
    assert(o.x == 7 && statics == 1, "a static method");
    assert(p.x == 3 && p.y == 4, "a constructor");
    return 0;
}

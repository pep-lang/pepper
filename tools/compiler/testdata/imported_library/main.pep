# A program that imports the Pepper library `geo` (`geo.pep`) built with
# `--lib pepper`, with none of its source.

import async;
import geo;

struct Circle {
    var r: int;

    construct(r: int) {
        this.r = r;
    }
}

extend Circle with geo.Shape {
    area(): int {
        return 3 * r * r;
    }
}

const counter = geo.Counter();

work() {
    counter.hits.fetch_add(1);
}

main(): int {
    var shapes = Array<geo.Shape>();
    shapes.append(geo.Square(3));
    shapes.append(Circle(1));
    var described = Array<String>();
    for (var shape in shapes) {
        described.append(shape.describe());
    }
    var thread = async.Thread.spawn(work);
    thread.join();
    var points = [geo.Point(1, 2), geo.Point(3, 4)];
    var names = geo.pair("a");
    var circles = geo.pair(Circle(2));
    print(
        $"{",".join(described)} {geo.sum(points)} {counter.hits.load()} {names.count} {circles[0].area()} {geo.answer()} {"x".shout()}"
    );
    return 0;
}

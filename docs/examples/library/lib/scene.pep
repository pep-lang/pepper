# A library built on the library `geo` (`geo.pep`), which it imports:
# `pepper build --lib pepper scene.pep -L lib -o lib/libscene.a`.
import geo;

export total_area(shapes: geo.Shape[]): int {
    var total = 0;
    for (var shape in shapes) {
        total += shape.area();
    }
    return total;
}

# A program that extends a struct of the Pepper library `geo` (`geo.pep`)
# with a method of its own, beside the method the Pepper library `measure`
# (`measure.pep`) extends it with, and calls both.

import geo;
import measure;

extend geo.Point {
    total(): int {
        return x + y;
    }
}

main(): int {
    var point = geo.Point(3, 4);
    print($"{point.total()} {point.product()} {measure.area(point)}");
    return 0;
}

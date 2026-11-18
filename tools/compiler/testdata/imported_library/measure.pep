# A Pepper library that extends a struct of the Pepper library `geo`
# (`geo.pep`, `pepper_library_test.pep`), exports the extension, and calls
# it itself.

import geo;

export extend geo.Point {
    product(): int {
        return x * y;
    }
}

export area(point: geo.Point): int {
    return point.product();
}

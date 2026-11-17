# A Pepper library that imports the Pepper library `geo` (`geo.pep`,
# `pepper_library_test.pep`): it re-exports one of its structs, sets a
# global from one of its globals, and calls its function and generic.

import geo;
export [Point] from geo;

const SCALED: int = geo.answer() * 2;

export scaled(): int {
    return SCALED;
}

export twice(points: geo.Point[]): int {
    return geo.sum(points) * 2;
}

export twin<T>(value: T): int {
    return geo.pair(value).count;
}

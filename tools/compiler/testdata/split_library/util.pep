# The second file of the library `geo.pep` roots: a private helper, which
# a generic the program instantiates calls, and a struct and a function the
# root re-exports.

_secret(): int {
    return 5;
}

export scale<T>(items: T[]): int {
    return (items.count as int) * _secret();
}

export struct Grid {
    var cells: int;

    construct(cells: int) {
        this.cells = cells;
    }
}

export total(grid: Grid): int {
    return grid.cells + _secret();
}

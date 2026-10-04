# Module-internal: no `export`, yet every file of `inventory` can use these.
const RESTOCK_LEVEL = 5;

struct Shelf {
    var count: int;
}

needs_restock(shelf: Shelf): bool {
    return shelf.count < RESTOCK_LEVEL;
}

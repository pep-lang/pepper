# Uses `Shelf`, `needs_restock` and `RESTOCK_LEVEL` from rules.pep with no
# import: files of one module see each other's declarations.
export struct Stock {
    var _shelf: Shelf;

    construct(count: int) {
        _shelf = Shelf();
        _shelf.count = count;
    }

    low(): bool {
        return needs_restock(_shelf);
    }

    missing(): int {
        if low() {
            return RESTOCK_LEVEL - _shelf.count;
        }
        return 0;
    }
}

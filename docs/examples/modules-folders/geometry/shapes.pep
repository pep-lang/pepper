# A file of the geometry module. Its exports are visible to the files of
# the module that import it, not to the module's importers.
export area(w: int, h: int): int {
    return w * h;
}

export struct Box<T> {
    var value: T;
}

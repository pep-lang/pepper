# One set: `area(int)` is exported; `area(int, int)` is private to this file.
export area(side: int): int {
    return area(side, side);
}

area(width: int, height: int): int {
    return width * height;
}

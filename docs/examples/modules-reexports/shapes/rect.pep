# A file of the shapes module. `helper` is private, so `export *` leaves it
# behind.
export struct Rect {
    var w: int;
    var h: int;
}

export make_rect(w: int, h: int): Rect {
    var r = Rect();
    r.w = w;
    r.h = h;
    return r;
}

export area(r: Rect): int {
    return r.w * r.h + helper();
}

helper(): int {
    return 0;
}

# Another file of the shapes module. The module passes on only `perimeter`
# (as `outline`) and `Side`; `diagonal_squared` stays inside it.
import "rect";

export perimeter(r: Rect): int {
    return 2 * (r.w + r.h);
}

export struct Side {
    var length: int;
}

export diagonal_squared(r: Rect): int {
    return r.w * r.w + r.h * r.h;
}

# A Pepper shared library that imports `base`: its global reads `base`'s,
# so `base` must be initialized first, and it fills `base`'s struct.

import base;

export const NEXT: int = base.START + 1;

export make(): base.Box {
    var box = base.make_box();
    box.add("top");
    return box;
}

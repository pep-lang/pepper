# The root of a Pepper library of two files (`pepper_library_test.pep`,
# #220): it re-exports what `util.pep` declares, keeps a private helper of
# the name `util.pep`'s has, and exports an overload set and a generic
# whose body calls its private helper.

import "util";

export [scale, Grid, total] from "util";

_secret(): int {
    return 7;
}

export twice<T>(value: T): int {
    return _secret() * 2;
}

export area(n: int): int {
    return n * n;
}

export area(n: int, m: int): int {
    return n * m;
}

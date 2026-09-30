# Overloaded free functions: one name, several parameter lists.

import io;

describe(n: long): String { return "a number"; }
describe(x: double): String { return "a fraction"; }
describe(s: String): String { return "some text"; }
describe(s: String, times: int): String { return "text, repeated"; }

# An exact match beats a widening, which beats a conversion; an
# `[Implicit]` constructor comes last.
size(p: io.Path): int { return 1; }
size(n: long): int { return 2; }

main(): int {
    var small: int = 7;
    assert(describe(small) == "a number", "int widens to long");
    assert(describe(2.5) == "a fraction", "exact match");
    assert(describe("hi") == "some text", "a literal promotes to String");
    assert(describe("hi", 3) == "text, repeated", "picked by argument count");

    assert(size(4) == 2, "an integer literal fits a long");
    assert(size("notes.txt") == 1, "only io.Path takes a String, by its [Implicit] constructor");
    return 0;
}

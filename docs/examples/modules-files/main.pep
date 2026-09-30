# Every import comes before the file's declarations.
import "util";                       # util.pep's exports, unqualified
import "util" as u;                  # the same exports, as u.name
import [thrice as triple] from "util";
import "helpers/text";               # a file in a subfolder

main(): int {
    assert(twice(BASE) == 20, "unqualified names from util.pep");
    assert(u.thrice(2) == 6, "qualified by the alias");
    assert(triple(3) == 9, "renamed by the import list");
    assert(shout("hi") == "hi!", "from helpers/text.pep");

    # An imported function is a value like any other.
    var f = u.twice;
    assert(f(4) == 8, "function reference through a qualifier");
    return 0;
}

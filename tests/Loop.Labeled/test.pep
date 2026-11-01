# Labeled `break` and `continue` leave nested `for` and `while` loops and
# release what they leave: each `Tracked` counts its destruction, so a
# leak leaves the count short and an over-release passes it.

import async;

const destroyed = async.Atomic<int>(0);

struct Tracked {
    var name: String;

    construct(name: String) {
        this.name = name;
    }

    destruct {
        destroyed.fetch_add(1);
    }
}

main(): int {
    var made = 0;
    var seen = 0;
    {
        var grid = [[Tracked("a"), Tracked("bb")], [Tracked("ccc"), Tracked("dddd")], [Tracked("e")]];
        made += 5;
        rows: for (var row in grid) {
            for (var cell in row) {
                var held = Tracked(cell.name + "!");
                made += 1;
                if (cell.name.size == 2) {
                    continue rows;
                }
                if (cell.name.size == 4) {
                    break rows;
                }
                seen += 1;
            }
        }
    }
    assert(seen == 2, "'a' and 'ccc' before the jumps");

    var n = 0;
    outer: while (n < 3) {
        n += 1;
        var keep = Tracked($"{n}");
        made += 1;
        for (var x in [Tracked("p"), Tracked("q")]) {
            var inner = Tracked(x.name);
            made += 3;
            if (n == 2) {
                break outer;
            }
            continue outer;
        }
    }
    assert(n == 2, "the second pass leaves");
    # Each pass of the second loop makes `keep`, a list of two and one
    # `inner` before it jumps: four, counted together.
    assert(destroyed.load() == made, $"{destroyed.load()} released, {made} made");
    return 0;
}

# Labeled loops: `break` and `continue` that name an outer loop.

main(): int {
    var grid = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];

    # `break rows` leaves both loops at once.
    var found = "";
    rows: for (var row in grid) {
        for (var cell in row) {
            if (cell > 4) {
                found = $"{cell}";
                break rows;
            }
        }
    }
    assert(found == "5", "the first cell above 4");

    # `continue rows` goes on to the next row, skipping the rest of this one.
    var firsts = 0;
    rows: for (var row in grid) {
        for (var cell in row) {
            firsts += cell;
            continue rows;
        }
    }
    assert(firsts == 1 + 4 + 7, "the first cell of each row");

    # A label works on `while` too.
    var tries = 0;
    attempts: while (tries < 10) {
        tries += 1;
        var step = 0;
        while (true) {
            step += 1;
            if (step == 3) {
                break attempts;
            }
        }
    }
    print($"{found} {firsts} {tries}");
    return 0;
}

# Output:
# 5 12 1

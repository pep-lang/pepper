struct Row {
    var id: int;
    var _cache: int;
    var name: String;
    var score: int;
    var notes: String;
}

# The sum of the public `int` fields of `Row` before 'notes': `continue`
# and `break` steer the unrolled `for`.
sum_leading_ints(row: Row): int {
    var total = 0;
    static (total, row) {
        for (var field in reflect.fields<Row>()) {
            if (field.name.starts_with("_")) {
                continue;
            }
            if (field.name == "notes") {
                break;
            }
            if (reflect.is_same<field.Type, int>()) {
                total += field.get(row);
            }
        }
    }
    return total;
}

# A compile-time `while` emits its body once per iteration: here, the
# first four powers of three, as four additions.
powers_of_three(): int {
    var sum = 0;
    static (sum) {
        var power = 1;
        while (power < 30) {
            sum += power;
            power = power * 3;
        }
    }
    return sum;
}

main(): int {
    var row = Row();
    row.id = 2;
    row.score = 40;
    assert(sum_leading_ints(row) == 42, "id and score; _cache is skipped");
    assert(powers_of_three() == 1 + 3 + 9 + 27, "one addition per iteration");
    return 0;
}

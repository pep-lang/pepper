# A loop variable over a range whose bounds' types are known at once casts
# like any number (#52): its type was left unresolved, and the cast failed
# with "cannot cast '__auto' to 'int'".

struct Sum {
    var total: int = 0;

    add(value: int) {
        total += value;
    }

    add(value: String) {
        total += value.size as int;
    }

    all(values: int[]) {
        for (var i in 0..values.count) {
            add((i + 1) as int);
        }
    }
}

main(): int {
    ulong n = 3;
    int total = 0;
    for (var i in 0..n) {
        total += i as int;
    }
    for (var j in 0..3) {
        int k = j as int;
        total += k;
    }
    var sum = Sum();
    sum.all([5, 6]);
    return total == 6 and sum.total == 3 ? 0 : 1;
}

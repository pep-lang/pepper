# Each construct whose type the compiler injects, in a body: a local's
# initializer, an argument, a `match` arm, a closure's body, and `?` on a
# `Result` and an `Optional` (pepper#103).
half(n: int): Result<int, String> {
    if (n % 2 != 0) {
        return Result<int, String>.Err("odd " + $"{n}");
    }
    return Result<int, String>.Ok(n / 2);
}

quarter(n: int): Result<int, String> {
    var h = half(n)?;
    return Result<int, String>.Ok(half(h)?);
}

first(items: int[]): int? {
    if (items.count == 0) {
        return Optional<int>.Empty;
    }
    return Optional<int>.Value(items[0]);
}

doubled_first(items: int[]): int? {
    return Optional<int>.Value(first(items)? * 2);
}

describe(n: int): String {
    return match (n) {
        0 => "zero" + "!",
        else => $"n{n}",
    };
}

main(): int {
    var text = "a" + "b" + $"{1}";
    var items = [1, 2, 3];
    var map = ["k": 4];
    var pair = (5, "p");
    var point = (x: 6, y: 7);
    var sum = 0;
    for (var i in 1..3) {
        sum += i;
    }
    if ($"{text} {items.count} {map["k"]} {pair.1} {point.y} {sum}" != "ab1 3 4 p 7 3") {
        return 1;
    }
    if (quarter(8).value() != 2 or quarter(6).error() != "odd 3") {
        return 2;
    }
    if (doubled_first([4]).value() != 8 or doubled_first(Array<int>()).is_value()) {
        return 3;
    }
    if (describe(0) != "zero!" or describe(3) != "n3") {
        return 4;
    }
    var label = (n: int) => "c" + $"{n}{[n].count}";
    if (label(2) != "c21") {
        return 5;
    }
    return 0;
}

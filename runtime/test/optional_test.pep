# Optional<T>: every method against a plain `T` and a struct `T`, the
# `T?` shorthand, empty slots, the panic on an empty optional's value, and
# Optional as an enum with Empty and Value cases.

struct Point {
    int x;

    construct(v: int) {
        this.x = v;
    }
}

struct Token {
    String text;

    construct(this.text = "") {}
}

struct Node {
    Token? leaf;
    Optional<int> count;

    construct() {}
}

first_negative(values: Array<int>): Optional<int> {
    for (var v in values) {
        if (v < 0) {
            return Optional<int>.Value(v);
        }
    }
    return Optional<int>.Empty;
}

first_even(values: Array<int>): int? {
    for (var v in values) {
        if (v % 2 == 0) {
            return Optional<int>.Value(v);
        }
    }
    return Optional<int>.Empty;
}

text_of(t: Token?): String {
    return t.value_or(Token("none")).text;
}

describe(o: String?): int {
    return match (o) {
        Empty => 0,
        Value(text) => text.length as int,
    };
}

[Test]
some_and_none_pod() {
    var a = Optional<int>.Value(42);
    expect_true(a.is_value());
    expect_false(a.is_empty());
    expect_equal(a.value(), 42);
    expect_equal(a.value_or(7), 42);
    var b = Optional<int>.Empty;
    expect_false(b.is_value());
    expect_true(b.is_empty());
    expect_equal(b.value_or(7), 7);
}

[Test]
some_of_a_zero_value_is_still_some() {
    var a = Optional<int>.Value(0);
    expect_true(a.is_value());
    var b = Optional<bool>.Value(false);
    expect_true(b.is_value());
    expect_false(b.value());
}

[Test]
struct_value_and_fallback() {
    var a = Optional<Point>.Value(Point(7));
    expect_equal(a.value().x, 7);
    var b = Optional<Point>.Empty;
    expect_equal(b.value_or(Point(3)).x, 3);
    expect_equal(a.value_or(Point(3)).x, 7);
}

[Test]
returned_from_a_function() {
    var values = Array<int>();
    values.append(1);
    expect_false(first_negative(values).is_value());
    values.append(-5);
    expect_equal(first_negative(values).value(), -5);
}

[Test]
[ShouldPanic("Optional.value on an Empty optional")]
value_of_none_panics() {
    var a = Optional<int>.Empty;
    a.value();
}

[Test]
question_mark_shorthand() {
    var values = Array<int>();
    values.append(3);
    expect_false(first_even(values).is_value());
    values.append(8);
    expect_equal(first_even(values).value(), 8);
    expect_equal(text_of(Optional<Token>.Empty), "none");
    Token? t = Optional<Token>.Value(Token("x"));
    expect_equal(text_of(t), "x");
    var all = Array<int?>();
    all.append(Optional<int>.Empty);
    expect_true(all[0].is_empty());
    var x = 3;
    var y = x > 2 ? 10 : 20;
    expect_equal(y, 10);
}

[Test]
optional_slots_start_as_none() {
    var n = Node();
    expect_true(n.leaf.is_empty());
    expect_true(n.count.is_empty());
    var local: int?;
    expect_true(local.is_empty());
    Token? c_style;
    expect_true(c_style.is_empty());
    n.leaf = Optional<Token>.Value(Token());
    expect_true(n.leaf.is_value());
}

[Test]
optional_is_an_enum_with_empty_and_value_cases() {
    var some = Optional<String>.Value("four");
    expect_equal(describe(some), 4);
    expect_equal(describe(Optional<String>.Empty), 0);
    var matched = false;
    if (some is Value(text)) {
        expect_equal(text, "four");
        matched = true;
    }
    expect_true(matched);
    expect_true(some == Optional<String>.Value("four"));
    expect_false(some == Optional<String>.Empty);
    String? unset;
    expect_true(unset == Optional<String>.Empty);
}

[Test]
optionals_of_comparable_values_are_comparable() {
    var empty = Optional<int>.Empty;
    expect_true(empty < Optional<int>.Value(-5));
    expect_true(Optional<int>.Value(1) < Optional<int>.Value(2));
    expect_equal(empty.compare(Optional<int>.Empty), 0);
    expect_true(Optional<String>.Value("b") > Optional<String>.Value("a"));
    var values = [Optional<int>.Value(3), empty, Optional<int>.Value(1)];
    values.sort();
    expect_true(values[0].is_empty());
    expect_equal(values[1].value(), 1);
    expect_equal(values[2].value(), 3);
}

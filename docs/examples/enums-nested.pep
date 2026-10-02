# Patterns nest: the values a case carries can be matched by patterns of
# their own, as tuple elements can.
enum Doc {
    Text(text: String),
    Line,
    Pair(left: Doc, right: Doc),
}

describe(found: Optional<Doc>): String {
    return match (found) {
        Empty => "nothing",
        # A literal compares the value: only an empty `Text`.
        Value(Text("")) => "empty text",
        # A case of the value's enum, binding its own values.
        Value(Text(t)) => t,
        Value(Line) => "a line",
        # Deeper still, with `_` for a value that does not matter.
        Value(Pair(Line, _)) => "a pair that starts with a line",
        Value(Pair) => "a pair",
    };
}

main(): int {
    assert(describe(Optional<Doc>.Empty) == "nothing", "no document");
    assert(describe(Optional<Doc>.Value(Doc.Text(""))) == "empty text", "a literal value");
    assert(describe(Optional<Doc>.Value(Doc.Text("hi"))) == "hi", "a bound value");
    assert(
        describe(Optional<Doc>.Value(Doc.Pair(Doc.Line, Doc.Text("x")))) == "a pair that starts with a line",
        "two levels deep"
    );

    # A bare name binds the value, unless the value's enum has a case of
    # that name: here `Empty` is `Optional<int>`'s case.
    var nested = Optional<Optional<int>>.Value(Optional<int>.Empty);
    var depth = match (nested) {
        Empty => 0,
        Value(Empty) => 1,
        Value(Value(n)) => 2 + n,
    };
    assert(depth == 1, "the inner Optional is empty");

    # Ranges and guards work inside too, and so does `is`.
    var count = Optional<int>.Value(7);
    var size = match (count) {
        Value(0) => "none",
        Value(1..10) => "a few",
        Value(n) if n < 0 => "negative",
        Value(_) => "many",
        Empty => "unknown",
    };
    assert(size == "a few", "a range inside a case");
    var pair = Doc.Pair(Doc.Text("left"), Doc.Line);
    if (pair is Pair(Text(word), Line)) {
        assert(word == "left", "is binds nested names");
    }
    return 0;
}

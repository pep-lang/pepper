struct Measurement<TValue, TUnit=String> {
    var value: TValue;
    var unit: TUnit;
}

main(): int {
    # `Measurement<float>` fills TUnit with its default, String.
    var length = Measurement<float>();
    length.value = 2.5;
    length.unit = "m";
    assert(length.unit == "m", "TUnit defaulted to String");

    # Any argument can still be given explicitly.
    var count = Measurement<int, int>();
    count.unit = 7;
    assert(count.unit == 7, "TUnit given as int");

    # The standard library's Result uses a default the same way:
    # Result<int> means Result<int, Error>.
    var ok = Result<int>.ok(42);
    assert(ok.unwrap() == 42, "Result with the default error type");
    return 0;
}

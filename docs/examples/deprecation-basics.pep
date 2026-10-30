struct Temperature {
    int celsius;

    # A method on its way out: it still works, but every call warns.
    [Deprecated("use 'fahrenheit' instead", "fahrenheit")]
    to_f(): int { return fahrenheit(); }

    fahrenheit(): int { return celsius * 9 / 5 + 32; }
}

# The second argument names the replacement: the warning carries a fix that
# renames the call.
[Deprecated("use 'boiling' instead", "boiling")]
boiling_point(): Temperature { return boiling(); }

# An enum case can be deprecated too: each use and each pattern naming it
# warns.
enum Scale {
    Celsius,
    [Deprecated("use 'Celsius' instead", "Celsius")]
    Centigrade,
}

boiling(): Temperature {
    var t = Temperature();
    t.celsius = 100;
    return t;
}

main(): int {
    # Both calls warn, and both still work.
    var old = boiling_point();
    assert(old.to_f() == 212, "the old API still works");

    var t = boiling();
    assert(t.fahrenheit() == 212, "100 C is 212 F");

    var scale = Scale.Centigrade;
    assert(scale is Centigrade, "an old case still matches");
    return 0;
}

# Build options: compile with `pep-build main.pep -D FAST_MATH -D LOG_LEVEL=2`
# to pick the other versions.

# `[BuildOption("NAME")]` keeps a declaration when `-D NAME` is given, and
# `!BuildOption(NAME)` inside a `Target` keeps its fallback otherwise.
[BuildOption("FAST_MATH")]
scale(x: int): int {
    return x << 1;
}

[Target(!BuildOption(FAST_MATH))]
scale(x: int): int {
    return x * 2;
}

# A `static` block reads an option's value while compiling, with a default
# for a build that does not set it.
log_level(): int {
    var level = 1;
    static (level) {
        if (reflect.build_option("LOG_LEVEL", "1") == "2") {
            level = 2;
        }
    }
    return level;
}

main(): int {
    if (scale(21) != 42) {
        return 1;
    }
    var level = log_level();
    if (level < 1 || level > 2) {
        return 2;
    }
    return 0;
}

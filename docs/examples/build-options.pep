# Build options: compile with
# `pep-build main.pep -D FAST_MATH -D LOG_LEVEL=2 -D QUIET_LEVEL=1` to pick
# the other versions.

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

# Two options compare with each other too, as numbers when both values are.
# The comparison is false, with a warning, unless the build defines both.
verbose(): bool {
    [Target(BuildOption(LOG_LEVEL) > BuildOption(QUIET_LEVEL))] {
        return true;
    }
    return false;
}

main(): int {
    if (scale(21) != 42) {
        return 1;
    }
    var level = log_level();
    if (level < 1 || level > 2) {
        return 2;
    }
    if (verbose() and level != 2) {
        return 3;
    }
    return 0;
}

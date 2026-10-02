# An enum can declare operators and an indexer, as a struct does.
enum Level: u8 {
    Low,
    Mid,
    High,

    # `a < b` calls `Level.<`: the cases rank in order.
    <(other: Level): bool {
        return (this as int) < (other as int);
    }

    # `level + 1` moves up a level, stopping at the top.
    +(steps: int): Level {
        var next = Level.from_value((this as int + steps) as u8);
        return next.is_ok() ? next.value() : Level.High;
    }

    # `-level` mirrors it.
    -(): Level {
        return match (this) {
            Low => Level.High,
            Mid => Level.Mid,
            High => Level.Low,
        };
    }

    # `level[i]` reads, like any indexer.
    [](bit: int): bool {
        return ((this as int) >> bit) & 1 == 1;
    }
}

main(): int {
    var level = Level.Low;
    assert(level < Level.Mid && !(Level.High < level), "cases rank in order");
    assert(level + 1 == Level.Mid && level + 5 == Level.High, "a step up");
    assert(-level == Level.High, "mirrored");
    assert(Level.Mid[0] && !Level.Mid[1] && Level.High[1], "bits");
    return 0;
}

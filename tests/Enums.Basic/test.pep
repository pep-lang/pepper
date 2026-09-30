enum Direction {
    North,
    East,
    South,
    West,
}

enum Flag: u8 {
    Off,
    On = 'y',
}

turn_right(d: Direction): Direction {
    match (d) {
        North => { return Direction.East; }
        East => { return Direction.South; }
        South => { return Direction.West; }
        West => { return Direction.North; }
    }
    return d;
}

struct Robot {
    Direction facing;
    Flag lamp;
}

main(): int {
    var r = Robot();
    if (r.facing != Direction.North) { return -1; }
    if (r.lamp != Flag.Off) { return -2; }

    # Four right turns come back to the start.
    var d = Direction.West;
    var turns = 0;
    while (turns < 4) {
        d = turn_right(d);
        turns += 1;
    }
    if (d != Direction.West) { return -3; }

    # An enum converts to its integer with 'as'.
    if ((Flag.On as int) != 121) { return -4; }
    if (sizeof<Flag>() != 1) { return -5; }

    match (turn_right(Direction.South)) {
        West => {}
        else => { return -6; }
    }
    return 0;
}

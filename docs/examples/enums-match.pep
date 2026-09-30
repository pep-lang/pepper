# 'match' runs the arm of the case a value holds, and must handle every case.
enum Light {
    Red,
    Amber,
    Green,
}

next(light: Light): Light {
    match (light) {
        Red => { return Light.Green; }
        Amber => { return Light.Red; }
        Green => { return Light.Amber; }
    }
    return light;
}

may_go(light: Light): bool {
    match (light) {
        Green => { return true; }
        else => { return false; }
    }
    return false;
}

wait_seconds(light: Light): int {
    match (light) {
        Red, Amber => { return 30; }
        Light.Green => { return 0; }
    }
    return 0;
}

main(): int {
    var light = Light.Red;
    var changes = 0;
    while (!may_go(light)) {
        light = next(light);
        changes += 1;
    }
    assert(changes == 1, "red turns green");
    assert(wait_seconds(Light.Amber) == 30, "one arm handles two cases");
    assert(wait_seconds(light) == 0, "a pattern may name the enum");
    return 0;
}

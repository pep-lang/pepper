# An enum can declare methods after its cases; `this` is the value.
enum Light: u8 {
    Red,
    Amber,
    Green,

    may_go(): bool {
        return this == Light.Green;
    }

    next(): Light {
        match (this) {
            Red => { return Light.Green; }
            Amber => { return Light.Red; }
            Green => { return Light.Amber; }
        }
        return this;
    }

    # A bare call of another method acts on `this`.
    after_two(): Light {
        return next().next();
    }

    # A method can be generic, like any function.
    choose<T>(stop: T, go: T): T {
        return may_go() ? go : stop;
    }

    static first(): Light {
        return Light.Red;
    }
}

main(): int {
    var light = Light.first();
    assert(!light.may_go(), "red means stop");
    assert(light.next().may_go(), "green follows red");
    assert(light.after_two() == Light.Amber, "then amber");
    assert(light.choose("wait", "walk") == "wait" && Light.Green.choose(0, 1) == 1, "a generic method");

    # Every enum has name() and from_value().
    assert(light.name() == "Red", "name() spells the case");
    var found = Light.from_value(2);
    assert(found.is_ok() and found.value() == Light.Green, "2 is Green");
    assert(!Light.from_value(7).is_ok(), "no case has the value 7");

    # Enums key hash maps and fill atomics, like integers.
    var waits = HashMap<Light, int>();
    waits[Light.Red] = 30;
    assert(waits[Light.Red] == 30, "an enum is a hash key");
    return 0;
}

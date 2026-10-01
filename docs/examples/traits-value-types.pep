trait Describe {
    describe(): String;
    # A default method works for value types too.
    shout(): String { return describe() + "!"; }
}

trait Zero {
    static zero(): this;
}

# A number type conforms like a struct; `this` is the value.
extend int with Describe {
    describe(): String { return this < 0 ? "negative" : "non-negative"; }
}

extend int with Zero {
    static zero(): int { return 0; }
}

enum Light {
    Red,
    Green,
}

# An enum whose cases carry no values can conform too.
extend Light with Describe {
    describe(): String { return this == Light.Red ? "stop" : "go"; }
}

# Each call is resolved for the type argument: no trait value is made.
describe_all<T: Describe>(items: Array<T>): String {
    var text = "";
    for (var item in items) {
        text = text + item.describe() + " ";
    }
    return text;
}

zero_of<T: Zero>(): T { return T.zero(); }

main(): int {
    var numbers = Array<int>();
    numbers.append(-1);
    numbers.append(2);
    assert(describe_all(numbers) == "negative non-negative ", "numbers");
    assert(Light.Green.shout() == "go!", "enum");
    assert((5).describe() == "non-negative", "a call on a value");
    assert(zero_of<int>() == 0, "a static member through T");
    return 0;
}

struct Temperature {
    var celsius: float = 0.0;
    construct(this.celsius = 0.0) {}
}

# `extend` adds methods to a struct declared elsewhere.
extend Temperature {
    fahrenheit(): float {
        return celsius * 9.0 / 5.0 + 32.0;
    }

    static freezing(): Temperature {
        return Temperature(0.0);
    }

    bool ==(Temperature other) {
        return celsius == other.celsius;
    }
}

# Library types can be extended too.
extend String {
    exclaim(): String {
        var s = String();
        s.append(this);
        s.append("!");
        return s;
    }
}

struct Box<T> {
    var value: T;
}

# Extending the generic struct adds the method to every Box<...>.
extend Box<T> {
    get(): T {
        return value;
    }
}

main(): int {
    var t = Temperature(100.0);
    assert(t.fahrenheit() == 212.0, "extension method");
    assert(Temperature.freezing() == Temperature(0.0), "static method and operator from an extension");

    assert("hello".exclaim() == "hello!", "String extension");

    var b = Box<int>();
    b.value = 5;
    assert(b.get() == 5, "Box<int>");
    var s = Box<String>();
    s.value = "five";
    assert(s.get() == "five", "Box<String>");
    return 0;
}

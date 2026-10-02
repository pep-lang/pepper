enum Level {
    Low,
    High = 10,
}

struct Settings {
    var name: String;
    var retries: int;
    var verbose: bool;
    var level: Level;
}

# A compile-time `if` keeps only the branch it takes, so each field is
# written by the code that fits its type.
render<T>(value: T): String {
    var out = StringBuilder();
    static (out, value) {
        for (var field in reflect.properties<T>()) {
            out.append($"{field.name}=");
            if (reflect.is_same<field.Type, String>()) {
                out.append($"\"{field.get(value)}\"");
            } else if (reflect.is_enum<field.Type>()) {
                out.append(level_name(field.get(value)));
            } else {
                out.append($"{field.get(value)}");
            }
            out.append(";");
        }
    }
    return out.to_string();
}

# `reflect.cases<E>()` lists an enum's cases; `case.get()` is the case
# itself in emitted code.
level_name(level: Level): String {
    var name = "";
    static (level, name) {
        for (var case in reflect.cases<Level>()) {
            if (level == case.get()) {
                name = case.name;
            }
        }
    }
    return name;
}

# `field.set(value, x)` assigns a field.
reset_counts<T>(value: T) {
    static (value) {
        for (var field in reflect.properties<T>()) {
            if (reflect.is_same<field.Type, int>()) {
                field.set(value, 0);
            }
        }
    }
}

main(): int {
    var settings = Settings();
    settings.name = "fast";
    settings.retries = 3;
    settings.level = Level.High;
    assert(
        render(settings) == "name=\"fast\";retries=3;verbose=false;level=High;",
        "each field is written by the code for its type"
    );
    reset_counts(settings);
    assert(settings.retries == 0, "set assigns the int fields");
    return 0;
}

# Strings joined with `+` and interpolated in attribute arguments, an
# attribute's field initializer, and `static` blocks (pepper#103).
[Attribute]
struct Name {
    const value: String;
    const suffix: String = "_" + "2";
}

struct User {
    [Name("user" + "_1")]
    var id: int;
    var email: String;

    construct(id: int, email: String) {
        this.id = id;
        this.email = email;
    }
}

keys<T>(): String {
    var out = "";
    static (out) {
        for (var field in reflect.properties<T>()) {
            var key = field.name + $"/{field.name.length}";
            if (field.has_attribute<Name>()) {
                key = field.attribute<Name>().value + field.attribute<Name>().suffix;
            }
            out = out + key + ";";
        }
    }
    return out;
}

values<T>(value: T): String {
    var out = "";
    static (out, value) {
        for (var field in reflect.fields<T>()) {
            out = out + $"{field.name}=" + $"{field.get(value)}" + ",";
        }
    }
    return out;
}

main(): int {
    if (keys<User>() != "user_1_2;email/5;") {
        return 1;
    }
    if (values(User(1, "e")) != "id=1,email=e,") {
        return 2;
    }
    return 0;
}

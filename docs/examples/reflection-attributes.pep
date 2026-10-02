# An attribute is a struct marked `[Attribute]`. Its fields hold what a
# use of it says; a field with an initializer may be left out.
[Attribute]
struct Name {
    const value: String;
}

[Attribute]
struct Ignore {}

struct User {
    [Name("user_id")]
    var id: int;
    var email: String;
    [Ignore]
    var session: int;
}

# The keys a struct's fields are written under: each field's `[Name]` if
# it has one, else the field's own name, skipping `[Ignore]`d fields.
keys<T>(): String[] {
    var keys: String[] = [];
    static (keys) {
        for (var field in reflect.properties<T>()) {
            if (!field.has_attribute<Ignore>()) {
                var key = field.name;
                if (field.has_attribute<Name>()) {
                    key = field.attribute<Name>().value;
                }
                keys.append(key);
            }
        }
    }
    return keys;
}

main(): int {
    var found = keys<User>();
    assert(found.count == 2, "the [Ignore]d field is skipped");
    assert(found[0] == "user_id", "[Name] renames the key");
    assert(found[1] == "email", "a field without [Name] keeps its name");
    return 0;
}

# A value struct that declares `==` and `__hash` is hashed by its `__hash`,
# which takes the value's storage as any of its methods does: a `HashSet`
# and a `HashMap` find a key equal to one put in, from a variable or a
# temporary, alone or in a tuple.

[Value]
struct Name {
    var text: String;
    var tag: int;

    construct(text: String, tag: int) {
        this.text = text;
        this.tag = tag;
    }

    # Equal by text alone, so the hash must leave `tag` out.
    ==(other: Name): bool {
        return text == other.text;
    }

    __hash(): u64 {
        return hash<String>(text);
    }
}

main(): int {
    var names = HashSet<Name>();
    names.insert(Name("ada", 1));
    if (!names.contains(Name("ada", 2))) {
        return 1;
    }
    var key = Name("ada", 3);
    if (!names.contains(key) or names.contains(Name("bob", 1))) {
        return 2;
    }
    var ages = HashMap<Name, int>();
    ages[Name("bob", 1)] = 36;
    if (ages[Name("bob", 9)] != 36) {
        return 3;
    }
    # In a tuple too, the element hashes by its `__hash`.
    var pairs = HashSet<(Name, int)>();
    pairs.insert((Name("cy", 1), 7));
    if (!pairs.contains((Name("cy", 2), 7))) {
        return 4;
    }
    return 0;
}

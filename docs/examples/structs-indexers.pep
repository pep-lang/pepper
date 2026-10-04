# A struct declaring `[]` can be indexed: one parameter reads, two write.
struct Shelf {
    var titles: Map<String, String>;
    var sections: Map<String, Shelf>;

    construct() {
        titles = Map<String, String>();
        sections = Map<String, Shelf>();
    }

    # `shelf["name"]` reads a section.
    [](name: String): Shelf {
        return sections[name];
    }

    # `shelf["name"] = section` writes one.
    [](name: String, section: Shelf): Shelf {
        sections[name] = section;
        return section;
    }

    # `shelf[slot]` and `shelf[slot] = title` overload `[]` by type.
    [](slot: ulong): String {
        return titles[$"{slot}"];
    }

    [](slot: ulong, title: String): String {
        titles[$"{slot}"] = title;
        return title;
    }
}

main(): int {
    var library = Shelf();
    library["fiction"] = Shelf();
    # A chained assignment writes into the shelf the first index reads,
    # like `var fiction = library["fiction"]; fiction[0] = ...;`.
    library["fiction"][0] = "Dune";
    library["fiction"]["classics"] = Shelf();
    library["fiction"]["classics"][0] = "Emma";
    assert(library["fiction"][0] == "Dune", "set through two indexers");
    assert(library["fiction"]["classics"][0] == "Emma", "and through three");
    return 0;
}

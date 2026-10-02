main(): int {
    var config = OrderedMap<String, String>();
    config["name"] = "pepper";
    config["version"] = "0.2";
    config["license"] = "MIT";

    # Setting a key that is present keeps its place.
    config["name"] = "Pepper";

    # Removing a key and adding it again moves it to the end.
    config.remove("version");
    config["version"] = "0.3";

    var keys = "";
    for (var (key, value) in config) {
        keys = keys + key + " ";
    }
    assert(keys == "name license version ", "insertion order");

    if (config.try_get("license") is Value(license)) {
        assert(license == "MIT", "found");
    }
    assert(config.try_get("author").is_none(), "absent");
    return 0;
}

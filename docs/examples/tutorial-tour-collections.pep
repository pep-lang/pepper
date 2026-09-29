main(): int {
    # Array<T> is a growable list. int[] is another way to write Array<int>.
    var scores = Array<int>();
    scores.append(90);
    scores.append(72);
    scores.append(85);
    assert(scores.count() == 3, "three scores");
    assert(scores[0] == 90, "indexing starts at 0");
    scores[1] = 75;
    assert(scores.contains(85), "contains");

    var total = 0;
    for (var score in scores) {
        total += score;
    }
    assert(total == 250, "90 + 75 + 85");

    int[] none = Array<int>();
    assert(none.empty(), "a new array is empty");

    # String holds UTF-8 text.
    var name = "Pepper";
    var greeting = "Hello, " + name;
    greeting += "!";
    assert(greeting == "Hello, Pepper!", "+ and += join strings");
    assert(greeting.length() == 14, "length counts characters");
    assert(greeting.starts_with("Hello"), "starts_with");
    assert(greeting.substr(7, 6) == "Pepper", "substr(start, count)");
    assert(greeting.find("Pepper") == 7, "find returns an offset, or -1");
    assert(greeting[0] == "H", "s[i] is a one-character String");

    # HashMap<K, V> maps keys to values.
    var ages = HashMap<String, int>();
    ages["Ada"] = 36;
    ages.insert("Alan", 41);
    assert(ages.count() == 2, "two entries");
    assert(ages["Ada"] == 36, "look up by key");
    assert(ages.contains("Alan"), "contains");
    assert(ages["Grace"] == 0, "a missing key reads as the default value");
    assert(!ages.contains("Grace"), "reading does not insert");
    ages.remove("Ada");
    assert(ages.count() == 1, "removed");

    # HashSet<K> keeps each key once.
    var seen = HashSet<String>();
    seen.insert("apple");
    seen.insert("apple");
    assert(seen.count() == 1, "duplicates are ignored");
    return 0;
}

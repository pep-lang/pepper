trait Shape {
    area(): int;
}

struct Square {
    int side;

    construct(side: int) {
        this.side = side;
    }
}

extend Square with Shape {
    area(): int {
        return side * side;
    }
}

total(values: long[]): long {
    long sum = 0;
    for (var value in values) {
        sum += value;
    }
    return sum;
}

main(): int {
    # An array literal is an Array of its elements' type.
    var primes = [2, 3, 5, 7];
    assert(primes.count == 4 && primes[3] == 7, "an Array<int>");

    # A trailing comma lets a long literal put one element per line.
    var operators = [
        "===",
        "!==",
        "=>",
    ];
    assert(operators[1] == "!==", "an Array<String>");

    # Where an Array type is expected, the elements convert to its element type.
    assert(total([1, 2, 3]) == 6, "an Array<long> argument");
    Shape[] shapes = [Square(2), Square(3)];
    assert(shapes[1].area() == 9, "elements convert to the trait type");

    # A map literal is a HashMap; a repeated key keeps its last value.
    var ages = ["Ada": 36, "Alan": 41];
    assert(ages["Alan"] == 41, "a HashMap<String, int>");

    # An array literal where a HashSet is expected makes a set.
    HashSet<String> keywords = ["if", "else", "if"];
    assert(keywords.count == 2, "duplicates are kept once");

    # [] and [:] are empty, where the type is declared.
    long[] none = [];
    HashMap<String, int> nobody = [:];
    assert(none.is_empty && nobody.count == 0, "empty collections");
    return 0;
}

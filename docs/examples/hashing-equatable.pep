# `[Equatable]` derives `==` and the hash from the fields, so they always
# agree.
[Equatable]
struct Person {
    String name;
    int id;
    # Not part of the identity: two records for the same person may differ.
    [Equatable(exclude = true)]
    String nickname;

    construct(this.name = "", this.id = 0, this.nickname = "") {}
}

# An enum whose cases carry values compares the case and then its values.
[Equatable]
enum Token {
    Word(text: String),
    Number(value: int),
    End,
}

main(): int {
    HashSet<Person> people = [Person("Ada", 1, "A"), Person("Ada", 1, "Countess")];
    assert(people.count == 1, "equal people are one member");
    assert(people.contains(Person("Ada", 1)), "the nickname is ignored");
    assert(!people.contains(Person("Ada", 2)), "a different id");
    assert(Person("Ada", 1) == Person("Ada", 1, "B"), "== is derived");

    var counts = HashMap<Token, int>();
    counts[Token.Word("pepper")] = 2;
    counts[Token.End] = 1;
    assert(counts[Token.Word("pepper")] == 2, "found by case and value");
    assert(Token.Word("salt") != Token.Word("pepper"), "different values");
    assert(Token.Number(0) != Token.End, "different cases");
    return 0;
}

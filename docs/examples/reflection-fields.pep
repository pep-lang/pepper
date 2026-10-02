struct Account {
    var owner: String;
    var _balance: int;

    construct(this.owner = "", this._balance = 0) {}

    # `reflect.fields<T>()` lists private fields too, so it is available
    # only in the file that declares `T`: code its author writes, like this
    # field-by-field `==`.
    ==(other: Account): bool {
        var same = true;
        static (same, other) {
            for (var field in reflect.fields<Account>()) {
                same = same && field.get(this) == field.get(other);
            }
        }
        return same;
    }
}

main(): int {
    assert(Account("ann", 5) == Account("ann", 5), "equal fields compare equal");
    assert(!(Account("ann", 5) == Account("ann", 6)), "a private field takes part");
    return 0;
}

struct Account {
    var balance: int = 0;
}

# The parameter is another reference to the caller's object, so changes to
# its fields are visible to the caller.
deposit(account: Account, amount: int) {
    account.balance += amount;
}

# Rebinding the parameter itself only changes this function's reference.
replace(account: Account) {
    account = Account();
    account.balance = 999;
}

main(): int {
    var mine = Account();
    var yours = mine;               # shares the object; nothing is copied
    yours.balance = 50;
    assert(mine.balance == 50, "assignment shares the object");

    deposit(mine, 25);
    assert(mine.balance == 75, "a function can change the shared object");

    replace(mine);
    assert(mine.balance == 75, "rebinding a parameter does not affect the caller");

    # To get an independent object, make a new one and copy the fields.
    var copy = Account();
    copy.balance = mine.balance;
    copy.balance = 0;
    assert(mine.balance == 75, "the copy is a separate object");
    return 0;
}

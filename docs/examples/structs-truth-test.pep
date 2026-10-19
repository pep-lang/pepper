# A struct that declares `!!(): bool` can be used as a condition.
struct Budget {
    var cents: int = 0;

    construct(this.cents = 0) {}

    # The truth test: `if (budget)` calls `budget.!!()`.
    !!(): bool {
        return cents > 0;
    }
}

struct Label {
    var text: String;

    construct(this.text = "") {}
}

spend(budget: Budget, amount: int): int {
    var spent = 0;
    # A condition, an operand of `&&`, and the operand of `!` all call `!!`.
    while (budget && amount > 0) {
        budget.cents -= 1;
        amount -= 1;
        spent += 1;
    }
    if (!budget) {
        print("budget used up");
    }
    return spent;
}

main(): int {
    var budget = Budget(3);
    assert(spend(budget, 2) == 2, "spent 2 of 3");
    assert(budget ? true : false, "a ternary condition calls !! too");
    assert(spend(budget, 5) == 1, "only 1 left");
    assert(!!budget == false, "!!x calls the truth test");

    # A struct without `!!` is not a condition: `if (label)` is an error.
    # Compare with `__null` to ask whether a reference is set.
    var label: Label;
    assert(label === __null, "no Label yet");
    label = Label("sale");
    assert(label !== __null, "now there is one");
    return 0;
}

# Output:
# budget used up

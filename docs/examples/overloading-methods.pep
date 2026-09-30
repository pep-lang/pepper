# Overloaded methods, static methods and operators.

struct Money {
    var cents: long;

    construct(long cents = 0) {
        this.cents = cents;
    }

    # Methods of one name in a struct overload like free functions.
    add(other: Money): Money { return Money(cents + other.cents); }
    add(dollars: int, cents: int): Money { return Money(this.cents + dollars * 100 + cents); }

    # Static methods overload among themselves.
    static of(cents: long): Money { return Money(cents); }
    static of(text: String): Money { return Money(text.size() as long); }

    # Operators are methods, so they overload by operand type too.
    +(other: Money): Money { return add(other); }
    +(more: int): Money { return Money(cents + more); }
}

main(): int {
    var a = Money.of(250);
    var b = a.add(1, 5);                  # add(int, int)
    assert(b.cents == 355, "two ints");
    assert(a.add(b).cents == 605, "a Money");

    var c = a + b + 10;                   # +(Money), then +(int)
    assert(c.cents == 615, "operators");
    assert(Money.of("four").cents == 4, "static of(String)");

    # A method used as a value takes the member its type names.
    var plus: (Money) => Money = a.add;
    assert(plus(a).cents == 500, "method value");
    return 0;
}

struct Money {
    var cents: int = 0;

    construct(this.cents = 0) {}

    # `a == b` calls `a.==(b)`. Without this method, `==` on two structs
    # compares identity, like `===`.
    bool ==(Money other) {
        return cents == other.cents;
    }

    # `!=` is derived from `==` when the struct does not define it.

    # `a + b` calls `a.+(b)` and returns a new Money.
    Money +(Money other) {
        return Money(cents + other.cents);
    }

    # `a += b` needs its own method; it is not rewritten to `a = a + b`.
    Money +=(Money other) {
        cents += other.cents;
        return this;
    }
}

struct Shelf {
    var slots: Array<String>;

    construct() {
        slots = Array<String>();
        slots.append("empty");
        slots.append("empty");
    }

    # An indexer with one parameter handles reads: `shelf[i]`.
    String [](int index) {
        return slots[index];
    }

    # An indexer with two parameters handles writes: `shelf[i] = value`.
    String [](int index, String value) {
        slots[index] = value;
        return value;
    }
}

main(): int {
    var price = Money(250);
    assert(price == Money(250), "== compares cents");
    assert(price != Money(100), "!= compares cents");
    # `===` and `!==` always compare identity: equal cents, different objects.
    assert(price !== Money(250), "!== compares identity");
    var same = price;
    assert(same === price, "=== is true for the same object");

    var total = price + Money(50);
    assert(total.cents == 300, "+ makes a new value");
    assert(price.cents == 250, "+ left its operands alone");

    total += Money(25);
    assert(total.cents == 325, "+= updated total in place");

    var shelf = Shelf();
    shelf[1] = "books";
    assert(shelf[1] == "books", "indexer write, then read");
    assert(shelf[0] == "empty", "the other slot is unchanged");
    return 0;
}

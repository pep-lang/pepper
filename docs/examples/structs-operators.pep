struct Money {
    var cents: int = 0;

    construct(this.cents = 0) {}

    # `a == b` calls `a.==(b)`. Without this method, `==` on two structs
    # compares identity, like `===`.
    ==(other: Money): bool {
        return cents == other.cents;
    }

    # `!=` is derived from `==` when the struct does not define it.

    # `a < b` calls `a.<(b)`.
    <(other: Money): bool {
        return cents < other.cents;
    }

    # `a + b` calls `a.+(b)` and returns a new Money.
    +(other: Money): Money {
        return Money(cents + other.cents);
    }

    # `-a` calls `a.-()`: a unary operator takes no parameters.
    -(): Money {
        return Money(0 - cents);
    }

    # `a - b` calls `a.-(b)`. The unary and binary `-` overload each other,
    # told apart by their number of parameters.
    -(other: Money): Money {
        return Money(cents - other.cents);
    }

    # `a += b` needs its own method; it is not rewritten to `a = a + b`.
    +=(other: Money): Money {
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
    [](index: int): String {
        return slots[index];
    }

    # An indexer with two parameters handles writes: `shelf[i] = value`.
    [](index: int, value: String): String {
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

    assert(price < total, "< compares cents");

    var refund = -price;
    assert(refund.cents == -250, "unary - calls -()");
    assert((total - price).cents == 50, "binary - calls -(other)");

    total += Money(25);
    assert(total.cents == 325, "+= updated total in place");

    var shelf = Shelf();
    shelf[1] = "books";
    assert(shelf[1] == "books", "indexer write, then read");
    assert(shelf[0] == "empty", "the other slot is unchanged");
    return 0;
}

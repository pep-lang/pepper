# An enum names a fixed set of cases; a slot of the enum type holds one.
enum Suit {
    Clubs,
    Diamonds,
    Hearts,
    Spades,
}

# A representation sets the stored integer type; a case may give its value.
enum Status: u8 {
    Ok,
    NotFound = 44,
    Failed,
}

struct Card {
    Suit suit;
    int rank = 1;
}

main(): int {
    var card = Card();
    assert(card.suit == Suit.Clubs, "a slot starts at the case whose value is 0");
    card.suit = Suit.Hearts;
    assert(card.suit != Suit.Spades, "cases compare with == and !=");

    # 'as' turns a case into its integer; the reverse is not allowed.
    assert((Suit.Hearts as int) == 2, "cases number from 0");
    assert((Status.Failed as int) == 45, "numbering continues after an explicit value");
    assert(sizeof<Status>() == 1, "Status is stored as a u8");
    return 0;
}

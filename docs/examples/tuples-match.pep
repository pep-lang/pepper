# `match` takes a tuple apart, testing every element at once.
enum Move {
    Rock,
    Paper,
    Scissors,
}

# Who wins: 1 for the first player, 2 for the second, 0 for a draw.
winner(first: Move, second: Move): int {
    match ((first, second)) {
        (Rock, Scissors), (Paper, Rock), (Scissors, Paper) => {
            return 1;
        }
        (Rock, Rock), (Paper, Paper), (Scissors, Scissors) => {
            return 0;
        }
        else => {
            return 2;
        }
    }
}

enum Token {
    Number(value: int),
    Word(text: String),
}

# Literals, cases with values, bound names and `_` mix in one pattern.
describe(token: Token, line: int): String {
    return match ((token, line)) {
        (Number(v), 1) => "a number on the first line",
        (Word(text), _) => text,
        (_, _) => "another number",
    };
}

main(): int {
    assert(winner(Move.Rock, Move.Scissors) == 1, "rock blunts scissors");
    assert(winner(Move.Paper, Move.Scissors) == 2, "scissors cut paper");
    assert(winner(Move.Paper, Move.Paper) == 0, "a draw");

    assert(describe(Token.Word("hi"), 3) == "hi", "a word binds its text");
    assert(describe(Token.Number(7), 1) == "a number on the first line", "a literal element");

    # A name binds its element; `is` tests one pattern.
    var at = (4, 2);
    if (at is (4, column)) {
        assert(column == 2, "bound by the pattern");
    }
    return 0;
}

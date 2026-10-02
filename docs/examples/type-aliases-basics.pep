# An alias is another name for an existing type.
type Score = int;
type Names = Array<String>;
type Handler = (int) => int;

struct Player {
    var name: String;
    var best: Score = 0;        # aliases work in fields...
}

type Team = Player;

double_it(x: int): int {
    return x * 2;
}

# ...and in parameters and return types.
apply(h: Handler, x: Score): Score {
    return h(x);
}

main(): int {
    var s: Score = 21;
    var plain: int = s;         # Score and int are the same type
    assert(apply(double_it, plain) == 42, "function type alias");

    var names = Names();        # construct through the alias
    names.append("Ada");
    assert(names.count == 1, "Names is Array<String>");

    var p = Team();
    p.best = s;
    var q: Player = p;          # Team and Player are the same type
    assert(q.best == 21, "struct alias");
    return 0;
}

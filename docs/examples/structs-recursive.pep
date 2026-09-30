# A field can hold the struct's own type: each Link points at the next one.
struct Link {
    var value: int;
    var next: Link;

    construct(this.value = 0) {}
}

# Two structs can refer to each other, in either declaration order.
struct Team {
    var name: String;
    var lead: Player;

    construct(this.name = "") {}
}

struct Player {
    var name: String;
    # A weak back pointer: the team owns its lead, so the player's link
    # back to the team must not keep the team alive (see the memory chapter).
    var team: Weak<Team>;

    construct(this.name = "") {}
}

sum(first: Link): int {
    var total = 0;
    var link: Link = first;
    while (link !== __null) {
        total = total + link.value;
        link = link.next;
    }
    return total;
}

main(): int {
    var list = Link(1);
    list.next = Link(2);
    list.next.next = Link(3);
    assert(sum(list) == 6, "the list holds 1, 2 and 3");
    assert(list.next.next.next === __null, "the last link has no next");

    var team = Team("Owls");
    team.lead = Player("Ada");
    team.lead.team = Weak<Team>(team);
    with (var t = team.lead.team) {
        assert(t.name == "Owls", "the player reaches its team");
    }
    return 0;
}

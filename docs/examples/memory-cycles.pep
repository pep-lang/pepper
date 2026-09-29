var destroyed = 0;

struct Person {
    var name: String;
    var friends: Array<Person>;

    construct(this.name = "") {
        friends = Array<Person>();
    }

    destruct {
        destroyed += 1;
    }
}

main(): int {
    # Two people who list each other as friends form a cycle: each keeps
    # the other alive, so neither is ever destroyed.
    {
        var ann = Person("Ann");
        var bob = Person("Bob");
        ann.friends.append(bob);
        bob.friends.append(ann);
    }
    assert(destroyed == 0, "the cycle leaked both objects");

    # Break the cycle before letting go, and both are destroyed.
    {
        var cat = Person("Cat");
        var dan = Person("Dan");
        cat.friends.append(dan);
        dan.friends.append(cat);
        dan.friends.clear();    # Dan no longer holds Cat
    }
    assert(destroyed == 2, "without the cycle, both were destroyed");
    return 0;
}

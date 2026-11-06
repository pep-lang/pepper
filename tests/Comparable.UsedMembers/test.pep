# The members of `Comparable` a Comparable Array, Optional or tuple gets
# from the trait wait for a use (#491); each use below still finds its
# member: an operator, a call, a constrained generic, and a sort.

struct P {
    var x: int;

    construct(x: int) {
        this.x = x;
    }

    compare(other: P): int {
        return x - other.x;
    }
}

extend P with Comparable;

largest<T: Comparable>(a: T, b: T): T {
    return a.max(b);
}

smallest<T: Comparable>(a: T, b: T): T {
    return a <= b ? a : b;
}

main(): int {
    assert([P(1)] < [P(2)], "an Array's <");
    assert([P(3)].clamp([P(1)], [P(2)])[0].x == 2, "an Array's clamp");
    assert(largest((P(1), P(2)), (P(2), P(1))).0.x == 2, "a tuple's max in a generic");
    assert(smallest((P(1), 5), (P(1), 4)).1 == 4, "a tuple's <= in a generic");
    var o = [Optional<P>.Value(P(2)), Optional<P>.Empty, Optional<P>.Value(P(1))];
    o.sort();
    assert(o[0].is_empty() && o[1].value().x == 1 && o[2].value().x == 2, "sorted Optionals");
    assert(Optional<P>.Value(P(1)) >= Optional<P>.Empty, "an Optional's >=");
    return 0;
}

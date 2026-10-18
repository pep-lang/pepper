main(): int {
    # A sieve: every number below 50 starts out as a candidate.
    var composite = BitSet(50);
    var primes = BitSet();
    for (var n in 2..50) {
        if (composite.contains(n)) {
            continue;
        }
        primes.insert(n);
        var multiple = n * n;
        while (multiple < 50) {
            composite.insert(multiple);
            multiple = multiple + n;
        }
    }
    assert(primes.count == 15, "15 primes below 50");

    # Members come out in ascending order.
    var first = "";
    for (var p in primes) {
        if (p > 11) {
            break;
        }
        first = $"{first}{p} ";
    }
    assert(first == "2 3 5 7 11 ", "ascending");

    # Set operations, by value or in place.
    BitSet odd = [1, 3, 5, 7, 9, 11];
    var odd_primes = primes.intersection(odd);
    assert(odd_primes.count == 4, "3, 5, 7 and 11");
    assert(odd_primes.is_subset(primes), "a subset");
    odd.difference_with(primes);
    assert(odd == BitSet([1, 9]), "1 and 9 are odd but not prime");
    return 0;
}

# A program that spins long enough to be profiled.

spin(n: long): long {
    long total = 0;
    for (var i in 0..n) {
        total += i % 7;
    }
    return total;
}

main(): int {
    print(to_string(spin(200000000)));
    return 0;
}

# A constructor's parameter may name a generic type that nothing else in
# the program uses (`int[]` here), even when no one calls the constructor:
# it is declared all the same, so its parameter types are specialized.

struct Bits {
    ulong[] words;

    construct() {}

    [Implicit]
    construct(items: int[]) {
        for (var item in items) {
            words.append(item as ulong);
        }
    }
}

main(): int {
    var b = Bits();
    return b.words.count as int;
}

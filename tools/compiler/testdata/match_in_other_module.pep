import m;

main(): int {
    return m.Db().run<int>((): m.Outcome<int> => m.Outcome<int>.ok(3)).value();
}

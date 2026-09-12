struct Test<T> {
    T x;
};

extend Test<int> {
    test(): int {
        return x;
    }
};

main(): int {
    const t = Test<int>();
    return t.test();
}

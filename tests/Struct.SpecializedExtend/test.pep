struct Test<T> {
    T x;
};

extend Test<int> {
    int test() {
        return x;
    }
};

int main() {
    const t = Test<int>();
    return t.test();
}
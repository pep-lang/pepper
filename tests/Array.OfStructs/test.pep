
use "../array";

struct Test {
    int x;

    new(this.x = 0) {}
};

int main() {
    var tests = array<Test>();
    tests.append(Test(42));
    tests.append(Test(12));
    tests[1] = Test(42);
    return tests[0].x - tests[1].x;
}

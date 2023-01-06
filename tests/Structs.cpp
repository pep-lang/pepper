//
// Created by Justin Boswell on 12/23/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Structs, Simple) {
    const char* source = R"SOURCE(
struct Test {
    int x = 0;
};

int test() {
    Test t = Test();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Auto) {
    const char* source = R"SOURCE(
struct Test {
    int x = 0;
};

int test() {
    const t = Test();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Constructor) {
    const char* source = R"SOURCE(
struct Test {
    int x = 0;

    new(this.x = 1) {}
};

int test() {
    Test t = Test();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Extension) {
    const char* source = R"SOURCE(
struct Test {
    int x;
    new() {
        x = 1;
    }
};

extend Test {
    void setX(int newX) {
        x = newX;
    }
}

int test() {
    Test t = Test();
    t.setX(10);
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, Range) {
    const char* source = R"SOURCE(
struct range_test {
    int start;
    int current = 0xffffffff;
    int end;
    int step;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
    }
}

extend range_test {
    bool next() {
        if (current == 0xffffffff) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    int value() {
        return current;
    }
}

int test() {
    range_test r = range_test(0, 10);
    int x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SimpleGeneric) {
    const char* source = R"SOURCE(
struct Test<T> {
    T x;
};

int test() {
    Test<int> t = Test<int>();
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SimpleGenericCtor) {
    const char* source = R"SOURCE(
struct Test<T> {
    T x;

    new(this.x) {}
};

int test() {
    Test<int> t = Test<int>(2);
    return t.x;
}
    )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, RangeGeneric) {
    const char* source = R"SOURCE(
struct range_test<T> {
    T start;
    T current;
    T end;
    T step;

    new(this.start, this.end = -1, this.step=1) {
        if (end == -1) {
            end = start + 1;
            step = 0;
        }
        current = start - step;
    }
}

extend range_test<T> {
    bool next() {
        if ((current + step) == start) {
            current = start;
        } else {
            current += step;
        }
        return current < end;
    }

    T value() {
        return current;
    }
}

int test() {
    range_test<int> r = range_test<int>(0, 10);
    int x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, SpecializedExtend) {
    const char* source = R"SOURCE(
struct Test<T> {
    T x;
};

extend Test<int> {
    int test() {
        return x;
    }
};

int test() {
    const t = Test<int>();
    return t.test();
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Structs, RefLifetime) {
    const char* source = R"SOURCE(
struct Test {
    int x = 0;
};

struct Foo {
    Test t;
    int y;

    new(this.t) {
        y = t.x;
    }
};

int test() {
    var t = Test();
    const f = Foo(t);
    return f.y;
}
    )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

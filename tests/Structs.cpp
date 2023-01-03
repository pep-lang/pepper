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
struct range {
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

extend range {
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
    range r = range(0, 10);
    int x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}

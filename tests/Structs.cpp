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

    new() {
        this.x = 1;
    }
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

/*
TEST(Structs, DISABLED_Range) {
    const char* source = R"SOURCE(
struct range {
    int current;
    int end;
    int step;

    new(int start, int end, int step=1) {
        this.current = start;
        this.end = end;
        this.step = step;
    }
}

extend range with {
    bool next() {
        this.current += step;
        return this.current < end;
    }
}

int test() {
    range r = range(0, 10, 1)
    int x = 0;
    while (r.next()) {
        x += 1;
    }
    return x;
}
    )SOURCE";
    EXPECT_EQ(10, CompileAndRun(TestName(test_info_), source));
}
*/
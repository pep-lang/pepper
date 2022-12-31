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
        this.x = 1;
    }
};

extend Test with {
    void setX(int newX) {
        this.x = newX;
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

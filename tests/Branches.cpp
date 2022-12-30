//
// Created by Justin Boswell on 12/26/22.
//
#include "TestUtils.h"
#include "gtest/gtest.h"

using namespace TestUtils;

TEST(Branches, If) {
    const char* source = R"SOURCE(
        int test() {
            int x = 0;
            if (x == 0)
                x = 1;
            return x;
        }
        )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, IfElse) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            if (x) {
                x = 2;
            } else {
                x = 3;
            }
            return x;
        }
        )SOURCE";
    EXPECT_EQ(2, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, NestedIf) {
    const char* source = R"SOURCE(
        int test() {
            int x = 2;
            int y = 3;
            if (y % x) {
                if (x && y) {
                    y -= x;
                } else {
                    y = 0;
                }
            }
            return y;
        }
        )SOURCE";
    EXPECT_EQ(1, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, NestedIfElse) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            int y = 2;
            if (y % x) {
                if (x && y) {
                    y -= x;
                } else {
                    y = 0;
                }
            } else {
                int z = 4;
                if (z % y) {
                    y = z;
                } else {
                    y = z*z;
                }
            }
            return y;
        }
        )SOURCE";
    EXPECT_EQ(16, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, Ternary) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            return x ? 0 : 1;
        }
        )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}

TEST(Branches, NestedTernary) {
    const char* source = R"SOURCE(
        int test() {
            int x = 1;
            int y = 0;
            return x ? 0 : (y ? 1: 0);
        }
        )SOURCE";
    EXPECT_EQ(0, CompileAndRun(TestName(test_info_), source));
}
